#!/usr/bin/env bash
set -euo pipefail

experiment_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$experiment_root"
export MACOSX_DEPLOYMENT_TARGET=14.0

swift build --configuration release
binary_path="$(swift build --configuration release --show-bin-path)"
apps_path="$experiment_root/.build/apps"
install_destination="${SENSVEIL_INSTALL_DESTINATION:-/Applications/Sensveil.app}"

signing_identity="${SENSVEIL_SIGNING_IDENTITY:--}"

if [[ "$signing_identity" == "-" ]]; then
    printf 'Using ad-hoc signing for local development. Rebuilds may require Accessibility permission again.\n' >&2
else
    printf 'Using the explicitly supplied signing identity; no fallback will be attempted.\n'
fi
mkdir -p "$apps_path"
iconset_path="$experiment_root/.build/Sensveil.iconset"
swift "$experiment_root/scripts/build-icon.swift" "$iconset_path"
iconutil --convert icns --output "$experiment_root/.build/Sensveil.icns" "$iconset_path"

for name in Sensveil SensveilPoC SensveilFixture; do
    app_path="$apps_path/$name.app"
    mkdir -p "$app_path/Contents/MacOS"
    cp "$experiment_root/Resources/$name-Info.plist" "$app_path/Contents/Info.plist"
    binary_name="$name"
    if [[ "$name" == Sensveil ]]; then binary_name=SensveilApp; fi
    cp "$binary_path/$binary_name" "$app_path/Contents/MacOS/$name"
    if [[ "$name" == Sensveil ]]; then
        mkdir -p "$app_path/Contents/Resources"
        cp "$experiment_root/.build/Sensveil.icns" "$app_path/Contents/Resources/Sensveil.icns"
    fi
    chmod +x "$app_path/Contents/MacOS/$name"
    plutil -lint "$app_path/Contents/Info.plist"
    codesign --force --sign "$signing_identity" "$app_path"
    codesign --verify --strict --verbose=2 "$app_path"
    printf 'Built %s\n' "$app_path"
done

if [[ "${SENSVEIL_INSTALL:-1}" == "1" ]]; then
    fail() { printf 'Installation stopped: %s\n' "$1" >&2; exit 1; }
    is_product() {
        [[ -d "$1" && ! -L "$1" && -f "$1/Contents/Info.plist" && ! -L "$1/Contents/Info.plist" ]] \
            && [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$1/Contents/Info.plist" 2>/dev/null)" == com.nieanshow.sensveil ]] \
            && [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$1/Contents/Info.plist" 2>/dev/null)" == Sensveil ]] \
            && [[ -f "$1/Contents/MacOS/Sensveil" && -x "$1/Contents/MacOS/Sensveil" && ! -L "$1/Contents/MacOS/Sensveil" ]]
    }
    assess() {
        local assessment
        if assessment="$(spctl --assess --type execute --verbose=4 "$1" 2>&1)"; then
            return 0
        fi
        if [[ "$assessment" == *CSSMERR_TP_CERT_REVOKED* || "$assessment" == *"certificate revoked"* ]]; then
            printf 'The signing certificate is revoked. Choose a valid, authorized identity; no fallback was used.\n' >&2
        else
            printf 'macOS rejected execution. Installation will not alter system security settings.\n' >&2
        fi
        return 1
    }
    product_pids() {
        local process_id command_path
        while read -r process_id command_path; do
            if [[ "$command_path" == "$install_destination/Contents/MacOS/Sensveil" ]]; then
                printf '%s\n' "$process_id"
            fi
        done < <(ps -axo pid=,comm=)
    }
    stop_product() {
        local process_id attempt
        while read -r process_id; do
            [[ -n "$process_id" ]] || continue
            kill -TERM "$process_id" 2>/dev/null || true
        done < <(product_pids)
        for attempt in {1..30}; do
            [[ -n "$(product_pids)" ]] || return 0
            sleep 0.1
        done
        return 1
    }

    [[ "$install_destination" == /* && "$(basename -- "$install_destination")" == Sensveil.app ]] \
        || fail 'Destination must be an absolute path ending in Sensveil.app.'
    [[ ! -L "$install_destination" ]] || fail 'Destination must not be a symbolic link.'
    install_parent="$(dirname -- "$install_destination")"
    [[ -d "$install_parent" && ! -L "$install_parent" ]] || fail 'Destination parent must be an existing, non-symlink directory.'
    install_parent="$(cd -- "$install_parent" && pwd -P)"
    install_destination="$install_parent/Sensveil.app"
    [[ ! -L "$install_destination" ]] || fail 'Destination must not be a symbolic link.'
    if [[ -e "$install_destination" ]]; then
        is_product "$install_destination" || fail 'Existing destination is not a Sensveil product bundle.'
    fi

    is_product "$apps_path/Sensveil.app" || fail 'Built product identity is invalid.'
    assess "$apps_path/Sensveil.app" || fail 'Built product did not pass macOS execution assessment.'
    staging_parent="$(mktemp -d "$install_parent/.sensveil-install.XXXXXX")"
    replacement_installed=0
    installation_complete=0
    rollback() {
        local result=$?
        trap - EXIT
        if [[ "$installation_complete" == 0 ]]; then
            if [[ "$replacement_installed" == 1 && -e "$install_destination" ]]; then
                if ! stop_product; then
                    printf 'Could not stop replacement; recovery files retained at %s\n' "$staging_parent" >&2
                    exit 1
                fi
                mv "$install_destination" "$staging_parent/failed.app" || exit 1
            fi
            if [[ -d "$staging_parent/previous.app" ]]; then
                mv "$staging_parent/previous.app" "$install_destination" || exit 1
                if [[ "$previous_was_running" == 1 ]]; then open "$install_destination" || true; fi
                printf 'Restored the previous Sensveil application.\n' >&2
            fi
        fi
        # This directory was created by mktemp, never supplied as a deletion target.
        rm -rf -- "$staging_parent"
        exit "$result"
    }
    previous_was_running=0
    trap rollback EXIT
    ditto "$apps_path/Sensveil.app" "$staging_parent/Sensveil.app"
    codesign --verify --strict "$staging_parent/Sensveil.app"
    [[ -z "$(product_pids)" ]] || previous_was_running=1
    stop_product || fail 'Current Sensveil did not exit; existing installation was kept.'
    if [[ -e "$install_destination" ]]; then mv "$install_destination" "$staging_parent/previous.app"; fi
    mv "$staging_parent/Sensveil.app" "$install_destination"
    replacement_installed=1
    codesign --verify --strict "$install_destination"
    assess "$install_destination" || fail 'Installed product did not pass macOS execution assessment.'
    printf 'Installed %s\n' "$install_destination"
    open -n "$install_destination" || fail 'macOS could not launch Sensveil.'
    launch_verified=0
    for attempt in {1..30}; do
        if [[ -n "$(product_pids)" ]]; then
            sleep 1
            if [[ -n "$(product_pids)" ]]; then launch_verified=1; break; fi
        fi
        sleep 0.1
    done
    [[ "$launch_verified" == 1 ]] || fail 'Sensveil did not remain running after launch.'
    installation_complete=1
    printf 'Launched %s\n' "$install_destination"
else
    printf 'Installation skipped (SENSVEIL_INSTALL=%s).\n' "${SENSVEIL_INSTALL:-1}"
fi
