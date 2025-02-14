#!/bin/bash

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Set variables
PLUGIN_NAME="LightBoxCamera"
PLUGIN_ID="com.lightbox.virtualcamera"
PLUGIN_DIR="/Library/CoreMediaIO/Plug-Ins/DAL"

# Remove plugin
if [ -d "$PLUGIN_DIR/$PLUGIN_NAME.plugin" ]; then
    rm -rf "$PLUGIN_DIR/$PLUGIN_NAME.plugin"
    echo "Plugin removed"
else
    echo "Plugin not found"
fi

# Unregister plugin
pkgutil --pkgs="$PLUGIN_ID" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    pkgutil --forget "$PLUGIN_ID"
    echo "Plugin unregistered"
else
    echo "Plugin not registered"
fi

echo "Virtual camera uninstalled successfully"
exit 0 