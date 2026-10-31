import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils/url_utils.dart';
import '../../data/local/keep_database.dart';
import '../../data/migration/keep_migration_service.dart';
import '../../data/sync/supabase_sync_service.dart';
import '../models/note_model.dart';
import 'device_services.dart';

enum KeepDrawerSection {
  notes,
  reminders,
  archive,
  trash,
  label,
}

class NavigationFilterState {
  final KeepDrawerSection section;
  final String? selectedLabel;

  const NavigationFilterState({
    this.section = KeepDrawerSection.notes,
    this.selectedLabel,
  });

  String get title {
    switch (section) {
      case KeepDrawerSection.notes:
        return 'Search your notes';
      case KeepDrawerSection.reminders:
        return 'Reminders';
      case KeepDrawerSection.archive:
        return 'Archive';
      case KeepDrawerSection.trash:
        return 'Trash';
      case KeepDrawerSection.label:
        return selectedLabel ?? 'Label';
    }
  }
}

// =============================================================================
// CORE SERVICE PROVIDERS
// =============================================================================
final keepDatabaseProvider = Provider<KeepDatabase>((ref) {
  final db = KeepDatabase();
  ref.onDispose(db.close);
  return db;
});

final supabaseSyncServiceProvider = Provider<SupabaseSyncService>((ref) {
  final db = ref.watch(keepDatabaseProvider);
  final service = SupabaseSyncService(db);
  unawaited(service.initialize());
  ref.onDispose(service.dispose);
  return service;
});

final cloudSyncStateProvider = StreamProvider<CloudSyncState>((ref) async* {
  final service = ref.watch(supabaseSyncServiceProvider);
  yield service.currentState;
  yield* service.stateStream;
});

final keepMigrationServiceProvider = Provider<KeepMigrationService>((ref) {
  final db = ref.watch(keepDatabaseProvider);
  return KeepMigrationService(db);
});

final keepOcrServiceProvider = Provider<KeepOcrService>((ref) {
  return KeepOcrService();
});

final keepVoiceServiceProvider = Provider<KeepVoiceService>((ref) {
  final service = KeepVoiceService();
  ref.onDispose(service.dispose);
  return service;
});

final keepBiometricServiceProvider = Provider<KeepBiometricService>((ref) {
  return KeepBiometricService();
});

final keepReminderServiceProvider = Provider<KeepReminderService>((ref) {
  final service = KeepReminderService();
  unawaited(service.initialize());
  ref.onDispose(service.dispose);
  return service;
});

final shareToKeepServiceProvider = Provider<ShareToKeepService>((ref) {
  final service = ShareToKeepService();
  unawaited(service.initialize());
  ref.onDispose(service.dispose);
  return service;
});

// =============================================================================
// REACTIVE DATA STREAMS
// =============================================================================
final allNotesStreamProvider = StreamProvider<List<NoteModel>>((ref) {
  final db = ref.watch(keepDatabaseProvider);
  return db.watchAllNotes();
});

final allLabelsStreamProvider = StreamProvider<List<LabelModel>>((ref) {
  final db = ref.watch(keepDatabaseProvider);
  return db.watchAllLabels();
});

// =============================================================================
// UI PREFERENCES & NAVIGATION STATE (Riverpod 3 Notifiers)
// =============================================================================
class NavigationFilterNotifier extends Notifier<NavigationFilterState> {
  @override
  NavigationFilterState build() => const NavigationFilterState();

  void selectSection(KeepDrawerSection section, {String? label}) {
    state = NavigationFilterState(section: section, selectedLabel: label);
  }
}

final navigationFilterProvider =
    NotifierProvider<NavigationFilterNotifier, NavigationFilterState>(
  NavigationFilterNotifier.new,
);

class GridModeNotifier extends Notifier<bool> {
  @override
  bool build() => true; // true = 2-column Masonry grid, false = 1-column list

  void toggle() => state = !state;
}

final isMultiColumnGridProvider =
    NotifierProvider<GridModeNotifier, bool>(GridModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void setThemeMode(ThemeMode mode) => state = mode;
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class MultiSelectNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  void toggle(String noteId) {
    final next = Set<String>.from(state);
    if (next.contains(noteId)) {
      next.remove(noteId);
    } else {
      next.add(noteId);
    }
    state = next;
  }

  void clear() => state = <String>{};
}

final selectedNotesProvider =
    NotifierProvider<MultiSelectNotifier, Set<String>>(MultiSelectNotifier.new);

class UnlockedNotesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  void markUnlocked(String noteId) {
    state = {...state, noteId};
  }
}

final unlockedNotesSessionProvider =
    NotifierProvider<UnlockedNotesNotifier, Set<String>>(
  UnlockedNotesNotifier.new,
);

// =============================================================================
// FILTERED NOTES VIEW MODEL
// =============================================================================
final filteredNotesProvider =
    Provider<({List<NoteModel> pinned, List<NoteModel> others})>((ref) {
  final asyncNotes = ref.watch(allNotesStreamProvider);
  final nav = ref.watch(navigationFilterProvider);

  final all = asyncNotes.value ?? const <NoteModel>[];

  Iterable<NoteModel> filtered;
  switch (nav.section) {
    case KeepDrawerSection.notes:
      filtered = all.where((n) => !n.isArchived && !n.isTrashed);
      break;
    case KeepDrawerSection.reminders:
      filtered = all.where((n) => !n.isTrashed && n.hasReminder);
      break;
    case KeepDrawerSection.archive:
      filtered = all.where((n) => n.isArchived && !n.isTrashed);
      break;
    case KeepDrawerSection.trash:
      filtered = all.where((n) => n.isTrashed);
      break;
    case KeepDrawerSection.label:
      final target = nav.selectedLabel;
      filtered = all.where(
        (n) => !n.isTrashed && target != null && n.labels.contains(target),
      );
      break;
  }

  final list = filtered.toList();
  if (nav.section == KeepDrawerSection.trash ||
      nav.section == KeepDrawerSection.archive) {
    return (pinned: const <NoteModel>[], others: list);
  }

  final pinned = list.where((n) => n.isPinned).toList();
  final others = list.where((n) => !n.isPinned).toList();
  return (pinned: pinned, others: others);
});

// =============================================================================
// ACTIONS CONTROLLER
// =============================================================================
class KeepActionsController {
  final Ref _ref;
  static const _uuid = Uuid();

  KeepActionsController(this._ref);

  KeepDatabase get _db => _ref.read(keepDatabaseProvider);
  SupabaseSyncService get _sync => _ref.read(supabaseSyncServiceProvider);
  KeepReminderService get _reminders => _ref.read(keepReminderServiceProvider);

  Future<void> saveNote(NoteModel note) async {
    final now = DateTime.now();

    // Extract URLs from content + checklist items and update link previews
    final fullText = [
      note.content,
      ...note.checklistItems.map((c) => c.text),
    ].join('\n');
    final urls = UrlUtils.extractUrls(fullText);
    final existingByUrl = {for (final p in note.linkPreviews) p.url: p};
    final updatedPreviews = <UrlMetadata>[];
    for (final url in urls) {
      if (existingByUrl.containsKey(url)) {
        updatedPreviews.add(existingByUrl[url]!);
      } else {
        final uri = Uri.tryParse(url);
        final domain = uri?.host.replaceFirst('www.', '') ?? url;
        updatedPreviews.add(
          UrlMetadata(
            url: url,
            title: domain,
            description: url,
            domain: domain,
          ),
        );
      }
    }

    final toSave = note.copyWith(
      linkPreviews: updatedPreviews,
      updatedAt: now,
      syncStatus: SyncStatus.pendingUpsert,
    );

    // Ensure any new labels attached to the note exist in labels table
    final existingLabels = await _db.getAllLabels();
    final existingNames = existingLabels.map((l) => l.name.toLowerCase()).toSet();
    for (final lbl in toSave.labels) {
      if (!existingNames.contains(lbl.toLowerCase())) {
        await _db.upsertLabel(
          LabelModel(
            id: _uuid.v4(),
            name: lbl,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
    }

    await _db.upsertNote(toSave);
    await _reminders.scheduleNoteReminder(toSave);
    unawaited(_sync.syncNow());

    // Fetch rich OpenGraph metadata in background if new URLs were detected
    if (urls.any((u) => !existingByUrl.containsKey(u))) {
      unawaited(_enrichLinkPreviews(toSave.id, urls));
    }
  }

  Future<void> _enrichLinkPreviews(String noteId, List<String> urls) async {
    final enriched = <UrlMetadata>[];
    for (final url in urls) {
      enriched.add(await UrlUtils.fetchPreview(url));
    }
    final latest = await _db.getNoteById(noteId);
    if (latest != null) {
      await _db.upsertNote(latest.copyWith(linkPreviews: enriched));
    }
  }

  Future<void> toggleArchive(NoteModel note) async {
    final nextArchived = !note.isArchived;
    await saveNote(
      note.copyWith(
        isArchived: nextArchived,
        isPinned: nextArchived ? false : note.isPinned,
      ),
    );
  }

  Future<void> togglePin(NoteModel note) async {
    final nextPinned = !note.isPinned;
    await saveNote(
      note.copyWith(
        isPinned: nextPinned,
        isArchived: nextPinned ? false : note.isArchived,
      ),
    );
  }

  Future<void> moveToTrash(NoteModel note) async {
    final now = DateTime.now();
    await _reminders.cancelNoteReminder(note.id);
    await saveNote(
      note.copyWith(
        isTrashed: true,
        isPinned: false,
        trashedAt: now,
      ),
    );
  }

  Future<void> restoreFromTrash(NoteModel note) async {
    await saveNote(
      note.copyWith(
        isTrashed: false,
        clearTrashedAt: true,
      ),
    );
  }

  Future<void> deletePermanently(String noteId) async {
    await _reminders.cancelNoteReminder(noteId);
    await _db.deleteNotePermanently(noteId);
    unawaited(_sync.syncNow());
  }

  Future<void> emptyTrash() async {
    await _db.emptyTrash();
    unawaited(_sync.syncNow());
  }

  Future<NoteModel> duplicateNote(NoteModel source) async {
    final now = DateTime.now();
    final newId = _uuid.v4();
    final copy = source.copyWith(
      id: newId,
      title: source.title.isNotEmpty ? '${source.title} (Copy)' : '',
      checklistItems: source.checklistItems
          .map((c) => c.copyWith(id: _uuid.v4()))
          .toList(),
      attachments: source.attachments
          .map((a) => a.copyWith(id: _uuid.v4(), noteId: newId))
          .toList(),
      createdAt: now,
      updatedAt: now,
      syncStatus: SyncStatus.pendingUpsert,
    );
    await saveNote(copy);
    return copy;
  }

  Future<void> reorderNotes(
    List<NoteModel> currentList,
    int oldIndex,
    int newIndex,
  ) async {
    if (oldIndex < 0 ||
        oldIndex >= currentList.length ||
        newIndex < 0 ||
        newIndex >= currentList.length) {
      return;
    }
    final reordered = List<NoteModel>.from(currentList);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    final now = DateTime.now();
    final total = reordered.length;
    for (var i = 0; i < total; i++) {
      final targetSort = (total - i).toDouble();
      final item = reordered[i];
      if (item.sortOrder != targetSort) {
        await _db.upsertNote(
          item.copyWith(
            sortOrder: targetSort,
            updatedAt: now,
            syncStatus: SyncStatus.pendingUpsert,
          ),
        );
      }
    }
    unawaited(_sync.syncNow());
  }

  // ===========================================================================
  // BATCH MULTI-SELECT OPERATIONS
  // ===========================================================================
  Future<void> batchPin(Set<String> ids) async {
    final notes = <NoteModel>[];
    for (final id in ids) {
      final n = await _db.getNoteById(id);
      if (n != null) notes.add(n);
    }
    if (notes.isEmpty) return;
    final shouldPin = notes.any((n) => !n.isPinned);
    for (final n in notes) {
      await saveNote(
        n.copyWith(
          isPinned: shouldPin,
          isArchived: shouldPin ? false : n.isArchived,
        ),
      );
    }
    _ref.read(selectedNotesProvider.notifier).clear();
  }

  Future<void> batchColor(Set<String> ids, String colorId) async {
    for (final id in ids) {
      final n = await _db.getNoteById(id);
      if (n != null) {
        await saveNote(n.copyWith(colorId: colorId));
      }
    }
    _ref.read(selectedNotesProvider.notifier).clear();
  }

  Future<void> batchArchive(Set<String> ids) async {
    for (final id in ids) {
      final n = await _db.getNoteById(id);
      if (n != null) {
        await toggleArchive(n);
      }
    }
    _ref.read(selectedNotesProvider.notifier).clear();
  }

  Future<void> batchTrash(Set<String> ids) async {
    for (final id in ids) {
      final n = await _db.getNoteById(id);
      if (n != null) {
        await moveToTrash(n);
      }
    }
    _ref.read(selectedNotesProvider.notifier).clear();
  }

  Future<void> batchAddLabel(Set<String> ids, String labelName) async {
    for (final id in ids) {
      final n = await _db.getNoteById(id);
      if (n != null && !n.labels.contains(labelName)) {
        await saveNote(n.copyWith(labels: [...n.labels, labelName]));
      }
    }
    _ref.read(selectedNotesProvider.notifier).clear();
  }

  Future<void> batchDuplicate(Set<String> ids) async {
    for (final id in ids) {
      final n = await _db.getNoteById(id);
      if (n != null) {
        await duplicateNote(n);
      }
    }
    _ref.read(selectedNotesProvider.notifier).clear();
  }

  // ===========================================================================
  // LABEL MANAGEMENT
  // ===========================================================================
  Future<void> createLabel(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final now = DateTime.now();
    await _db.upsertLabel(
      LabelModel(
        id: _uuid.v4(),
        name: trimmed,
        createdAt: now,
        updatedAt: now,
      ),
    );
    unawaited(_sync.syncNow());
  }

  Future<void> renameLabel(String id, String oldName, String newName) async {
    await _db.renameLabel(id, oldName, newName);
    unawaited(_sync.syncNow());
  }

  Future<void> deleteLabel(String id, String name) async {
    await _db.deleteLabel(id, name);
    unawaited(_sync.syncNow());
  }
}

final keepActionsProvider = Provider<KeepActionsController>((ref) {
  return KeepActionsController(ref);
});
