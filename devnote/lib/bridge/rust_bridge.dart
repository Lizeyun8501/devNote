import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:ffi/ffi.dart';

import '../models/note.dart';
import '../models/note_folder.dart';

typedef DevnoteInitNative = Int32 Function(Pointer<Utf8> dbPath);
typedef DevnoteInit = int Function(Pointer<Utf8> dbPath);

typedef DevnoteCreateNoteNative = Pointer<Utf8> Function(
    Pointer<Utf8> title, Pointer<Utf8> content, Pointer<Utf8> folderId);
typedef DevnoteCreateNote = Pointer<Utf8> Function(
    Pointer<Utf8> title, Pointer<Utf8> content, Pointer<Utf8> folderId);

typedef DevnoteListNotesNative = Pointer<Utf8> Function(Pointer<Utf8> folderId);
typedef DevnoteListNotes = Pointer<Utf8> Function(Pointer<Utf8> folderId);

typedef DevnoteGetNoteNative = Pointer<Utf8> Function(Pointer<Utf8> id);
typedef DevnoteGetNote = Pointer<Utf8> Function(Pointer<Utf8> id);

typedef DevnoteUpdateNoteNative = Int32 Function(
    Pointer<Utf8> id, Pointer<Utf8> title, Pointer<Utf8> content);
typedef DevnoteUpdateNote = int Function(
    Pointer<Utf8> id, Pointer<Utf8> title, Pointer<Utf8> content);

typedef DevnoteDeleteNoteNative = Int32 Function(Pointer<Utf8> id);
typedef DevnoteDeleteNote = int Function(Pointer<Utf8> id);

typedef DevnoteCreateFolderNative = Pointer<Utf8> Function(
    Pointer<Utf8> name, Pointer<Utf8> parentId);
typedef DevnoteCreateFolder = Pointer<Utf8> Function(
    Pointer<Utf8> name, Pointer<Utf8> parentId);

typedef DevnoteListFoldersNative = Pointer<Utf8> Function();
typedef DevnoteListFolders = Pointer<Utf8> Function();

typedef DevnoteFreeStringNative = Void Function(Pointer<Utf8> s);
typedef DevnoteFreeString = void Function(Pointer<Utf8> s);

class RustBridge {
  RustBridge._();

  static final RustBridge instance = RustBridge._();

  late final DynamicLibrary _lib;
  late final DevnoteInit _init;
  late final DevnoteCreateNote _createNote;
  late final DevnoteListNotes _listNotes;
  late final DevnoteGetNote _getNote;
  late final DevnoteUpdateNote _updateNote;
  late final DevnoteDeleteNote _deleteNote;
  late final DevnoteCreateFolder _createFolder;
  late final DevnoteListFolders _listFolders;
  late final DevnoteFreeString _freeString;

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    _lib = _loadLibrary();

    _init = _lib.lookupFunction<DevnoteInitNative, DevnoteInit>(
        'devnote_init');
    _createNote =
        _lib.lookupFunction<DevnoteCreateNoteNative, DevnoteCreateNote>(
            'devnote_create_note');
    _listNotes =
        _lib.lookupFunction<DevnoteListNotesNative, DevnoteListNotes>(
            'devnote_list_notes');
    _getNote = _lib.lookupFunction<DevnoteGetNoteNative, DevnoteGetNote>(
        'devnote_get_note');
    _updateNote =
        _lib.lookupFunction<DevnoteUpdateNoteNative, DevnoteUpdateNote>(
            'devnote_update_note');
    _deleteNote =
        _lib.lookupFunction<DevnoteDeleteNoteNative, DevnoteDeleteNote>(
            'devnote_delete_note');
    _createFolder =
        _lib.lookupFunction<DevnoteCreateFolderNative, DevnoteCreateFolder>(
            'devnote_create_folder');
    _listFolders =
        _lib.lookupFunction<DevnoteListFoldersNative, DevnoteListFolders>(
            'devnote_list_folders');
    _freeString =
        _lib.lookupFunction<DevnoteFreeStringNative, DevnoteFreeString>(
            'devnote_free_string');

    final dir = await getApplicationDocumentsDirectory();
    final dbPath = '${dir.path}/devnote.db';
    final dbPathPtr = dbPath.toNativeUtf8();
    try {
      final result = _init(dbPathPtr);
      if (result != 0) {
        throw Exception('Failed to initialize database');
      }
    } finally {
      malloc.free(dbPathPtr);
    }

    _initialized = true;
  }

  DynamicLibrary _loadLibrary() {
    if (Platform.isAndroid) {
      return DynamicLibrary.open('libdevnote_core.so');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libdevnote_core.so');
    } else if (Platform.isIOS || Platform.isMacOS) {
      return DynamicLibrary.process();
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('devnote_core.dll');
    }
    throw UnsupportedError('Unsupported platform');
  }

  String? _readAndFree(Pointer<Utf8> ptr) {
    if (ptr == nullptr) return null;
    try {
      return ptr.toDartString();
    } finally {
      _freeString(ptr);
    }
  }

  Note? createNote(String title, String content, {String? folderId}) {
    final titlePtr = title.toNativeUtf8();
    final contentPtr = content.toNativeUtf8();
    final folderIdPtr = folderId?.toNativeUtf8() ?? nullptr;
    try {
      final resultPtr = _createNote(titlePtr, contentPtr, folderIdPtr);
      final json = _readAndFree(resultPtr);
      if (json == null) return null;
      return Note.fromJson(
          _parseJson(json) as Map<String, dynamic>);
    } finally {
      malloc.free(titlePtr);
      malloc.free(contentPtr);
      if (folderIdPtr != nullptr) {
        malloc.free(folderIdPtr);
      }
    }
  }

  List<Note> listNotes({String? folderId}) {
    final folderIdPtr = folderId?.toNativeUtf8() ?? nullptr;
    try {
      final resultPtr = _listNotes(folderIdPtr);
      final json = _readAndFree(resultPtr);
      if (json == null) return [];
      return Note.fromJsonList(json);
    } finally {
      if (folderIdPtr != nullptr) {
        malloc.free(folderIdPtr);
      }
    }
  }

  Note? getNote(String id) {
    final idPtr = id.toNativeUtf8();
    try {
      final resultPtr = _getNote(idPtr);
      final json = _readAndFree(resultPtr);
      if (json == null) return null;
      return Note.fromJson(
          _parseJson(json) as Map<String, dynamic>);
    } finally {
      malloc.free(idPtr);
    }
  }

  int updateNote(String id, String title, String content) {
    final idPtr = id.toNativeUtf8();
    final titlePtr = title.toNativeUtf8();
    final contentPtr = content.toNativeUtf8();
    try {
      return _updateNote(idPtr, titlePtr, contentPtr);
    } finally {
      malloc.free(idPtr);
      malloc.free(titlePtr);
      malloc.free(contentPtr);
    }
  }

  int deleteNote(String id) {
    final idPtr = id.toNativeUtf8();
    try {
      return _deleteNote(idPtr);
    } finally {
      malloc.free(idPtr);
    }
  }

  NoteFolder? createFolder(String name, {String? parentId}) {
    final namePtr = name.toNativeUtf8();
    final parentIdPtr = parentId?.toNativeUtf8() ?? nullptr;
    try {
      final resultPtr = _createFolder(namePtr, parentIdPtr);
      final json = _readAndFree(resultPtr);
      if (json == null) return null;
      return NoteFolder.fromJson(
          _parseJson(json) as Map<String, dynamic>);
    } finally {
      malloc.free(namePtr);
      if (parentIdPtr != nullptr) {
        malloc.free(parentIdPtr);
      }
    }
  }

  List<NoteFolder> listFolders() {
    final resultPtr = _listFolders();
    final json = _readAndFree(resultPtr);
    if (json == null) return [];
    return NoteFolder.fromJsonList(json);
  }

  dynamic _parseJson(String source) {
    return jsonDecode(source);
  }
}
