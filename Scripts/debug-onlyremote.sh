#!/bin/zsh
# Build OnlyRemote (Debug), install it on a simulator or device, launch it,
# and attach its console output.
#
# usage: Scripts/debug-onlyremote.sh [--device <name|udid>] [--simulator <name|udid>] [--no-build]
#   --simulator  simulator to use (default: "iPhone 17 Pro")
#   --device     paired physical iPhone/iPad instead of a simulator
#   --no-build   reuse the last Debug build

set -euo pipefail

repo=${0:A:h:h}
derived_data=${DERIVED_DATA:-$repo/build/DerivedData}
bundle_id=jacklandrin.OnlySwitchRemote

simulator="iPhone 17 Pro"
device=""
build=true
while (( $# )); do
  case $1 in
    --simulator) simulator=${2:?missing simulator}; shift 2 ;;
    --device) device=${2:?missing device}; shift 2 ;;
    --no-build) build=false; shift ;;
    *) print -u2 "usage: $0 [--device <name|udid>] [--simulator <name|udid>] [--no-build]"; exit 64 ;;
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

build_remote() {
  local destination=$1
  xcodebuild \
    -project "$repo/OnlySwitch.xcodeproj" \
    -scheme OnlySwitchRemote \
    -configuration Debug \
    -destination "$destination" \
    -derivedDataPath "$derived_data" \
    -allowProvisioningUpdates \
    build | format_build_output
}

if [[ -n $device ]]; then
  app="$derived_data/Build/Products/Debug-iphoneos/OnlySwitchRemote.app"
  if $build; then
    build_remote "generic/platform=iOS"
  fi
  [[ -d $app ]] || { print -u2 "app not found: $app"; exit 66 }

  xcrun devicectl device install app --device "$device" "$app"
  print "Launching on $device — console attached (Ctrl-C to stop)"
  exec xcrun devicectl device process launch \
    --device "$device" --terminate-existing --console "$bundle_id"
fi

app="$derived_data/Build/Products/Debug-iphonesimulator/OnlySwitchRemote.app"

# Resolve a simulator name to a UDID, preferring the newest iOS runtime that has it.
if [[ ! $simulator =~ '^[0-9A-Fa-f-]{36}$' ]]; then
  name=$simulator
  simulator=$(xcrun simctl list devices available -j | python3 -I -c '
import json, re, sys
name = sys.argv[1]
runtimes = json.load(sys.stdin)["devices"]
def version(runtime):
    # e.g. "...SimRuntime.iOS-27-2" or "...SimRuntime.iOS-27-2-iPhone19-4"
    return [int(p) for p in re.match(r"(\d+(?:-\d+)*)", runtime.split(".iOS-", 1)[1]).group(1).split("-")]
ios = sorted((r for r in runtimes if ".iOS-" in r), key=version, reverse=True)
print(next((d["udid"] for r in ios for d in runtimes[r] if d["name"] == name), ""))
' "$name")
  [[ -n $simulator ]] || { print -u2 "no available iOS simulator named: $name"; exit 66 }
fi

# Boot the simulator if needed; "already booted" is not an error.
xcrun simctl boot "$simulator" 2>/dev/null || true
# Show the Simulator window when that app is installed; the simulator runs headless otherwise.
open -b com.apple.iphonesimulator 2>/dev/null || true

if $build; then
  build_remote "platform=iOS Simulator,id=$simulator"
fi
[[ -d $app ]] || { print -u2 "app not found: $app"; exit 66 }

xcrun simctl install "$simulator" "$app"
print "Launching on ${name:-$simulator} ($simulator) — console attached (Ctrl-C to stop)"
exec xcrun simctl launch --console-pty --terminate-running-process "$simulator" "$bundle_id"
