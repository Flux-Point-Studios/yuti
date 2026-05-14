# GameChanger Callback URL Fix

## Problem Summary

The GameChanger wallet connection worked perfectly in the pricing page but failed to return with data correctly on the profile page. **Additionally, there were iOS-specific callback issues** where the custom URL scheme wasn't being handled properly.

## Root Cause Analysis

### **The Critical Difference: Browser Session Context**

**Pricing Page (Working):**
- Used `showDialog()` with `CardanoWalletDialog`
- `FlutterWebAuth.authenticate()` maintained the browser session context
- Callback result was returned directly to the awaiting code
- No navigation away from the current page

**Profile Page (Not Working):**
- Used `WalletAuthService.authenticateWithWallet()` wrapper
- Lost the original page context when FlutterWebAuth redirected
- Callback redirected to `/gamechanger-callback` route instead of returning to service
- The callback screen had no connection to the original WalletAuthService call

### **iOS-Specific Issues Identified**

**Platform Detection Problems:**
- Web detection logic wasn't comprehensive enough
- iOS platform not properly identified in some cases
- `kIsWeb` check missing in some platform detection code

**URL Scheme Configuration:**
- iOS Info.plist needed more robust URL scheme configuration
- Custom scheme handling required additional error handling
- FlutterWebAuth callback scheme detection needed improvement

**Callback Handling:**
- iOS callback flow different from web flow
- Need fallback mechanism for when FlutterWebAuth fails on iOS
- Enhanced error messages for iOS-specific issues

### **Technical Details**

The issue was that `FlutterWebAuth.authenticate()` behaves differently depending on the calling context:

1. **In a Dialog Context**: Maintains session state and returns results directly
2. **In a Service Context**: Loses connection when page context changes, falls back to routing
3. **On iOS**: Additional complexity with custom URL schemes and app lifecycle management

## Solution Implemented

### **Modified `/lib/screens/profile_screen.dart`:**

1. **Removed WalletAuthService dependency**:
   ```dart
   // REMOVED:
   final WalletAuthService _walletAuthService = WalletAuthService();
   final result = await _walletAuthService.authenticateWithWallet(WalletAuthType.link);
   ```

2. **Added direct dialog approach**:
   ```dart
   // ADDED:
   import '../widgets/cardano_wallet_dialog.dart';
   
   Future<void> _linkWallet() async {
     // Use the same dialog approach as pricing page to preserve context
     final walletConnected = await _showCardanoWalletDialog();
     
     if (walletConnected == true) {
       _showSuccess('Wallet linked successfully!');
       await _loadUserData();
     }
   }
   
   Future<bool?> _showCardanoWalletDialog() {
     return showDialog<bool>(
       context: context,
       barrierDismissible: false,
       builder: (context) => CardanoWalletDialog(authService: _authService),
     );
   }
   ```

3. **Updated unlink method**:
   ```dart
   // CHANGED:
   await _authService.disconnectCardanoWallet();
   // INSTEAD OF:
   await _walletAuthService.unlinkWallet();
   ```

### **Enhanced iOS Support in `/lib/services/gamechanger_service.dart`:**

1. **Improved Platform Detection**:
   ```dart
   // Enhanced platform detection for better iOS compatibility
   final isRunningOnWeb = kIsWeb || 
       currentUri.scheme == 'https' || 
       currentUri.scheme == 'http';
   ```

2. **iOS-Specific Error Handling**:
   ```dart
   // iOS-specific error handling
   if (errorMessage.contains('scheme does not have a registered handler') ||
       errorMessage.contains('No app associated with url') ||
       errorMessage.contains('URL scheme not registered')) {
     throw GameChangerException(
         'iOS URL scheme not properly configured...');
   }
   ```

3. **iOS Fallback Connection Method**:
   ```dart
   /// iOS-specific fallback connection method using URL launcher
   Future<GameChangerWalletData> _connectWalletIosFallback({bool isMainnet = true}) async {
     // Direct URL launcher approach when FlutterWebAuth fails
   }
   ```

### **Updated iOS Configuration `/ios/Runner/Info.plist`:**

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLName</key>
        <string>bluelight.app</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>bluelight</string>
        </array>
    </dict>
    <dict>
        <key>CFBundleURLName</key>
        <string>bluelight.gamechanger</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>bluelight</string>
        </array>
    </dict>
</array>
```

### **Enhanced Callback Screen `/lib/screens/gamechanger_callback_screen.dart`:**

- Added separate handling for web vs native platforms
- Improved iOS-specific callback processing
- Better error messages and user guidance

## Why This Fixes It

1. **Session Preservation**: The dialog approach keeps the browser session intact
2. **Direct Return**: FlutterWebAuth returns results directly to the dialog instead of navigating to callback route
3. **Context Consistency**: Both pricing page and profile page now use identical callback handling
4. **Simplified Flow**: Removes the unnecessary WalletAuthService wrapper that was breaking the session
5. **iOS Compatibility**: Enhanced platform detection and URL scheme handling
6. **Fallback Support**: iOS fallback method when standard FlutterWebAuth fails
7. **Better Error Handling**: Specific error messages for iOS-related issues

## Testing Instructions

### Web Testing
The profile page GameChanger wallet linking should now:
- ✅ Show the same wallet dialog as pricing page
- ✅ Return with wallet data correctly
- ✅ Process the callback in the same browser session
- ✅ Link the wallet to the user's account successfully

### iOS Testing
The iOS GameChanger wallet linking should now:
- ✅ Properly detect iOS platform vs web
- ✅ Use correct custom URL scheme (`bluelight://`)
- ✅ Handle URL scheme configuration errors gracefully
- ✅ Provide fallback connection method if needed
- ✅ Show informative error messages for iOS-specific issues

### Debug Information
The enhanced logging will now show:
- Platform detection details (`kIsWeb`, URI scheme)
- Callback URL generation for each platform
- URL scheme validation results
- Detailed error information for troubleshooting

## Files Modified

- `/lib/screens/profile_screen.dart` - Updated wallet linking flow to use dialog approach
- `/lib/services/gamechanger_service.dart` - Enhanced iOS support and error handling
- `/ios/Runner/Info.plist` - Improved URL scheme configuration
- `/lib/screens/gamechanger_callback_screen.dart` - Added iOS-specific callback handling
- `/GAMECHANGER_CALLBACK_FIX.md` - Updated documentation with iOS fixes

## Debugging Steps for iOS Issues

If iOS callback issues persist:

1. **Check iOS Logs**: Look for URL scheme and FlutterWebAuth errors
2. **Verify URL Scheme**: Ensure `bluelight://` is properly registered
3. **Test URL Scheme**: Use Safari to test `bluelight://test` URLs
4. **Check GameChanger App**: Ensure GameChanger wallet app is installed
5. **Review Error Messages**: Use the enhanced error messages for specific guidance