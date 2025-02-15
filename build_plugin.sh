#!/bin/bash

# Set up plugin directory structure
mkdir -p LightBoxCamera.plugin/Contents/MacOS
mkdir -p installer/build

# Build the plugin
cd LightBoxCamera.plugin/Contents/MacOS
make clean && make

# Set permissions
chmod 755 LightBoxCamera

# Build the installer package
cd ../../../installer
./build.sh

# Copy the installer package to the Xcode project's Resources directory
RESOURCES_DIR="../LightBoxDesktop/Resources"
mkdir -p "$RESOURCES_DIR"
cp "build/LightBoxCamera.pkg" "$RESOURCES_DIR/"

echo "Plugin built and installer package created successfully in $RESOURCES_DIR" 