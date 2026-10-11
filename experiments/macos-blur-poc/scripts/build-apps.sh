#!/usr/bin/env bash
set -euo pipefail

experiment_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$experiment_root"
export MACOSX_DEPLOYMENT_TARGET=14.0

swift build --configuration release
binary_path="$(swift build --configuration release --show-bin-path)"
apps_path="$experiment_root/.build/apps"
signing_identity="${SENSVEIL_SIGNING_IDENTITY:--}"
mkdir -p "$apps_path"

for name in SensveilPoC SensveilFixture; do
    app_path="$apps_path/$name.app"
    mkdir -p "$app_path/Contents/MacOS"
    cp "$experiment_root/Resources/$name-Info.plist" "$app_path/Contents/Info.plist"
    cp "$binary_path/$name" "$app_path/Contents/MacOS/$name"
    chmod +x "$app_path/Contents/MacOS/$name"
    plutil -lint "$app_path/Contents/Info.plist"
    codesign --force --sign "$signing_identity" "$app_path"
    codesign --verify --strict --verbose=2 "$app_path"
    printf 'Built %s\n' "$app_path"
done
