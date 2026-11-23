import 'package:cloud_firestore/cloud_firestore.dart';

class BoardMessage {
  final String id;
  final String text;
  final String authorUid;
  final String authorName;
  final int schemaVersion;
  final String category;
  final DateTime? createdAt;
  final DateTime? editedAt;

  const BoardMessage({
    required this.id,
    required this.text,
    required this.authorUid,
    required this.authorName,
    this.schemaVersion = 2,
    this.category = 'general',
    this.createdAt,
    this.editedAt,
  });

  bool get isEdited => editedAt != null;

  factory BoardMessage.fromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    final rawCreated = data['createdAt'];
    final rawEdited = data['editedAt'];
    final rawVersion = data['schemaVersion'];

    // Backward-compatible read: v1 docs used 'body' and lacked 'schemaVersion' & 'category'
    final resolvedText = (data['text'] ?? data['body'] ?? '').toString();
    final resolvedVersion = rawVersion is int ? rawVersion : 1;

    return BoardMessage(
      id: doc.id,
      text: resolvedText,
      authorUid: (data['authorUid'] ?? '').toString(),
      authorName: (data['authorName'] ?? 'Unknown').toString(),
      schemaVersion: resolvedVersion,
      category: (data['category'] ?? 'general').toString(),
      createdAt: rawCreated is Timestamp ? rawCreated.toDate() : null,
      editedAt: rawEdited is Timestamp ? rawEdited.toDate() : null,
    );
  }
}