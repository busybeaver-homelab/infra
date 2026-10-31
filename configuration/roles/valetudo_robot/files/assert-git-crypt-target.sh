#!/usr/bin/env bash
# Refuses to let robot calibration/identity data be written anywhere that is
# not git-crypt protected in an unlocked checkout.
#
# Usage: assert-git-crypt-target.sh <repo_root> <target_rel_path>
#
# Exits 0 only if both hold:
#   - <git-dir>/git-crypt/keys holds a key. The per-worktree git dir is checked
#     (not --git-common-dir) because that is where git-crypt reads its key: a
#     worktree created without the git-crypt symlink would commit plaintext.
#   - `git check-attr filter -- <target>` reports `filter: git-crypt`.
# Otherwise exits 1 (2 on wrong usage).

set -euo pipefail

if (($# != 2)); then
  printf 'usage: %s <repo_root> <target_rel_path>\n' "${0##*/}" >&2
  exit 2
fi

repo_root="$1"
target="$2"

refuse() {
  printf 'ERROR: %s is not git-crypt protected or the repository is locked; refusing to write calibration data\n' \
    "${target}" >&2
  exit 1
}

# The target must stay inside the repository.
case "/${target}/" in
  //* | */../*) refuse ;;
esac

git_dir="$(git -C "${repo_root}" rev-parse --git-dir 2>/dev/null)" || refuse
case "${git_dir}" in
  /*) ;;
  *) git_dir="${repo_root}/${git_dir}" ;;
esac

keys_dir="${git_dir}/git-crypt/keys"
[[ -d "${keys_dir}" ]] || refuse
# A locked repository may keep an empty keys directory; require a key file.
key_found=0
for key in "${keys_dir}"/*; do
  if [[ -f "${key}" ]]; then
    key_found=1
    break
  fi
done
((key_found == 1)) || refuse

# -z output: <path> NUL <attribute> NUL <value> NUL
attr_fields=()
while IFS= read -r -d '' field; do
  attr_fields+=("${field}")
done < <(git -C "${repo_root}" check-attr -z filter -- "${target}" 2>/dev/null)

if ((${#attr_fields[@]} != 3)) || [[ "${attr_fields[1]}" != filter || "${attr_fields[2]}" != git-crypt ]]; then
  refuse
fi
