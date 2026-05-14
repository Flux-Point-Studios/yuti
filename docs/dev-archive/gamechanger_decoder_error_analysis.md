# GameChanger Finance: "Unknown Decoder Header" Error Analysis

## What the Error Means

The **"Failed to decode API call. Unknown decoder header. Cannot decode"** error occurs when the GameChanger Finance wallet cannot identify how to decompress and decode the payload in a URL.

## How GameChanger Encoding Works

GameChanger uses a header-based encoding system where the first character(s) before a hyphen indicate the compression and encoding type:

| Header | Compression | Encoding |
|--------|-------------|----------|
| `0-`   | None        | Raw JSON |
| `1-`   | Gzip        | Base64-URL (no =) |
| `2-`   | LZMA        | Base64-URL |

## The Problem

In your case, the URL:
```
…/api/2/run/H4sIAOu-d2gA_22QwUoDMRCG…
```

**Missing the header prefix!** It should be:
```
…/api/2/run/1-H4sIAOu-d2gA_22QwUoDMRCG…
```

The payload starts with `H4sI` (base64 data) instead of `1-H4sI` (header + base64 data).

## Common Causes

1. **Manual URL manipulation** - accidentally removing the header during string operations
2. **Double URL encoding** - encoding the payload twice
3. **"Sanitizing" URLs** - removing digits or special characters for QR codes
4. **String splitting errors** - splitting on `-` and losing the first part
5. **URI parsing issues** - losing segments when rebuilding URLs

## Quick Fix

### Verification
Paste the payload part into a text editor:
- ✅ **Correct**: Starts with `1-` 
- ❌ **Wrong**: Starts with `H4sI` or other base64 characters

### Solution (Dart)
```dart
import 'dart:convert';
import 'package:archive/archive.dart';

String encodeGcScript(Map<String, dynamic> script) {
  final gz = GZipEncoder().encode(utf8.encode(jsonEncode(script)))!;
  final b64 = base64UrlEncode(gz).replaceAll('=', '');
  return '1-$b64';  // ← Add header here!
}

String buildGcUrl(Map<String,dynamic> script, {bool mainnet = true}) {
  final payload = encodeGcScript(script);
  final host = mainnet
      ? 'https://wallet.gamechanger.finance'
      : 'https://beta-wallet.gamechanger.finance';
  return '$host/api/2/run/$payload';
}
```

## Testing
1. Generate URL with `buildGcUrl(myScript)`
2. Copy the complete link
3. Paste in mobile browser
4. Should see "Action Request" dialog instead of red error

## Note on Other Errors

The CORS/504 errors in logs are **secondary effects** - they happen because the wallet tries to fetch blockchain data after decoding fails. Fix the header issue and these will disappear.

## Checklist
- [ ] Payload starts with `1-`
- [ ] No double URL encoding
- [ ] Header preserved in QR codes/shortened URLs
- [ ] Using proper encoding function