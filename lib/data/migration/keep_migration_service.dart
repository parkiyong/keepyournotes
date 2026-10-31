import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../domain/models/note_model.dart';
import '../local/keep_database.dart';

class MigrationResult {
  final int notesProcessed;
  final int labelsProcessed;
  final int attachmentsProcessed;
  final String? archivePath;

  const MigrationResult({
    required this.notesProcessed,
    required this.labelsProcessed,
    required this.attachmentsProcessed,
    this.archivePath,
  });
}

/// Handles complete data export (ZIP with JSON + Markdown + Media files)
/// and data import (both native Keep Backup ZIP and Google Takeout Keep ZIP/JSON).
class KeepMigrationService {
  final KeepDatabase _db;
  static const _uuid = Uuid();

  KeepMigrationService(this._db);

  /// Creates a portable ZIP archive containing:
  /// - `keep_backup.json` (lossless structured dump of all notes & labels)
  /// - `markdown/<note_id>.md` (human-readable Markdown with YAML frontmatter)
  /// - `media/<filename>` (all attached images, drawings, and audio clips)
  Future<MigrationResult> exportFullBackupZip({Directory? targetDirectory}) async {
    final notes = await _db.getAllNotes();
    final labels = await _db.getAllLabels();
    final archive = Archive();

    int attachmentCount = 0;

    // 1. Add media attachments and rewrite portable media paths in backup JSON
    final exportedNotesJson = <Map<String, dynamic>>[];

    for (final note in notes) {
      final exportedAttachments = <Map<String, dynamic>>[];
      for (final att in note.attachments) {
        final attMap = att.toJson();
        if (att.localPath.isNotEmpty) {
          final file = File(att.localPath);
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            final ext = p.extension(att.localPath);
            final portableFileName = '${att.id}$ext';
            archive.addFile(
              ArchiveFile('media/$portableFileName', bytes.length, bytes),
            );
            attMap['archiveMediaFile'] = 'media/$portableFileName';
            attachmentCount++;
          }
        }
        exportedAttachments.add(attMap);
      }

      final noteJson = note.toJson();
      noteJson['attachments'] = exportedAttachments;
      exportedNotesJson.add(noteJson);

      // 2. Add Markdown export for each note
      final mdContent = utf8.encode(note.toMarkdown());
      final safeTitle = note.title
          .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')
          .toLowerCase();
      final shortId =
          note.id.length > 6 ? note.id.substring(0, 6) : note.id;
      final mdName = safeTitle.isNotEmpty
          ? '${safeTitle}_$shortId.md'
          : 'note_$shortId.md';
      archive.addFile(
        ArchiveFile('markdown/$mdName', mdContent.length, mdContent),
      );
    }

    // 3. Add root `keep_backup.json`
    final backupPayload = {
      'version': 1,
      'exported_at': DateTime.now().toIso8601String(),
      'labels': labels.map((l) => l.toJson()).toList(),
      'notes': exportedNotesJson,
    };
    final jsonBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(backupPayload),
    );
    archive.addFile(
      ArchiveFile('keep_backup.json', jsonBytes.length, jsonBytes),
    );

    final zipBytes = ZipEncoder().encode(archive);
    final outDir = targetDirectory ?? await getTemporaryDirectory();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final zipFile = File(p.join(outDir.path, 'keep_backup_$timestamp.zip'));
    await zipFile.writeAsBytes(zipBytes);

    return MigrationResult(
      notesProcessed: notes.length,
      labelsProcessed: labels.length,
      attachmentsProcessed: attachmentCount,
      archivePath: zipFile.path,
    );
  }

  /// Imports notes, labels, and media from either:
  /// - Our native `keep_backup_*.zip` bundle
  /// - A Google Takeout Keep `.zip` archive (`Takeout/Keep/*.json`)
  /// - A standalone `.json` file
  Future<MigrationResult> importBackupFile(File file, {Directory? mediaRootDir}) async {
    final ext = p.extension(file.path).toLowerCase();
    final baseMediaDir = mediaRootDir ?? await _ensureLocalMediaDirectory();

    if (ext == '.json') {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic> && decoded.containsKey('notes')) {
        return _importNativeBackupMap(decoded, const {}, baseMediaDir);
      } else if (decoded is Map<String, dynamic>) {
        final note = _parseGoogleTakeoutNote(decoded, const {}, baseMediaDir);
        await _db.upsertNote(note);
        for (final lbl in note.labels) {
          await _db.upsertLabel(
            LabelModel(
              id: _uuid.v4(),
              name: lbl,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
        }
        return MigrationResult(
          notesProcessed: 1,
          labelsProcessed: note.labels.length,
          attachmentsProcessed: note.attachments.length,
        );
      }
    }

    // ZIP Archive import
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final archiveFilesByName = <String, ArchiveFile>{};
    for (final entry in archive) {
      if (entry.isFile) {
        archiveFilesByName[entry.name] = entry;
        archiveFilesByName[p.basename(entry.name)] = entry;
      }
    }

    // Case 1: Native `keep_backup.json` inside ZIP
    if (archiveFilesByName.containsKey('keep_backup.json')) {
      final backupFile = archiveFilesByName['keep_backup.json']!;
      final jsonStr = utf8.decode(backupFile.content as List<int>);
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      return _importNativeBackupMap(map, archiveFilesByName, baseMediaDir);
    }

    // Case 2: Google Takeout Keep ZIP (`Takeout/Keep/*.json`)
    int notesCount = 0;
    int attachmentsCount = 0;
    final discoveredLabels = <String>{};

    for (final entry in archive) {
      if (entry.isFile && entry.name.toLowerCase().endsWith('.json')) {
        try {
          final jsonStr = utf8.decode(entry.content as List<int>);
          final decoded = jsonDecode(jsonStr);
          if (decoded is Map<String, dynamic> &&
              (decoded.containsKey('textContent') ||
                  decoded.containsKey('listContent') ||
                  decoded.containsKey('title') ||
                  decoded.containsKey('color'))) {
            final note = _parseGoogleTakeoutNote(
              decoded,
              archiveFilesByName,
              baseMediaDir,
            );
            await _db.upsertNote(note);
            notesCount++;
            attachmentsCount += note.attachments.length;
            discoveredLabels.addAll(note.labels);
          }
        } catch (_) {
          // Ignore non-Keep JSON files inside Takeout archive
        }
      }
    }

    final now = DateTime.now();
    for (final labelName in discoveredLabels) {
      await _db.upsertLabel(
        LabelModel(
          id: _uuid.v4(),
          name: labelName,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    return MigrationResult(
      notesProcessed: notesCount,
      labelsProcessed: discoveredLabels.length,
      attachmentsProcessed: attachmentsCount,
    );
  }

  Future<MigrationResult> _importNativeBackupMap(
    Map<String, dynamic> backupMap,
    Map<String, ArchiveFile> archiveFiles,
    Directory mediaDir,
  ) async {
    int notesCount = 0;
    int labelsCount = 0;
    int attachmentsCount = 0;

    final rawLabels = backupMap['labels'] as List<dynamic>? ?? [];
    for (final item in rawLabels) {
      final label = LabelModel.fromJson(item as Map<String, dynamic>);
      await _db.upsertLabel(
        label.copyWith(syncStatus: SyncStatus.pendingUpsert),
      );
      labelsCount++;
    }

    final rawNotes = backupMap['notes'] as List<dynamic>? ?? [];
    for (final item in rawNotes) {
      final noteJson = Map<String, dynamic>.from(item as Map<String, dynamic>);
      final rawAtts = noteJson['attachments'] as List<dynamic>? ?? [];
      final restoredAttachments = <Map<String, dynamic>>[];

      for (final rawAtt in rawAtts) {
        final attMap = Map<String, dynamic>.from(rawAtt as Map<String, dynamic>);
        final archiveRef = attMap['archiveMediaFile'] as String?;
        if (archiveRef != null && archiveFiles.containsKey(archiveRef)) {
          final entry = archiveFiles[archiveRef]!;
          final fileBytes = entry.content as List<int>;
          final destFile = File(p.join(mediaDir.path, p.basename(archiveRef)));
          await destFile.writeAsBytes(fileBytes);
          attMap['localPath'] = destFile.path;
          attachmentsCount++;
        }
        restoredAttachments.add(attMap);
      }

      noteJson['attachments'] = restoredAttachments;
      final note = NoteModel.fromJson(noteJson).copyWith(
        syncStatus: SyncStatus.pendingUpsert,
      );
      await _db.upsertNote(note);
      notesCount++;
    }

    return MigrationResult(
      notesProcessed: notesCount,
      labelsProcessed: labelsCount,
      attachmentsProcessed: attachmentsCount,
    );
  }

  NoteModel _parseGoogleTakeoutNote(
    Map<String, dynamic> takeout,
    Map<String, ArchiveFile> archiveFiles,
    Directory mediaDir,
  ) {
    final noteId = _uuid.v4();
    final title = takeout['title'] as String? ?? '';
    final textContent = takeout['textContent'] as String? ?? '';

    final rawList = takeout['listContent'] as List<dynamic>? ?? [];
    final checklistItems = <ChecklistItem>[];
    for (var i = 0; i < rawList.length; i++) {
      final entry = rawList[i] as Map<String, dynamic>;
      checklistItems.add(
        ChecklistItem(
          id: _uuid.v4(),
          text: entry['text'] as String? ?? '',
          isChecked: entry['isChecked'] as bool? ?? false,
          indentLevel: 0,
          sortOrder: i,
        ),
      );
    }

    final rawLabels = takeout['labels'] as List<dynamic>? ?? [];
    final labels = rawLabels
        .map((e) => (e as Map<String, dynamic>)['name'] as String? ?? '')
        .where((name) => name.isNotEmpty)
        .toList();

    final createdUsec = (takeout['createdTimestampUsec'] as num?)?.toInt();
    final editedUsec = (takeout['userEditedTimestampUsec'] as num?)?.toInt();
    final createdAt = createdUsec != null
        ? DateTime.fromMicrosecondsSinceEpoch(createdUsec)
        : DateTime.now();
    final updatedAt = editedUsec != null
        ? DateTime.fromMicrosecondsSinceEpoch(editedUsec)
        : createdAt;

    final rawAttachments = takeout['attachments'] as List<dynamic>? ?? [];
    final attachments = <NoteAttachment>[];
    for (final rawAtt in rawAttachments) {
      final attMap = rawAtt as Map<String, dynamic>;
      final filePath = attMap['filePath'] as String? ?? '';
      final mimetype = (attMap['mimetype'] as String? ?? '').toLowerCase();
      if (filePath.isNotEmpty) {
        final matchEntry = archiveFiles[filePath] ??
            archiveFiles[p.basename(filePath)];
        String localFilePath = '';
        if (matchEntry != null) {
          final dest = File(
            p.join(mediaDir.path, '${_uuid.v4()}_${p.basename(filePath)}'),
          );
          dest.writeAsBytesSync(matchEntry.content as List<int>);
          localFilePath = dest.path;
        }
        final type = mimetype.startsWith('audio/')
            ? AttachmentType.audio
            : AttachmentType.image;
        attachments.add(
          NoteAttachment(
            id: _uuid.v4(),
            noteId: noteId,
            type: type,
            localPath: localFilePath,
            createdAt: createdAt,
            updatedAt: updatedAt,
          ),
        );
      }
    }

    return NoteModel(
      id: noteId,
      title: title,
      content: textContent,
      isChecklist: checklistItems.isNotEmpty,
      checklistItems: checklistItems,
      colorId: _mapTakeoutColor(takeout['color'] as String?),
      isPinned: takeout['isPinned'] as bool? ?? false,
      isArchived: takeout['isArchived'] as bool? ?? false,
      isTrashed: takeout['isTrashed'] as bool? ?? false,
      labels: labels,
      attachments: attachments,
      createdAt: createdAt,
      updatedAt: updatedAt,
      syncStatus: SyncStatus.pendingUpsert,
    );
  }

  String _mapTakeoutColor(String? takeoutColor) {
    switch ((takeoutColor ?? 'DEFAULT').toUpperCase()) {
      case 'RED':
        return 'coral';
      case 'ORANGE':
        return 'peach';
      case 'YELLOW':
        return 'sand';
      case 'GREEN':
        return 'mint';
      case 'TEAL':
        return 'sage';
      case 'BLUE':
      case 'CERULEAN':
        return 'fog';
      case 'DARK_BLUE':
        return 'storm';
      case 'PURPLE':
        return 'dusk';
      case 'PINK':
        return 'blossom';
      case 'BROWN':
        return 'clay';
      case 'GRAY':
        return 'chalk';
      default:
        return 'default';
    }
  }

  Future<Directory> _ensureLocalMediaDirectory() async {
    final docDir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(p.join(docDir.path, 'keep_media'));
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    return mediaDir;
  }
}
