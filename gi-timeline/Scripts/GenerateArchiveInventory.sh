#!/bin/zsh

set -euo pipefail

readonly archive_path="${1:?usage: GenerateArchiveInventory.sh /absolute/path/App.xcarchive /absolute/path/archive-inventory.tsv}"
readonly output_path="${2:?an absolute output path is required}"

fail() {
  print -u2 -- "error: archive inventory failed: $1"
  exit 1
}

[[ "$archive_path" == /* ]] || fail "archive path must be absolute"
[[ "$output_path" == /* ]] || fail "output path must be absolute"
[[ -d "$archive_path" && -f "$archive_path/Info.plist" ]] || fail "archive or archive Info.plist is missing"
[[ "$output_path" != "$archive_path"/* ]] || fail "inventory output must be outside the archive"
[[ -d "${output_path:h}" ]] || fail "output directory does not exist"

readonly application_path="$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:ApplicationPath' "$archive_path/Info.plist" 2>/dev/null)"
readonly app_path="$archive_path/Products/$application_path"
readonly info_path="$app_path/Info.plist"
[[ -d "$app_path" && -f "$info_path" ]] || fail "archived app or processed Info.plist is missing"

readonly special_node="$(/usr/bin/find "$archive_path" ! -type f ! -type d ! -type l -print -quit)"
[[ -z "$special_node" ]] || fail "archive contains an unsupported filesystem node: ${special_node#$archive_path/}"

readonly temporary_output="$(/usr/bin/mktemp "${output_path:h}/.GIJournal-archive-inventory.XXXXXX")"
cleanup() { /bin/rm -f "$temporary_output"; }
trap cleanup EXIT

escape_field() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//$'\t'/\\t}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\n'/\\n}"
  print -rn -- "$value"
}

{
  print -- $'GI_JOURNAL_ARCHIVE_INVENTORY\t3'
  print -- $'bundle_id\t'"$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_path")"
  print -- $'marketing_version\t'"$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_path")"
  print -- $'build_number\t'"$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_path")"
  print -- $'archive_team\t'"$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:Team' "$archive_path/Info.plist" 2>/dev/null)"
  print -- $'signing_identity\t'"$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:SigningIdentity' "$archive_path/Info.plist" 2>/dev/null)"
  print -- $'kind\trelative_path_escaped\tmode\tbytes_or_target_escaped\tsha256\tfile_description'

  /usr/bin/find "$archive_path" -type d -print0 | LC_ALL=C /usr/bin/sort -z | while IFS= read -r -d $'\0' item; do
    relative_path="${item#$archive_path/}"
    [[ "$item" != "$archive_path" ]] || relative_path="."
    mode="$(/usr/bin/stat -f '%Lp' "$item")"
    print -rn -- $'directory\t'
    escape_field "$relative_path"
    print -- $'\t'"${mode}"$'\t-\t-\tdirectory'
  done

  /usr/bin/find "$archive_path" -type f -print0 | LC_ALL=C /usr/bin/sort -z | while IFS= read -r -d $'\0' item; do
    relative_path="${item#$archive_path/}"
    mode="$(/usr/bin/stat -f '%Lp' "$item")"
    bytes="$(/usr/bin/stat -f '%z' "$item")"
    digest="$(/usr/bin/shasum -a 256 "$item" | /usr/bin/awk '{print $1}')"
    description="$(/usr/bin/file -b "$item" | /usr/bin/tr '\t\r\n' '   ')"
    print -rn -- $'file\t'
    escape_field "$relative_path"
    print -- $'\t'"${mode}"$'\t'"${bytes}"$'\t'"${digest}"$'\t'"${description}"
  done

  /usr/bin/find "$archive_path" -type l -print0 | LC_ALL=C /usr/bin/sort -z | while IFS= read -r -d $'\0' item; do
    relative_path="${item#$archive_path/}"
    mode="$(/usr/bin/stat -f '%Lp' "$item")"
    target="$(/usr/bin/readlink "$item")"
    print -rn -- $'symlink\t'
    escape_field "$relative_path"
    print -rn -- $'\t'"${mode}"$'\t'
    escape_field "$target"
    print -- $'\t-\tsymlink'
  done
} > "$temporary_output"

/bin/chmod 0644 "$temporary_output"
/bin/mv -f "$temporary_output" "$output_path"
trap - EXIT

print -- "ARCHIVE_INVENTORY: PASS"
print -- "output=${output_path} sha256=$(/usr/bin/shasum -a 256 "$output_path" | /usr/bin/awk '{print $1}')"
