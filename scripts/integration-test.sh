#!/usr/bin/env bash
# Integration smoke test: build Caffeine.app, run it briefly with a debug
# auto-activate env var, and verify that `pmset -g assertions` reflects the
# expected IOPMAssertion types. Exits non-zero on any mismatch.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DERIVED="${DERIVED:-/tmp/caffeine-derived}"
APP="$DERIVED/Build/Products/Debug/Caffeine.app"
BINARY="$APP/Contents/MacOS/Caffeine"

echo "==> Building Caffeine.app (Debug)"
xcodebuild \
    -project src/Caffeine.xcodeproj \
    -scheme Caffeine \
    -destination 'platform=macOS' \
    -configuration Debug \
    -derivedDataPath "$DERIVED" \
    build CODE_SIGNING_ALLOWED=NO > /tmp/caffeine-xcodebuild.log

if [[ ! -x "$BINARY" ]]; then
    echo "FAIL: built binary not found at $BINARY"
    tail -50 /tmp/caffeine-xcodebuild.log
    exit 1
fi

APP_PID=""
cleanup() {
    if [[ -n "$APP_PID" ]]; then
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    fi
    pkill -f "Caffeine.app/Contents/MacOS/Caffeine" 2>/dev/null || true
}
trap cleanup EXIT

# Polls `pmset -g assertions` for up to ASSERTION_POLL_TIMEOUT seconds (default 30)
# until at least one Caffeine-owned assertion appears, or fails. Returns the
# matched output on stdout.
poll_for_caffeine_assertions() {
    local timeout="${ASSERTION_POLL_TIMEOUT:-30}"
    local interval=1
    local elapsed=0
    local out=""
    while ((elapsed < timeout)); do
        out=$(pmset -g assertions | grep -E "\(Caffeine\)" || true)
        if [[ -n "$out" ]]; then
            printf '%s\n' "$out"
            return 0
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
    return 1
}

run_case() {
    local mode="$1"
    local expect_present="$2"
    local expect_absent="${3:-}"

    echo "==> Case: CA_TEST_AUTOACTIVATE=$mode"
    CA_TEST_AUTOACTIVATE="$mode" "$BINARY" &
    APP_PID=$!

    local out
    if ! out=$(poll_for_caffeine_assertions); then
        echo "FAIL: no Caffeine-owned assertions appeared within ${ASSERTION_POLL_TIMEOUT:-30}s"
        pmset -g assertions | tail -50
        return 1
    fi

    for needle in $expect_present; do
        if ! echo "$out" | grep -q "$needle"; then
            echo "FAIL: expected assertion type '$needle' not present"
            echo "$out"
            return 1
        fi
        echo "    ok: held $needle"
    done

    if [[ -n "$expect_absent" ]]; then
        if echo "$out" | grep -q "$expect_absent"; then
            echo "FAIL: assertion type '$expect_absent' should not be present"
            echo "$out"
            return 1
        fi
        echo "    ok: not holding $expect_absent"
    fi

    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
    APP_PID=""
}

run_case "lid-closed" "PreventUserIdleDisplaySleep PreventUserIdleSystemSleep PreventSystemSleep"
run_case "lid-open"   "PreventUserIdleDisplaySleep PreventUserIdleSystemSleep" "PreventSystemSleep"

echo "==> Integration checks passed"
