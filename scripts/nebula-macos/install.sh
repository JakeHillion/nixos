#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST_FILE="$SCRIPT_DIR/me.jakehillion.nebula-service.plist"

echo "Unloading old Nebula service..."
sudo launchctl bootout system/me.jakehillion.nebula-service 2>/dev/null || true

echo "Installing new plist..."
sudo cp "$PLIST_FILE" /Library/LaunchDaemons/me.jakehillion.nebula-service.plist
sudo chown root:wheel /Library/LaunchDaemons/me.jakehillion.nebula-service.plist
sudo chmod 644 /Library/LaunchDaemons/me.jakehillion.nebula-service.plist

echo "Loading new service..."
sudo launchctl bootstrap system /Library/LaunchDaemons/me.jakehillion.nebula-service.plist

echo "Checking service status..."
sleep 2
sudo launchctl print system/me.jakehillion.nebula-service

echo ""
echo "Done! Service installed and running."
