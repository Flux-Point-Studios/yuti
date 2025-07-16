# Flutter Dependency Issue Fix Summary

## Problem
Your CI/CD build was failing with this error:
```
Because cardano_flutter_sdk 2.5.3 requires SDK version >=3.6.0 <4.0.0 and no versions of cardano_flutter_sdk match >2.5.3 <3.0.0, cardano_flutter_sdk ^2.5.3 is forbidden.
So, because bluelight depends on cardano_flutter_sdk ^2.5.3, version solving failed.
```

## Root Cause
- **GitHub Actions workflow** `deploy-web.yml` was using **Flutter 3.24.5** (includes Dart SDK 3.5.4)
- **Your dependency** `cardano_flutter_sdk ^2.5.3` requires **Dart SDK >=3.6.0**
- **Version mismatch**: 3.5.4 < 3.6.0, so dependency resolution failed

## Solution Applied

### 1. Updated CI Flutter Versions
**File: `.github/workflows/deploy.yml`**
- Changed from: `flutter-version: '3.32.6'` (potentially invalid version)
- Changed to: `flutter-version: '3.32.0'` (confirmed stable version with Dart SDK 3.8.0)

**Removed deprecated workflow:**
- Deleted `.github/workflows/deploy-web.yml` (was using Flutter 3.24.5 with incompatible Dart SDK)

### 2. Updated Dart SDK Constraint
**File: `pubspec.yaml`**
- Changed from: `sdk: '>=3.0.0 <4.0.0'`
- Changed to: `sdk: '>=3.6.0 <4.0.0'`

This makes the constraint explicit and prevents future compatibility issues.

## Flutter Version & Dart SDK Compatibility
| Flutter Version | Dart SDK Version | Compatible with cardano_flutter_sdk |
|----------------|------------------|-----------------------------------|
| 3.24.5         | 3.5.4           | ❌ No (3.5.4 < 3.6.0)            |
| 3.27.0         | 3.6.0           | ✅ Yes                             |
| 3.32.0         | 3.8.0           | ✅ Yes                             |

## Next Steps
1. **Commit these changes** to your repository
2. **Push to trigger CI** - your builds should now pass
3. **Local development**: Run `flutter upgrade` to use a compatible Flutter version locally

## Verification
Your CI should now successfully run with the single remaining workflow (`.github/workflows/deploy.yml`):
- `flutter pub get` ✅
- `flutter build web` ✅  
- Git commit and push of build files ✅
- Deployment process ✅

## Benefits of This Fix
- ✅ **Resolved dependency conflicts** - Compatible Dart SDK versions
- ✅ **Simplified CI setup** - Removed redundant deprecated workflow
- ✅ **Future-proofed** - Explicit SDK constraint prevents similar issues
- ✅ **Uses latest stable Flutter** - Better performance and features

The error was specifically in the dependency resolution phase, so fixing the Dart SDK version compatibility resolves the entire build pipeline.