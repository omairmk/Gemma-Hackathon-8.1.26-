#!/bin/zsh
set -euo pipefail

if [[ "${QWEN3_EMBED_ENABLED:-NO}" != "YES" ]]; then
  exit 0
fi

function fail() {
  print -u2 -- "EmbedQwen3Decomposed: $1"
  exit 1
}

: "${QWEN3_SNAPSHOT_ABSOLUTE_PATH:?QWEN3_SNAPSHOT_ABSOLUTE_PATH is required}"
: "${QWEN3_EMBED_DESTINATION:?QWEN3_EMBED_DESTINATION is required}"
: "${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is required}"
: "${DERIVED_FILE_DIR:?DERIVED_FILE_DIR is required}"
: "${QWEN3_EMBED_STAMP:?QWEN3_EMBED_STAMP is required}"
: "${QWEN3_EMBED_RECEIPT:?QWEN3_EMBED_RECEIPT is required}"

typeset source_root="${QWEN3_SNAPSHOT_ABSOLUTE_PATH%/}"
typeset target_root="${TARGET_BUILD_DIR%/}"
typeset destination="${QWEN3_EMBED_DESTINATION%/}"
typeset derived_root="${DERIVED_FILE_DIR%/}"
typeset stamp="${QWEN3_EMBED_STAMP%/}"
typeset receipt="${QWEN3_EMBED_RECEIPT%/}"

[[ "$source_root" == /* ]] || fail "snapshot must be an absolute path"
[[ -n "$target_root" && -n "$destination" && "$destination" == "$target_root/"* ]] || fail "destination must be a nonempty child of TARGET_BUILD_DIR"
typeset destination_relative="${destination#${target_root}/}"
[[ -n "$destination_relative" && "$destination_relative" != "$destination" ]] || fail "destination must be a nonempty child of TARGET_BUILD_DIR"
case "/${destination_relative}/" in
  *"/../"* | *"//"*) fail "destination may not contain traversal" ;;
esac

for derived_output in "$stamp" "$receipt"; do
  [[ "$derived_output" == "$derived_root/"* && "$derived_output" != "$derived_root" ]] || fail "receipt outputs must be children of DERIVED_FILE_DIR"
done

typeset -A manifest=(
  [.gitattributes]=34448b82c17d60fec9b65b1f093c115ddbaadc04beb1b0140b6bfed2e012a930
  [README.md]=ede73d0babc5bc8fa1eeaed1f9564eab6e5094500e5561f94235a15c96aa1cf0
  [added_tokens.json]=c0284b582e14987fbd3d5a2cb2bd139084371ed9acbae488829a1c900833c680
  [chat_template.jinja]=3636d0f0bd6bef02654cdffdc447b79cb2cef8ab02cc75267345946291a489e4
  [chat_template.json]=6f8a6a55027e3da5160105556cda5dd69f6423f1c32645f6730d32de7773d0c4
  [config.json]=6e992843f82cbaf02e8eae2f1c803f8a56f70951fa8a1f30fc1bf8d9ec2d7ec3
  [generation_config.json]=1e241830b48b397cb0900101421df5450baddc7adf01e5fc86b5615865f3bae4
  [merges.txt]=8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5
  [model.safetensors]=4750d95a2162829e127a94e83ac350d498d02070aab216c4687da48804a06ffb
  [model.safetensors.index.json]=30ba24b1c93436450f2e202de402058ecea7417cf66785d4c73e52d1575e6d97
  [preprocessor_config.json]=93585062a80db5e8ca038efc7726a3e6411d9db948472d81d63c6303993be8c5
  [special_tokens_map.json]=76862e765266b85aa9459767e33cbaf13970f327a0e88d1c65846c2ddd3a1ecd
  [tokenizer.json]=aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4
  [tokenizer_config.json]=81ec7bb9530159b326c0bef1d0b6c33d392090524014ea3f0123a3c1eb9c2af5
  [video_preprocessor_config.json]=59c5c9eb52182eb14c06ffb10ca9effd29adce5f238a95de23ca14a38dbd2cb1
  [vocab.json]=ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910
)

function verify_snapshot() {
  typeset root="$1"
  [[ -d "$root" && ! -L "$root" ]] || fail "snapshot root is missing or is a symlink: $root"

  integer actual_count=0
  typeset item name actual_hash
  while IFS= read -r -d $'\0' item; do
    (( actual_count += 1 ))
    name="${item:t}"
    [[ -n "${manifest[$name]-}" ]] || fail "unexpected snapshot entry: $name"
    [[ -f "$item" && ! -L "$item" ]] || fail "snapshot entry must be a regular non-symlink file: $name"
    actual_hash="$(/usr/bin/shasum -a 256 "$item" | /usr/bin/awk '{print $1}')"
    [[ "$actual_hash" == "${manifest[$name]}" ]] || fail "hash mismatch for $name"
  done < <(/usr/bin/find "$root" -mindepth 1 -maxdepth 1 -print0)

  (( actual_count == ${#manifest} )) || fail "snapshot has $actual_count entries; expected ${#manifest}"
  for name in "${(@k)manifest}"; do
    [[ -f "$root/$name" && ! -L "$root/$name" ]] || fail "required snapshot entry is missing or a symlink: $name"
  done
}

verify_snapshot "$source_root"
if [[ -e "$destination" && -L "$destination" ]]; then
  fail "destination must not be a symlink"
fi

/bin/mkdir -p "${destination:h}"
/usr/bin/rsync -a --delete "$source_root/" "$destination/"
verify_snapshot "$destination"

/bin/mkdir -p "${stamp:h}" "${receipt:h}"
typeset receipt_temporary="${receipt}.tmp.$$"
{
  print -r -- "schema=qwen3-decomposed-snapshot-receipt-v1"
  print -r -- "source=$source_root"
  print -r -- "destination=$destination"
  for name in "${(@ok)manifest}"; do
    print -r -- "$name ${manifest[$name]}"
  done
} > "$receipt_temporary"
/bin/mv -f "$receipt_temporary" "$receipt"
/usr/bin/touch "$stamp"
