# Shared Swift lookup. Source this from other scripts.
if [[ -n "${HOME:-}" && -x "${HOME}/swift-6.3.3/usr/bin/swift" ]]; then
  export PATH="${HOME}/swift-6.3.3/usr/bin:${PATH}"
fi
if [[ -x /opt/swift/usr/bin/swift ]]; then
  export PATH="/opt/swift/usr/bin:${PATH}"
fi
if [[ -n "${HOME:-}" && -x "${HOME}/.local/share/swiftly/bin/swift" ]]; then
  export PATH="${HOME}/.local/share/swiftly/bin:${PATH}"
fi
