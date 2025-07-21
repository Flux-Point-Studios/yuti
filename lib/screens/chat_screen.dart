import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:qr_flutter/qr_flutter.dart';
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
import '../screens/profile_screen.dart';
import '../screens/pricing_screen.dart';
import '../screens/wallet_screen.dart';

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

  bool _isTyping = false;
  bool _isListening = false;
  bool _isSidebarVisible = false;
  ChatSession? _currentSession;
  
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
    _initializeChatHistory();
    _initializeSpeech();
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
      setState(() {
        _remainingMessages = remaining;
        _isLimitReached = remaining <= 0;
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

      // Get fresh messages from Supabase for this session
      final messagesResponse = await SupabaseService.client
          .from('messages')
          .select('*')
          .eq('chat_id', sessionId)
          .order('created_at', ascending: true);

      print(
          '🔍 DEBUG: Found ${messagesResponse.length} messages for session $sessionId');

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

      // Add welcome message only if no messages were found from server
      if (_messages.isEmpty) {
        print('🔍 DEBUG: No messages found, adding welcome message');
        _addWelcomeMessage();
      }
    } catch (e) {
      print('🔍 DEBUG: Error reloading messages: $e');
      // On error, add welcome message
      _addWelcomeMessage();
    }
  }

  void _addWelcomeMessage() {
    print(
        '🔍 DEBUG: Adding welcome message. Current messages count: ${_messages.length}');

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

    // Save to current session
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
          // Wallet button
          IconButton(
            icon: Icon(Icons.account_balance_wallet, color: Colors.white.withOpacity(0.8)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => WalletScreen(authService: _authService),
                ),
              );
            },
          ),
          // Profile button
          IconButton(
            icon: Icon(Icons.person, color: Colors.white.withOpacity(0.8)),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
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

    // Count Agent T responses
    final agentResponses = _messages.where((m) => !m.isUser).length;
    final shouldShowWarning = agentResponses >= 15 && agentResponses < 20 && _remainingMessages <= 5;
    final shouldShowBlocked = _isLimitReached;

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
      child: Row(
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
    );
  }

  Widget _buildUserBubble(ChatMessage message) {
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
          ),
          onTapLink: (text, href, title) {
            // TODO: Handle link taps
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

  Widget _buildQrCodeMessage(ChatMessage message) {
    final address = message.metadata?['address'] ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          message.text,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: QrImageView(
            data: address,
            size: 200,
            backgroundColor: Colors.white,
          ),
        ),
      ],
    );
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

  void _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isLimitReached) return;

    final userMessage = ChatMessage.text(text: text, isUser: true);

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
      final title = text.length > 30 ? '${text.substring(0, 30)}...' : text;
      await _chatHistoryService.updateSessionTitle(_currentSession!.id, title);
      _currentSession = _currentSession!.copyWith(title: title);
    }

    // Scroll to bottom
    _scrollToBottom();

    try {
      setState(() {
        _debugInfo = 'Making API call to T Backend...';
      });
      
      final response = await _chatService.sendMessage(text);
      
      setState(() {
        _debugInfo = 'API call successful, processing response...';
      });
      
      final aiMessage = ChatMessage.text(text: response, isUser: false);
      
      setState(() {
        _messages.add(aiMessage);
        _isTyping = false;
        _debugInfo = 'AI response received and displayed successfully';
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
