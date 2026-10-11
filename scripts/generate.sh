#!/usr/bin/env bash
# Generate testdata/schema/* into tests/generated/.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "${root}"
# shellcheck disable=SC1091
source "${root}/scripts/swift-env.sh"
mkdir -p tests/generated
swift build --product gld-iongen-swift
binpath="$(swift build --product gld-iongen-swift --show-bin-path)"
shopt -s nullglob
for schema in testdata/schema/*.json testdata/schema/*.ion; do
  "${binpath}/gld-iongen-swift" --schema "${schema}" --out tests/generated
done
