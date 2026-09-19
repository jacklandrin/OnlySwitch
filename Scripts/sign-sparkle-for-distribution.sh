#!/bin/sh

# Sparkle contains nested XPC services and helper executables. When the app is
# packaged outside Xcode's Archive-and-Export workflow, those nested items can
# retain their upstream or development signatures. Re-sign them from the
# inside out with the same Developer ID identity used for the application.

set -eu

if [ "${CODE_SIGNING_ALLOWED:-NO}" != "YES" ] || [ -z "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
    exit 0
fi

sparkle_framework="${TARGET_BUILD_DIR}/${WRAPPER_NAME}/Contents/Frameworks/Sparkle.framework"

if [ ! -d "$sparkle_framework" ]; then
    exit 0
fi

sign() {
    /usr/bin/codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --options runtime --timestamp "$@"
}

sign "$sparkle_framework/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$sparkle_framework/Versions/B/XPCServices/Downloader.xpc"
sign "$sparkle_framework/Versions/B/Autoupdate"
sign "$sparkle_framework/Versions/B/Updater.app"
sign "$sparkle_framework"
