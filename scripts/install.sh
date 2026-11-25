#!/bin/sh
# Builds Quaterm (Release) and installs it into /Applications.
# A locally built app is not quarantined, so it runs without Apple notarization.
# Usage: ./scripts/install.sh        (INSTALL_DIR=/path overrides /Applications)
set -eu
cd "$(dirname "$0")/.."
dest="${INSTALL_DIR:-/Applications}"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: xcodegen not found. Install it with: brew install xcodegen" >&2
    exit 1
fi

# xcodebuild needs a full Xcode, not the Command Line Tools.
if [ -z "${DEVELOPER_DIR:-}" ] && ! xcodebuild -version >/dev/null 2>&1; then
    # Pick the newest installed Xcode by version, not by name.
    newest=$(for app in /Applications/Xcode*.app; do
        if [ -x "$app/Contents/Developer/usr/bin/xcodebuild" ]; then
            printf '%s\t%s\n' "$(defaults read "$app/Contents/Info" CFBundleShortVersionString)" "$app"
        fi
    done | sort -V | tail -1 | cut -f2)
    if [ -n "$newest" ]; then
        DEVELOPER_DIR="$newest/Contents/Developer"
    fi
    if [ -z "${DEVELOPER_DIR:-}" ]; then
        echo "error: Xcode not found in /Applications. Install Xcode 26 or later." >&2
        exit 1
    fi
    export DEVELOPER_DIR
    echo "Using $DEVELOPER_DIR"
fi

xcodegen generate --quiet
xcodebuild -project Quaterm.xcodeproj -scheme Quaterm -configuration Release \
    -derivedDataPath build -destination 'platform=macOS' -quiet build

# Copy next to the old app first, so a failed copy leaves the installed one intact.
rm -rf "$dest/Quaterm.app.new"
ditto build/Build/Products/Release/Quaterm.app "$dest/Quaterm.app.new"
rm -rf "$dest/Quaterm.app"
mv "$dest/Quaterm.app.new" "$dest/Quaterm.app"
# Refresh the Finder / Dock icon cache for the new copy. ditto keeps the build's date on the
# bundle, and macOS keeps showing the old icon unless the date changes.
touch "$dest/Quaterm.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$dest/Quaterm.app"

echo "Installed $dest/Quaterm.app"
if pgrep -xq Quaterm; then
    echo "Quaterm is running the old build. Quit it and open it again."
fi
