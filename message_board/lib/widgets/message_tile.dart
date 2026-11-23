import 'package:flutter/material.dart';
import '../models/board_message.dart';

class MessageTile extends StatelessWidget {
  final BoardMessage message;
  final bool isMine;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const MessageTile({
    super.key,
    required this.message,
    required this.isMine,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      child: ListTile(
        title: Text(
          message.text,
          style: const TextStyle(fontSize: 16),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${message.authorName} • v${message.schemaVersion} [${message.category}]${message.isEdited ? ' (edited)' : ''}',
            style: TextStyle(
              fontSize: 12,
              color: message.schemaVersion == 1
                  ? Colors.orange.shade800
                  : Colors.grey.shade700,
            ),
          ),
        ),
        trailing: isMine
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Edit message',
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: onEdit,
                  ),
                  IconButton(
                    tooltip: 'Delete message',
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: onDelete,
                  ),
                ],
              )
            : null,
      ),
    );
  }
}