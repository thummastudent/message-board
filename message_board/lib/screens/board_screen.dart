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

  static const int _pageSize = 25;
  int _currentLimit = _pageSize;
  bool _isPosting = false;
  late String _currentDraftId;

  @override
  void initState() {
    super.initState();
    _currentDraftId = _generateDraftId();
  }

  String _generateDraftId() {
    final uid = _authService.currentUser?.uid ?? 'anon';
    return '${uid}_${DateTime.now().microsecondsSinceEpoch}';
  }

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
      await _boardService.createMessage(
        text: text,
        customDocId: _currentDraftId,
      );
      _messageController.clear();
      _currentDraftId = _generateDraftId();
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

  Future<void> _runIdempotentDuplicateTest() async {
    final deterministicId = _generateDraftId();
    try {
      await Future.wait([
        _boardService.createMessage(
          text: 'Idempotency check (concurrent duplicate write)',
          customDocId: deterministicId,
        ),
        _boardService.createMessage(
          text: 'Idempotency check (concurrent duplicate write)',
          customDocId: deterministicId,
        ),
      ]);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Fired 2 concurrent writes for $deterministicId — only 1 doc created!',
            ),
          ),
        );
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Idempotency test error: ${e.message}')),
        );
      }
    }
  }

  Future<void> _handleSchemaAction(String action) async {
    try {
      if (action == 'seed_v1') {
        await _boardService.seedLegacyV1Message();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Seeded legacy v1 message document.')),
          );
        }
      } else if (action == 'migrate_v2') {
        final count = await _boardService.migrateV1ToV2();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Migrated $count v1 document(s) to v2!')),
          );
        }
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Schema action error: ${e.message}')),
        );
      }
    }
  }

  Future<void> _handleBatchAction(String action) async {
    try {
      if (action == 'seed_105') {
        await _boardService.seedBatchMessages(count: 105);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Batch-seeded 105 messages (showing latest 25).'),
            ),
          );
        }
      } else if (action == 'cursor_probe') {
        final firstPage =
            await _boardService.fetchLatestPageSnapshot(pageSize: _pageSize);
        if (firstPage.docs.isEmpty) return;
        final cursorDoc = firstPage.docs.last;
        final nextPage = await _boardService.fetchOlderPage(
          lastVisibleDoc: cursorDoc,
          pageSize: _pageSize,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Cursor query after ${cursorDoc.id}: fetched ${nextPage.docs.length} older docs.',
              ),
            ),
          );
        }
      } else if (action == 'clear_mine') {
        final deleted = await _boardService.deleteAllMyMessagesBatch();
        setState(() => _currentLimit = _pageSize);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Atomic batch deleted $deleted of your messages.'),
            ),
          );
        }
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Batch action error: ${e.message}')),
        );
      }
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
          PopupMenuButton<String>(
            tooltip: 'Batch & Pagination (Spice #6)',
            icon: const Icon(Icons.layers_outlined),
            onSelected: _handleBatchAction,
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'seed_105',
                child: Text('Batch Seed 105 Messages'),
              ),
              PopupMenuItem(
                value: 'cursor_probe',
                child: Text('Test Cursor Page Query'),
              ),
              PopupMenuItem(
                value: 'clear_mine',
                child: Text('Batch Delete All My Posts'),
              ),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: 'Schema Versioning (Spice #5)',
            icon: const Icon(Icons.schema_outlined),
            onSelected: _handleSchemaAction,
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 'seed_v1',
                child: Text('Seed Legacy v1 Doc'),
              ),
              PopupMenuItem(
                value: 'migrate_v2',
                child: Text('Migrate v1 -> v2'),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Test Idempotent Duplicate Submit',
            icon: const Icon(Icons.repeat_one),
            onPressed: _runIdempotentDuplicateTest,
          ),
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
              stream: _boardService.messagesStream(limit: _currentLimit),
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

                final hasMorePages = messages.length >= _currentLimit;

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length + (hasMorePages ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (hasMorePages && index == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.expand_less),
                          label: Text(
                            'Showing latest ${messages.length} • Load 25 older',
                          ),
                          onPressed: () {
                            setState(() {
                              _currentLimit += _pageSize;
                            });
                          },
                        ),
                      );
                    }

                    final msgIndex = hasMorePages ? index - 1 : index;
                    final msg = messages[msgIndex];
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