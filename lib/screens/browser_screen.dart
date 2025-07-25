import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../utils/app_colors.dart';
import '../widgets/glassmorphism_container.dart';

class BrowserScreen extends StatefulWidget {
  final String? initialUrl;
  
  const BrowserScreen({
    Key? key,
    this.initialUrl,
  }) : super(key: key);

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  late final WebViewController _controller;
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = true;
  String _currentUrl = '';
  bool _canGoBack = false;
  bool _canGoForward = false;
  double _progress = 0.0;

  // Common Web3 dApps and useful sites
  final List<Map<String, String>> _bookmarks = [
    {'name': 'Uniswap', 'url': 'https://app.uniswap.org'},
    {'name': 'Cardano DeFi', 'url': 'https://cardanodefillama.io'},
    {'name': 'SundaeSwap', 'url': 'https://sundaeswap.finance'},
    {'name': 'Minswap', 'url': 'https://minswap.org'},
    {'name': 'JPG Store', 'url': 'https://jpg.store'},
    {'name': 'OpenCNFT', 'url': 'https://opencnft.io'},
    {'name': 'DeFiLlama', 'url': 'https://defillama.com'},
    {'name': 'CoinGecko', 'url': 'https://coingecko.com'},
  ];

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            setState(() {
              _progress = progress / 100.0;
            });
          },
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _currentUrl = url;
              _urlController.text = url;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
            _updateNavigationState();
          },
          onWebResourceError: (WebResourceError error) {
            print('Web resource error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl ?? 'https://google.com'));

    if (widget.initialUrl != null) {
      _urlController.text = widget.initialUrl!;
    }
  }

  Future<void> _updateNavigationState() async {
    final canGoBack = await _controller.canGoBack();
    final canGoForward = await _controller.canGoForward();
    setState(() {
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
    });
  }

  void _navigateToUrl(String url) {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    _controller.loadRequest(Uri.parse(url));
    setState(() {
      _urlController.text = url;
    });
  }

  void _refresh() {
    _controller.reload();
  }

  void _goBack() {
    if (_canGoBack) {
      _controller.goBack();
    }
  }

  void _goForward() {
    if (_canGoForward) {
      _controller.goForward();
    }
  }

  void _showBookmarks() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        child: GlassmorphismContainer(
          glassType: GlassType.overlay,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Web3 Bookmarks',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: _bookmarks.length,
                  itemBuilder: (context, index) {
                    final bookmark = _bookmarks[index];
                    return _buildBookmarkTile(bookmark);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBookmarkTile(Map<String, String> bookmark) {
    return GlassmorphismContainer(
      glassType: GlassType.light,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
          _navigateToUrl(bookmark['url']!);
        },
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.language,
                color: AppColors.primaryBlue,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bookmark['name']!,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    bookmark['url']!,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              color: AppColors.textTertiary,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            _buildToolbar(),
            _buildAddressBar(),
            if (_isLoading) _buildProgressBar(),
            Expanded(
              child: WebViewWidget(controller: _controller),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return GlassmorphismContainer(
      glassType: GlassType.medium,
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_back,
              color: AppColors.textPrimary,
            ),
          ),
          IconButton(
            onPressed: _canGoBack ? _goBack : null,
            icon: Icon(
              Icons.arrow_back_ios,
              color: _canGoBack 
                ? AppColors.textPrimary 
                : AppColors.textTertiary,
            ),
          ),
          IconButton(
            onPressed: _canGoForward ? _goForward : null,
            icon: Icon(
              Icons.arrow_forward_ios,
              color: _canGoForward 
                ? AppColors.textPrimary 
                : AppColors.textTertiary,
            ),
          ),
          IconButton(
            onPressed: _refresh,
            icon: const Icon(
              Icons.refresh,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _showBookmarks,
            icon: const Icon(
              Icons.bookmarks,
              color: AppColors.primaryBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressBar() {
    return GlassmorphismContainer(
      glassType: GlassType.light,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(
            Icons.lock,
            color: AppColors.primaryBlue,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _urlController,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
              decoration: const InputDecoration(
                hintText: 'Enter URL or search...',
                hintStyle: TextStyle(color: AppColors.textTertiary),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onSubmitted: _navigateToUrl,
            ),
          ),
          IconButton(
            onPressed: () => _navigateToUrl(_urlController.text),
            icon: const Icon(
              Icons.arrow_forward,
              color: AppColors.primaryBlue,
              size: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Container(
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      child: LinearProgressIndicator(
        value: _progress,
        backgroundColor: AppColors.backgroundMedium,
        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
      ),
    );
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }
}