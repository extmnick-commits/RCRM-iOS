#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
check_dir="$(mktemp -d "${TMPDIR:-/tmp}/rcrm-step2.XXXXXX")"
trap 'rm -rf "$check_dir"' EXIT
# Compile the app's Foundation-only domain declarations directly, without Firebase
# credentials or a separate copy of the implementation.
python3 - "$project_dir" "$check_dir/main.swift" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
source = (root / 'RCRM/RCRMApp.swift').read_text()
domain = source[source.index('enum PipelineType:'):source.index('struct Lead: Identifiable')]
tests = (root / 'Tests/Step2DomainChecks.swift').read_text()
Path(sys.argv[2]).write_text('import Foundation\n' + domain + '\n' + tests)
PY
if [[ "${1:-}" == "--simulator" && -n "${2:-}" ]]; then
    simulator_id="$2"
    simulator_arch="$(uname -m)"
    simulator_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
    xcrun --sdk iphonesimulator swiftc -sdk "$simulator_sdk" -target "$simulator_arch-apple-ios17.0-simulator" \
        -module-cache-path "$check_dir/cache" "$check_dir/main.swift" -o "$check_dir/Step2DomainChecks"
    xcrun simctl spawn "$simulator_id" "$check_dir/Step2DomainChecks"
elif [[ $# -eq 0 ]]; then
    swift -module-cache-path "$check_dir/cache" "$check_dir/main.swift"
else
    echo "Usage: bash Tests/run-step2-checks.sh [--simulator <booted-device-UDID>]" >&2
    exit 2
fi
