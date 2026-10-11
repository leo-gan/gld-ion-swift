#!/usr/bin/env bash
# Install Swift 6.3.3 on Ubuntu when it is not already on PATH.
set -euo pipefail

add_path() {
  local dir="$1"
  if [[ -n "${GITHUB_PATH:-}" ]]; then
    echo "${dir}" >> "${GITHUB_PATH}"
  fi
  export PATH="${dir}:${PATH}"
}

if command -v swift >/dev/null 2>&1; then
  swift --version
  exit 0
fi
if [[ -x "${HOME}/.local/share/swiftly/bin/swift" ]]; then
  add_path "${HOME}/.local/share/swiftly/bin"
  swift --version
  exit 0
fi
if [[ -x "${HOME}/swift-6.3.3/usr/bin/swift" ]]; then
  add_path "${HOME}/swift-6.3.3/usr/bin"
  swift --version
  exit 0
fi

. /etc/os-release
case "${VERSION_ID}" in
  24.04) tag=ubuntu2404; dist=ubuntu24.04 ;;
  22.04) tag=ubuntu2204; dist=ubuntu22.04 ;;
  *)
    echo "No Swift 6.3.3 tarball mapped for Ubuntu ${VERSION_ID}" >&2
    exit 1
    ;;
esac

sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  binutils git unzip gnupg2 libc6-dev libcurl4-openssl-dev libedit2 \
  libpython3-dev libsqlite3-0 libxml2-dev libncurses-dev pkg-config \
  tzdata zlib1g-dev ca-certificates curl
sudo apt-get install -y --no-install-recommends libgcc-13-dev libstdc++-13-dev libz3-dev \
  || sudo apt-get install -y --no-install-recommends libgcc-14-dev libstdc++-14-dev libz3-dev

prefix="${HOME}/swift-6.3.3"
mkdir -p "${prefix}"
url="https://download.swift.org/swift-6.3.3-release/${tag}/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE-${dist}.tar.gz"
curl -fL --retry 3 "${url}" | tar -xz -C "${prefix}" --strip-components=1
add_path "${prefix}/usr/bin"
swift --version
