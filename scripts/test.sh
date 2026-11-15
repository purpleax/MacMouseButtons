#!/bin/bash
# Runs the unit tests. With only the command line tools installed, SwiftPM
# can't find the Swift Testing macro plugin on its own, so point it there.
set -euo pipefail
cd "$(dirname "$0")/.."

PLUGINS="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [[ -d "$PLUGINS" ]]; then
    exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
fi
exec swift test "$@"
