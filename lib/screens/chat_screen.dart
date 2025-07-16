import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../services/chat_service.dart';
import '../services/speech_service.dart';
import '../services/chat_history_service.dart';
import '../services/supabase_service.dart';
import '../utils/app_colors.dart';
import '../widgets/chat_sidebar.dart';

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

  bool _isTyping = false;
  bool _isListening = false;
  bool _isSidebarVisible = false;
  ChatSession? _currentSession;

  @override
  void initState() {
    super.initState();
    _initializeChatHistory();
    _initializeSpeech();
  }

  Future<void> _initializeChatHistory() async {
    try {
      await _chatHistoryService.initialize();

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
      _messages = List.from(session.messages);
    });

    // Force reload messages from server for this session
    await _reloadMessagesFromServer(session.id);

    // Add welcome message if session is empty (after server reload)
    if (_messages.isEmpty) {
      _addWelcomeMessage();
    }

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

      setState(() {
        _messages = messages;
      });

      print('🔍 DEBUG: Loaded ${_messages.length} messages into UI');
    } catch (e) {
      print('🔍 DEBUG: Error reloading messages: $e');
    }
  }

  void _addWelcomeMessage() {
    final welcomeMessage = ChatMessage.text(
      text:
          "Hello! I'm Agent T, your crypto concierge. I can help you manage your digital assets, answer questions, and more. "
          "I'm at your service. How can I help?",
      isUser: false,
    );

    setState(() {
      _messages.add(welcomeMessage);
    });

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
          // New chat button
          IconButton(
            icon: Icon(Icons.add, color: Colors.white.withOpacity(0.8)),
            onPressed: _createNewChatFromHeader,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _messages.length + (_isTyping ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isTyping && index == _messages.length) {
          return _buildTypingIndicator();
        }
        return _buildMessageBubble(_messages[index]);
      },
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
                  'assets/@bluelight.png',
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.account_balance_wallet,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue,
        borderRadius: BorderRadius.circular(
          20,
        ).copyWith(bottomRight: const Radius.circular(4)),
      ),
      child: Text(
        message.text,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
    );
  }

  Widget _buildAssistantBubble(ChatMessage message) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(
        20,
      ).copyWith(bottomLeft: const Radius.circular(4)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(
              20,
            ).copyWith(bottomLeft: const Radius.circular(4)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primaryBlue.withOpacity(0.15),
                Colors.black.withOpacity(0.3),
              ],
            ),
            border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (message.type == MessageType.text)
                MarkdownBody(
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
                )
              else if (message.type == MessageType.qrCode)
                _buildQrCodeMessage(message)
              else if (message.type == MessageType.transaction)
                _buildTransactionMessage(message)
              else if (message.type == MessageType.swap)
                _buildSwapMessage(message),
            ],
          ),
        ),
      ),
    );
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
                'assets/@bluelight.png',
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.account_balance_wallet,
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
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
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
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: 'Ask me anything...',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 16,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
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
              color: AppColors.primaryBlue,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: _sendMessage,
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    final userMessage = ChatMessage.text(text: text, isUser: true);

    // Add user message
    setState(() {
      _messages.add(userMessage);
      _inputController.clear();
      _isTyping = true;
    });

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
      final smartTitle = _chatHistoryService.generateSmartTitle(_messages);
      await _chatHistoryService.updateSessionTitle(
        _currentSession!.id,
        smartTitle,
      );
      setState(() {
        _currentSession = _currentSession!.copyWith(title: smartTitle);
      });
    }

    // Scroll to bottom
    _scrollToBottom();

    try {
      // Process message
      final response = await _chatService.processMessage(text);

      setState(() {
        _messages.add(response);
        _isTyping = false;
      });

      // Save assistant response to current session
      if (_currentSession != null) {
        await _chatHistoryService.addMessageToSession(
          _currentSession!.id,
          response,
        );
      }

      _scrollToBottom();
    } catch (e) {
      final errorMessage = ChatMessage.text(
        text: "❌ I'm sorry, something went wrong. Please try again.",
        isUser: false,
      );

      setState(() {
        _messages.add(errorMessage);
        _isTyping = false;
      });

      // Save error message to current session
      if (_currentSession != null) {
        await _chatHistoryService.addMessageToSession(
          _currentSession!.id,
          errorMessage,
        );
      }
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

  Future<void> _createNewChatFromHeader() async {
    final newSession = await _chatHistoryService.createNewSession();
    await _onSessionSelected(newSession);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _speechService.dispose();
    super.dispose();
  }
}
