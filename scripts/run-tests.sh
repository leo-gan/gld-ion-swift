#!/usr/bin/env bash
# Unit tests, then the vendored ion-tests corpus.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "${root}"
# shellcheck disable=SC1091
source "${root}/scripts/swift-env.sh"

swift test
swift build --product ion-suite
binpath="$(swift build --product ion-suite --show-bin-path)"
"${binpath}/ion-suite" --all
echo "all test files passed"
