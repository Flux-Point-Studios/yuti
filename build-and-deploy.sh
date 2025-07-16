#!/bin/bash

# BlueLight Flutter Web Build & Deploy Script
# This script builds Flutter web locally and deploys via Vercel static hosting
# Date: 7/16/2025

set -e  # Exit on any error

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

echo "🚀 BlueLight Flutter Web Build & Deploy"
echo "========================================"

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    print_error "Flutter is not installed or not in PATH"
    exit 1
fi

print_status "Flutter version:"
flutter --version

# Check for uncommitted changes
if [[ -n $(git status -s) ]]; then
    print_warning "You have uncommitted changes. Continuing will include them in the build."
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Aborted by user"
        exit 1
    fi
fi

# Clean previous builds
print_status "Cleaning previous builds..."
flutter clean

# Get dependencies
print_status "Getting Flutter dependencies..."
flutter pub get

# Build for web with optimizations
print_status "Building Flutter web app..."
print_status "Using: flutter build web --release --pwa-strategy offline-first"
flutter build web --release --pwa-strategy offline-first

# Verify build output
if [ ! -d "build/web" ]; then
    print_error "Build failed - build/web directory not found"
    exit 1
fi

print_success "Flutter web build completed successfully!"

# Check for required files
print_status "Verifying build output..."
required_files=("build/web/index.html" "build/web/manifest.json" "build/web/favicon.png")
for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        print_error "Required file missing: $file"
        exit 1
    fi
done

print_success "All required files present!"

# Stage all changes
print_status "Staging changes for git..."
git add .

# Check if there are changes to commit
if git diff --staged --quiet; then
    print_warning "No changes to commit - build output is identical"
    echo "Deployment not needed, but you can still push if desired."
    read -p "Push anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Deployment cancelled"
        exit 0
    fi
else
    # Show what changed
    print_status "Changes to be committed:"
    git diff --staged --stat
fi

# Get commit message or use default
if [ -n "$1" ]; then
    COMMIT_MSG="🚀 Deploy: $1"
else
    COMMIT_MSG="🚀 Auto-deploy: Update Flutter web build $(date +'%Y-%m-%d %H:%M')"
fi

# Commit changes
print_status "Committing build files..."
git commit -m "$COMMIT_MSG"

# Push to trigger Vercel deployment
print_status "Pushing to GitHub (triggers Vercel deployment)..."
git push

print_success "🎉 Deployment complete!"
echo ""
print_status "What happens next:"
echo "  1. ✅ Git push completed"
echo "  2. ⚡ Vercel automatically detects the push"
echo "  3. 📦 Vercel serves pre-built files from build/web/"
echo "  4. 🌐 Your app updates at the deployed URL"
echo ""
print_status "Check deployment status at: https://vercel.com/dashboard"
echo ""
print_success "GameChanger wallet integration with transport header fix is now live! 🎉" 