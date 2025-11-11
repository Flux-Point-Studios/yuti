import 'dart:async';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/speech_service.dart';
import '../services/chat_history_service.dart';
import '../services/supabase_service.dart';
import '../utils/app_colors.dart';
import '../widgets/chat_sidebar.dart';
import '../widgets/glassmorphism_container.dart';
import '../widgets/message_limit_widget.dart';
import '../screens/pricing_screen.dart';
import '../screens/browser_screen.dart'; // Added import for BrowserScreen
import '../services/cardano_wallet_service.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<ChatMessage> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ChatService _chatService = ChatService();
  final SpeechService _speechService = SpeechService();
  final ChatHistoryService _chatHistoryService = ChatHistoryService();
  final AuthService _authService = AuthService();
  final CardanoWalletService _cardanoService = CardanoWalletService();

  bool _isTyping = false;
  bool _isListening = false;
  bool _isSidebarVisible = false;
  ChatSession? _currentSession;
  String? _attachedImageDataUri;
  String? _attachedImageThumbDataUri;
  static const int _maxImageBytes = 2 * 1024 * 1024; // 2MB budget for API payload
  static const int _thumbMaxWidth = 300; // preview thumbnail width
  
  // Message limit tracking
  int _remainingMessages = 20;
  bool _isLimitReached = false;
  
  // Debug info for TestFlight debugging
  String _debugInfo = 'Ready';
  bool _showDebugPanel = false;
  int _tapCount = 0;

  @override
  void initState() {
    super.initState();
    _enforceAccessAndInit();
  }

  Future<void> _enforceAccessAndInit() async {
    final allowed = await _enforceAccess();
    if (!mounted || !allowed) return;
    await _initializeChatHistory();
    await _initializeSpeech();
  }

  Future<bool> _enforceAccess() async {
    try {
      // Ensure user/session state is loaded
      await _authService.refreshUser();

      // If not authenticated, send to login
      if (!_authService.isAuthenticated) {
        debugPrint('🔍 DEBUG: Access gate - not authenticated, redirecting to /login');
        if (mounted) Navigator.pushReplacementNamed(context, '/login');
        return false;
      }

      // Admin bypass via SupabaseService
      final user = _authService.currentUser!;
      if (SupabaseService.isAdminEmail(user.email)) {
        debugPrint('🔍 DEBUG: Access gate - admin bypass');
        return true;
      }

      // Check subscription and premium wallet access
      final hasSubscription = await _authService.checkSubscriptionAccess();
      final hasPremiumWallet = _cardanoService.hasPremiumAccess;
      debugPrint('🔍 DEBUG: Access gate - hasSubscription: $hasSubscription, hasPremiumWallet: $hasPremiumWallet');

      if (!hasSubscription && !hasPremiumWallet) {
        // Route to pricing for clear next step
        debugPrint('🔍 DEBUG: Access gate - redirecting to Pricing');
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const PricingScreen()),
          );
        }
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('🔍 DEBUG: Access gate error: $e');
      return true; // fail-open to avoid locking users out unexpectedly
    }
  }

  Future<void> _initializeChatHistory() async {
    try {
      await _chatHistoryService.initialize();
      
      // Load message limits
      await _updateMessageLimits();

      // Check if there's a current session
      final currentSession = _chatHistoryService.getCurrentSession();
      if (currentSession != null) {
        _loadSession(currentSession);
      } else {
        // Create a new session if none exists
        await _createNewSession();
      }
    } catch (e) {
      print('Error initializing chat history: $e');
      await _createNewSession();
    }
  }

  Future<void> _updateMessageLimits() async {
    try {
      final remaining = await _chatHistoryService.getUserRemainingMessages();
      print('🔍 DEBUG: Message limits - Remaining: $remaining, IsLimitReached: ${remaining <= 0}');
      setState(() {
        // -1 indicates unlimited (admin or premium via DB sentinel)
        _remainingMessages = remaining;
        _isLimitReached = remaining == -1 ? false : remaining <= 0;
      });
    } catch (e) {
      print('Error updating message limits: $e');
      // Default to allowing messages on error
      setState(() {
        _remainingMessages = 20;
        _isLimitReached = false;
      });
    }
  }

  Future<void> _initializeSpeech() async {
    await _speechService.initialize();

    // Listen to transcription updates
    _speechService.transcriptionStream.listen((text) {
      if (text.isNotEmpty) {
        setState(() {
          _inputController.text = text;
        });
      }
    });

    // Listen to status changes
    _speechService.statusStream.listen((status) {
      setState(() {
        _isListening = status == SpeechStatus.listening;
      });
    });
  }

  Future<void> _createNewSession() async {
    try {
      final newSession = await _chatHistoryService.createNewSession();
      await _loadSession(newSession);
    } catch (e) {
      print('Error creating new session: $e');
      _addWelcomeMessage();
    }
  }

  Future<void> _loadSession(ChatSession session) async {
    setState(() {
      _currentSession = session;
      _messages =
          []; // Start with empty messages, let server reload populate them
    });

    // Force reload messages from server for this session
    await _reloadMessagesFromServer(session.id);

    // Scroll to bottom
    _scrollToBottom();
  }

  Future<void> _reloadMessagesFromServer(String sessionId) async {
    try {
      print('🔍 DEBUG: Reloading messages for session $sessionId');

      // If not authenticated, load from local storage immediately
      if (!_authService.isAuthenticated) {
        print('🔍 DEBUG: Not authenticated - loading messages from local storage');
        final localSession = _chatHistoryService
            .sessions
            .where((s) => s.id == sessionId)
            .cast<ChatSession?>()
            .firstWhere((s) => s != null, orElse: () => null);

        if (localSession != null) {
          setState(() {
            _messages = List<ChatMessage>.from(localSession.messages);
          });
          print('🔍 DEBUG: Loaded ${_messages.length} local messages for session $sessionId');
          if (_messages.isEmpty) {
            _addWelcomeMessage();
          }
          return;
        }
      }

      // Get fresh messages from Supabase for this session
      final messagesResponse = await SupabaseService.client
          .from('messages')
          .select('*')
          .eq('chat_id', sessionId)
          .order('created_at', ascending: true);

      print(
          '🔍 DEBUG: Found ${messagesResponse.length} messages for session $sessionId');

      // If server returned no messages, fallback to local storage
      if (messagesResponse.isEmpty) {
        print('🔍 DEBUG: Server returned no messages - falling back to local storage');
        final localSession = _chatHistoryService
            .sessions
            .where((s) => s.id == sessionId)
            .cast<ChatSession?>()
            .firstWhere((s) => s != null, orElse: () => null);

        if (localSession != null && localSession.messages.isNotEmpty) {
          setState(() {
            _messages = List<ChatMessage>.from(localSession.messages);
          });
          print('🔍 DEBUG: Loaded ${_messages.length} local messages for session $sessionId');
          return;
        }
      }

      final messages = messagesResponse
          .map((m) => ChatMessage.fromJson({
                'id': m['id'],
                'text': m['content'] ?? '',
                'isUser': m['role'] == 'user',
                'timestamp': m['created_at'],
                'type': 'text',
                'metadata': null,
              }))
          .toList();

      // Debug the actual message content
      print('🔍 DEBUG: Raw message data: $messagesResponse');
      for (var i = 0; i < messages.length; i++) {
        print(
            '🔍 DEBUG: Message $i: "${messages[i].text}" isUser: ${messages[i].isUser}');
      }

      setState(() {
        _messages = messages;
      });

      print('🔍 DEBUG: Loaded ${_messages.length} messages into UI');
      print(
          '🔍 DEBUG: Current _messages length after setState: ${_messages.length}');

      // Add welcome message only if no messages were found anywhere
      if (_messages.isEmpty) {
        print('🔍 DEBUG: No messages found, adding welcome message');
        _addWelcomeMessage();
      }
    } catch (e) {
      print('🔍 DEBUG: Error reloading messages: $e');
      // On error, try local fallback
      try {
        final localSession = _chatHistoryService
            .sessions
            .where((s) => s.id == sessionId)
            .cast<ChatSession?>()
            .firstWhere((s) => s != null, orElse: () => null);
        if (localSession != null) {
          setState(() {
            _messages = List<ChatMessage>.from(localSession.messages);
          });
          print('🔍 DEBUG: Fallback loaded ${_messages.length} local messages');
          if (_messages.isEmpty) {
            _addWelcomeMessage();
          }
          return;
        }
      } catch (_) {}

      // If all else fails, add welcome message
      _addWelcomeMessage();
    }
  }

  void _addWelcomeMessage() {
    print(
        '🔍 DEBUG: Adding welcome message. Current messages count: ${_messages.length}');

    // Check if welcome message already exists
    final hasWelcomeMessage = _messages.any((m) => 
        !m.isUser && m.text.startsWith("Hello! I'm Agent T, your crypto concierge"));
    
    if (hasWelcomeMessage) {
      print('🔍 DEBUG: Welcome message already exists, skipping');
      return;
    }

    final welcomeMessage = ChatMessage.text(
      text:
          "Hello! I'm Agent T, your crypto concierge. I can help you manage your digital assets, answer questions, and more. "
          "I'm at your service. How can I help?",
      isUser: false,
    );

    setState(() {
      _messages.add(welcomeMessage);
    });

    print(
        '🔍 DEBUG: Welcome message added. New messages count: ${_messages.length}');

    // Save to current session (but it won't count towards limit as it's a greeting)
    if (_currentSession != null) {
      _chatHistoryService.addMessageToSession(
        _currentSession!.id,
        welcomeMessage,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.backgroundDark,
                  AppColors.backgroundDark.withBlue(30),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  _buildHeader(),
                  Expanded(child: _buildMessageList()),
                  _buildInputArea(),
                ],
              ),
            ),
          ),
          ChatSidebar(
            isVisible: _isSidebarVisible,
            onClose: () => setState(() => _isSidebarVisible = false),
            onSessionSelected: _onSessionSelected,
            currentSessionId: _currentSession?.id,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Menu button for sidebar
          IconButton(
            icon: Icon(Icons.menu, color: Colors.white.withOpacity(0.8)),
            onPressed: () => setState(() => _isSidebarVisible = true),
          ),
          const SizedBox(width: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset(
              'assets/bluelight.png',
              width: 40,
              height: 40,
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primaryBlue.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet,
                    color: AppColors.primaryBlue,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentSession?.title ?? 'Agent T',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'Agent T - Your Crypto Concierge',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    print('🔍 DEBUG: Building message list with ${_messages.length} messages');
    for (var i = 0; i < _messages.length; i++) {
      print(
          '🔍 DEBUG: Rendering message $i: "${_messages[i].text.substring(0, _messages[i].text.length > 50 ? 50 : _messages[i].text.length)}..."');
    }

    // Show warning based on remaining messages from database, not local message count
    // Local message count includes historical messages from all sessions
    final shouldShowWarning = _remainingMessages <= 5 && _remainingMessages > 0;
    // Do not show blocked when unlimited (-1) or when not actually reached
    final shouldShowBlocked = _isLimitReached && _remainingMessages != -1;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _messages.length + 
                 (_isTyping ? 1 : 0) + 
                 (shouldShowWarning ? 1 : 0) + 
                 (shouldShowBlocked ? 1 : 0),
      itemBuilder: (context, index) {
        // Show warning widget after 15th agent response
        if (shouldShowWarning && index == _messages.length) {
          return MessageLimitWidget(
            type: MessageLimitType.warning,
            remainingMessages: _remainingMessages,
            onUpgradePressed: _navigateToPricing,
          );
        }
        
        // Show blocked widget when limit reached
        if (shouldShowBlocked && index == _messages.length + (shouldShowWarning ? 1 : 0)) {
          return MessageLimitWidget(
            type: MessageLimitType.blocked,
            remainingMessages: 0,
            onUpgradePressed: _navigateToPricing,
          );
        }
        
        // Show typing indicator
        if (_isTyping && index == _messages.length + (shouldShowWarning ? 1 : 0) + (shouldShowBlocked ? 1 : 0)) {
          return _buildTypingIndicator();
        }
        
        // Show regular message
        return _buildMessageBubble(_messages[index]);
      },
    );
  }

  bool _isWelcomeMessage(ChatMessage message) {
    return !message.isUser && message.text.startsWith("Hello! I'm Agent T, your crypto concierge");
  }

  void _navigateToPricing() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PricingScreen()),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final isUser = message.isUser;
    final alignment = isUser ? Alignment.centerRight : Alignment.centerLeft;

    return Container(
      alignment: alignment,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isUser) ...[
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.primaryBlue.withOpacity(0.2),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/agent_t_pfp.png',
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.smart_toy,
                          size: 20,
                          color: AppColors.primaryBlue,
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  child: isUser
                      ? _buildUserBubble(message)
                      : _buildAssistantBubble(message),
                ),
              ),
              if (isUser) const SizedBox(width: 8),
            ],
          ),
          if (!isUser && !_isWelcomeMessage(message)) ...[
            const SizedBox(height: 4),
            _buildAssistantActions(message),
          ],
        ],
      ),
    );
  }

  Widget _buildUserBubble(ChatMessage message) {
    if (message.type == MessageType.image) {
      final dataUri = message.metadata != null
          ? ((message.metadata!['thumb_data_uri'] as String?) ??
              (message.metadata!['data_uri'] as String?))
          : null;
      Widget imageWidget;
      if (dataUri != null && dataUri.contains(',')) {
        final b64 = dataUri.split(',').last;
        try {
          final bytes = base64Decode(b64);
          imageWidget = ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              bytes,
              width: 200,
              height: 200,
              fit: BoxFit.cover,
            ),
          );
        } catch (_) {
          imageWidget = const Icon(Icons.image, color: AppColors.textPrimary, size: 48);
        }
      } else {
        imageWidget = const Icon(Icons.image, color: AppColors.textPrimary, size: 48);
      }

      return GlassmorphismContainer(
        glassType: GlassType.light,
        borderRadius: BorderRadius.circular(20).copyWith(bottomRight: const Radius.circular(4)),
        padding: const EdgeInsets.all(12),
        blur: 8.0,
        showGlow: true,
        customGradient: AppColors.primaryGradient.scale(0.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            imageWidget,
            if (message.text.trim().isNotEmpty && message.text.trim() != '[image]') ...[
              const SizedBox(height: 8),
              Text(
                message.text,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return GlassmorphismContainer(
      glassType: GlassType.light,
      borderRadius: BorderRadius.circular(20).copyWith(bottomRight: const Radius.circular(4)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      blur: 8.0,
      showGlow: true,
      customGradient: AppColors.primaryGradient.scale(0.4),
      child: Text(
        message.text,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildAssistantBubble(ChatMessage message) {
    return GlassmorphismContainer(
      glassType: GlassType.medium,
      borderRadius: BorderRadius.circular(20).copyWith(bottomLeft: const Radius.circular(4)),
      padding: const EdgeInsets.all(16),
      blur: 12.0,
      showGlow: true,
      customGradient: AppColors.glassGradient,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMessageContent(message),
        ],
      ),
    );
  }

  Widget _buildMessageContent(ChatMessage message) {
    switch (message.type) {
      case MessageType.text:
        // If assistant text contains an address, show our QR/Toggle UI
        if (!message.isUser) {
          // Do NOT inject QR for send confirmations to avoid confusion
          final lower = message.text.toLowerCase();
          final isSendConfirm = lower.contains('i would send') || lower.contains('transaction');
          if (!isSendConfirm) {
            final addr = _extractAddressFromText(message.text);
            if (addr != null) {
              return _QrToggle(address: addr, caption: message.text);
            }
          }
        }
        return MarkdownBody(
          data: message.text,
          styleSheet: MarkdownStyleSheet(
            p: const TextStyle(color: Colors.white, fontSize: 16),
            strong: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            em: const TextStyle(
              color: Colors.white,
              fontStyle: FontStyle.italic,
            ),
            code: TextStyle(
              backgroundColor: Colors.white.withOpacity(0.1),
              color: AppColors.primaryBlue,
              fontFamily: 'monospace',
              fontSize: 14,
            ),
            codeblockDecoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
            codeblockPadding: const EdgeInsets.all(12),
            blockquoteDecoration: BoxDecoration(
              color: AppColors.primaryBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: const Border(
                left: BorderSide(
                  color: AppColors.primaryBlue,
                  width: 4,
                ),
              ),
            ),
            listBullet: const TextStyle(
              color: AppColors.primaryBlue,
              fontSize: 16,
            ),
            a: const TextStyle(
              color: AppColors.primaryBlue,
              decoration: TextDecoration.underline,
            ),
          ),
          extensionSet: md.ExtensionSet.gitHubWeb,
          onTapLink: (text, href, title) {
            if (href == null || href.isEmpty) return;
            _handleLinkTap(href);
          },
        );
      case MessageType.qrCode:
        return _buildQrCodeMessage(message);
      case MessageType.transaction:
        return _buildTransactionMessage(message);
      case MessageType.swap:
        return _buildSwapMessage(message);
      default:
        return Text(
          message.text,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        );
    }
  }

  Widget _buildAssistantActions(ChatMessage message) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.copy, size: 18, color: AppColors.textSecondary),
          tooltip: 'Copy',
          onPressed: () => _copyAssistantMessage(message.text),
        ),
      ],
    );
  }

  Future<void> _copyAssistantMessage(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Copied to clipboard'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 1),
        ),
      );
    } catch (e) {
      // Silently ignore copy failures
    }
  }

  Future<void> _handleLinkTap(String href) async {
    final trimmed = href.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return;

    final isHttp = uri.scheme == 'http' || uri.scheme == 'https';
    final looksLikeWeb = trimmed.startsWith('www.');

    if (isHttp || looksLikeWeb) {
      final url = isHttp ? trimmed : 'https://$trimmed';
      if (kIsWeb) {
        try {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        } catch (_) {}
      } else {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => BrowserScreen(initialUrl: url),
          ),
        );
      }
      return;
    }

    try {
      final can = await canLaunchUrl(Uri.parse(trimmed));
      if (can) {
        await launchUrl(Uri.parse(trimmed), mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  Widget _buildQrCodeMessage(ChatMessage message) {
    final address = message.metadata?['address'] ?? '';
    return _QrToggle(address: address, caption: message.text);
  }

  Widget _buildTransactionMessage(ChatMessage message) {
    // TODO: Implement transaction message UI
    return Text(
      message.text,
      style: const TextStyle(color: Colors.white, fontSize: 16),
    );
  }

  Widget _buildSwapMessage(ChatMessage message) {
    // TODO: Implement swap message UI
    return Text(
      message.text,
      style: const TextStyle(color: Colors.white, fontSize: 16),
    );
  }

  Widget _buildTypingIndicator() {
    return Container(
      alignment: Alignment.centerLeft,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primaryBlue.withOpacity(0.2),
            child: ClipOval(
              child: Image.asset(
                'assets/agent_t_pfp.png',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.smart_toy,
                    size: 20,
                    color: AppColors.primaryBlue,
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                _buildDot(0),
                const SizedBox(width: 4),
                _buildDot(1),
                const SizedBox(width: 4),
                _buildDot(2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 600 + (index * 200)),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withOpacity(0.3 + (value * 0.5)),
          ),
        );
      },
      onEnd: () {
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  Widget _buildInputArea() {
    return Column(
      children: [
        // Debug panel
        _buildDebugPanel(),
        if (_attachedImageDataUri != null) _buildAttachmentPreview(),
        
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Debug toggle - tap the handle 5 times to show debug
              GestureDetector(
                onTap: () {
                  _tapCount++;
                  if (_tapCount >= 5) {
                    setState(() {
                      _showDebugPanel = !_showDebugPanel;
                      _tapCount = 0;
                    });
                  }
                  // Reset counter after 2 seconds
                  Timer(Duration(seconds: 2), () => _tapCount = 0);
                },
                child: Container(
                  height: 20,
                  width: double.infinity,
                  child: Center(
                    child: Container(
                      width: 30,
                      height: 3,
                      decoration: BoxDecoration(
                        color: Colors.grey[600],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
              
              SizedBox(height: 8),
              
              // Input field
              Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          // Slash command button
                                                   IconButton(
                           icon: Text(
                             '/',
                             style: TextStyle(
                               color: Colors.white.withOpacity(0.8),
                               fontSize: 18,
                               fontWeight: FontWeight.bold,
                             ),
                           ),
                           tooltip: 'Commands',
                           onPressed: _showCommandPalette,
                         ),
                          Expanded(
                            child: TextField(
                              controller: _inputController,
                              enabled: !_isLimitReached,
                              style: TextStyle(
                                color: _isLimitReached ? Colors.white.withOpacity(0.3) : Colors.white, 
                                fontSize: 16,
                              ),
                              decoration: InputDecoration(
                                hintText: _isLimitReached ? 'Daily limit reached. Upgrade to continue...' : 'Ask me anything...',
                                hintStyle: TextStyle(
                                  color: _isLimitReached ? Colors.white.withOpacity(0.3) : Colors.white.withOpacity(0.5),
                                  fontSize: 16,
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                              ),
                              onSubmitted: (_) => _isLimitReached ? null : _sendMessage(),
                              textInputAction: TextInputAction.send,
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _isListening ? Icons.mic : Icons.mic_none,
                              color: _isListening
                                  ? AppColors.primaryBlue
                                  : Colors.white.withOpacity(0.6),
                            ),
                            onPressed: _toggleVoiceInput,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.attach_file, color: AppColors.textPrimary),
                    onPressed: _showImageSourcePicker,
                    tooltip: 'Attach image',
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: _isLimitReached 
                        ? Colors.grey.withOpacity(0.3) 
                        : AppColors.primaryBlue,
                      shape: BoxShape.circle,
                      boxShadow: _isLimitReached ? [] : [
                        BoxShadow(
                          color: AppColors.primaryBlue.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.send, 
                        color: _isLimitReached ? Colors.white.withOpacity(0.3) : Colors.white,
                      ),
                      onPressed: _isLimitReached ? null : _sendMessage,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDebugPanel() {
    if (!_showDebugPanel) {
      return Container();
    }
    
    return Container(
      margin: EdgeInsets.all(8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.bug_report, color: Colors.blue, size: 16),
              SizedBox(width: 8),
              Text('DEBUG INFO', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
              Spacer(),
              GestureDetector(
                onTap: () => setState(() => _showDebugPanel = false),
                child: Icon(Icons.close, color: Colors.blue, size: 16),
              ),
            ],
          ),
          SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _debugInfo,
              style: TextStyle(color: Colors.green, fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentPreview() {
    // Show a compact preview with Remove action
    Widget thumb;
    try {
      final sourceDataUri = _attachedImageThumbDataUri ?? _attachedImageDataUri!;
      final b64 = sourceDataUri.split(',').last;
      final bytes = base64Decode(b64);
      thumb = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(bytes, width: 44, height: 44, fit: BoxFit.cover),
      );
    } catch (_) {
      thumb = const Icon(Icons.image, color: Colors.white, size: 28);
    }
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 4),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.15)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                thumb,
                const SizedBox(width: 8),
                const Text('Image attached', style: TextStyle(color: Colors.white)),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () {
                    setState(() { 
                      _attachedImageDataUri = null; 
                      _attachedImageThumbDataUri = null; 
                    });
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(6.0),
                    child: Icon(Icons.close, color: Colors.white70, size: 18),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage() async {
    final text = _inputController.text.trim();
    if ((_isLimitReached) || (text.isEmpty && _attachedImageDataUri == null)) return;

    final bool hasImage = _attachedImageDataUri != null;
    final userMessage = hasImage
        ? ChatMessage(
            text: text.isEmpty ? '[image]' : text,
            isUser: true,
            type: MessageType.image,
            metadata: {
              if (_attachedImageThumbDataUri != null) 'thumb_data_uri': _attachedImageThumbDataUri,
              'hasImage': true,
            },
          )
        : ChatMessage.text(text: text, isUser: true);

    // Add user message
    setState(() {
      _messages.add(userMessage);
      _inputController.clear();
      _isTyping = true;
      _debugInfo = 'User message sent, calling AI API...';
    });

    print('🔍 DEBUG: User message added, _isTyping set to true');
    print('🔍 DEBUG: Current messages count: ${_messages.length}');

    // Save to current session
    if (_currentSession != null) {
      await _chatHistoryService.addMessageToSession(
        _currentSession!.id,
        userMessage,
      );
    }

    // Update session title if it's the first user message
    if (_currentSession != null &&
        _messages.where((m) => m.isUser).length == 1) {
      final baseTitle = (text.isEmpty && hasImage) ? 'Image' : text;
      final title = baseTitle.length > 30 ? '${baseTitle.substring(0, 30)}...' : baseTitle;
      await _chatHistoryService.updateSessionTitle(_currentSession!.id, title);
      _currentSession = _currentSession!.copyWith(title: title);
    }

    // Scroll to bottom
    _scrollToBottom();

    setState(() { _debugInfo = 'Making API call to T Backend...'; });

    try {
      final effectiveText = (text.isEmpty && hasImage) ? 'Analyze this image' : text;
      final response = await _chatService.sendMessage(
        effectiveText,
        imageDataUri: _attachedImageDataUri,
      );
      
      setState(() {
        _debugInfo = 'API call successful, processing response...';
      });
      
      final aiMessage = ChatMessage.text(text: response, isUser: false);
      
      setState(() {
        _messages.add(aiMessage);
        _isTyping = false;
        _debugInfo = 'AI response received and displayed successfully';
        // Clear attachment after successful send
        _attachedImageDataUri = null;
        _attachedImageThumbDataUri = null;
      });

      // Save AI response to session
      if (_currentSession != null) {
        await _chatHistoryService.addMessageToSession(
          _currentSession!.id,
          aiMessage,
        );
      }

      // Update message limits after Agent T responds
      await _updateMessageLimits();

      _scrollToBottom();
    } catch (e) {
      setState(() {
        _isTyping = false;
        _debugInfo = 'ERROR: ${e.toString()}';
      });
      
      final errorMessage = ChatMessage.text(
        text: 'Sorry, I encountered an error. Please try again.',
        isUser: false,
      );
      setState(() {
        _messages.add(errorMessage);
      });

      // Save error message to session
      if (_currentSession != null) {
        await _chatHistoryService.addMessageToSession(
          _currentSession!.id,
          errorMessage,
        );
      }

      // Update message limits even after error (error counts as Agent T response)
      await _updateMessageLimits();

      _scrollToBottom();
    }
  }

  Future<void> _showImageSourcePicker() async {
    if (kIsWeb) {
      // Web: default to gallery
      await _pickImageAttachment(ImageSource.gallery);
      return;
    }
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(12),
          child: GlassmorphismContainer(
            glassType: GlassType.overlay,
            borderRadius: BorderRadius.circular(16),
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.camera_alt, color: AppColors.primaryBlue),
                  title: const Text('Take photo', style: TextStyle(color: AppColors.textPrimary)),
                  onTap: () async {
                    Navigator.pop(context);
                    await _pickImageAttachment(ImageSource.camera);
                  },
                ),
                const Divider(color: AppColors.glassBorder),
                ListTile(
                  leading: const Icon(Icons.photo_library, color: AppColors.primaryBlue),
                  title: const Text('Choose from gallery', style: TextStyle(color: AppColors.textPrimary)),
                  onTap: () async {
                    Navigator.pop(context);
                    await _pickImageAttachment(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickImageAttachment(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: source == ImageSource.camera ? 1600 : 1800,
        imageQuality: 90,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      final lower = picked.path.toLowerCase();
      String mime = lower.endsWith('.png')
          ? 'image/png'
          : lower.endsWith('.webp') ? 'image/webp' : 'image/jpeg';
      
      // Enforce max size and build data URI (may re-encode as JPEG)
      final encoded = await _encodeDataUriWithinLimit(bytes, mime);
      final dataUri = encoded.$1;
      mime = encoded.$2;

      // Build thumbnail preview
      final thumbDataUri = await _generateThumbnailDataUri(bytes);

      setState(() {
        _attachedImageDataUri = dataUri;
        _attachedImageThumbDataUri = thumbDataUri ?? _attachedImageDataUri;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Image attach failed: $e')));
    }
  }

  Future<(String, String)> _encodeDataUriWithinLimit(Uint8List inputBytes, String originalMime) async {
    // If already under limit, keep as is
    if (inputBytes.lengthInBytes <= _maxImageBytes) {
      final b64 = base64Encode(inputBytes);
      return ('data:$originalMime;base64,$b64', originalMime);
    }
    try {
      final decoded = img.decodeImage(inputBytes);
      if (decoded == null) {
        final b64 = base64Encode(inputBytes);
        return ('data:$originalMime;base64,$b64', originalMime);
      }
      // Try progressively smaller sizes/qualities
      final targetWidths = [1600, 1280, 1000, 800, 640, 480, 360];
      final qualities = [85, 75, 65, 55, 45, 35, 30];
      for (final w in targetWidths) {
        final resized = decoded.width > w ? img.copyResize(decoded, width: w) : decoded;
        for (final q in qualities) {
          final jpg = img.encodeJpg(resized, quality: q);
          if (jpg.length <= _maxImageBytes) {
            final b64 = base64Encode(jpg);
            return ('data:image/jpeg;base64,$b64', 'image/jpeg');
          }
        }
      }
      // Fallback to the smallest attempt
      final smallest = img.encodeJpg(img.copyResize(decoded, width: 360), quality: 30);
      final b64 = base64Encode(smallest);
      return ('data:image/jpeg;base64,$b64', 'image/jpeg');
    } catch (_) {
      // On failure, return original
      final b64 = base64Encode(inputBytes);
      return ('data:$originalMime;base64,$b64', originalMime);
    }
  }

  Future<String?> _generateThumbnailDataUri(Uint8List inputBytes) async {
    try {
      final decoded = img.decodeImage(inputBytes);
      if (decoded == null) return null;
      final resized = decoded.width > _thumbMaxWidth 
          ? img.copyResize(decoded, width: _thumbMaxWidth)
          : decoded;
      final jpg = img.encodeJpg(resized, quality: 60);
      final b64 = base64Encode(Uint8List.fromList(jpg));
      return 'data:image/jpeg;base64,$b64';
    } catch (_) {
      return null;
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggleVoiceInput() async {
    if (_isListening) {
      await _speechService.stopListening();
    } else {
      await _speechService.startListening(
        onResult: (text) {
          // Automatically send when user stops speaking
          if (text.isNotEmpty && !_speechService.isListening) {
            _sendMessage();
          }
        },
      );
    }
  }

  void _showCommandPalette() {
    final commands = [
      {'label': '/search', 'insert': '/search '},
      {'label': '/swap', 'insert': '/swap '},
      {'label': '/send', 'insert': '/send '},
      {'label': '/receive', 'insert': '/receive '},
      {'label': '/balance', 'insert': '/balance'},
      {'label': '/status', 'insert': '/status '},
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: 360,
          padding: const EdgeInsets.all(16),
          child: GlassmorphismContainer(
            glassType: GlassType.overlay,
            borderRadius: BorderRadius.circular(16),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Commands',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.separated(
                    itemCount: commands.length,
                    separatorBuilder: (_, __) => const Divider(color: AppColors.glassBorder),
                    itemBuilder: (context, index) {
                      final cmd = commands[index];
                      return ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        leading: const Icon(Icons.chevron_right, color: AppColors.primaryBlue),
                        title: Text(
                          cmd['label']!,
                          style: const TextStyle(color: AppColors.textPrimary),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          setState(() {
                            _inputController.text = cmd['insert']!;
                            _inputController.selection = TextSelection.fromPosition(
                              TextPosition(offset: _inputController.text.length),
                            );
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _onSessionSelected(ChatSession session) async {
    await _chatHistoryService.setCurrentSession(session.id);
    await _loadSession(session);
  }



  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _speechService.dispose();
    super.dispose();
  }
}

class _QrToggle extends StatefulWidget {
  final String address;
  final String caption;
  const _QrToggle({Key? key, required this.address, required this.caption}) : super(key: key);

  @override
  State<_QrToggle> createState() => _QrToggleState();
}

class _QrToggleState extends State<_QrToggle> {
  bool _showQr = true;

  void _openFullscreen() {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      builder: (ctx) {
        return GestureDetector(
          onTap: () => Navigator.of(ctx).pop(),
          child: Container(
            color: Colors.transparent,
            padding: const EdgeInsets.all(24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: QrImageView(
                      data: widget.address,
                      size: 320,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.H,
                      embeddedImage: const AssetImage('assets/bluelight.png'),
                      embeddedImageStyle: const QrEmbeddedImageStyle(size: Size(64, 64)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tap anywhere to close',
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.caption,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _showQr = !_showQr),
          onLongPress: () { if (_showQr) _openFullscreen(); },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _showQr
                ? Container(
                    key: const ValueKey('qr'),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: QrImageView(
                      data: widget.address,
                      size: 200,
                      backgroundColor: Colors.white,
                      errorCorrectionLevel: QrErrorCorrectLevel.H,
                      embeddedImage: const AssetImage('assets/bluelight.png'),
                      embeddedImageStyle: const QrEmbeddedImageStyle(size: Size(36, 36)),
                    ),
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _showQr = true),
                    child: Container(
                    key: const ValueKey('addr'),
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.12)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: SelectableText(
                            widget.address,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () async {
                            await Clipboard.setData(ClipboardData(text: widget.address));
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Address copied'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                          child: const Icon(Icons.copy, color: Colors.white70, size: 16),
                        ),
                      ],
                    ),
                  )),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _showQr ? 'Tap to show address' : 'Tap to show QR code',
          style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 12, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }
}

String? _extractAddressFromText(String text) {
  final codeAddr = RegExp(r'`(addr1[0-9a-z]+|addr_test1[0-9a-z]+)`', caseSensitive: false).firstMatch(text);
  if (codeAddr != null) return codeAddr.group(1);
  final bare = RegExp(r'(addr1[0-9a-z]+|addr_test1[0-9a-z]+)', caseSensitive: false).firstMatch(text);
  if (bare != null) return bare.group(1);
  return null;
}
