#!/usr/bin/env bash
set -eo pipefail
source "$(dirname "$0")/../scripts/image_changed.sh"

inspect_manifest() {
    case "$1" in
        source:latest)
            if [[ "$scenario" == single ]]; then
                echo '{"config":{"digest":"config"},"layers":[{"digest":"layer"}]}'
            else
                echo '{"manifests":[{"digest":"source","platform":{"os":"linux","architecture":"amd64","variant":"v1"}}]}'
            fi ;;
        target:latest)
            case "$scenario" in
                missing) echo 'manifest unknown' >&2; return 1 ;;
                auth) echo 'unauthorized' >&2; return 1 ;;
                network) echo 'connection refused' >&2; return 1 ;;
                timeout) echo 'request timed out' >&2; return 124 ;;
                target_single) echo '{"config":{"digest":"config"},"layers":[{"digest":"layer"}]}' ;;
                *) echo '{"manifests":[{"digest":"target","platform":{"os":"linux","architecture":"amd64"}}]}' ;;
            esac ;;
        source:latest@source)
            echo '{"config":{"digest":"config"},"layers":[{"digest":"layer"}]}' ;;
        target:latest@target)
            case "$scenario" in
                config) echo '{"config":{"digest":"changed"},"layers":[{"digest":"layer"}]}' ;;
                layers) echo '{"config":{"digest":"config"},"layers":[{"digest":"changed"}]}' ;;
                *) echo '{"config":{"digest":"config"},"layers":[{"digest":"layer"}]}' ;;
            esac ;;
        *) echo "Unexpected reference: $1" >&2; return 1 ;;
    esac
}

check() {
    local scenario="$1" expected="$2" actual=0
    image_changed source:latest target:latest linux/amd64 || actual=$?
    if [[ "$actual" -ne "$expected" ]]; then
        echo "FAIL: $scenario expected $expected, got $actual" >&2
        exit 1
    fi
    echo "PASS: $scenario"
}

check unchanged 0
check config 1
check layers 1
check missing 1
check auth 2
check network 2
check single 0
check target_single 0
check timeout 2

# Exercise the real inspection wrapper: diagnostic logs must not enter JSON.
source "$(dirname "$0")/../scripts/image_changed.sh"
timeout() {
    shift 2
    "$@"
}
docker() {
    echo '{"config":{"digest":"config"},"layers":[{"digest":"layer"}]}'
}
check wrapper_json 0
