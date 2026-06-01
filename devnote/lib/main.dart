import 'package:flutter/material.dart';

import 'bridge/rust_bridge.dart';
import 'models/note.dart';

void main() {
  runApp(const DevNoteApp());
}

class DevNoteApp extends StatelessWidget {
  const DevNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DevNote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
        ),
        cardColor: const Color(0xFF1E1E1E),
      ),
      home: const NoteListPage(),
    );
  }
}

class NoteListPage extends StatefulWidget {
  const NoteListPage({super.key});

  @override
  State<NoteListPage> createState() => _NoteListPageState();
}

class _NoteListPageState extends State<NoteListPage> {
  List<Note> _notes = [];
  bool _loading = true;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initAndLoad();
  }

  Future<void> _initAndLoad() async {
    try {
      await RustBridge.instance.init();
      _initialized = true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Init failed: $e')),
        );
      }
    }
    await _loadNotes();
  }

  Future<void> _loadNotes() async {
    if (!_initialized) return;
    final notes = RustBridge.instance.listNotes();
    if (mounted) {
      setState(() {
        _notes = notes;
        _loading = false;
      });
    }
  }

  void _deleteNote(String id) {
    RustBridge.instance.deleteNote(id);
    _loadNotes();
  }

  void _navigateToEditor({Note? note}) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NoteEditorPage(note: note),
      ),
    );
    if (result == true) {
      await _loadNotes();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DevNote'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _navigateToEditor(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notes.isEmpty
              ? Center(
                  child: Text(
                    'No notes yet',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _notes.length,
                  itemBuilder: (context, index) {
                    final note = _notes[index];
                    return Dismissible(
                      key: ValueKey(note.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        color: Colors.red,
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => _deleteNote(note.id),
                      child: Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: ListTile(
                          title: Text(
                            note.title.isEmpty ? 'Untitled' : note.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: note.content.isNotEmpty
                              ? Text(
                                  note.content,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.grey[400],
                                    fontSize: 13,
                                  ),
                                )
                              : null,
                          onTap: () => _navigateToEditor(note: note),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _navigateToEditor(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class NoteEditorPage extends StatefulWidget {
  final Note? note;

  const NoteEditorPage({super.key, this.note});

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController =
        TextEditingController(text: widget.note?.content ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _saveNote() {
    final title = _titleController.text.trim();
    final content = _contentController.text;

    if (widget.note != null) {
      RustBridge.instance
          .updateNote(widget.note!.id, title.isEmpty ? 'Untitled' : title, content);
    } else {
      RustBridge.instance
          .createNote(title.isEmpty ? 'Untitled' : title, content);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _saveNote();
        Navigator.pop(context, true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.note != null ? 'Edit Note' : 'New Note'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              _saveNote();
              Navigator.pop(context, true);
            },
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _titleController,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(
                  hintText: 'Title',
                  border: InputBorder.none,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: _contentController,
                  maxLines: null,
                  style: const TextStyle(fontSize: 16),
                  decoration: const InputDecoration(
                    hintText: 'Start writing...',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
