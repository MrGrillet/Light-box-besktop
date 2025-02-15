#!/bin/bash

# Set variables
PLUGIN_PATH="../LightBoxCamera.plugin"
PACKAGE_NAME="LightBoxCamera.pkg"
COMPONENT_PKG="LightBoxCamera-component.pkg"
IDENTIFIER="com.lightbox.camera"
VERSION="1.0"
INSTALL_LOCATION="/Library/CoreMediaIO/Plug-Ins/DAL"
BUILD_DIR="build"

# Create build directory if it doesn't exist
mkdir -p "$BUILD_DIR"

echo "Building component package..."
echo "Plugin path: $PLUGIN_PATH"
ls -la "$PLUGIN_PATH"

# Create component package
pkgbuild --root "$PLUGIN_PATH" \
         --install-location "$INSTALL_LOCATION" \
         --scripts scripts \
         --identifier "$IDENTIFIER" \
         --version "$VERSION" \
         "$BUILD_DIR/$COMPONENT_PKG"

echo "Building product archive..."
# Create product archive with admin privileges requirement
productbuild --distribution distribution.xml \
             --resources . \
             --package-path "$BUILD_DIR" \
             "$BUILD_DIR/$PACKAGE_NAME"

echo "Installer package created at $BUILD_DIR/$PACKAGE_NAME" 