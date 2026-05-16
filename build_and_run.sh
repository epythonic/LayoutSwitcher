#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="$SCRIPT_DIR/LayoutSwitcher.xcodeproj"
SCHEME="LayoutSwitcher"
DERIVED_DATA_PATH="/private/tmp/layoutswitcher-build-and-run-dd"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/LayoutSwitcher.app"
BUNDLE_ID="GM.LayoutSwitcher"

echo "Cleaning previous fresh-build artifacts..."
rm -rf "$DERIVED_DATA_PATH"

echo "Building $SCHEME from source..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -destination "platform=macOS" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -skipPackagePluginValidation \
  clean build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build succeeded, but app bundle was not found at: $APP_PATH" >&2
  exit 1
fi

echo "Stopping any running LayoutSwitcher instance..."
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
sleep 1

if pgrep -x "$SCHEME" >/dev/null 2>&1; then
  pkill -x "$SCHEME" || true
  sleep 1
fi

echo "Launching fresh app bundle: $APP_PATH"
open "$APP_PATH"

echo "Done."
