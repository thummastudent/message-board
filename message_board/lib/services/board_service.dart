import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_user.dart';
import '../models/board_message.dart';

class BoardService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  CollectionReference get _messages => _db.collection('messages');

  // SPICE #6: Live stream capped by pageSize (newest messages first, reversed for display)
  Stream<List<BoardMessage>> messagesStream({int limit = 25}) {
    return _messages
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => BoardMessage.fromDoc(doc))
            .toList()
            .reversed
            .toList());
  }

  // SPICE #6: Cursor-based pagination to fetch older pages using startAfterDocument
  Future<QuerySnapshot> fetchOlderPage({
    required DocumentSnapshot lastVisibleDoc,
    int pageSize = 25,
  }) {
    return _messages
        .orderBy('createdAt', descending: true)
        .startAfterDocument(lastVisibleDoc)
        .limit(pageSize)
        .get();
  }

  // Helper to fetch raw snapshot page for cursor tracking
  Future<QuerySnapshot> fetchLatestPageSnapshot({int pageSize = 25}) {
    return _messages
        .orderBy('createdAt', descending: true)
        .limit(pageSize)
        .get();
  }

  Future<String> _resolveAuthorName(User user) async {
    String authorName = user.email ?? 'Anonymous';
    final userDoc = await _db.collection('users').doc(user.uid).get();
    if (userDoc.exists && userDoc.data() != null) {
      final profile = AppUser.fromMap(userDoc.data() as Map<String, dynamic>);
      if (profile.fullName.isNotEmpty) {
        authorName = profile.fullName;
      }
    }
    return authorName;
  }

  // CREATE (v2 schema + idempotency)
  Future<void> createMessage({
    required String text,
    String? customDocId,
    String category = 'general',
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

    final authorName = await _resolveAuthorName(user);

    final payload = {
      'text': trimmed,
      'authorUid': user.uid,
      'authorName': authorName,
      'schemaVersion': 2,
      'category': category,
      'createdAt': FieldValue.serverTimestamp(),
      'editedAt': null,
    };

    if (customDocId != null) {
      final docRef = _messages.doc(customDocId);
      await _db.runTransaction((transaction) async {
        final existing = await transaction.get(docRef);
        if (!existing.exists) {
          transaction.set(docRef, payload);
        }
      });
    } else {
      await _messages.add(payload);
    }
  }

  // SPICE #5: Seed a legacy v1 document
  Future<void> seedLegacyV1Message() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final authorName = await _resolveAuthorName(user);

    await _messages.add({
      'body': 'Legacy v1 post (uses old "body" field, no schemaVersion/category)',
      'authorUid': user.uid,
      'authorName': authorName,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // SPICE #5: Lossless migration from v1 to v2
  Future<int> migrateV1ToV2() async {
    final user = _auth.currentUser;
    if (user == null) return 0;

    final query = await _messages.where('authorUid', isEqualTo: user.uid).get();

    final batch = _db.batch();
    int migratedCount = 0;

    for (final doc in query.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final version = data['schemaVersion'];
      if (version == null || (version is int && version < 2)) {
        final legacyText = (data['text'] ?? data['body'] ?? '').toString();
        batch.update(doc.reference, {
          'text': legacyText,
          'schemaVersion': 2,
          'category': data['category'] ?? 'general',
          'body': FieldValue.delete(),
        });
        migratedCount++;
      }
    }

    if (migratedCount > 0) {
      await batch.commit();
    }
    return migratedCount;
  }

  // SPICE #6: Seed 105 messages using atomic WriteBatch to demonstrate cursor pagination
  Future<void> seedBatchMessages({int count = 105}) async {
    final user = _auth.currentUser;
    if (user == null) return;
    final authorName = await _resolveAuthorName(user);

    final batch = _db.batch();
    final baseTime = DateTime.now().subtract(Duration(minutes: count));

    for (int i = 1; i <= count; i++) {
      final docRef = _messages.doc();
      batch.set(docRef, {
        'text': 'Seeded batch message #$i of$count',
        'authorUid': user.uid,
        'authorName': authorName,
        'schemaVersion': 2,
        'category': 'batch-seed',
        'createdAt': Timestamp.fromDate(baseTime.add(Duration(seconds: i))),
        'editedAt': null,
      });
    }

    await batch.commit();
  }

  // SPICE #6: Atomic batch delete of all messages owned by the signed-in user
  Future<int> deleteAllMyMessagesBatch() async {
    final user = _auth.currentUser;
    if (user == null) return 0;

    final query = await _messages.where('authorUid', isEqualTo: user.uid).get();
    if (query.docs.isEmpty) return 0;

    final batch = _db.batch();
    for (final doc in query.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    return query.docs.length;
  }

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

  Future<void> deleteMessage(String messageId) async {
    await _messages.doc(messageId).delete();
  }
}