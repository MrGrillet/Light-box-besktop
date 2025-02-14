#!/bin/bash

# Enable debug output
set -x

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

# Set variables
PLUGIN_NAME="LightBoxCamera"
PLUGIN_ID="com.lightbox.virtualcamera"
PLUGIN_DIR="/Library/CoreMediaIO/Plug-Ins/DAL"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Debug output
echo "Current user: $(whoami)"
echo "Script directory: $SCRIPT_DIR"
echo "Current directory: $(pwd)"
echo "Looking for plugin in: $SCRIPT_DIR/$PLUGIN_NAME.plugin"
ls -la "$SCRIPT_DIR" || echo "Cannot list directory contents"

# Check if plugin exists
if [ ! -d "$SCRIPT_DIR/$PLUGIN_NAME.plugin" ]; then
    echo "Error: Plugin not found at $SCRIPT_DIR/$PLUGIN_NAME.plugin"
    # List contents of parent directories to help debug
    echo "Contents of script directory:"
    ls -la "$SCRIPT_DIR"
    echo "Contents of Resources directory:"
    ls -la "$(dirname "$SCRIPT_DIR")"
    exit 1
fi

# Create plugin directory if it doesn't exist
if ! mkdir -p "$PLUGIN_DIR"; then
    echo "Error: Failed to create plugin directory at $PLUGIN_DIR"
    exit 1
fi

# Copy plugin to destination
echo "Copying plugin to $PLUGIN_DIR/"
if ! cp -R "$SCRIPT_DIR/$PLUGIN_NAME.plugin" "$PLUGIN_DIR/"; then
    echo "Error: Failed to copy plugin"
    exit 1
fi

# Set permissions
echo "Setting permissions..."
if ! chown -R root:wheel "$PLUGIN_DIR/$PLUGIN_NAME.plugin"; then
    echo "Error: Failed to set ownership"
    exit 1
fi

if ! chmod -R 755 "$PLUGIN_DIR/$PLUGIN_NAME.plugin"; then
    echo "Error: Failed to set permissions"
    exit 1
fi

# Register plugin
echo "Registering plugin..."
if ! pkgutil --pkgs="$PLUGIN_ID" > /dev/null 2>&1; then
    if ! pkgutil --forget "$PLUGIN_ID"; then
        echo "Warning: Failed to forget existing plugin registration"
    fi
    echo "Plugin registered"
fi

echo "Virtual camera installed successfully"
exit 0 