import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_user.dart';
import '../models/board_message.dart';

class BoardService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference get _messages => _db.collection('messages');

  // READ: Live stream mapped to typed BoardMessage objects
  Stream<List<BoardMessage>> messagesStream() {
    return _messages
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => BoardMessage.fromDoc(doc)).toList());
  }

  // CREATE: Stores authorUid, authorName, text, and serverTimestamp
  Future<void> createMessage({
    required String text,
    String? customDocId,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'unauthenticated',
        message: 'You must be signed in to post a message.',
      );
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    String authorName = user.email ?? 'Anonymous';
    final userDoc = await _db.collection('users').doc(user.uid).get();
    if (userDoc.exists && userDoc.data() != null) {
      final profile = AppUser.fromMap(userDoc.data() as Map<String, dynamic>);
      if (profile.fullName.isNotEmpty) {
        authorName = profile.fullName;
      }
    }

    final payload = {
      'text': trimmed,
      'authorUid': user.uid,
      'authorName': authorName,
      'createdAt': FieldValue.serverTimestamp(),
      'editedAt': null,
    };

    if (customDocId != null) {
      await _messages.doc(customDocId).set(payload);
    } else {
      await _messages.add(payload);
    }
  }

  // UPDATE: Updates only text and editedAt timestamp
  Future<void> updateMessage({
    required String messageId,
    required String newText,
  }) async {
    final trimmed = newText.trim();
    if (trimmed.isEmpty) return;

    await _messages.doc(messageId).update({
      'text': trimmed,
      'editedAt': FieldValue.serverTimestamp(),
    });
  }

  // DELETE: Deletes a single message document by ID
  Future<void> deleteMessage(String messageId) async {
    await _messages.doc(messageId).delete();
  }
}