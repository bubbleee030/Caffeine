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
RULE=/etc/sudoers.d/caffeine-lid
LID_TEST_TOUCHED_SLEEP=0

# Prints "Yes" or "No": the SleepDisabled (pmset disablesleep) setting.
sleep_disabled_value() {
    ioreg -rn IOPMrootDomain -d 1 | awk -F'= ' '/"SleepDisabled"/ { print $2; exit }'
}

# Waits up to 30 s for SleepDisabled to equal $1 ("Yes"/"No").
wait_for_sleep_disabled() {
    local want="$1" elapsed=0
    while ((elapsed < 30)); do
        [[ "$(sleep_disabled_value)" == "$want" ]] && return 0
        sleep 1
        elapsed=$((elapsed + 1))
    done
    return 1
}

cleanup() {
    if [[ -n "$APP_PID" ]]; then
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    fi
    # Never leave the Mac unable to sleep because a check failed midway.
    if [[ "$LID_TEST_TOUCHED_SLEEP" == 1 && "$(sleep_disabled_value)" == "Yes" ]]; then
        sudo -n /usr/bin/pmset disablesleep 0 || echo "WARN: run 'sudo pmset disablesleep 0' manually"
    fi
}
trap cleanup EXIT

# Polls `pmset -g assertions` for up to ASSERTION_POLL_TIMEOUT seconds (default 30)
# until at least one assertion owned by the process under test ($APP_PID)
# appears, or fails. Returns the matched output on stdout. Filtering by PID
# keeps an installed copy of Caffeine that happens to be running (e.g. launched
# at login) from polluting the results.
poll_for_caffeine_assertions() {
    local timeout="${ASSERTION_POLL_TIMEOUT:-30}"
    local interval=1
    local elapsed=0
    local out=""
    while ((elapsed < timeout)); do
        out=$(pmset -g assertions | grep -E "pid ${APP_PID}\(Caffeine\)" || true)
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

run_lid_battery_cases() {
    if [[ ! -e "$RULE" ]]; then
        echo "==> SKIP lid-battery cases: $RULE not installed (enable closed-lid mode once in the app)"
        return 0
    fi
    if [[ "$(sleep_disabled_value)" == "Yes" ]]; then
        echo "==> SKIP lid-battery cases: SleepDisabled is already on (set by something else)"
        return 0
    fi
    LID_TEST_TOUCHED_SLEEP=1

    echo "==> Case: CA_TEST_AUTOACTIVATE=lid-battery (quit restores sleep)"
    CA_TEST_AUTOACTIVATE=lid-battery "$BINARY" &
    APP_PID=$!
    wait_for_sleep_disabled Yes || { echo "FAIL: SleepDisabled never turned on"; return 1; }
    echo "    ok: SleepDisabled on while active"
    kill "$APP_PID"
    wait "$APP_PID" 2>/dev/null || true
    APP_PID=""
    wait_for_sleep_disabled No || { echo "FAIL: SleepDisabled still on after SIGTERM"; return 1; }
    echo "    ok: SleepDisabled restored on termination"

    echo "==> Case: crash recovery (kill -9, relaunch restores sleep)"
    CA_TEST_AUTOACTIVATE=lid-battery "$BINARY" &
    APP_PID=$!
    wait_for_sleep_disabled Yes || { echo "FAIL: SleepDisabled never turned on"; return 1; }
    kill -9 "$APP_PID"
    wait "$APP_PID" 2>/dev/null || true
    APP_PID=""
    [[ "$(sleep_disabled_value)" == "Yes" ]] || { echo "FAIL: expected SleepDisabled to survive a crash"; return 1; }
    CA_TEST_AUTOACTIVATE=lid-open "$BINARY" &
    APP_PID=$!
    wait_for_sleep_disabled No || { echo "FAIL: relaunch did not restore SleepDisabled"; return 1; }
    echo "    ok: relaunch restored SleepDisabled after crash"
    kill "$APP_PID"
    wait "$APP_PID" 2>/dev/null || true
    APP_PID=""
}
run_lid_battery_cases

echo "==> Integration checks passed"
