import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class NoteEditorDialog extends StatefulWidget {
  final String initialNote;
  final String username;

  const NoteEditorDialog({
    super.key,
    required this.initialNote,
    required this.username,
  });

  @override
  State<NoteEditorDialog> createState() => _NoteEditorDialogState();
}

class _NoteEditorDialogState extends State<NoteEditorDialog> {
  late final TextEditingController _controller;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNote);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Заметка о ${widget.username}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            maxLength: 60,
            decoration: const InputDecoration(
              hintText: 'Напишите заметку...',
              border: OutlineInputBorder(),
            ),
          ),
          if (_isSaving) const CircularProgressIndicator(),
        ],
      ),
      actions: [
        if (widget.initialNote.isNotEmpty)
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.pop(context, '__DELETE__'),
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: _isSaving
              ? null
              : () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}