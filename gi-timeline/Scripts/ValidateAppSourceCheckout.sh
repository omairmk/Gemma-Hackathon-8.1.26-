#!/bin/zsh

set -euo pipefail

readonly source_root="${1:?usage: ValidateAppSourceCheckout.sh /absolute/path/SRCROOT EXPECTED_SOURCE_COMMIT EXPECTED_SOURCE_TREE}"
readonly expected_source_commit="${2:?expected source commit is required}"
readonly expected_source_tree="${3:?expected source tree is required}"

fail() {
  print -u2 -- "error: App Store source-checkout validation failed: $1"
  exit 1
}

[[ "$source_root" == /* && -d "$source_root" && ! -L "$source_root" ]] \
  || fail "source root must be an absolute, non-symlink directory"
[[ ${#expected_source_commit} == 40 && "$expected_source_commit" != *[^0-9a-f]* ]] \
  || fail "expected source commit must be a 40-character lowercase Git commit"
[[ ${#expected_source_tree} == 40 && "$expected_source_tree" != *[^0-9a-f]* ]] \
  || fail "expected source tree must be a 40-character lowercase Git tree"

readonly git_root="$(/usr/bin/git -C "$source_root" rev-parse --show-toplevel 2>/dev/null)" \
  || fail "source root is not inside a Git worktree"
readonly source_prefix="$(/usr/bin/git -C "$source_root" rev-parse --show-prefix 2>/dev/null)" \
  || fail "could not resolve source-root path inside the Git worktree"
[[ -n "$source_prefix" ]] || fail "source root must be a scoped repository subdirectory"
readonly head_commit="$(/usr/bin/git -C "$git_root" rev-parse HEAD 2>/dev/null)"
readonly head_tree="$(/usr/bin/git -C "$git_root" rev-parse 'HEAD^{tree}' 2>/dev/null)"
[[ "$head_commit" == "$expected_source_commit" ]] || fail "expected source commit does not match HEAD"
[[ "$head_tree" == "$expected_source_tree" ]] || fail "expected source tree does not match HEAD^{tree}"

readonly source_status="$(/usr/bin/git -C "$git_root" status --porcelain --untracked-files=all -- "$source_prefix")"
[[ -z "$source_status" ]] || fail "source subtree has tracked, staged, or untracked changes"

typeset -i tracked_file_count=0
while IFS= read -r -d $'\0' tree_record; do
  local_metadata="${tree_record%%$'\t'*}"
  repository_path="${tree_record#*$'\t'}"
  [[ "$local_metadata" != "$tree_record" && "$repository_path" == "$source_prefix"* ]] \
    || fail "could not parse a scoped HEAD tree record"
  typeset -a metadata_fields
  metadata_fields=( ${(s: :)local_metadata} )
  [[ ${#metadata_fields[@]} == 3 && "${metadata_fields[2]}" == "blob" ]] \
    || fail "source subtree contains a non-blob Git entry at ${repository_path}"
  file_mode="${metadata_fields[1]}"
  expected_blob="${metadata_fields[3]}"
  case "$file_mode" in
    100644|100755) ;;
    *) fail "source subtree contains an unreviewed Git mode ${file_mode} at ${repository_path}" ;;
  esac
  absolute_path="$git_root/$repository_path"
  [[ -f "$absolute_path" && ! -L "$absolute_path" ]] \
    || fail "tracked source is missing, non-regular, or a symlink at ${repository_path}"
  actual_blob="$(/usr/bin/git hash-object --no-filters -- "$absolute_path")" \
    || fail "could not hash working source at ${repository_path}"
  [[ "$actual_blob" == "$expected_blob" ]] \
    || fail "working bytes differ from HEAD despite index flags at ${repository_path}"
  (( tracked_file_count += 1 ))
done < <(/usr/bin/git -C "$git_root" ls-tree -r -z HEAD -- "$source_prefix")
(( tracked_file_count > 0 )) || fail "source subtree contains no tracked files"

while IFS= read -r -d $'\0' tagged_path; do
  [[ "${tagged_path[1]}" == "H" ]] \
    || fail "tracked source carries an assume-unchanged, skip-worktree, or unmerged index flag: ${tagged_path[2,-1]}"
done < <(/usr/bin/git -C "$git_root" ls-files -v -z -- "$source_prefix")

typeset -a ignored_input_scopes
ignored_input_scopes=(
  "${source_prefix}GITimeline"
  "${source_prefix}GITimeline.xcodeproj"
  "${source_prefix}Package.swift"
  "${source_prefix}Scripts"
  "${source_prefix}Sources"
  "${source_prefix}Vendor"
  "${source_prefix}.swiftpm/configuration"
  "${source_prefix}.swiftpm/security"
)
typeset ignored_build_input=""
while IFS= read -r -d $'\0' ignored_path; do
  case "$ignored_path" in
    "${source_prefix}GITimeline.xcodeproj/xcuserdata/"*.xcuserdatad/xcschemes/xcschememanagement.plist|\
    "${source_prefix}GITimeline.xcodeproj/project.xcworkspace/xcuserdata/"*.xcuserdatad/UserInterfaceState.xcuserstate)
      # These exact per-user Xcode UI/scheme-order files are not build inputs.
      # User-authored .xcscheme files and every other ignored project file fail.
      ;;
    *)
      ignored_build_input="$ignored_path"
      break
      ;;
  esac
done < <(/usr/bin/git -C "$git_root" ls-files --others --ignored --exclude-standard -z -- $ignored_input_scopes)
[[ -z "$ignored_build_input" ]] \
  || fail "ignored content exists in a production build-input scope: ${ignored_build_input}"

# Public-binary source-membership truth (2026-08-19): the GITimelineCore
# SwiftPM target declares no explicit sources:/exclude: list (Package.swift),
# so it auto-compiles every .swift file found anywhere under
# Sources/GITimelineCore/ into BOTH public app products, and until now no
# validator watched that membership -- a committed file could silently
# expand the compiled public-binary surface with no additional review gate.
# This block pins the reviewed set of record as of 2026-08-19, including
# PhotoSuggestionHybrid.swift, PhotoSuggestionV1.swift, PhotoSuggestionV2.swift,
# and ConfirmationProvenance.swift, which are authorized-additive per the
# 2026-08-17 checkpoint, so that any FUTURE addition, removal, or rename
# under that tree is a conscious, reviewed act instead of a silent
# compile-time surface change. This is a narrow truth-layer guard only: the
# structural fix (moving these into their own SwiftPM target) is deferred to
# the promotion step, where it can be done without rippling into frozen
# candidate files (Adapter/Composer/Harness imports, this script's own
# --core-source path); that restructure supersedes this block when it lands.
readonly gitimelinecore_sources_root="${source_root}/Sources/GITimelineCore"
[[ -d "$gitimelinecore_sources_root" && ! -L "$gitimelinecore_sources_root" ]] \
  || fail "GITimelineCore sources directory is missing or is a symlink"
typeset -a expected_gitimelinecore_sources
expected_gitimelinecore_sources=(
  ClinicalTimeline.swift
  ConfirmationProvenance.swift
  JournalExport.swift
  NewEntryWorkflow.swift
  Observation.swift
  PhotoSuggestionEvaluation.swift
  PhotoSuggestionHybrid.swift
  PhotoSuggestionV1.swift
  PhotoSuggestionV2.swift
  SafetyRules.swift
)
typeset -a actual_gitimelinecore_sources
actual_gitimelinecore_sources=()
while IFS= read -r -d $'\0' gitimelinecore_source_path; do
  actual_gitimelinecore_sources+=("${gitimelinecore_source_path#$gitimelinecore_sources_root/}")
done < <(/usr/bin/find "$gitimelinecore_sources_root" -type f -name '*.swift' -print0)
typeset -a unexpected_gitimelinecore_sources
unexpected_gitimelinecore_sources=(${actual_gitimelinecore_sources:|expected_gitimelinecore_sources})
[[ ${#unexpected_gitimelinecore_sources[@]} == 0 ]] \
  || fail "GITimelineCore Sources contains file(s) not in the reviewed public-binary inventory: ${(j:, :)unexpected_gitimelinecore_sources}"
typeset -a missing_gitimelinecore_sources
missing_gitimelinecore_sources=(${expected_gitimelinecore_sources:|actual_gitimelinecore_sources})
[[ ${#missing_gitimelinecore_sources[@]} == 0 ]] \
  || fail "GITimelineCore Sources is missing reviewed public-binary inventory file(s): ${(j:, :)missing_gitimelinecore_sources}"

[[ -x "${source_root}/Scripts/ValidateLocalOnlySource.sh" ]] \
  || fail "local-only source validator is missing or not executable"
"${source_root}/Scripts/ValidateLocalOnlySource.sh" \
  || fail "local-only source contract failed"

print -- "APPSTORE_SOURCE_CHECKOUT_VALIDATION: PASS"
print -- "source_commit=${head_commit} source_tree=${head_tree} tracked_files_verified=${tracked_file_count} source_prefix=${source_prefix}"
