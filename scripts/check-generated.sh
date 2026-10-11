#!/usr/bin/env bash
# Regenerate into a temp directory and diff against tests/generated.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "${root}"
# shellcheck disable=SC1091
source "${root}/scripts/swift-env.sh"
swift build --product gld-iongen-swift
binpath="$(swift build --product gld-iongen-swift --show-bin-path)"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
shopt -s nullglob
for schema in testdata/schema/*.json testdata/schema/*.ion; do
  "${binpath}/gld-iongen-swift" --schema "${schema}" --out "${tmp}"
done
diff -ru tests/generated "${tmp}"
