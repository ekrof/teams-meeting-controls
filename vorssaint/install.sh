#!/bin/zsh
# Compiles the switcher and installs a LaunchAgent that keeps it running.
# Remove again with: ./install.sh uninstall
set -e
here=${0:A:h}
bin=$HOME/.local/bin/vorssaint-profile-switcher
plist=$HOME/Library/LaunchAgents/local.vorssaint-profile-switcher.plist

if [[ $1 == uninstall ]]; then
  launchctl bootout gui/$UID "$plist" 2>/dev/null || true
  [[ -x $bin ]] && "$bin" apply "$here/config.json" default || true
  rm -f "$plist" "$bin"
  echo uninstalled
  exit 0
fi

mkdir -p ${bin:h}
swiftc -O "$here/switcher.swift" -o "$bin"
cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>local.vorssaint-profile-switcher</string>
<key>ProgramArguments</key><array><string>$bin</string><string>watch</string><string>$here/config.json</string></array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
</dict></plist>
PLIST
launchctl bootout gui/$UID "$plist" 2>/dev/null || true
launchctl bootstrap gui/$UID "$plist"
echo installed
