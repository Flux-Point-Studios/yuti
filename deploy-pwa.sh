#!/bin/bash

# Cardevia PWA Deployment Script
# This script builds the Flutter app for web and prepares it for PWA deployment

set -e  # Exit on any error

echo "🚀 Starting Cardevia PWA deployment process..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    print_error "Flutter is not installed or not in PATH"
    exit 1
fi

print_status "Flutter version:"
flutter --version

# Clean previous builds
print_status "Cleaning previous builds..."
flutter clean

# Get dependencies
print_status "Getting Flutter dependencies..."
flutter pub get

# Build for web with optimizations
print_status "Building Flutter app for web (PWA)..."

# Build for web with PWA optimizations
print_status "Building with PWA optimizations and offline-first strategy..."
flutter build web --release --pwa-strategy offline-first

# Verify build output
if [ ! -d "build/web" ]; then
    print_error "Build failed - build/web directory not found"
    exit 1
fi

print_success "Flutter web build completed successfully!"

# Check for required PWA files
print_status "Verifying PWA files..."

required_files=("build/web/index.html" "build/web/manifest.json" "build/web/favicon.png")
for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        print_error "Required file missing: $file"
        exit 1
    fi
done

# Check for icons
if [ ! -d "build/web/icons" ]; then
    print_error "Icons directory missing in build output"
    exit 1
fi

print_success "All required PWA files are present!"

# Display build info
print_status "Build information:"
echo "  📁 Build directory: $(pwd)/build/web"
echo "  📱 PWA Manifest: $(pwd)/build/web/manifest.json"
echo "  🖼️  Icons: $(pwd)/build/web/icons/"
echo "  📄 Index file: $(pwd)/build/web/index.html"

# Show deployment options
echo ""
print_status "🚀 Deployment Options:"
echo ""
echo "1. 🔥 Firebase Hosting:"
echo "   - Run: firebase deploy"
echo "   - Make sure firebase.json points to build/web"
echo ""
echo "2. ⚡ Vercel:"
echo "   - Run: vercel --prod"
echo "   - Or use Vercel CLI in build/web directory"
echo ""
echo "3. 🌐 Netlify:"
echo "   - Drag and drop build/web folder to Netlify"
echo "   - Or use Netlify CLI: netlify deploy --prod --dir=build/web"
echo ""
echo "4. 📦 Other static hosting:"
echo "   - Upload contents of build/web to your web server"
echo "   - Ensure HTTPS is enabled"
echo ""

# Optional: Auto-deploy if deployment target is specified
if [ "$1" = "firebase" ]; then
    print_status "Auto-deploying to Firebase..."
    if command -v firebase &> /dev/null; then
        firebase deploy
        print_success "Deployed to Firebase Hosting!"
    else
        print_error "Firebase CLI not found. Install with: npm install -g firebase-tools"
    fi
elif [ "$1" = "vercel" ]; then
    print_status "Auto-deploying to Vercel..."
    if command -v vercel &> /dev/null; then
        cd build/web && vercel --prod
        print_success "Deployed to Vercel!"
    else
        print_error "Vercel CLI not found. Install with: npm install -g vercel"
    fi
fi

print_success "PWA build and preparation completed! 🎉"
print_status "Next steps:"
echo "  1. Deploy to your hosting platform using HTTPS"
echo "  2. Test PWA installation on mobile devices"
echo "  3. Run Lighthouse audit to verify PWA compliance"
echo "  4. Test offline functionality"

echo ""
print_status "Testing commands:"
echo "  • Lighthouse audit: lighthouse https://your-domain.com --view"
echo "  • Local testing: flutter run -d chrome (for development)"
echo "" 