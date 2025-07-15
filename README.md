<<<<<<< HEAD
# Cardevia Mobile Wallet

A conversational Cardano wallet built with Flutter, following the mobile transformation documentation.

## Features Implemented

### Core Wallet Functionality ✅
- **HD Wallet Creation & Restoration**: Generate new 24-word mnemonic or restore existing wallet
- **Secure Storage**: Uses Flutter Secure Storage for encrypted key management
- **Address Management**: Generate payment and stake addresses
- **Balance Queries**: Check ADA balance and token holdings via Blockfrost
- **Transaction Support**: Framework for sending ADA (transaction building needs SDK updates)

### Conversational UI ✅
- **Glass Morphism Design**: Beautiful translucent UI with blue color theme from T logo
- **Chat Interface**: Natural language interaction for all wallet operations
- **Typing Indicators**: Shows when assistant is processing
- **Rich Message Types**: Support for text, QR codes, transactions, and swaps
- **Markdown Support**: Formatted responses with code blocks and emphasis

### Intent Detection & Processing ✅
- **Balance Inquiries**: "What's my balance?", "How much ADA do I have?"
- **Send Commands**: "Send 10 ADA to addr1..."
- **Receive Address**: "Show my address", "QR code"
- **Swap Commands**: "Swap 2 ETH for ADA"
- **Transaction History**: "Show my transactions"
- **General Queries**: Falls back to T-Backend AI for other questions

### Integration Services ✅
- **Blockfrost API**: Query blockchain data (balances, UTXOs, transactions)
- **T-Backend Integration**: AI responses for general queries
- **UEX Swap Integration**: Multi-turn conversations for token swaps

### Security Features ✅
- **Encrypted Storage**: Mnemonics stored securely using platform keychains
- **Address Validation**: Validates Cardano addresses before transactions
- **Warning Messages**: Clear security warnings during wallet creation

## Project Structure

```
mobile/
├── lib/
│   ├── config/
│   │   └── app_config.dart         # Configuration and API keys
│   ├── models/
│   │   └── chat_message.dart       # Message data models
│   ├── screens/
│   │   ├── splash_screen.dart      # Initial loading screen
│   │   ├── onboarding_screen.dart  # Wallet setup flow
│   │   └── chat_screen.dart        # Main chat interface
│   ├── services/
│   │   ├── wallet_service.dart     # Cardano wallet operations
│   │   ├── blockfrost_service.dart # Blockchain queries
│   │   ├── transaction_service.dart # Transaction building
│   │   └── chat_service.dart       # Message processing & intents
│   ├── utils/
│   │   └── app_colors.dart         # Theme colors
│   └── main.dart                   # App entry point
├── assets/
│   ├── Tlogo1.1.png               # Main logo
│   └── agent_t_pfp.png            # Assistant avatar
├── pubspec.yaml                    # Dependencies
└── README.md                       # This file
```

## Running the App

1. Ensure Flutter is installed and configured
2. Set up environment variables or update `app_config.dart`:
   - `BLOCKFROST_API_KEY`: Your Blockfrost project ID
   - `T_BACKEND_URL`: T-Backend API URL
   - `T_BACKEND_API_KEY`: T-Backend API key
   
3. Install dependencies:
   ```bash
   flutter pub get
   ```

4. Run the app:
   ```bash
   flutter run
   ```

## Current Limitations

1. **Transaction Building**: The Cardano SDK transaction builder implementation needs updates for full transaction support
2. **UEX Integration**: Currently simulated - needs backend proxy implementation
3. **Hardware Wallet**: Ledger support not yet implemented
4. **Voice Input**: Speech-to-text placeholder in UI but not connected

## Next Steps

1. Complete transaction building with proper SDK integration
2. Implement T-Backend proxy endpoints for UEX swaps
3. Add voice input using speech_to_text package
4. Implement staking delegation features
5. Add NFT display and management
6. Integrate hardware wallet support

## Design Highlights

The app features a stunning glass morphism design with:
- Translucent message bubbles with backdrop blur
- Blue gradient theme matching the T logo (#39A5F1)
- Dark background for contrast
- Smooth animations and transitions
- Conversational onboarding flow

## Security Considerations

- Never expose API keys in the app
- Use secure storage for all sensitive data
- Validate all user inputs
- Implement confirmation dialogs for large transactions
- Regular security audits recommended
=======
# bluelight
mobile crypto hub
>>>>>>> 1b1bfd3f12f964af04bac961bbfa7adb8d2d75a1
