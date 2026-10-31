import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gkeep/app.dart';
import 'package:gkeep/core/utils/url_utils.dart';
import 'package:gkeep/data/local/keep_database.dart';
import 'package:gkeep/data/migration/keep_migration_service.dart';
import 'package:gkeep/domain/models/note_model.dart';
import 'package:gkeep/domain/services/keep_providers.dart';

void main() {
  group('KeepDatabase Offline SQLite & FTS5 Tests', () {
    late KeepDatabase db;

    setUp(() {
      db = KeepDatabase.memory();
    });

    tearDown(() async {
      await db.close();
    });

    test('persists notes, checklists, attachments, and performs FTS5 search',
        () async {
      final now = DateTime.now();
      final note = NoteModel(
        id: 'note-1',
        title: 'Weekly Groceries',
        content: 'Buy organic apples and almond milk',
        isChecklist: true,
        checklistItems: const [
          ChecklistItem(
            id: 'item-1',
            text: 'Sourdough bread',
            isChecked: false,
            indentLevel: 0,
            sortOrder: 0,
          ),
          ChecklistItem(
            id: 'item-2',
            text: 'Avocados',
            isChecked: true,
            indentLevel: 1,
            sortOrder: 1,
          ),
        ],
        colorId: 'mint',
        backgroundTheme: 'groceries',
        isPinned: true,
        labels: const ['shopping', 'home'],
        createdAt: now,
        updatedAt: now,
      );

      await db.upsertNote(note);

      final all = await db.getAllNotes();
      expect(all.length, 1);
      expect(all.first.title, 'Weekly Groceries');
      expect(all.first.checklistItems.length, 2);
      expect(all.first.checklistItems[1].indentLevel, 1);
      expect(all.first.colorId, 'mint');

      // Full-Text Search (FTS5) on checklist item text and label
      final matchesBread = await db.searchNotes('Sourdough');
      expect(matchesBread.length, 1);
      expect(matchesBread.first.id, 'note-1');

      final matchesLabel = await db.searchNotes('shopping');
      expect(matchesLabel.length, 1);

      final noMatches = await db.searchNotes('nonexistentkeyword');
      expect(noMatches, isEmpty);
    });

    test('renames and deletes labels across all tagged notes', () async {
      final now = DateTime.now();
      await db.upsertLabel(
        LabelModel(
          id: 'lbl-1',
          name: 'work',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.upsertNote(
        NoteModel(
          id: 'note-work',
          title: 'Q4 Roadmap',
          labels: const ['work'],
          createdAt: now,
          updatedAt: now,
        ),
      );

      await db.renameLabel('lbl-1', 'work', 'engineering');
      final renamedNote = await db.getNoteById('note-work');
      expect(renamedNote!.labels, contains('engineering'));
      expect(renamedNote.labels, isNot(contains('work')));

      await db.deleteLabel('lbl-1', 'engineering');
      final afterDelete = await db.getNoteById('note-work');
      expect(afterDelete!.labels, isEmpty);
    });

    test('auto-purges trashed notes older than 7 days', () async {
      final tenDaysAgo = DateTime.now().subtract(const Duration(days: 10));
      await db.upsertNote(
        NoteModel(
          id: 'expired-trash',
          title: 'Old Trashed Note',
          isTrashed: true,
          trashedAt: tenDaysAgo,
          createdAt: tenDaysAgo,
          updatedAt: tenDaysAgo,
        ),
      );

      await db.purgeExpiredTrash();
      final result = await db.getNoteById('expired-trash');
      expect(result, isNull);
    });
  });

  group('KeepMigrationService Export & Import Round-Trip Tests', () {
    late KeepDatabase sourceDb;
    late KeepDatabase targetDb;
    late Directory tempDir;

    setUp(() async {
      sourceDb = KeepDatabase.memory();
      targetDb = KeepDatabase.memory();
      tempDir = await Directory.systemTemp.createTemp('keep_migration_test_');
    });

    tearDown(() async {
      await sourceDb.close();
      await targetDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('exports full ZIP bundle (JSON + Markdown + Media) and restores cleanly',
        () async {
      final now = DateTime.now();
      final dummyImage = File('${tempDir.path}/sample.png');
      await dummyImage.writeAsBytes([137, 80, 78, 71, 13, 10, 26, 10]);

      await sourceDb.upsertLabel(
        LabelModel(
          id: 'l1',
          name: 'recipes',
          createdAt: now,
          updatedAt: now,
        ),
      );

      await sourceDb.upsertNote(
        NoteModel(
          id: 'n1',
          title: 'Pasta Carbonara',
          content: 'Guanciale, Pecorino, Eggs, Black Pepper',
          colorId: 'peach',
          backgroundTheme: 'recipes',
          labels: const ['recipes'],
          attachments: [
            NoteAttachment(
              id: 'att1',
              noteId: 'n1',
              type: AttachmentType.image,
              localPath: dummyImage.path,
              ocrText: 'Authentic Roman Recipe',
              createdAt: now,
              updatedAt: now,
            ),
          ],
          createdAt: now,
          updatedAt: now,
        ),
      );

      final exporter = KeepMigrationService(sourceDb);
      final exportResult =
          await exporter.exportFullBackupZip(targetDirectory: tempDir);
      expect(exportResult.notesProcessed, 1);
      expect(exportResult.labelsProcessed, 1);
      expect(exportResult.attachmentsProcessed, 1);
      expect(exportResult.archivePath, isNotNull);

      final zipFile = File(exportResult.archivePath!);
      expect(await zipFile.exists(), isTrue);

      // Import into fresh targetDb
      final importer = KeepMigrationService(targetDb);
      final importResult = await importer.importBackupFile(
        zipFile,
        mediaRootDir: tempDir,
      );
      expect(importResult.notesProcessed, 1);
      expect(importResult.labelsProcessed, 1);

      final restoredNotes = await targetDb.getAllNotes();
      expect(restoredNotes.length, 1);
      expect(restoredNotes.first.title, 'Pasta Carbonara');
      expect(restoredNotes.first.attachments.first.ocrText,
          'Authentic Roman Recipe');
    });

    test('imports Google Takeout Keep JSON format accurately', () async {
      final takeoutFile = File('${tempDir.path}/TakeoutNote.json');
      final takeoutJson = {
        'color': 'YELLOW',
        'isTrashed': false,
        'isPinned': true,
        'isArchived': false,
        'title': 'Imported from Google Keep Takeout',
        'listContent': [
          {'text': 'First Takeout item', 'isChecked': false},
          {'text': 'Second Takeout item', 'isChecked': true},
        ],
        'labels': [
          {'name': 'takeout-tag'}
        ],
        'userEditedTimestampUsec': 1700000000000000,
      };
      await takeoutFile.writeAsString(jsonEncode(takeoutJson));

      final importer = KeepMigrationService(targetDb);
      final res = await importer.importBackupFile(
        takeoutFile,
        mediaRootDir: tempDir,
      );
      expect(res.notesProcessed, 1);

      final notes = await targetDb.getAllNotes();
      expect(notes.single.title, 'Imported from Google Keep Takeout');
      expect(notes.single.colorId, 'sand'); // YELLOW -> sand
      expect(notes.single.isPinned, isTrue);
      expect(notes.single.isChecklist, isTrue);
      expect(notes.single.checklistItems.length, 2);
      expect(notes.single.labels, contains('takeout-tag'));
    });
  });

  group('URL Extraction & Widget UI Tests', () {
    test('extracts valid URLs from note text', () {
      const sample =
          'Read https://flutter.dev/docs and https://supabase.com/docs.';
      final urls = UrlUtils.extractUrls(sample);
      expect(
        urls,
        containsAll(['https://flutter.dev/docs', 'https://supabase.com/docs']),
      );
    });

    testWidgets('renders Home screen and creates a new note via Editor',
        (WidgetTester tester) async {
      final memoryDb = KeepDatabase.memory();
      addTearDown(memoryDb.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            keepDatabaseProvider.overrideWithValue(memoryDb),
          ],
          child: const KeepCloneApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify empty state and search bar
      expect(find.text('Search your notes'), findsOneWidget);
      expect(find.text('Notes you add appear here'), findsOneWidget);

      // Tap FAB to create a new note
      await tester.tap(find.byKey(const Key('create_note_fab')));
      await tester.pumpAndSettle();

      // Enter title and content
      await tester.enterText(
        find.byKey(const Key('note_title_input')),
        'Launch Prep Note',
      );
      await tester.enterText(
        find.byKey(const Key('note_content_input')),
        'Ship Android and iOS Keep clone with #release',
      );
      await tester.pump();

      // Inline #release autocomplete chip should appear
      expect(find.text('Create "#release"'), findsOneWidget);
      await tester.tap(find.text('Create "#release"'));
      await tester.pump();

      // Save and return to Home screen
      await tester.tap(find.byKey(const Key('editor_back_button')));
      await tester.pumpAndSettle();

      // Verify note card and inline label chip render on Home screen
      expect(find.text('Launch Prep Note'), findsOneWidget);
      expect(find.text('release'), findsOneWidget);
    });
  });
}
