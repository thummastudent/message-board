import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/board_message.dart';
import '../services/auth_service.dart';
import '../services/board_service.dart';
import '../widgets/message_tile.dart';

class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key});

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen> {
  final AuthService _authService = AuthService();
  final BoardService _boardService = BoardService();
  final _messageController = TextEditingController();

  bool _isPosting = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _postMessage() async {
    if (_isPosting) return;
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    setState(() => _isPosting = true);
    try {
      await _boardService.createMessage(text: text);
      _messageController.clear();
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Post failed (${e.code}): ${e.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  Future<void> _showEditDialog(BoardMessage message) async {
    final editController = TextEditingController(text: message.text);
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Message'),
        content: TextField(
          controller: editController,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, editController.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (updated != null && updated.trim().isNotEmpty) {
      try {
        await _boardService.updateMessage(
          messageId: message.id,
          newText: updated,
        );
      } on FirebaseException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Update denied (${e.code}): ${e.message}')),
          );
        }
      }
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    try {
      await _boardService.deleteMessage(messageId);
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete denied (${e.code}): ${e.message}')),
        );
      }
    }
  }

  // Deliberately attempts an unauthorized write to verify Firestore Security Rules
  Future<void> _runRulesDenialProbe() async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc('unauthorized_other_uid_probe')
          .set({'tampered': true});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('WARNING: Write succeeded! Check rules.')),
        );
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Rules Denial Verified'),
            content: Text(
              'Firestore blocked unauthorized write:\n\n[${e.code}] ${e.message}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = _authService.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Message Board'),
        actions: [
          IconButton(
            tooltip: 'Test Rules Denial',
            icon: const Icon(Icons.security),
            onPressed: _runRulesDenialProbe,
          ),
          IconButton(
            tooltip: 'Sign Out',
            icon: const Icon(Icons.logout),
            onPressed: () => _authService.signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<BoardMessage>>(
              stream: _boardService.messagesStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Error loading board: ${snapshot.error}'),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data ?? [];
                if (messages.isEmpty) {
                  return const Center(
                    child: Text(
                      'No messages yet.\nBe the first to post on the board!',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return MessageTile(
                      message: msg,
                      isMine: msg.authorUid == currentUid,
                      onEdit: () => _showEditDialog(msg),
                      onDelete: () => _deleteMessage(msg.id),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Write a message...',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _postMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _isPosting ? null : _postMessage,
                    child: Text(_isPosting ? '...' : 'Post'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}