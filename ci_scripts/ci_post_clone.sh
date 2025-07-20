#!/bin/bash

set -e  # Exit on any error

echo "🚀 BlueLight Xcode Cloud Setup"
echo "=================================="

# Install Flutter
echo "📦 Installing Flutter..."
cd $CI_PRIMARY_REPOSITORY_PATH
curl -o flutter.tar.xz https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_3.32.6-stable.tar.xz
tar xf flutter.tar.xz
export PATH="$PATH:`pwd`/flutter/bin"

# Verify Flutter installation
echo "✅ Flutter version:"
flutter --version

# Configure Flutter for CI
flutter config --no-analytics
flutter config --disable-telemetry

# Get Flutter dependencies
echo "📱 Getting Flutter dependencies..."
flutter pub get

# Generate iOS configuration files (this also runs pod install)
echo "⚙️  Generating iOS configuration..."
flutter build ios --config-only

# Verify generated files exist
echo "🔍 Verifying generated files..."
if [ -f "ios/Flutter/Generated.xcconfig" ]; then
    echo "✅ Generated.xcconfig exists"
else
    echo "❌ Generated.xcconfig missing"
    exit 1
fi

if [ -d "ios/Pods/Target Support Files/Pods-Runner" ]; then
    echo "✅ CocoaPods files generated"
    ls -la "ios/Pods/Target Support Files/Pods-Runner/"*.xcfilelist | head -5
else
    echo "❌ CocoaPods files missing"
    exit 1
fi

echo "✅ Xcode Cloud setup complete!"
echo "==================================" 