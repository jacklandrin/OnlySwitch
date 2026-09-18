#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  print -u2 "usage: $0 <version-file>"
  exit 64
fi

version_file=$1

if [[ ! -f "$version_file" ]]; then
  print -u2 "version file not found: $version_file"
  exit 66
fi

matches=(${(f)$(/usr/bin/awk '/^CURRENT_PROJECT_VERSION = [0-9]+$/ { print $3 }' "$version_file")})

if [[ ${#matches} -ne 1 ]]; then
  print -u2 "expected exactly one numeric CURRENT_PROJECT_VERSION in $version_file"
  exit 65
fi

next_version=$((matches[1] + 1))
file_mode=$(stat -f '%Lp' "$version_file")
temporary_file=$(mktemp "${version_file}.XXXXXX")
trap 'rm -f "$temporary_file"' EXIT

/usr/bin/awk -v next_version="$next_version" '
  /^CURRENT_PROJECT_VERSION = [0-9]+$/ {
    print "CURRENT_PROJECT_VERSION = " next_version
    next
  }
  { print }
' "$version_file" > "$temporary_file"

/bin/chmod "$file_mode" "$temporary_file"
/bin/mv "$temporary_file" "$version_file"
trap - EXIT

print "Bumped $(basename "$version_file") to $next_version"
