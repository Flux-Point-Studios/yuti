import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../widgets/glassmorphism_container.dart';

enum MessageLimitType {
  warning, // At 15 messages
  blocked, // At 20 messages
}

class MessageLimitWidget extends StatelessWidget {
  final MessageLimitType type;
  final int remainingMessages;
  final VoidCallback onUpgradePressed;

  const MessageLimitWidget({
    Key? key,
    required this.type,
    required this.remainingMessages,
    required this.onUpgradePressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GlassmorphismContainer(
        glassType: GlassType.medium,
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.all(16),
        blur: 12.0,
        showGlow: true,
        customGradient: type == MessageLimitType.warning 
          ? _getWarningGradient()
          : _getBlockedGradient(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  type == MessageLimitType.warning ? Icons.warning_amber : Icons.block,
                  color: type == MessageLimitType.warning ? Colors.orange : Colors.red,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    type == MessageLimitType.warning 
                      ? 'Approaching Daily Limit'
                      : 'Daily Limit Reached',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _getMessageText(),
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onUpgradePressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.arrow_upward, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      type == MessageLimitType.warning ? 'Upgrade Now' : 'Upgrade to Continue',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (type == MessageLimitType.warning) ...[
              const SizedBox(height: 8),
              Text(
                '$remainingMessages AI responses remaining today',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getMessageText() {
    switch (type) {
      case MessageLimitType.warning:
        return 'You\'re approaching your daily limit of 20 AI responses as a FREE user. Upgrade to PREMIUM for unlimited conversations with Agent T.';
      case MessageLimitType.blocked:
        return 'You\'ve reached your daily limit of 20 AI responses as a FREE user. Upgrade to PREMIUM for unlimited access or wait until tomorrow for your limit to reset.';
    }
  }

  LinearGradient _getWarningGradient() {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.orange.withOpacity(0.2),
        Colors.amber.withOpacity(0.1),
        Colors.transparent,
      ],
    );
  }

  LinearGradient _getBlockedGradient() {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.red.withOpacity(0.2),
        Colors.deepOrange.withOpacity(0.1),
        Colors.transparent,
      ],
    );
  }
} 