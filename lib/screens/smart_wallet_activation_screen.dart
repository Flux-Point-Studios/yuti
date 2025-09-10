import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../utils/app_colors.dart';
import '../services/smart_wallet_service.dart';

class SmartWalletActivationScreen extends StatefulWidget {
  final String email;
  const SmartWalletActivationScreen({Key? key, required this.email}) : super(key: key);

  @override
  State<SmartWalletActivationScreen> createState() => _SmartWalletActivationScreenState();
}

class _SmartWalletActivationScreenState extends State<SmartWalletActivationScreen> {
  final SmartWalletService _smart = SmartWalletService();
  late final WebViewController _controller;
  bool _checking = false;
  String? _status;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse('https://wallet.zkfold.io'));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkActivated() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _status = 'Checking wallet status…';
    });
    try {
      final addr = await _smart.getWalletAddressByEmail(widget.email);
      if (addr != null && addr.isNotEmpty) {
        setState(() {
          _status = 'Wallet activated!';
        });
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _status = 'Not activated yet. Follow the instructions in the page.';
      });
    } catch (e) {
      setState(() {
        _status = 'Unable to verify activation: $e';
      });
    } finally {
      setState(() {
        _checking = false;
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => _checkActivated());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: Colors.white,
        title: const Text('Activate Smart Wallet'),
      ),
      body: Column(
        children: [
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1), width: 0.5)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _status ?? 'Sign in with Google on the page and follow instructions to activate your wallet',
                    style: TextStyle(color: Colors.white.withOpacity(0.9)),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _checking ? null : () { _checkActivated(); _startPolling(); },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue, foregroundColor: Colors.white),
                  child: _checking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Check Status'),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
} 