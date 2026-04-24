#!/usr/bin/env bash
set -euo pipefail

CONF=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

APP_NAME=${APP_NAME:-MyApp}
BUNDLE_ID=${BUNDLE_ID:-com.example.myapp}
MACOS_MIN_VERSION=${MACOS_MIN_VERSION:-14.0}
MENU_BAR_APP=${MENU_BAR_APP:-0}
SIGNING_MODE=${SIGNING_MODE:-}
APP_IDENTITY=${APP_IDENTITY:-}
APP_OUTPUT_DIR=${APP_OUTPUT_DIR:-$ROOT/.build/packaged-apps}

if [[ -f "$ROOT/version.env" ]]; then
  source "$ROOT/version.env"
else
  MARKETING_VERSION=${MARKETING_VERSION:-0.1.0}
  BUILD_NUMBER=${BUILD_NUMBER:-1}
fi

ARCH_LIST=( ${ARCHES:-} )
if [[ ${#ARCH_LIST[@]} -eq 0 ]]; then
  HOST_ARCH=$(uname -m)
  ARCH_LIST=("$HOST_ARCH")
fi

XCODE_DEV_DIR=${XCODE_DEV_DIR:-/Applications/Xcode.app/Contents/Developer}
XCODE_TOOLCHAIN_DIR="$XCODE_DEV_DIR/Toolchains/XcodeDefault.xctoolchain"
XCODE_SDK_ROOT="$XCODE_DEV_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
XCODE_SWIFT_FRONTEND="$XCODE_TOOLCHAIN_DIR/usr/bin/swift-frontend"
APP_INTENTS_METADATA_PROCESSOR="$XCODE_TOOLCHAIN_DIR/usr/bin/appintentsmetadataprocessor"
APP_INTENTS_PROTOCOLS_SOURCE="$XCODE_TOOLCHAIN_DIR/usr/share/swift/SwiftConstantValues/AppIntents.json"
XCODE_VERSION_PLIST="$XCODE_DEV_DIR/../version.plist"

for ARCH in "${ARCH_LIST[@]}"; do
  swift build -c "$CONF" --arch "$ARCH"
done

APP="$APP_OUTPUT_DIR/${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

# Convert Icon.icon to Icon.icns if present (requires iconutil).
ICON_SOURCE="$ROOT/Icon.icon"
ICON_TARGET="$ROOT/Icon.icns"
if [[ -f "$ICON_SOURCE" ]]; then
  iconutil --convert icns --output "$ICON_TARGET" "$ICON_SOURCE"
fi

LSUI_VALUE="false"
if [[ "$MENU_BAR_APP" == "1" ]]; then
  LSUI_VALUE="true"
fi

BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
GIT_COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${MARKETING_VERSION}</string>
    <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key><string>${MACOS_MIN_VERSION}</string>
    <key>LSUIElement</key><${LSUI_VALUE}/>
    <key>NSSupportsAppShortcuts</key><true/>
    <key>CFBundleIconFile</key><string>Icon</string>
    <key>BuildTimestamp</key><string>${BUILD_TIMESTAMP}</string>
    <key>GitCommit</key><string>${GIT_COMMIT}</string>
</dict>
</plist>
PLIST

build_product_path() {
  local name="$1"
  local arch="$2"
  case "$arch" in
    arm64|x86_64) echo ".build/${arch}-apple-macosx/$CONF/$name" ;;
    *) echo ".build/$CONF/$name" ;;
  esac
}

verify_binary_arches() {
  local binary="$1"; shift
  local expected=("$@")
  local actual
  actual=$(lipo -archs "$binary")
  local actual_count expected_count
  actual_count=$(wc -w <<<"$actual" | tr -d ' ')
  expected_count=${#expected[@]}
  if [[ "$actual_count" -ne "$expected_count" ]]; then
    echo "ERROR: $binary arch mismatch (expected: ${expected[*]}, actual: ${actual})" >&2
    exit 1
  fi
  for arch in "${expected[@]}"; do
    if [[ "$actual" != *"$arch"* ]]; then
      echo "ERROR: $binary missing arch $arch (have: ${actual})" >&2
      exit 1
    fi
  done
}

install_binary() {
  local name="$1"
  local dest="$2"
  local binaries=()
  for arch in "${ARCH_LIST[@]}"; do
    local src
    src=$(build_product_path "$name" "$arch")
    if [[ ! -f "$src" ]]; then
      echo "ERROR: Missing ${name} build for ${arch} at ${src}" >&2
      exit 1
    fi
    binaries+=("$src")
  done
  if [[ ${#ARCH_LIST[@]} -gt 1 ]]; then
    lipo -create "${binaries[@]}" -output "$dest"
  else
    cp "${binaries[0]}" "$dest"
  fi
  chmod +x "$dest"
  verify_binary_arches "$dest" "${ARCH_LIST[@]}"
}

install_binary "$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

generate_app_intents_metadata() {
  local target_sources_dir="$ROOT/Sources/$APP_NAME"
  if [[ ! -d "$target_sources_dir" ]]; then
    return
  fi

  if [[ ! -x "$XCODE_SWIFT_FRONTEND" || ! -x "$APP_INTENTS_METADATA_PROCESSOR" ]]; then
    echo "warning: Xcode App Intents tools were not found; skipping Shortcuts metadata generation." >&2
    return
  fi

  if [[ ! -d "$XCODE_SDK_ROOT" || ! -f "$APP_INTENTS_PROTOCOLS_SOURCE" || ! -f "$XCODE_VERSION_PLIST" ]]; then
    echo "warning: Xcode SDK files are incomplete; skipping Shortcuts metadata generation." >&2
    return
  fi

  local xcode_build_version
  xcode_build_version=$(/usr/libexec/PlistBuddy -c 'Print :ProductBuildVersion' "$XCODE_VERSION_PLIST" 2>/dev/null || true)
  if [[ -z "$xcode_build_version" ]]; then
    echo "warning: Could not determine Xcode build version; skipping Shortcuts metadata generation." >&2
    return
  fi

  local module_name="${MODULE_NAME:-$APP_NAME}"
  local target_triple="${ARCH_LIST[0]}-apple-macos${MACOS_MIN_VERSION}"
  local work_dir="$ROOT/.build/appintents"
  local module_cache="$work_dir/module-cache"
  local const_values_dir="$work_dir/const-values"
  local metadata_output_dir="$work_dir/output"
  local protocols_json="$work_dir/protocols.json"
  local source_file_list="$work_dir/sources.txt"
  local const_values_list="$work_dir/const-values.txt"

  rm -rf "$work_dir"
  mkdir -p "$module_cache" "$const_values_dir" "$metadata_output_dir"

  plutil -extract constValueProtocols json -o "$protocols_json" "$APP_INTENTS_PROTOCOLS_SOURCE"

  local all_swift_sources=()
  while IFS= read -r source; do
    all_swift_sources+=("$source")
  done < <(find "$target_sources_dir" -name '*.swift' -print | sort)

  local app_intent_sources=()
  while IFS= read -r source; do
    app_intent_sources+=("$source")
  done < <(
    rg -l \
      "AppIntent|AppShortcutsProvider|AppEntity|AppEnum|DynamicOptionsProvider|EntityQuery|IntentValueQuery|AppIntentsPackage" \
      "$target_sources_dir" \
      --glob '*.swift' \
      | sort
  )

  if [[ ${#all_swift_sources[@]} -eq 0 || ${#app_intent_sources[@]} -eq 0 ]]; then
    return
  fi

  : > "$source_file_list"
  : > "$const_values_list"

  local primary_source other_sources const_values_path
  for primary_source in "${app_intent_sources[@]}"; do
    printf '%s\n' "$primary_source" >> "$source_file_list"
    const_values_path="$const_values_dir/$(basename "$primary_source").swiftconstvalues"

    other_sources=()
    local source
    for source in "${all_swift_sources[@]}"; do
      if [[ "$source" != "$primary_source" ]]; then
        other_sources+=("$source")
      fi
    done

    "$XCODE_SWIFT_FRONTEND" \
      -frontend \
      -typecheck \
      "${other_sources[@]}" \
      -primary-file "$primary_source" \
      -emit-const-values-path "$const_values_path" \
      -const-gather-protocols-file "$protocols_json" \
      -target "$target_triple" \
      -enable-objc-interop \
      -sdk "$XCODE_SDK_ROOT" \
      -module-cache-path "$module_cache" \
      -swift-version 6 \
      -module-name "$module_name" \
      -empty-abi-descriptor \
      -resource-dir "$XCODE_TOOLCHAIN_DIR/usr/lib/swift"

    printf '%s\n' "$const_values_path" >> "$const_values_list"
  done

  "$APP_INTENTS_METADATA_PROCESSOR" \
    --output "$metadata_output_dir" \
    --toolchain-dir "$XCODE_TOOLCHAIN_DIR" \
    --module-name "$module_name" \
    --sdk-root "$XCODE_SDK_ROOT" \
    --xcode-version "$xcode_build_version" \
    --platform-family macOS \
    --deployment-target "$MACOS_MIN_VERSION" \
    --target-triple "$target_triple" \
    --source-file-list "$source_file_list" \
    --swift-const-vals-list "$const_values_list"

  if [[ -d "$metadata_output_dir/Metadata.appintents" ]]; then
    rm -rf "$APP/Contents/Resources/Metadata.appintents"
    cp -R "$metadata_output_dir/Metadata.appintents" "$APP/Contents/Resources/"
  else
    echo "warning: App Intents metadata was not generated; Shortcuts actions may not appear." >&2
  fi
}

generate_app_intents_metadata

# Bundle app resources (if any).
APP_RESOURCES_DIR="$ROOT/Sources/$APP_NAME/Resources"
if [[ -d "$APP_RESOURCES_DIR" ]]; then
  cp -R "$APP_RESOURCES_DIR/." "$APP/Contents/Resources/"
fi

# SwiftPM resource bundles are emitted next to the built binary.
PREFERRED_BUILD_DIR="$(dirname "$(build_product_path "$APP_NAME" "${ARCH_LIST[0]}")")"
shopt -s nullglob
SWIFTPM_BUNDLES=("${PREFERRED_BUILD_DIR}/"*.bundle)
shopt -u nullglob
if [[ ${#SWIFTPM_BUNDLES[@]} -gt 0 ]]; then
  for bundle in "${SWIFTPM_BUNDLES[@]}"; do
    cp -R "$bundle" "$APP/Contents/Resources/"
  done
fi

# Embed frameworks if any exist in the build folder.
FRAMEWORK_DIRS=(".build/$CONF" ".build/${ARCH_LIST[0]}-apple-macosx/$CONF")
for dir in "${FRAMEWORK_DIRS[@]}"; do
  if compgen -G "${dir}/*.framework" >/dev/null; then
    cp -R "${dir}/"*.framework "$APP/Contents/Frameworks/"
    chmod -R a+rX "$APP/Contents/Frameworks"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/$APP_NAME"
    break
  fi
done

if [[ -f "$ICON_TARGET" ]]; then
  cp "$ICON_TARGET" "$APP/Contents/Resources/Icon.icns"
fi

# Ensure contents are writable before stripping attributes and signing.
chmod -R u+w "$APP"

# Strip extended attributes to prevent AppleDouble files that break code sealing.
xattr -cr "$APP"
find "$APP" -name '._*' -delete

ENTITLEMENTS_DIR="$ROOT/.build/entitlements"
DEFAULT_ENTITLEMENTS="$ENTITLEMENTS_DIR/${APP_NAME}.entitlements"
mkdir -p "$ENTITLEMENTS_DIR"

APP_ENTITLEMENTS=${APP_ENTITLEMENTS:-$DEFAULT_ENTITLEMENTS}
if [[ ! -f "$APP_ENTITLEMENTS" ]]; then
  cat > "$APP_ENTITLEMENTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Add entitlements here if needed. -->
</dict>
</plist>
PLIST
fi

if [[ "$SIGNING_MODE" == "adhoc" || -z "$APP_IDENTITY" ]]; then
  CODESIGN_ARGS=(--force --sign "-")
else
  CODESIGN_ARGS=(--force --timestamp --options runtime --sign "$APP_IDENTITY")
fi

# Sign embedded frameworks and their nested binaries before the app bundle.
sign_frameworks() {
  local fw
  for fw in "$APP/Contents/Frameworks/"*.framework; do
    if [[ ! -d "$fw" ]]; then
      continue
    fi
    while IFS= read -r -d '' bin; do
      codesign "${CODESIGN_ARGS[@]}" "$bin"
    done < <(find "$fw" -type f -perm -111 -print0)
    codesign "${CODESIGN_ARGS[@]}" "$fw"
  done
}
sign_frameworks

codesign "${CODESIGN_ARGS[@]}" \
  --entitlements "$APP_ENTITLEMENTS" \
  "$APP"

echo "Created $APP"
