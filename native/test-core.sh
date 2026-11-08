#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/Core"
# Prefer the standalone CLT so these tests do not need Xcode/iOS/signing.
# Global flags must also reach SwiftPM's generated test runner.
clt="/Library/Developer/CommandLineTools"
frameworks="$clt/Library/Developer/Frameworks"
if [[ -x "$clt/usr/bin/swift" && -d "$frameworks/Testing.framework" ]]; then
    export DEVELOPER_DIR="$clt"
    exec "$clt/usr/bin/swift" test --build-system native --disable-xctest \
        -Xswiftc -F -Xswiftc "$frameworks" \
        -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
        -Xlinker -rpath -Xlinker "$frameworks" "$@"
else
    exec swift test "$@"
fi
