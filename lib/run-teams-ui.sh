#!/bin/zsh
# Runs the Teams UI tool, building it from teams-ui.swift on first use (or when the source changes).
# The binary is machine-specific (CPU architecture), so it is built locally and never shipped.
dir=${0:A:h}
bin=$dir/teams-ui
if [[ ! -x $bin || $dir/teams-ui.swift -nt $bin ]]; then
  if ! command -v swiftc >/dev/null 2>&1; then
    echo "Install Xcode Command Line Tools: xcode-select --install"
    exit 1
  fi
  swiftc -O "$dir/teams-ui.swift" -o "$bin" 2>/dev/null || { echo "Build failed"; exit 1; }
fi
exec "$bin" "$@"
