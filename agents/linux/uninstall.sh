#!/bin/bash

# Ensure run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (sudo)." >&2
    exit 1
fi

echo "Stopping services..."
systemctl stop xmrig-miner.service 2>/dev/null
systemctl stop xmrig-reporter.service 2>/dev/null

echo "Disabling services..."
systemctl disable xmrig-miner.service 2>/dev/null
systemctl disable xmrig-reporter.service 2>/dev/null

echo "Removing systemd service files..."
rm -f /etc/systemd/system/xmrig-miner.service
rm -f /etc/systemd/system/xmrig-reporter.service
systemctl daemon-reload

echo "Removing installed directories..."
rm -rf /opt/xmrig-agent/
rm -rf /etc/xmrig-agent/
rm -rf /var/log/xmrig-agent/

echo "Deleting user xmrig..."
userdel xmrig 2>/dev/null

echo "Uninstall complete."
