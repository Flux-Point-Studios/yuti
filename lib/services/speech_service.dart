import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';

// Speech-to-text service for voice commands
class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _isAvailable = false;
  bool _disposed = false;
  
  // Stream controllers
  final _transcriptionController = StreamController<String>.broadcast();
  final _statusController = StreamController<SpeechStatus>.broadcast();
  
  // Singleton pattern
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;
  SpeechService._internal();
  
  // Getters
  bool get isListening => _isListening;
  bool get isAvailable => _isAvailable;
  Stream<String> get transcriptionStream => _transcriptionController.stream;
  Stream<SpeechStatus> get statusStream => _statusController.stream;
  
  // Initialize speech recognition
  Future<bool> initialize() async {
    if (_disposed) return false;
    try {
      // On web: skip permission_handler checks (speech permission not implemented)
      if (kIsWeb) {
        _isAvailable = await _speech.initialize(
          onStatus: (status) {
            if (_disposed) return;
            debugPrint('Speech status: $status');
            _handleStatusChange(status);
          },
          onError: (error) {
            if (_disposed) return;
            debugPrint('Speech error: $error');
            _statusController.add(SpeechStatus.error);
            _isListening = false;
          },
        );
        if (_isAvailable) {
          _statusController.add(SpeechStatus.ready);
        } else {
          _statusController.add(SpeechStatus.unavailable);
        }
        return _isAvailable;
      }

      // Non-web platforms: check and request microphone permission
      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        final result = await Permission.microphone.request();
        if (!result.isGranted) {
          _statusController.add(SpeechStatus.permissionDenied);
          return false;
        }
      }

      // iOS-specific speech recognition permission; wrap to avoid unimplemented errors
      try {
        final speechPerm = await Permission.speech.status;
        if (!speechPerm.isGranted) {
          final speechResult = await Permission.speech.request();
          if (!speechResult.isGranted) {
            _statusController.add(SpeechStatus.permissionDenied);
            return false;
          }
        }
      } catch (_) {
        // Permission.speech may be unavailable on some platforms; ignore safely
      }
      
      // Initialize speech recognition
      _isAvailable = await _speech.initialize(
        onStatus: (status) {
          if (_disposed) return;
          debugPrint('Speech status: $status');
          _handleStatusChange(status);
        },
        onError: (error) {
          if (_disposed) return;
          debugPrint('Speech error: $error');
          _statusController.add(SpeechStatus.error);
          _isListening = false;
        },
      );
      
      if (_isAvailable) {
        _statusController.add(SpeechStatus.ready);
      } else {
        _statusController.add(SpeechStatus.unavailable);
      }
      
      return _isAvailable;
    } catch (e) {
      if (_disposed) return false;
      debugPrint('Failed to initialize speech: $e');
      _statusController.add(SpeechStatus.error);
      return false;
    }
  }
  
  // Start listening for voice input
  Future<void> startListening({
    Duration? pauseFor,
    void Function(String)? onResult,
  }) async {
    if (_disposed || !_isAvailable || _isListening) return;
    
    try {
      _isListening = true;
      _statusController.add(SpeechStatus.listening);
      
      await _speech.listen(
        onResult: (result) {
          if (_disposed) return;
          final transcript = result.recognizedWords;
          if (!_transcriptionController.isClosed) {
            _transcriptionController.add(transcript);
          }
          if (onResult != null) {
            onResult(transcript);
          }
          if (result.finalResult) {
            stopListening();
          }
        },
        pauseFor: pauseFor ?? const Duration(seconds: 3),
        partialResults: true,
        onDevice: true, // Use on-device recognition if available
        listenMode: stt.ListenMode.confirmation,
      );
    } catch (e) {
      if (_disposed) return;
      debugPrint('Error starting speech recognition: $e');
      _isListening = false;
      _statusController.add(SpeechStatus.error);
    }
  }
  
  // Stop listening
  Future<void> stopListening() async {
    if (_disposed || !_isListening) return;
    
    try {
      await _speech.stop();
      _isListening = false;
      if (!_statusController.isClosed) {
        _statusController.add(SpeechStatus.ready);
      }
    } catch (e) {
      debugPrint('Error stopping speech recognition: $e');
      _isListening = false;
    }
  }
  
  // Cancel listening
  Future<void> cancelListening() async {
    if (_disposed || !_isListening) return;
    
    try {
      await _speech.cancel();
      _isListening = false;
      if (!_statusController.isClosed) {
        _statusController.add(SpeechStatus.ready);
      }
    } catch (e) {
      debugPrint('Error cancelling speech recognition: $e');
      _isListening = false;
    }
  }
  
  // Handle status changes
  void _handleStatusChange(String status) {
    if (_disposed) return;
    switch (status) {
      case 'listening':
        if (!_statusController.isClosed) {
          _statusController.add(SpeechStatus.listening);
        }
        break;
      case 'notListening':
        _isListening = false;
        if (!_statusController.isClosed) {
          _statusController.add(SpeechStatus.ready);
        }
        break;
      case 'done':
        _isListening = false;
        if (!_statusController.isClosed) {
          _statusController.add(SpeechStatus.ready);
        }
        break;
      default:
        break;
    }
  }
  
  // Get available locales
  Future<List<stt.LocaleName>> getAvailableLocales() async {
    if (_disposed || !_isAvailable) return [];
    
    try {
      return await _speech.locales();
    } catch (e) {
      debugPrint('Error getting locales: $e');
      return [];
    }
  }
  
  // Set language/locale
  Future<void> setLocale(String localeId) async {
    // Implementation depends on your requirements
  }
  
  // Clean up resources
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try { stopListening(); } catch (_) {}
    if (!_transcriptionController.isClosed) {
      _transcriptionController.close();
    }
    if (!_statusController.isClosed) {
      _statusController.close();
    }
  }
}

// Speech recognition status
enum SpeechStatus {
  uninitialized,
  ready,
  listening,
  permissionDenied,
  unavailable,
  error,
} 