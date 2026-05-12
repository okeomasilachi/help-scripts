#!/bin/bash

# Define your SDK path
export ANDROID_HOME="/home/onyedibia/android-sdk"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

SDK_PATH="$ANDROID_HOME"

# 1. Locate the tools specifically in your SDK
SDK_MANAGER="$SDK_PATH/cmdline-tools/latest/bin/sdkmanager"
AVD_MANAGER="$SDK_PATH/cmdline-tools/latest/bin/avdmanager"

if [ ! -f "$SDK_MANAGER" ] || [ ! -f "$AVD_MANAGER" ]; then
    echo "Error: Could not find sdkmanager or avdmanager in $SDK_PATH"
    echo "Check if cmdline-tools are installed in $SDK_PATH/cmdline-tools/latest"
    exit 1
fi

echo "Using tools at: $SDK_MANAGER"

# 2. Accept licenses
echo "Accepting licenses..."
yes | "$SDK_MANAGER" --licenses > /dev/null

# 3. Install necessary components
echo "Installing necessary components (platform-tools, emulator, system-image)..."
"$SDK_MANAGER" "platform-tools" "emulator" "system-images;android-30;google_apis;x86_64"

# 4. Create the AVD with a low-res Nexus 5 profile
echo "Creating 'LiteDevice'..."
echo "no" | "$AVD_MANAGER" create avd -n LiteDevice -k "system-images;android-30;google_apis;x86_64" -d "Nexus 5" --force

# 5. Apply RAM and Performance optimizations
CONFIG_PATH="$HOME/.android/avd/LiteDevice.avd/config.ini"
if [ -f "$CONFIG_PATH" ]; then
    echo "Applying optimizations to config.ini..."
    touch "$CONFIG_PATH"
    sed -i '/hw.ramSize/d' "$CONFIG_PATH"
    echo "hw.ramSize=2048" >> "$CONFIG_PATH"
    sed -i '/vm.heapSize/d' "$CONFIG_PATH"
    echo "vm.heapSize=512" >> "$CONFIG_PATH"
    sed -i '/hw.gpu.enabled/d' "$CONFIG_PATH"
    echo "hw.gpu.enabled=yes" >> "$CONFIG_PATH"
    sed -i '/hw.gpu.mode/d' "$CONFIG_PATH"
    echo "hw.gpu.mode=host" >> "$CONFIG_PATH"
    sed -i '/hw.cpu.ncore/d' "$CONFIG_PATH"
    echo "hw.cpu.ncore=4" >> "$CONFIG_PATH"
    sed -i '/showDeviceFrame/d' "$CONFIG_PATH"
    echo "showDeviceFrame=no" >> "$CONFIG_PATH"
    sed -i '/hw.keyboard/d' "$CONFIG_PATH"
    echo "hw.keyboard=yes" >> "$CONFIG_PATH"
fi

echo "------------------------------------------------"
echo "Setup Complete!"
echo "To start the emulator with Hardware Acceleration (recommended):"
echo "$ANDROID_HOME/emulator/emulator -avd LiteDevice -no-snapshot-load -gpu host &"
echo ""
echo "Or if it still hangs, try Software Rendering (slower):"
echo "$ANDROID_HOME/emulator/emulator -avd LiteDevice -no-snapshot-load -gpu swiftshader_indirect &"
echo "------------------------------------------------"
