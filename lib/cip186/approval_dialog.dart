import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import 'deeplink_service.dart';
import 'uri_parser.dart';

/// The wallet's user-consent sheet for an inbound CIP-186 request. Returns true
/// if the user approves, false if they reject or dismiss. This is the visible
/// "wallet asks permission" step of the deep-link signing flow.
Future<bool> showCip186ApprovalDialog(
  BuildContext context,
  Cip186ApprovalRequest request,
) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.7),
    builder: (context) => _Cip186ApprovalSheet(request: request),
  );
  return result ?? false;
}

class _Cip186ApprovalSheet extends StatelessWidget {
  const _Cip186ApprovalSheet({required this.request});

  final Cip186ApprovalRequest request;

  bool get _isConnect => request.method == Cip186Method.connect;

  String get _title => _isConnect ? 'Connection request' : 'Signature request';

  String get _action => _isConnect
      ? 'wants to connect to your wallet'
      : 'wants you to sign a transaction';

  IconData get _icon => _isConnect ? Icons.link_rounded : Icons.draw_rounded;

  @override
  Widget build(BuildContext context) {
    final dappName = (request.dappName?.isNotEmpty ?? false)
        ? request.dappName!
        : (request.dappHost ?? 'A dApp');

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.backgroundDark,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.primaryBlue.withOpacity(0.4)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryBlue.withOpacity(0.25),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryBlue.withOpacity(0.15),
                border: Border.all(color: AppColors.primaryBlue.withOpacity(0.5)),
              ),
              child: Icon(_icon, size: 30, color: AppColors.primaryBlue),
            ),
            const SizedBox(height: 16),
            Text(
              _title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white.withOpacity(0.85),
                  height: 1.4,
                ),
                children: [
                  TextSpan(
                    text: dappName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: ' $_action.'),
                ],
              ),
            ),
            if (request.dappHost != null) ...[
              const SizedBox(height: 6),
              Text(
                request.dappHost!,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],
            if (!_isConnect && request.txHashHex != null) ...[
              const SizedBox(height: 16),
              _DetailRow(label: 'Transaction', value: _shortHash(request.txHashHex!)),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.white.withOpacity(0.2)),
                      ),
                    ),
                    child: Text(
                      'Reject',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Approve',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'via CIP-186 deep-link signing',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withOpacity(0.35),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _shortHash(String hex) {
    if (hex.length <= 16) return hex;
    return '${hex.substring(0, 8)}…${hex.substring(hex.length - 8)}';
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.6),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
