import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:uuid/uuid.dart';
import '../models/chat_session.dart';
import '../models/chat_message.dart';
import '../services/supabase_service.dart';
import '../services/auth_service.dart';

class ChatHistoryService {
  static const String _storageKey = 'chat_sessions';
  static const String _currentSessionKey = 'current_session_id';
  static const _storage = FlutterSecureStorage();
  static const _uuid = Uuid();

  // Singleton pattern
  static final ChatHistoryService _instance = ChatHistoryService._internal();
  factory ChatHistoryService() => _instance;
  ChatHistoryService._internal();

  // In-memory cache
  List<ChatSession> _sessions = [];
  String? _currentSessionId;

  List<ChatSession> get sessions => List.from(_sessions);
  String? get currentSessionId => _currentSessionId;

  SupabaseClient get _supabase => SupabaseService.client;
  AuthService get _authService => AuthService();

  Future<void> initialize() async {
    await _loadFromStorage();
    await _syncWithServer();
  }

  Future<void> _loadFromStorage() async {
    try {
      final sessionsJson = await _storage.read(key: _storageKey);
      final currentSessionId = await _storage.read(key: _currentSessionKey);

      if (sessionsJson != null) {
        final sessionsList = json.decode(sessionsJson) as List;
        _sessions = sessionsList.map((s) => ChatSession.fromJson(s)).toList();
      }

      _currentSessionId = currentSessionId;
    } catch (e) {
      print('Error loading chat history from storage: $e');
    }
  }

  Future<void> _saveToStorage() async {
    try {
      final sessionsJson =
          json.encode(_sessions.map((s) => s.toJson()).toList());
      await _storage.write(key: _storageKey, value: sessionsJson);

      if (_currentSessionId != null) {
        await _storage.write(
            key: _currentSessionKey, value: _currentSessionId!);
      }
    } catch (e) {
      print('Error saving chat history to storage: $e');
    }
  }

  Future<void> _syncWithServer() async {
    try {
      final user = _authService.currentUser;
      if (user == null || user.id.startsWith('guest_')) return;

      // Fetch chats from server
      final chatsResponse = await _supabase
          .from('chats')
          .select('*')
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      final List<ChatSession> serverSessions = [];

      for (final chat in chatsResponse) {
        // Fetch messages for this chat
        final messagesResponse = await _supabase
            .from('messages')
            .select('*')
            .eq('chat_id', chat['id'])
            .order('created_at', ascending: true);

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

        serverSessions.add(ChatSession(
          id: chat['id'],
          title: chat['title'] ?? 'New Chat',
          messages: messages,
          createdAt: DateTime.parse(chat['created_at']),
          updatedAt: DateTime.parse(chat['updated_at'] ?? chat['created_at']),
        ));
      }

      // Merge with local sessions (server takes precedence)
      _sessions = serverSessions;
      await _saveToStorage();
    } catch (e) {
      print('Error syncing with server: $e');
    }
  }

  Future<ChatSession> createNewSession({String? title}) async {
    final sessionId = _uuid.v4();
    final now = DateTime.now();

    final session = ChatSession(
      id: sessionId,
      title: title ?? 'New Chat',
      messages: [],
      createdAt: now,
      updatedAt: now,
    );

    _sessions.insert(0, session);
    _currentSessionId = sessionId;

    await _saveToStorage();
    await _createSessionOnServer(session);

    return session;
  }

  Future<void> _createSessionOnServer(ChatSession session) async {
    try {
      final user = _authService.currentUser;
      if (user == null || user.id.startsWith('guest_')) return;

      await _supabase.from('chats').insert({
        'id': session.id,
        'user_id': user.id,
        'title': session.title,
        'path': '/chat/${session.id}',
        'created_at': session.createdAt.toIso8601String(),
        'updated_at': session.updatedAt.toIso8601String(),
      });
    } catch (e) {
      print('Error creating session on server: $e');
    }
  }

  Future<void> addMessageToCurrentSession(ChatMessage message) async {
    if (_currentSessionId == null) {
      await createNewSession();
    }

    final sessionIndex = _sessions.indexWhere((s) => s.id == _currentSessionId);
    if (sessionIndex == -1) return;

    final updatedMessages =
        List<ChatMessage>.from(_sessions[sessionIndex].messages);
    updatedMessages.add(message);

    // Update title if this is the first user message
    String title = _sessions[sessionIndex].title;
    if (updatedMessages.where((m) => m.isUser).length == 1 && message.isUser) {
      title = _generateTitle(message.text);
    }

    _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
      messages: updatedMessages,
      title: title,
      updatedAt: DateTime.now(),
    );

    await _saveToStorage();
    await _saveMessageToServer(message);

    if (title != _sessions[sessionIndex].title) {
      await _updateSessionTitleOnServer(_currentSessionId!, title);
    }
  }

  // Backward compatibility methods for chat_screen.dart
  Future<void> addMessageToSession(
      String sessionId, ChatMessage message) async {
    final sessionIndex = _sessions.indexWhere((s) => s.id == sessionId);
    if (sessionIndex == -1) return;

    final updatedMessages =
        List<ChatMessage>.from(_sessions[sessionIndex].messages);
    updatedMessages.add(message);

    _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
      messages: updatedMessages,
      updatedAt: DateTime.now(),
    );

    await _saveToStorage();
    await _saveMessageToServer(message);
  }

  String generateSmartTitle(List<ChatMessage> messages) {
    try {
      final firstUserMessage = messages.firstWhere((m) => m.isUser);
      return _generateTitle(firstUserMessage.text);
    } catch (e) {
      return 'New Chat';
    }
  }

  Future<void> updateSessionTitle(String sessionId, String title) async {
    final sessionIndex = _sessions.indexWhere((s) => s.id == sessionId);
    if (sessionIndex == -1) return;

    _sessions[sessionIndex] = _sessions[sessionIndex].copyWith(
      title: title,
      updatedAt: DateTime.now(),
    );

    await _saveToStorage();
    await _updateSessionTitleOnServer(sessionId, title);
  }

  Future<void> setCurrentSession(String sessionId) async {
    _currentSessionId = sessionId;
    await _storage.write(key: _currentSessionKey, value: sessionId);
  }

  Future<void> _saveMessageToServer(ChatMessage message) async {
    try {
      final user = _authService.currentUser;
      if (user == null ||
          user.id.startsWith('guest_') ||
          _currentSessionId == null) {
        return;
      }

      await _supabase.from('messages').insert({
        'id': message.id,
        'chat_id': _currentSessionId,
        'content': message.text,
        'role': message.isUser ? 'user' : 'assistant',
        'created_at': message.timestamp.toIso8601String(),
      });
    } catch (e) {
      print('Error saving message to server: $e');
    }
  }

  Future<void> _updateSessionTitleOnServer(
      String sessionId, String title) async {
    try {
      final user = _authService.currentUser;
      if (user == null || user.id.startsWith('guest_')) return;

      await _supabase.from('chats').update({
        'title': title,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', sessionId);
    } catch (e) {
      print('Error updating session title on server: $e');
    }
  }

  Future<void> switchToSession(String sessionId) async {
    _currentSessionId = sessionId;
    await _storage.write(key: _currentSessionKey, value: sessionId);
  }

  Future<void> deleteSession(String sessionId) async {
    _sessions.removeWhere((s) => s.id == sessionId);

    if (_currentSessionId == sessionId) {
      _currentSessionId = _sessions.isNotEmpty ? _sessions.first.id : null;
    }

    await _saveToStorage();
    await _deleteSessionFromServer(sessionId);
  }

  Future<void> _deleteSessionFromServer(String sessionId) async {
    try {
      final user = _authService.currentUser;
      if (user == null || user.id.startsWith('guest_')) return;

      // Delete messages first
      await _supabase.from('messages').delete().eq('chat_id', sessionId);

      // Delete chat
      await _supabase.from('chats').delete().eq('id', sessionId);
    } catch (e) {
      print('Error deleting session from server: $e');
    }
  }

  ChatSession? getCurrentSession() {
    if (_currentSessionId == null) return null;
    try {
      return _sessions.firstWhere((s) => s.id == _currentSessionId);
    } catch (e) {
      return _sessions.isNotEmpty ? _sessions.first : null;
    }
  }

  List<ChatMessage> getCurrentMessages() {
    final session = getCurrentSession();
    return session?.messages ?? [];
  }

  Future<void> clearAllSessions() async {
    _sessions.clear();
    _currentSessionId = null;
    await _storage.delete(key: _storageKey);
    await _storage.delete(key: _currentSessionKey);
  }

  String _generateTitle(String message) {
    // Simple title generation from first message
    final words = message.split(' ').take(6).join(' ');
    return words.length > 30 ? '${words.substring(0, 30)}...' : words;
  }
}
