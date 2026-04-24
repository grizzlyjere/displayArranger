#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="${APP_NAME:-DisplayArranger}"
BUNDLE_ID="${BUNDLE_ID:-com.jeremy.displayarranger}"
DESTINATION="${DESTINATION:-/Applications/${APP_NAME}.app}"
APP_OUTPUT_DIR="${APP_OUTPUT_DIR:-$ROOT/.build/packaged-apps}"

cd "$ROOT"

bundle_id_for_app() {
  local app_path="$1"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist" 2>/dev/null || true
}

metadata_status_for_app() {
  local app_path="$1"
  if [[ -d "$app_path/Contents/Resources/Metadata.appintents" ]]; then
    echo "present"
  else
    echo "missing"
  fi
}

warn_about_duplicate_installs() {
  local chosen_destination="$1"
  local candidate
  local found_conflict=0

  for candidate in "/Applications/${APP_NAME}.app" "$HOME/Applications/${APP_NAME}.app"; do
    if [[ "$candidate" == "$chosen_destination" || ! -d "$candidate" ]]; then
      continue
    fi

    if [[ "$(bundle_id_for_app "$candidate")" != "$BUNDLE_ID" ]]; then
      continue
    fi

    found_conflict=1
    echo "warning: Found another installed copy at ${candidate}" >&2
    echo "warning: Its App Intents metadata is $(metadata_status_for_app "$candidate")." >&2
  done

  if [[ "$found_conflict" == "1" ]]; then
    echo "warning: Multiple installed copies with bundle ID ${BUNDLE_ID} can prevent Shortcuts from discovering the newest build." >&2
    echo "warning: Remove the older copy, then launch the app again and reopen Shortcuts." >&2
  fi
}

if [[ "$DESTINATION" == /Applications/* ]]; then
  if [[ -e "$DESTINATION" && ! -w "$DESTINATION" ]]; then
    DESTINATION="$HOME/Applications/${APP_NAME}.app"
  elif [[ ! -w "/Applications" ]]; then
    DESTINATION="$HOME/Applications/${APP_NAME}.app"
  fi
fi

mkdir -p "$(dirname "$DESTINATION")"

echo "==> Packaging ${APP_NAME}.app"
SIGNING_MODE=adhoc APP_NAME="$APP_NAME" BUNDLE_ID="$BUNDLE_ID" APP_OUTPUT_DIR="$APP_OUTPUT_DIR" "$ROOT/Scripts/package_app.sh" release

echo "==> Installing to ${DESTINATION}"
rm -rf "$DESTINATION"
cp -R "$APP_OUTPUT_DIR/${APP_NAME}.app" "$DESTINATION"

if [[ -d "$DESTINATION/Contents/Resources/Metadata.appintents" ]]; then
  echo "==> App Intents metadata bundled successfully"
else
  echo "warning: ${APP_NAME}.app was installed without Metadata.appintents; Shortcuts actions will not appear." >&2
fi

warn_about_duplicate_installs "$DESTINATION"

echo "==> Launching ${APP_NAME}"
open "$DESTINATION"

cat <<EOF

Installed:
  $DESTINATION

In macOS Shortcuts, create a new shortcut and search for:
  - Export Display Layout
  - Apply Display Layout
  - DisplayArranger

If the actions do not appear right away:
  1. Quit Shortcuts.
  2. Launch ${APP_NAME} once from $(dirname "$DESTINATION").
  3. Reopen Shortcuts and search again.

If you see a Metadata.appintents warning above, rebuild after installing Xcode and/or pointing the build at /Applications/Xcode.app/Contents/Developer.
EOF
