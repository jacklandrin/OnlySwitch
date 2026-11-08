#!/bin/zsh
# Build OnlySwitch (Debug), relaunch it, and stream its logs or attach LLDB.
#
# usage: Scripts/debug-onlyswitch.sh [--lldb] [--no-build]
#   --lldb      launch under LLDB instead of streaming logs
#   --no-build  reuse the last Debug build

set -euo pipefail

repo=${0:A:h:h}
derived_data=${DERIVED_DATA:-$repo/build/DerivedData}
app="$derived_data/Build/Products/Debug/OnlySwitch.app"

use_lldb=false
build=true
for arg in "$@"; do
  case $arg in
    --lldb) use_lldb=true ;;
    --no-build) build=false ;;
    *) print -u2 "usage: $0 [--lldb] [--no-build]"; exit 64 ;;
  esac
done

# xcbeautify is optional; without it, show only errors and the result line.
format_build_output() {
  if command -v xcbeautify >/dev/null; then
    xcbeautify
  else
    grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true
  fi
}

if $build; then
  xcodebuild \
    -project "$repo/OnlySwitch.xcodeproj" \
    -scheme OnlySwitch \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data" \
    build | format_build_output
fi

if [[ ! -d "$app" ]]; then
  print -u2 "app not found: $app"
  exit 66
fi

# Only one menu-bar instance should run at a time.
pkill -x OnlySwitch 2>/dev/null && sleep 1 || true

if $use_lldb; then
  exec lldb -o run "$app/Contents/MacOS/OnlySwitch"
fi

open "$app"
print "Launched $app — streaming logs (Ctrl-C to stop)"
exec log stream --level debug --style compact --predicate 'process == "OnlySwitch"'
