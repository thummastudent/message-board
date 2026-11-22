import 'package:cloud_firestore/cloud_firestore.dart';

class BoardMessage {
  final String id;
  final String text;
  final String authorUid;
  final String authorName;
  final DateTime? createdAt;
  final DateTime? editedAt;

  const BoardMessage({
    required this.id,
    required this.text,
    required this.authorUid,
    required this.authorName,
    this.createdAt,
    this.editedAt,
  });

  bool get isEdited => editedAt != null;

  factory BoardMessage.fromDoc(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    final rawCreated = data['createdAt'];
    final rawEdited = data['editedAt'];

    return BoardMessage(
      id: doc.id,
      text: (data['text'] ?? '').toString(),
      authorUid: (data['authorUid'] ?? '').toString(),
      authorName: (data['authorName'] ?? 'Unknown').toString(),
      createdAt: rawCreated is Timestamp ? rawCreated.toDate() : null,
      editedAt: rawEdited is Timestamp ? rawEdited.toDate() : null,
    );
  }
}