#!/usr/bin/env bash
#
# Resets Caffeine to a fresh-install state for development: quits the app and
# removes its preferences, sandbox container and privacy (TCC) grants.
# The "Launch at Login" item can't be removed from a script — toggle it off in
# the app first, or remove it in System Settings > General > Login Items.
#

set -uo pipefail

BUNDLE_ID="net.domzilla.caffeine"

echo "==> Quitting Caffeine"
osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
pkill -x Caffeine 2>/dev/null || true

echo "==> Removing preferences"
defaults delete "$BUNDLE_ID" 2>/dev/null || true
rm -rf "$HOME/Library/Containers/$BUNDLE_ID"

echo "==> Resetting privacy permissions"
tccutil reset All "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "==> Done"
