import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/models/note_model.dart';

/// Offline-first Drift SQLite + FTS5 database for Keep Notes.
class KeepDatabase extends GeneratedDatabase {
  KeepDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  factory KeepDatabase.memory() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    return KeepDatabase(NativeDatabase.memory());
  }

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      final dir = await getApplicationDocumentsDirectory();
      final dbFile = File(p.join(dir.path, 'gkeep_offline.sqlite'));
      return NativeDatabase.createInBackground(dbFile);
    });
  }

  final StreamController<void> _changeSignal =
      StreamController<void>.broadcast();

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await _createTables();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await _createTables();
          await purgeExpiredTrash();
        },
      );

  Future<void> _createTables() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS notes (
        id TEXT PRIMARY KEY NOT NULL,
        user_id TEXT,
        title TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        rich_spans TEXT NOT NULL DEFAULT '[]',
        is_checklist INTEGER NOT NULL DEFAULT 0,
        checklist_items TEXT NOT NULL DEFAULT '[]',
        color_id TEXT NOT NULL DEFAULT 'default',
        background_theme TEXT NOT NULL DEFAULT 'none',
        is_pinned INTEGER NOT NULL DEFAULT 0,
        is_archived INTEGER NOT NULL DEFAULT 0,
        is_trashed INTEGER NOT NULL DEFAULT 0,
        trashed_at TEXT,
        is_locked INTEGER NOT NULL DEFAULT 0,
        sort_order REAL NOT NULL DEFAULT 0.0,
        reminder_at TEXT,
        reminder_recurrence TEXT NOT NULL DEFAULT 'none',
        reminder_location TEXT,
        link_previews TEXT NOT NULL DEFAULT '[]',
        labels TEXT NOT NULL DEFAULT '[]',
        attachments TEXT NOT NULL DEFAULT '[]',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pendingUpsert'
      )
    ''');

    await customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5(
        note_id UNINDEXED,
        searchable_text
      )
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS labels (
        id TEXT PRIMARY KEY NOT NULL,
        name TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        sync_status TEXT NOT NULL DEFAULT 'pendingUpsert'
      )
    ''');

    await customStatement('''
      CREATE TABLE IF NOT EXISTS deleted_records (
        id TEXT PRIMARY KEY NOT NULL,
        entity_type TEXT NOT NULL,
        deleted_at TEXT NOT NULL
      )
    ''');
  }

  void _notifyListeners() {
    if (!_changeSignal.isClosed) {
      _changeSignal.add(null);
    }
  }

  Stream<List<NoteModel>> watchAllNotes() async* {
    yield await getAllNotes();
    await for (final _ in _changeSignal.stream) {
      yield await getAllNotes();
    }
  }

  Stream<List<LabelModel>> watchAllLabels() async* {
    yield await getAllLabels();
    await for (final _ in _changeSignal.stream) {
      yield await getAllLabels();
    }
  }

  Future<List<NoteModel>> getAllNotes() async {
    final rows = await customSelect(
      'SELECT * FROM notes ORDER BY is_pinned DESC, sort_order DESC, updated_at DESC',
    ).get();
    return rows.map(_rowToNote).toList();
  }

  Future<NoteModel?> getNoteById(String id) async {
    final rows = await customSelect(
      'SELECT * FROM notes WHERE id = ? LIMIT 1',
      variables: [Variable.withString(id)],
    ).get();
    if (rows.isEmpty) return null;
    return _rowToNote(rows.first);
  }

  Future<void> upsertNote(NoteModel note, {bool fromRemoteSync = false}) async {
    final syncStatus =
        fromRemoteSync ? SyncStatus.synced.name : note.syncStatus.name;

    await transaction(() async {
      await customStatement(
        '''
        INSERT INTO notes (
          id, user_id, title, content, rich_spans, is_checklist, checklist_items,
          color_id, background_theme, is_pinned, is_archived, is_trashed, trashed_at,
          is_locked, sort_order, reminder_at, reminder_recurrence, reminder_location,
          link_previews, labels, attachments, created_at, updated_at, sync_status
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          user_id = excluded.user_id,
          title = excluded.title,
          content = excluded.content,
          rich_spans = excluded.rich_spans,
          is_checklist = excluded.is_checklist,
          checklist_items = excluded.checklist_items,
          color_id = excluded.color_id,
          background_theme = excluded.background_theme,
          is_pinned = excluded.is_pinned,
          is_archived = excluded.is_archived,
          is_trashed = excluded.is_trashed,
          trashed_at = excluded.trashed_at,
          is_locked = excluded.is_locked,
          sort_order = excluded.sort_order,
          reminder_at = excluded.reminder_at,
          reminder_recurrence = excluded.reminder_recurrence,
          reminder_location = excluded.reminder_location,
          link_previews = excluded.link_previews,
          labels = excluded.labels,
          attachments = excluded.attachments,
          created_at = excluded.created_at,
          updated_at = excluded.updated_at,
          sync_status = excluded.sync_status
        ''',
        [
          note.id,
          note.userId,
          note.title,
          note.content,
          jsonEncode(note.richSpans.map((s) => s.toJson()).toList()),
          note.isChecklist ? 1 : 0,
          jsonEncode(note.checklistItems.map((c) => c.toJson()).toList()),
          note.colorId,
          note.backgroundTheme,
          note.isPinned ? 1 : 0,
          note.isArchived ? 1 : 0,
          note.isTrashed ? 1 : 0,
          note.trashedAt?.toIso8601String(),
          note.isLocked ? 1 : 0,
          note.sortOrder,
          note.reminderAt?.toIso8601String(),
          note.reminderRecurrence,
          note.reminderLocation != null
              ? jsonEncode(note.reminderLocation!.toJson())
              : null,
          jsonEncode(note.linkPreviews.map((l) => l.toJson()).toList()),
          jsonEncode(note.labels),
          jsonEncode(note.attachments.map((a) => a.toJson()).toList()),
          note.createdAt.toIso8601String(),
          note.updatedAt.toIso8601String(),
          syncStatus,
        ],
      );

      // Update FTS5 index
      await customStatement(
        'DELETE FROM notes_fts WHERE note_id = ?',
        [note.id],
      );
      await customStatement(
        'INSERT INTO notes_fts (note_id, searchable_text) VALUES (?, ?)',
        [note.id, note.searchableText],
      );
    });

    _notifyListeners();
  }

  /// Full-text search using SQLite FTS5 with fallback substring matching.
  Future<List<NoteModel>> searchNotes(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return getAllNotes();
    }

    // Sanitize FTS5 query tokens for prefix matching
    final tokens = trimmed
        .replaceAll(RegExp(r'[^\w\s#]'), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .map((t) => '"${t.replaceAll('"', '')}"*')
        .join(' AND ');

    if (tokens.isNotEmpty) {
      try {
        final rows = await customSelect(
          '''
          SELECT n.* FROM notes n
          INNER JOIN notes_fts f ON n.id = f.note_id
          WHERE notes_fts MATCH ? AND n.is_trashed = 0
          ORDER BY n.is_pinned DESC, n.updated_at DESC
          ''',
          variables: [Variable.withString(tokens)],
        ).get();
        if (rows.isNotEmpty) {
          return rows.map(_rowToNote).toList();
        }
      } catch (_) {
        // Fallback to case-insensitive LIKE below
      }
    }

    final likePattern = '%$trimmed%';
    final rows = await customSelect(
      '''
      SELECT * FROM notes
      WHERE is_trashed = 0 AND (
        title LIKE ? OR content LIKE ? OR checklist_items LIKE ? OR labels LIKE ? OR attachments LIKE ?
      )
      ORDER BY is_pinned DESC, updated_at DESC
      ''',
      variables: [
        Variable.withString(likePattern),
        Variable.withString(likePattern),
        Variable.withString(likePattern),
        Variable.withString(likePattern),
        Variable.withString(likePattern),
      ],
    ).get();
    return rows.map(_rowToNote).toList();
  }

  Future<void> deleteNotePermanently(String id, {bool fromRemoteSync = false}) async {
    await transaction(() async {
      await customStatement('DELETE FROM notes WHERE id = ?', [id]);
      await customStatement('DELETE FROM notes_fts WHERE note_id = ?', [id]);
      if (!fromRemoteSync) {
        await customStatement(
          'INSERT OR REPLACE INTO deleted_records (id, entity_type, deleted_at) VALUES (?, ?, ?)',
          [id, 'note', DateTime.now().toIso8601String()],
        );
      }
    });
    _notifyListeners();
  }

  Future<void> emptyTrash() async {
    final trashed = await customSelect(
      'SELECT id FROM notes WHERE is_trashed = 1',
    ).get();
    for (final row in trashed) {
      await deleteNotePermanently(row.read<String>('id'));
    }
  }

  /// Auto-purges notes that have been in Trash for more than 7 days (Google Keep behavior).
  Future<void> purgeExpiredTrash() async {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    final rows = await customSelect(
      'SELECT id, trashed_at FROM notes WHERE is_trashed = 1 AND trashed_at IS NOT NULL',
    ).get();
    for (final r in rows) {
      final raw = r.readNullable<String>('trashed_at');
      if (raw != null) {
        final dt = DateTime.tryParse(raw);
        if (dt != null && dt.isBefore(cutoff)) {
          await deleteNotePermanently(r.read<String>('id'));
        }
      }
    }
  }

  // ===========================================================================
  // LABELS CRUD
  // ===========================================================================
  Future<List<LabelModel>> getAllLabels() async {
    final rows = await customSelect(
      'SELECT * FROM labels ORDER BY name COLLATE NOCASE ASC',
    ).get();
    return rows.map((r) {
      final syncStr = r.read<String>('sync_status');
      return LabelModel(
        id: r.read<String>('id'),
        name: r.read<String>('name'),
        createdAt: DateTime.tryParse(r.read<String>('created_at')) ?? DateTime.now(),
        updatedAt: DateTime.tryParse(r.read<String>('updated_at')) ?? DateTime.now(),
        syncStatus: SyncStatus.values.firstWhere(
          (e) => e.name == syncStr,
          orElse: () => SyncStatus.pendingUpsert,
        ),
      );
    }).toList();
  }

  Future<void> upsertLabel(LabelModel label, {bool fromRemoteSync = false}) async {
    final status =
        fromRemoteSync ? SyncStatus.synced.name : label.syncStatus.name;
    await customStatement(
      '''
      INSERT INTO labels (id, name, created_at, updated_at, sync_status)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(name) DO UPDATE SET
        updated_at = excluded.updated_at,
        sync_status = excluded.sync_status
      ''',
      [
        label.id,
        label.name.trim(),
        label.createdAt.toIso8601String(),
        label.updatedAt.toIso8601String(),
        status,
      ],
    );
    _notifyListeners();
  }

  Future<void> renameLabel(String id, String oldName, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    final now = DateTime.now();

    await transaction(() async {
      await customStatement(
        'UPDATE labels SET name = ?, updated_at = ?, sync_status = ? WHERE id = ?',
        [trimmed, now.toIso8601String(), SyncStatus.pendingUpsert.name, id],
      );

      final allNotes = await getAllNotes();
      for (final note in allNotes) {
        if (note.labels.contains(oldName)) {
          final updatedLabels = note.labels
              .map((l) => l == oldName ? trimmed : l)
              .toSet()
              .toList();
          await upsertNote(
            note.copyWith(
              labels: updatedLabels,
              updatedAt: now,
              syncStatus: SyncStatus.pendingUpsert,
            ),
          );
        }
      }
    });
    _notifyListeners();
  }

  Future<void> deleteLabel(String id, String labelName,
      {bool fromRemoteSync = false}) async {
    final now = DateTime.now();
    await transaction(() async {
      await customStatement('DELETE FROM labels WHERE id = ?', [id]);
      if (!fromRemoteSync) {
        await customStatement(
          'INSERT OR REPLACE INTO deleted_records (id, entity_type, deleted_at) VALUES (?, ?, ?)',
          [id, 'label', now.toIso8601String()],
        );
      }
      final allNotes = await getAllNotes();
      for (final note in allNotes) {
        if (note.labels.contains(labelName)) {
          await upsertNote(
            note.copyWith(
              labels: note.labels.where((l) => l != labelName).toList(),
              updatedAt: now,
              syncStatus: SyncStatus.pendingUpsert,
            ),
          );
        }
      }
    });
    _notifyListeners();
  }

  // ===========================================================================
  // OUTBOX SYNC QUERIES
  // ===========================================================================
  Future<List<NoteModel>> getPendingNotes() async {
    final rows = await customSelect(
      'SELECT * FROM notes WHERE sync_status != ?',
      variables: [Variable.withString(SyncStatus.synced.name)],
    ).get();
    return rows.map(_rowToNote).toList();
  }

  Future<List<LabelModel>> getPendingLabels() async {
    final rows = await customSelect(
      'SELECT * FROM labels WHERE sync_status != ?',
      variables: [Variable.withString(SyncStatus.synced.name)],
    ).get();
    return rows.map((r) {
      return LabelModel(
        id: r.read<String>('id'),
        name: r.read<String>('name'),
        createdAt: DateTime.tryParse(r.read<String>('created_at')) ?? DateTime.now(),
        updatedAt: DateTime.tryParse(r.read<String>('updated_at')) ?? DateTime.now(),
        syncStatus: SyncStatus.pendingUpsert,
      );
    }).toList();
  }

  Future<List<Map<String, String>>> getPendingDeletions() async {
    final rows = await customSelect('SELECT * FROM deleted_records').get();
    return rows
        .map((r) => {
              'id': r.read<String>('id'),
              'entity_type': r.read<String>('entity_type'),
            })
        .toList();
  }

  Future<void> clearPendingDeletion(String id) async {
    await customStatement('DELETE FROM deleted_records WHERE id = ?', [id]);
  }

  Future<void> markNoteSynced(String id) async {
    await customStatement(
      'UPDATE notes SET sync_status = ? WHERE id = ?',
      [SyncStatus.synced.name, id],
    );
    _notifyListeners();
  }

  Future<void> markLabelSynced(String id) async {
    await customStatement(
      'UPDATE labels SET sync_status = ? WHERE id = ?',
      [SyncStatus.synced.name, id],
    );
    _notifyListeners();
  }

  NoteModel _rowToNote(QueryRow r) {
    final syncStr = r.read<String>('sync_status');
    final syncStatus = SyncStatus.values.firstWhere(
      (e) => e.name == syncStr,
      orElse: () => SyncStatus.pendingUpsert,
    );

    final map = <String, dynamic>{
      'id': r.read<String>('id'),
      'user_id': r.readNullable<String>('user_id'),
      'title': r.read<String>('title'),
      'content': r.read<String>('content'),
      'rich_spans': r.read<String>('rich_spans'),
      'is_checklist': r.read<int>('is_checklist'),
      'checklist_items': r.read<String>('checklist_items'),
      'color_id': r.read<String>('color_id'),
      'background_theme': r.read<String>('background_theme'),
      'is_pinned': r.read<int>('is_pinned'),
      'is_archived': r.read<int>('is_archived'),
      'is_trashed': r.read<int>('is_trashed'),
      'trashed_at': r.readNullable<String>('trashed_at'),
      'is_locked': r.read<int>('is_locked'),
      'sort_order': r.read<double>('sort_order'),
      'reminder_at': r.readNullable<String>('reminder_at'),
      'reminder_recurrence': r.read<String>('reminder_recurrence'),
      'reminder_location': r.readNullable<String>('reminder_location'),
      'link_previews': r.read<String>('link_previews'),
      'labels': r.read<String>('labels'),
      'attachments': r.read<String>('attachments'),
      'created_at': r.read<String>('created_at'),
      'updated_at': r.read<String>('updated_at'),
    };
    return NoteModel.fromJson(map).copyWith(syncStatus: syncStatus);
  }

  @override
  Future<void> close() async {
    await _changeSignal.close();
    return super.close();
  }
}
