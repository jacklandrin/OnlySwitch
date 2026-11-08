#!/bin/zsh
# Fails when an Xcode target folder contains source code beyond its entry point.
# All code belongs in the Modules package (see ARCHITECTURE.md, "Thin app targets").
set -euo pipefail
repo=${0:A:h:h}
allowed=(
  "OnlySwitch/main.swift"
  "OnlySwitchRemote/App/OnlySwitchRemoteApp.swift"
  "OnlyWidget/OnlyWidgetBundle.swift"
  "OnlySwitchPrivilegedHelper/main.swift"
)
violations=()
for dir in OnlySwitch OnlySwitchRemote OnlyWidget OnlySwitchPrivilegedHelper; do
  while IFS= read -r file; do
    rel=${file#$repo/}
    (( ${allowed[(Ie)$rel]} )) || violations+=("$rel")
  done < <(find "$repo/$dir" -type f \( -name '*.swift' -o -name '*.m' -o -name '*.mm' -o -name '*.c' -o -name '*.h' \))
done
if (( ${#violations} )); then
  print -u2 "Source files found in thin targets; move them into Modules/:"
  printf '  %s\n' "${violations[@]}" >&2
  exit 1
fi
print "Thin targets OK"
