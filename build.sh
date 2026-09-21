#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/build"
APP="$OUT/TouchBarChat.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"
CORE_OUT="$OUT/core"

SWIFTC="${SWIFTC:-/Library/Developer/CommandLineTools/usr/bin/swiftc}"
if [[ ! -x "$SWIFTC" ]]; then
  SWIFTC="$(command -v swiftc || true)"
fi
if [[ -z "$SWIFTC" || ! -x "$SWIFTC" ]]; then
  echo "error: swiftc not found. Install Xcode or Command Line Tools." >&2
  exit 1
fi

SDK="${SDK:-}"
if [[ -z "$SDK" ]]; then
  if [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk ]]; then
    SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
  else
    SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
  fi
fi
if [[ -z "$SDK" || ! -d "$SDK" ]]; then
  echo "error: macOS SDK not found. Set SDK=/path/to/MacOSX.sdk or install Command Line Tools." >&2
  exit 1
fi

TARGET="${TARGET:-arm64-apple-macos13.0}"

shopt -s nullglob
CORE_SWIFT=( "$ROOT/Sources/TouchBarChatCore/"*.swift )
APP_SWIFT=( "$ROOT/App/Sources/"*.swift )
if [[ ${#CORE_SWIFT[@]} -eq 0 ]]; then
  echo "error: no Sources/TouchBarChatCore/*.swift files found" >&2
  exit 1
fi
if [[ ${#APP_SWIFT[@]} -eq 0 ]]; then
  echo "error: no App/Sources/*.swift files found" >&2
  exit 1
fi

echo "==> Building TouchBarChatCore library"
echo "    swiftc: $SWIFTC"
echo "    sdk:    $SDK"
echo "    target: $TARGET"

rm -rf "$CORE_OUT"
mkdir -p "$CORE_OUT"

"$SWIFTC" \
  -sdk "$SDK" \
  -target "$TARGET" \
  -parse-as-library \
  -module-name TouchBarChatCore \
  -emit-module \
  -emit-module-path "$CORE_OUT/TouchBarChatCore.swiftmodule" \
  -emit-library \
  -o "$CORE_OUT/libTouchBarChatCore.a" \
  "${CORE_SWIFT[@]}"

echo "==> Building TouchBarChat.app"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"
cp "$ROOT/App/Resources/Info.plist" "$APP/Contents/Info.plist"

echo "==> Generating AppIcon.icns"
"$SWIFTC" -sdk "$SDK" -target "$TARGET" -framework AppKit -framework Foundation \
  -o "$OUT/generate-app-icon" "$ROOT/scripts/generate-app-icon.swift"
"$OUT/generate-app-icon" "$RES/AppIcon.icns"

"$SWIFTC" \
  -sdk "$SDK" \
  -target "$TARGET" \
  -import-objc-header "$ROOT/App/Sources/TouchBarPrivate.h" \
  -I "$CORE_OUT" \
  -L "$CORE_OUT" \
  -lTouchBarChatCore \
  -framework AppKit \
  -framework Foundation \
  -framework Security \
  -F/System/Library/PrivateFrameworks \
  -framework DFRFoundation \
  -o "$MACOS/TouchBarChat" \
  "${APP_SWIFT[@]}"

if ! codesign --force --deep --sign - "$APP"; then
  echo "error: codesign failed for $APP" >&2
  exit 1
fi

echo "==> Built $APP"
echo "    Run with:  open \"$APP\""
echo "    Test with: swift test"
echo "    Or:        \"$MACOS/TouchBarChat\""
