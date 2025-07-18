# iOS Deployment Guide for BlueLight
*Created: July 17, 2025*

## Overview

This guide documents the complete iOS build and deployment pipeline for the BlueLight Cardano wallet app. The system uses GitHub Actions for automated building and App Store Connect API for automated uploads.

## 🏗️ Build System Architecture

### GitHub Actions Workflow
- **File**: `.github/workflows/ios-build.yml`
- **Trigger**: Manual workflow dispatch only (no conflicts with Vercel web deployment)
- **Output**: Signed IPA files ready for App Store distribution

### Key Features
- ✅ **Manual Code Signing**: Uses imported certificates and provisioning profiles
- ✅ **Multiple Export Methods**: development, ad-hoc, app-store, enterprise
- ✅ **Automated App Store Upload**: Optional upload to App Store Connect
- ✅ **Zero Conflicts**: Completely separate from web deployment pipeline

## 🔐 Code Signing Setup

### Required Secrets (GitHub Repository Settings)
```
IOS_CERTIFICATE_BASE64          # Base64 encoded .p12 certificate file
IOS_CERTIFICATE_PASSWORD        # Password for .p12 certificate  
IOS_PROVISION_PROFILE_BASE64    # Base64 encoded .mobileprovision file
KEYCHAIN_PASSWORD               # Keychain password for CI environment
```

### Certificate Generation
1. **Apple Developer Account**: Generate distribution certificate
2. **Export as .p12**: Include private key, set password
3. **Encode to Base64**: `base64 -i certificate.p12 | pbcopy`
4. **Add to GitHub Secrets**: Paste base64 string

### Provisioning Profile
1. **Create in Apple Developer**: App Store Distribution profile
2. **Download .mobileprovision**: For bundle ID `com.bluelight.wallet`
3. **Encode to Base64**: `base64 -i profile.mobileprovision | pbcopy`
4. **Add to GitHub Secrets**: Paste base64 string

## 🚀 Build Process

### Manual Trigger
1. **GitHub Actions** → **Build iOS App** workflow
2. **Click "Run workflow"**
3. **Select Options**:
   - Build type: `release` (for App Store) or `debug` (for testing)
   - Export method: `app-store`, `ad-hoc`, `development`, or `enterprise`

### Automatic Steps
1. **Setup Environment**: macOS runner, Xcode, Flutter
2. **Code Signing Setup**: Import certificates and profiles
3. **Project Configuration**: Set manual signing, team ID, provisioning profile
4. **Build IPA**: `flutter build ipa --release --export-options-plist=ExportOptions.plist`
5. **Upload Artifacts**: IPA available for download

### Build Output
- **Artifacts**: `ios-build-release-[BUILD_NUMBER]`
- **Contains**: `.ipa` file and `Runner.app` bundle
- **Size**: ~48MB for release builds
- **Retention**: 30 days

## 🍎 App Store Connect Integration

### API Setup
1. **App Store Connect**: Users and Access → Integrations → App Store Connect API
2. **Generate Key**: "App Manager" or "Developer" role
3. **Download .p8 file**: Store securely (only shown once)
4. **Note Credentials**: Key ID and Issuer ID

### Local Upload Setup
```bash
# Create standard directory for API keys
mkdir -p ~/.private_keys

# Copy API key file
cp ~/Downloads/AuthKey_[KEY_ID].p8 ~/.private_keys/

# Upload IPA to App Store Connect
xcrun altool --upload-app --type ios -f bluelight.ipa \
  --apiKey [KEY_ID] \
  --apiIssuer [ISSUER_ID]
```

### Current API Credentials
- **Key ID**: `PMMG369C2M`
- **Issuer ID**: `5be249f9-c023-40cf-b140-0f78caf40ed7`
- **Location**: `~/.private_keys/AuthKey_PMMG369C2M.p8`

## 🎨 App Icon Management

### Source File
- **Location**: `assets/bluelight.png`
- **Dimensions**: 429x429 pixels
- **Format**: PNG with transparency support

### Icon Generation Process
```bash
cd ios/Runner/Assets.xcassets/AppIcon.appiconset

# Generate all required iOS icon sizes
sips -z 20 20 ../../../../assets/bluelight.png --out Icon-App-20x20@1x.png
sips -z 40 40 ../../../../assets/bluelight.png --out Icon-App-20x20@2x.png
sips -z 60 60 ../../../../assets/bluelight.png --out Icon-App-20x20@3x.png
# ... (continue for all 15 required sizes)
```

### Required Icon Sizes
- **iPhone**: 20x20, 29x29, 40x40, 60x60 (@1x, @2x, @3x)
- **iPad**: 20x20, 29x29, 40x40, 76x76, 83.5x83.5 (@1x, @2x)
- **App Store**: 1024x1024 (@1x)

## 📱 Version Management

### Version Format
- **pubspec.yaml**: `version: 1.0.1+3`
- **Semantic**: `[MAJOR].[MINOR].[PATCH]+[BUILD]`
- **App Store**: Displays as "Version 1.0.1 (3)"

### Build Number Requirements
- **Must be higher** than previously uploaded build
- **Integer format**: 1, 2, 3, 4, etc.
- **Increment for each upload**: Even if version stays same

### Update Process
```bash
# Update build number in pubspec.yaml
version: 1.0.1+3  # Increment +2 to +3

# Commit changes
git add pubspec.yaml
git commit -m "Increment build number to 1.0.1+3"
git push

# Trigger new build via GitHub Actions
```

## 🛡️ Security & Compliance

### Encryption Declaration
**Info.plist Configuration**:
```xml
<!-- App uses standard encryption only - no custom algorithms -->
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

**Purpose**: Prevents App Store Connect encryption dialog on upload

### URL Schemes
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>bluelight</string>
        </array>
    </dict>
</array>
```

**Purpose**: Enables GameChanger wallet deep link callbacks

## 🔄 Deployment Workflow

### Complete Process
1. **Development**: Make code changes, test locally
2. **Version Update**: Increment build number in `pubspec.yaml`
3. **Commit Changes**: Push to GitHub main branch
4. **Trigger Build**: Manual GitHub Actions workflow
5. **Download IPA**: From GitHub Actions artifacts
6. **Upload to App Store**: Using `xcrun altool` command
7. **App Store Processing**: 5-15 minutes for new build to appear
8. **Submit for Review**: Via App Store Connect web interface

### Quick Upload Script
```bash
#!/bin/bash
# upload-ios.sh

IPA_FILE="bluelight.ipa"
API_KEY="PMMG369C2M"
ISSUER_ID="5be249f9-c023-40cf-b140-0f78caf40ed7"

if [ ! -f "$IPA_FILE" ]; then
    echo "❌ IPA file not found: $IPA_FILE"
    exit 1
fi

echo "🚀 Uploading $IPA_FILE to App Store Connect..."
xcrun altool --upload-app --type ios -f "$IPA_FILE" \
    --apiKey "$API_KEY" \
    --apiIssuer "$ISSUER_ID"

if [ $? -eq 0 ]; then
    echo "✅ Upload successful!"
else
    echo "❌ Upload failed. Check build number and credentials."
fi
```

## 🐛 Troubleshooting

### Common Issues

**"Bundle version must be higher"**
- Solution: Increment build number in `pubspec.yaml`

**"No profiles found"**
- Solution: Check provisioning profile secrets and team ID

**"Failed to authenticate"**
- Solution: Verify API key file location `~/.private_keys/`

**"Code signing failed"**
- Solution: Check certificate and provisioning profile match

### Debug Commands
```bash
# Check installed profiles
ls -la ~/Library/MobileDevice/Provisioning\ Profiles/

# Verify code signing identity
security find-identity -v -p codesigning

# Check Xcode project configuration
grep -A 5 -B 5 "DEVELOPMENT_TEAM\|PROVISIONING_PROFILE_SPECIFIER" ios/Runner.xcodeproj/project.pbxproj
```

## 📊 Current Status

### Build Statistics
- **Latest Version**: 1.0.1+3
- **IPA Size**: ~48.7MB
- **Build Time**: ~10 minutes via GitHub Actions
- **Upload Speed**: ~33MB/s to App Store Connect

### Successful Uploads
- **Build 2**: July 17, 2025 - UUID: `ee368742-97b2-4e3f-ad93-5047012f0756`
- **Build 3**: July 17, 2025 - UUID: `80756e65-e2fa-4680-89e4-35dc22b61cb2`

### App Store Status
- ✅ **TestFlight**: Ready for beta testing
- ✅ **Branding**: BlueLight icons applied
- ✅ **Compliance**: Encryption exemption configured
- 🟡 **Review**: Ready for App Store submission

## 🎯 Best Practices

### Development Workflow
1. **Test thoroughly** before triggering builds
2. **Increment build numbers** for each App Store upload  
3. **Use semantic versioning** for major releases
4. **Keep API keys secure** and rotate periodically
5. **Monitor build artifacts** for size and performance

### Security Guidelines
- 🔒 **Never commit** certificates or API keys to git
- 🔒 **Use GitHub Secrets** for all sensitive credentials
- 🔒 **Rotate API keys** every 6-12 months
- 🔒 **Limit API key permissions** to minimum required scope

### Performance Optimization
- 📦 **Monitor IPA size** - current ~48MB is reasonable
- 🚀 **Use release builds** for App Store uploads
- 🧹 **Clean build artifacts** to save storage space
- ⚡ **Parallel builds** - current setup optimized for speed

---

*This guide documents the complete iOS deployment pipeline implemented on July 17, 2025. The system successfully builds, signs, and uploads BlueLight iOS apps to the App Store with zero manual intervention required for the build process.* 