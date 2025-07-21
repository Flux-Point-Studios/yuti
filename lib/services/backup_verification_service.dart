import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BackupVerificationService {
  static const String _backupVerifiedKey = 'mnemonic_backup_verified';
  static const String _backupVerificationAttemptsKey = 'backup_verification_attempts';
  static const _storage = FlutterSecureStorage();
  
  // Singleton pattern
  static final BackupVerificationService _instance = BackupVerificationService._internal();
  factory BackupVerificationService() => _instance;
  BackupVerificationService._internal();

  /// Check if user has verified their mnemonic backup
  Future<bool> isBackupVerified() async {
    try {
      final String? verified = await _storage.read(key: _backupVerifiedKey);
      return verified == 'true';
    } catch (e) {
      print('🔍 DEBUG: Error checking backup verification status: $e');
      return false;
    }
  }

  /// Mark backup as verified
  Future<void> markBackupAsVerified() async {
    try {
      await _storage.write(key: _backupVerifiedKey, value: 'true');
      await _storage.delete(key: _backupVerificationAttemptsKey); // Reset attempts
      print('🔍 DEBUG: Backup marked as verified');
    } catch (e) {
      print('🔍 DEBUG: Error marking backup as verified: $e');
    }
  }

  /// Reset backup verification (when wallet is recreated)
  Future<void> resetBackupVerification() async {
    try {
      await _storage.delete(key: _backupVerifiedKey);
      await _storage.delete(key: _backupVerificationAttemptsKey);
      print('🔍 DEBUG: Backup verification reset');
    } catch (e) {
      print('🔍 DEBUG: Error resetting backup verification: $e');
    }
  }

  /// Get number of verification attempts made
  Future<int> getVerificationAttempts() async {
    try {
      final String? attempts = await _storage.read(key: _backupVerificationAttemptsKey);
      return int.tryParse(attempts ?? '0') ?? 0;
    } catch (e) {
      print('🔍 DEBUG: Error getting verification attempts: $e');
      return 0;
    }
  }

  /// Increment verification attempts
  Future<void> incrementVerificationAttempts() async {
    try {
      final int currentAttempts = await getVerificationAttempts();
      await _storage.write(key: _backupVerificationAttemptsKey, value: (currentAttempts + 1).toString());
    } catch (e) {
      print('🔍 DEBUG: Error incrementing verification attempts: $e');
    }
  }

  /// Generate random word positions for verification
  List<int> generateRandomWordPositions({int count = 4, int totalWords = 24}) {
    final random = Random();
    final Set<int> positions = <int>{};
    
    while (positions.length < count) {
      positions.add(random.nextInt(totalWords));
    }
    
    return positions.toList()..sort();
  }

  /// Create verification challenge for mnemonic backup
  BackupVerificationChallenge createVerificationChallenge(String mnemonic) {
    final List<String> words = mnemonic.split(' ');
    
    if (words.length < 12) {
      throw Exception('Invalid mnemonic: must have at least 12 words');
    }
    
    // Generate 4 random positions to test
    final List<int> positions = generateRandomWordPositions(count: 4, totalWords: words.length);
    
    // Create the challenge
    final List<WordChallenge> challenges = positions.map((position) {
      return WordChallenge(
        position: position + 1, // 1-based position for user display
        correctWord: words[position],
      );
    }).toList();
    
    return BackupVerificationChallenge(challenges: challenges);
  }

  /// Verify user's answers to the backup challenge
  BackupVerificationResult verifyBackupChallenge(
    BackupVerificationChallenge challenge,
    Map<int, String> userAnswers,
  ) {
    int correctAnswers = 0;
    final List<int> incorrectPositions = [];
    
    for (final wordChallenge in challenge.challenges) {
      final userAnswer = userAnswers[wordChallenge.position]?.trim().toLowerCase();
      final correctAnswer = wordChallenge.correctWord.toLowerCase();
      
      if (userAnswer == correctAnswer) {
        correctAnswers++;
      } else {
        incorrectPositions.add(wordChallenge.position);
      }
    }
    
    final bool isVerified = correctAnswers == challenge.challenges.length;
    
    return BackupVerificationResult(
      isVerified: isVerified,
      correctAnswers: correctAnswers,
      totalQuestions: challenge.challenges.length,
      incorrectPositions: incorrectPositions,
      accuracy: correctAnswers / challenge.challenges.length,
    );
  }

  /// Get suggestions for common mnemonic word mistakes
  List<String> getSimilarWords(String word) {
    // This could be expanded with a comprehensive BIP39 wordlist comparison
    // For now, return some basic suggestions
    final commonMistakes = {
      'abandon': ['about', 'ability'],
      'ability': ['abandon', 'about'],
      'about': ['abandon', 'ability'],
      'above': ['about', 'absorb'],
      'absorb': ['above', 'abstract'],
      // Add more as needed...
    };
    
    return commonMistakes[word.toLowerCase()] ?? [];
  }

  /// Get user-friendly messages for verification results
  String getVerificationMessage(BackupVerificationResult result) {
    if (result.isVerified) {
      return '🎉 Perfect! Your backup is verified and secure.';
    } else if (result.accuracy >= 0.75) {
      return '⚠️ Almost there! Check words at positions: ${result.incorrectPositions.join(', ')}';
    } else if (result.accuracy >= 0.5) {
      return '❌ Please double-check your backup. Several words don\'t match.';
    } else {
      return '🚨 Backup verification failed. Please review your backup carefully.';
    }
  }

  /// Check if backup verification is required
  Future<bool> isVerificationRequired() async {
    final bool verified = await isBackupVerified();
    if (verified) return false;
    
    final int attempts = await getVerificationAttempts();
    // Allow up to 3 attempts before requiring re-backup
    return attempts < 3;
  }
}

/// Data class for backup verification challenge
class BackupVerificationChallenge {
  final List<WordChallenge> challenges;
  
  const BackupVerificationChallenge({required this.challenges});
  
  /// Get positions being tested (for UI display)
  List<int> get positions => challenges.map((c) => c.position).toList();
}

/// Individual word challenge within backup verification
class WordChallenge {
  final int position; // 1-based position (for user display)
  final String correctWord;
  
  const WordChallenge({
    required this.position,
    required this.correctWord,
  });
}

/// Result of backup verification attempt
class BackupVerificationResult {
  final bool isVerified;
  final int correctAnswers;
  final int totalQuestions;
  final List<int> incorrectPositions;
  final double accuracy;
  
  const BackupVerificationResult({
    required this.isVerified,
    required this.correctAnswers,
    required this.totalQuestions,
    required this.incorrectPositions,
    required this.accuracy,
  });
  
  @override
  String toString() {
    return 'BackupVerificationResult(verified: $isVerified, score: $correctAnswers/$totalQuestions, accuracy: ${(accuracy * 100).toStringAsFixed(1)}%)';
  }
} 