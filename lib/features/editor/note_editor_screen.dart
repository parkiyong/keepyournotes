import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/keep_colors.dart';
import '../../core/utils/url_utils.dart';
import '../../domain/models/note_model.dart';
import '../../domain/services/keep_providers.dart';
import '../drawing/drawing_canvas_screen.dart';
import '../reminders/reminder_picker_sheet.dart';

class _EditorSnapshot {
  final String title;
  final String content;
  final List<ChecklistItem> checklistItems;

  const _EditorSnapshot({
    required this.title,
    required this.content,
    required this.checklistItems,
  });
}

class NoteEditorScreen extends ConsumerStatefulWidget {
  final NoteModel? initialNote;
  final bool startAsChecklist;
  final bool startWithDrawing;
  final bool startWithVoice;
  final bool startWithImagePicker;

  const NoteEditorScreen({
    super.key,
    this.initialNote,
    this.startAsChecklist = false,
    this.startWithDrawing = false,
    this.startWithVoice = false,
    this.startWithImagePicker = false,
  });

  @override
  ConsumerState<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends ConsumerState<NoteEditorScreen> {
  static const _uuid = Uuid();
  late NoteModel _note;
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  final TextEditingController _newChecklistItemController =
      TextEditingController();

  final List<_EditorSnapshot> _undoStack = [];
  final List<_EditorSnapshot> _redoStack = [];
  bool _isApplyingSnapshot = false;

  bool _showFormattingBar = false;
  bool _checkedSectionExpanded = true;
  String _liveVoiceTranscript = '';
  String? _inlineHashtagQuery;

  // Rich text active toggles
  bool _isBold = false;
  bool _isItalic = false;
  bool _isUnderline = false;
  int _headingLevel = 0; // 0 = normal, 1 = H1, 2 = H2

  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _playingAttachmentId;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _note = widget.initialNote ??
        NoteModel(
          id: _uuid.v4(),
          isChecklist: widget.startAsChecklist,
          checklistItems: widget.startAsChecklist
              ? [ChecklistItem(id: _uuid.v4(), text: '', sortOrder: 0)]
              : const [],
          createdAt: now,
          updatedAt: now,
        );

    _titleController = TextEditingController(text: _note.title);
    _contentController = TextEditingController(text: _note.content);

    // Restore primary text style state from richSpans if present
    if (_note.richSpans.isNotEmpty) {
      final first = _note.richSpans.first;
      _isBold = first.isBold;
      _isItalic = first.isItalic;
      _isUnderline = first.isUnderline;
      _headingLevel = first.headingLevel;
    }

    _pushUndoSnapshot();
    _contentController.addListener(_onContentChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.startWithDrawing) {
        _openDrawingCanvas();
      } else if (widget.startWithVoice) {
        _showVoiceRecordingDialog();
      } else if (widget.startWithImagePicker) {
        _pickImage(ImageSource.gallery);
      }
    });
  }

  @override
  void dispose() {
    _contentController.removeListener(_onContentChanged);
    _titleController.dispose();
    _contentController.dispose();
    _newChecklistItemController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _pushUndoSnapshot() {
    if (_isApplyingSnapshot) return;
    final snap = _EditorSnapshot(
      title: _titleController.text,
      content: _contentController.text,
      checklistItems: List<ChecklistItem>.from(_note.checklistItems),
    );
    if (_undoStack.isNotEmpty) {
      final last = _undoStack.last;
      if (last.title == snap.title &&
          last.content == snap.content &&
          last.checklistItems.length == snap.checklistItems.length) {
        return;
      }
    }
    _undoStack.add(snap);
    if (_undoStack.length > 40) {
      _undoStack.removeAt(0);
    }
  }

  void _undo() {
    if (_undoStack.length <= 1) return;
    _isApplyingSnapshot = true;
    final current = _undoStack.removeLast();
    _redoStack.add(current);
    final prev = _undoStack.last;
    setState(() {
      _titleController.text = prev.title;
      _contentController.text = prev.content;
      _note = _note.copyWith(
        title: prev.title,
        content: prev.content,
        checklistItems: prev.checklistItems,
      );
    });
    _isApplyingSnapshot = false;
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    _isApplyingSnapshot = true;
    final next = _redoStack.removeLast();
    _undoStack.add(next);
    setState(() {
      _titleController.text = next.title;
      _contentController.text = next.content;
      _note = _note.copyWith(
        title: next.title,
        content: next.content,
        checklistItems: next.checklistItems,
      );
    });
    _isApplyingSnapshot = false;
  }

  void _onContentChanged() {
    final text = _contentController.text;
    final selection = _contentController.selection;
    _pushUndoSnapshot();

    // Detect `#label` inline autocomplete token before cursor
    final cursor =
        selection.baseOffset >= 0 ? selection.baseOffset : text.length;
    final prefix = text.substring(0, cursor.clamp(0, text.length));
    final match = RegExp(r'(?:^|\s)#([a-zA-Z0-9_-]*)$').firstMatch(prefix);
    setState(() {
      _inlineHashtagQuery = match?.group(1);
    });
  }

  void _applyInlineHashtagLabel(String labelName) {
    final text = _contentController.text;
    final cursor = _contentController.selection.baseOffset >= 0
        ? _contentController.selection.baseOffset
        : text.length;
    final prefix = text.substring(0, cursor.clamp(0, text.length));
    final suffix = text.substring(cursor.clamp(0, text.length));
    final replacedPrefix =
        prefix.replaceFirst(RegExp(r'#([a-zA-Z0-9_-]*)$'), '');

    _contentController.text = '$replacedPrefix$suffix'.trimRight();
    if (!_note.labels.contains(labelName)) {
      setState(() {
        _note = _note.copyWith(labels: [..._note.labels, labelName]);
        _inlineHashtagQuery = null;
      });
    } else {
      setState(() => _inlineHashtagQuery = null);
    }
    ref.read(keepActionsProvider).createLabel(labelName);
  }

  NoteModel _buildCurrentNoteState() {
    final spans = <RichTextSpanRule>[
      if (_isBold || _isItalic || _isUnderline || _headingLevel > 0)
        RichTextSpanRule(
          start: 0,
          end: _contentController.text.length,
          isBold: _isBold,
          isItalic: _isItalic,
          isUnderline: _isUnderline,
          headingLevel: _headingLevel,
        ),
    ];

    return _note.copyWith(
      title: _titleController.text.trim(),
      content: _contentController.text,
      richSpans: spans,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _saveAndExit() async {
    final current = _buildCurrentNoteState();
    if (current.isEmpty && widget.initialNote == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    await ref.read(keepActionsProvider).saveNote(current);
    if (mounted) Navigator.of(context).pop();
  }

  void _toggleChecklistMode() {
    setState(() {
      if (!_note.isChecklist) {
        final lines = _contentController.text
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .toList();
        final items = lines.isEmpty
            ? [ChecklistItem(id: _uuid.v4(), text: '', sortOrder: 0)]
            : [
                for (var i = 0; i < lines.length; i++)
                  ChecklistItem(
                    id: _uuid.v4(),
                    text: lines[i],
                    sortOrder: i,
                  ),
              ];
        _note = _note.copyWith(isChecklist: true, checklistItems: items);
      } else {
        final joined = _note.checklistItems.map((i) => i.text).join('\n');
        _contentController.text = joined;
        _note = _note.copyWith(isChecklist: false);
      }
    });
  }

  Future<void> _openDrawingCanvas({NoteAttachment? existingDrawing}) async {
    final result = await Navigator.of(context).push<DrawingCanvasResult>(
      MaterialPageRoute(
        builder: (_) => DrawingCanvasScreen(
          initialStrokes: existingDrawing?.strokes ?? const [],
          initialGrid: existingDrawing?.drawingGrid ?? 'dots',
        ),
      ),
    );
    if (result == null) return;

    final now = DateTime.now();
    setState(() {
      if (existingDrawing != null) {
        final updatedList = _note.attachments.map((a) {
          if (a.id == existingDrawing.id) {
            return a.copyWith(
              localPath: result.filePath,
              strokes: result.strokes,
              drawingGrid: result.gridType,
              updatedAt: now,
            );
          }
          return a;
        }).toList();
        _note = _note.copyWith(attachments: updatedList);
      } else {
        final newAtt = NoteAttachment(
          id: _uuid.v4(),
          noteId: _note.id,
          type: AttachmentType.drawing,
          localPath: result.filePath,
          strokes: result.strokes,
          drawingGrid: result.gridType,
          createdAt: now,
          updatedAt: now,
        );
        _note = _note.copyWith(attachments: [..._note.attachments, newAtt]);
      }
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 88);
      if (picked == null) return;

      final appDir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory(p.join(appDir.path, 'keep_media'));
      if (!await mediaDir.exists()) {
        await mediaDir.create(recursive: true);
      }
      final ext = p.extension(picked.path).isNotEmpty
          ? p.extension(picked.path)
          : '.jpg';
      final savedFile =
          File(p.join(mediaDir.path, 'img_${_uuid.v4()}$ext'));
      await File(picked.path).copy(savedFile.path);

      final now = DateTime.now();
      final att = NoteAttachment(
        id: _uuid.v4(),
        noteId: _note.id,
        type: AttachmentType.image,
        localPath: savedFile.path,
        createdAt: now,
        updatedAt: now,
      );
      setState(() {
        _note = _note.copyWith(attachments: [..._note.attachments, att]);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not attach image: $e')),
        );
      }
    }
  }

  Future<void> _runOcrOnAttachment(NoteAttachment att) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Running on-device OCR (Grab image text)...')),
    );
    final extracted = await ref
        .read(keepOcrServiceProvider)
        .extractTextFromImage(att.localPath);
    if (!mounted) return;
    if (extracted.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No text detected in image.')),
      );
      return;
    }

    setState(() {
      if (_note.isChecklist) {
        final lines = extracted
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty);
        final nextItems = [
          ..._note.checklistItems,
          for (final l in lines)
            ChecklistItem(
              id: _uuid.v4(),
              text: l,
              sortOrder: _note.checklistItems.length,
            ),
        ];
        _note = _note.copyWith(checklistItems: nextItems);
      } else {
        final existing = _contentController.text.trim();
        _contentController.text =
            existing.isEmpty ? extracted : '$existing\n\n$extracted';
      }

      // Also store OCR text inside attachment metadata for search indexing
      final updatedAtts = _note.attachments.map((a) {
        if (a.id == att.id) return a.copyWith(ocrText: extracted);
        return a;
      }).toList();
      _note = _note.copyWith(attachments: updatedAtts);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Grabbed text from image into note!')),
    );
  }

  Future<void> _showVoiceRecordingDialog() async {
    final voiceService = ref.read(keepVoiceServiceProvider);
    setState(() {
      _liveVoiceTranscript = '';
    });

    final path = await voiceService.startRecording(
      onTranscriptUpdate: (liveText) {
        if (mounted) {
          setState(() => _liveVoiceTranscript = liveText);
        }
      },
    );

    if (path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission required to record audio.'),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.graphic_eq,
                    size: 48,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Recording voice note...',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _liveVoiceTranscript.isNotEmpty
                        ? '"$_liveVoiceTranscript"'
                        : 'Speak now — live transcription will appear in your note',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Stop & Attach Recording'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    final result = await voiceService.stopRecording();

    if (result.path != null) {
      final now = DateTime.now();
      final audioAtt = NoteAttachment(
        id: _uuid.v4(),
        noteId: _note.id,
        type: AttachmentType.audio,
        localPath: result.path!,
        durationMs: result.durationMs,
        transcript: result.transcript,
        createdAt: now,
        updatedAt: now,
      );
      setState(() {
        _note = _note.copyWith(attachments: [..._note.attachments, audioAtt]);
        if (result.transcript.isNotEmpty && !_note.isChecklist) {
          final prev = _contentController.text.trim();
          _contentController.text =
              prev.isEmpty ? result.transcript : '$prev\n${result.transcript}';
        }
      });
    }
  }

  Future<void> _openReminderSheet() async {
    final result = await showModalBottomSheet<ReminderConfigResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReminderPickerSheet(
        initialReminderAt: _note.reminderAt,
        initialRecurrence: _note.reminderRecurrence,
        initialLocation: _note.reminderLocation,
      ),
    );
    if (result == null) return;

    setState(() {
      if (result.cleared) {
        _note = _note.copyWith(
          clearReminderAt: true,
          clearReminderLocation: true,
          reminderRecurrence: 'none',
        );
      } else if (result.location != null) {
        _note = _note.copyWith(
          reminderLocation: result.location,
          clearReminderAt: true,
        );
      } else if (result.reminderAt != null) {
        _note = _note.copyWith(
          reminderAt: result.reminderAt,
          reminderRecurrence: result.recurrence,
          clearReminderLocation: true,
        );
      }
    });
  }

  void _showColorAndBackgroundSheet() {
    final brightness = Theme.of(context).brightness;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Colour',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 52,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        itemCount: KeepPalette.colors.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final c = KeepPalette.colors[index];
                          final selected = _note.colorId == c.id;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _note = _note.copyWith(colorId: c.id);
                              });
                              setSheetState(() {});
                            },
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: c.backgroundFor(brightness),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected
                                      ? Theme.of(context).colorScheme.primary
                                      : c.borderFor(brightness),
                                  width: selected ? 2.5 : 1.2,
                                ),
                              ),
                              child: selected
                                  ? Icon(
                                      Icons.check,
                                      size: 20,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Background theme',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 68,
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        scrollDirection: Axis.horizontal,
                        itemCount: KeepPalette.themes.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final t = KeepPalette.themes[index];
                          final selected = _note.backgroundTheme == t.id;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _note = _note.copyWith(backgroundTheme: t.id);
                              });
                              setSheetState(() {});
                            },
                            child: Container(
                              width: 68,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selected
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.grey.withValues(alpha: 0.4),
                                  width: selected ? 2.5 : 1.0,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(t.icon, size: 22),
                                  const SizedBox(height: 4),
                                  Text(
                                    t.label,
                                    style: const TextStyle(fontSize: 10),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAddAttachmentSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Add image'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.brush_outlined),
              title: const Text('Drawing'),
              onTap: () {
                Navigator.pop(ctx);
                _openDrawingCanvas();
              },
            ),
            ListTile(
              leading: const Icon(Icons.mic_none_outlined),
              title: const Text('Recording (Voice + Speech-to-Text)'),
              onTap: () {
                Navigator.pop(ctx);
                _showVoiceRecordingDialog();
              },
            ),
            ListTile(
              leading: Icon(
                _note.isChecklist
                    ? Icons.notes_outlined
                    : Icons.check_box_outlined,
              ),
              title: Text(
                _note.isChecklist ? 'Hide tick boxes' : 'Tick boxes (Checklist)',
              ),
              onTap: () {
                Navigator.pop(ctx);
                _toggleChecklistMode();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showMoreActionsSheet() {
    final allLabels =
        ref.read(allLabelsStreamProvider).value ?? const <LabelModel>[];

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () async {
                Navigator.pop(ctx);
                await ref
                    .read(keepActionsProvider)
                    .moveToTrash(_buildCurrentNoteState());
                if (mounted) Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Make a copy'),
              onTap: () async {
                Navigator.pop(ctx);
                await ref
                    .read(keepActionsProvider)
                    .duplicateNote(_buildCurrentNoteState());
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Note duplicated.')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Send / Share'),
              onTap: () async {
                Navigator.pop(ctx);
                final current = _buildCurrentNoteState();
                final mediaFiles = current.attachments
                    .where((a) =>
                        a.localPath.isNotEmpty && File(a.localPath).existsSync())
                    .map((a) => XFile(a.localPath))
                    .toList();
                final textToShare = [
                  if (current.title.isNotEmpty) current.title,
                  if (current.isChecklist)
                    ...current.checklistItems.map(
                        (i) => '${i.isChecked ? "[x]" : "[ ]"} ${i.text}')
                  else if (current.content.isNotEmpty)
                    current.content,
                ].join('\n');

                await SharePlus.instance.share(
                  ShareParams(
                    text: textToShare.isNotEmpty ? textToShare : 'Keep Note',
                    subject: current.title,
                    files: mediaFiles.isNotEmpty ? mediaFiles : null,
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: const Text('Labels'),
              onTap: () {
                Navigator.pop(ctx);
                _showLabelPickerDialog(allLabels);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLabelPickerDialog(List<LabelModel> allLabels) async {
    final newLabelCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final currentLabels = _note.labels;
            return AlertDialog(
              title: const Text('Note labels'),
              content: SizedBox(
                width: 320,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: newLabelCtrl,
                      decoration: InputDecoration(
                        hintText: 'Enter label name',
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            final name = newLabelCtrl.text.trim();
                            if (name.isEmpty) return;
                            ref.read(keepActionsProvider).createLabel(name);
                            if (!_note.labels.contains(name)) {
                              setState(() {
                                _note = _note.copyWith(
                                  labels: [..._note.labels, name],
                                );
                              });
                            }
                            newLabelCtrl.clear();
                            setDialogState(() {});
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: allLabels.map((lbl) {
                          final checked = currentLabels.contains(lbl.name);
                          return CheckboxListTile(
                            dense: true,
                            value: checked,
                            title: Text(lbl.name),
                            onChanged: (v) {
                              setState(() {
                                if (v == true) {
                                  _note = _note.copyWith(
                                    labels: [..._note.labels, lbl.name],
                                  );
                                } else {
                                  _note = _note.copyWith(
                                    labels: _note.labels
                                        .where((l) => l != lbl.name)
                                        .toList(),
                                  );
                                }
                              });
                              setDialogState(() {});
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  TextStyle _contentTextStyle(BuildContext context) {
    double fontSize = 16.0;
    FontWeight weight = _isBold ? FontWeight.bold : FontWeight.normal;
    if (_headingLevel == 1) {
      fontSize = 22.0;
      weight = FontWeight.bold;
    } else if (_headingLevel == 2) {
      fontSize = 18.5;
      weight = FontWeight.w600;
    }
    return TextStyle(
      fontSize: fontSize,
      fontWeight: weight,
      fontStyle: _isItalic ? FontStyle.italic : FontStyle.normal,
      decoration:
          _isUnderline ? TextDecoration.underline : TextDecoration.none,
      height: 1.4,
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final paletteColor = KeepPalette.byId(_note.colorId);
    final bgColor = paletteColor.backgroundFor(brightness);
    final allLabels =
        ref.watch(allLabelsStreamProvider).value ?? const <LabelModel>[];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _saveAndExit();
      },
      child: Scaffold(
        backgroundColor: bgColor,
        appBar: AppBar(
          backgroundColor: bgColor,
          leading: IconButton(
            key: const Key('editor_back_button'),
            icon: const Icon(Icons.arrow_back),
            onPressed: _saveAndExit,
          ),
          actions: [
            IconButton(
              tooltip: _note.isPinned ? 'Unpin' : 'Pin',
              icon: Icon(
                _note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              onPressed: () {
                setState(() => _note = _note.copyWith(isPinned: !_note.isPinned));
              },
            ),
            IconButton(
              tooltip: 'Remind me',
              icon: Icon(
                _note.hasReminder
                    ? Icons.notifications_active
                    : Icons.add_alert_outlined,
              ),
              onPressed: _openReminderSheet,
            ),
            IconButton(
              tooltip: _note.isLocked ? 'Unlock note' : 'Lock note with Biometrics/PIN',
              icon: Icon(
                _note.isLocked ? Icons.lock : Icons.lock_open_outlined,
              ),
              onPressed: () {
                setState(() => _note = _note.copyWith(isLocked: !_note.isLocked));
                ref
                    .read(unlockedNotesSessionProvider.notifier)
                    .markUnlocked(_note.id);
              },
            ),
            IconButton(
              tooltip: _note.isArchived ? 'Unarchive' : 'Archive',
              icon: Icon(
                _note.isArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
              ),
              onPressed: () {
                setState(
                    () => _note = _note.copyWith(isArchived: !_note.isArchived));
              },
            ),
          ],
        ),
        body: CustomPaint(
          painter: KeepThemeBackgroundPainter(
            themeId: _note.backgroundTheme,
            brightness: brightness,
          ),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    // 1. Visual Attachments (Images & Drawings)
                    if (_note.visualAttachments.isNotEmpty) ...[
                      _buildVisualAttachmentsSection(),
                      const SizedBox(height: 12),
                    ],

                    // 2. Title Field
                    TextField(
                      key: const Key('note_title_input'),
                      controller: _titleController,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Title',
                        border: InputBorder.none,
                      ),
                      maxLines: null,
                      onChanged: (_) => _pushUndoSnapshot(),
                    ),

                    // 3. Body Content OR Checklist
                    if (_note.isChecklist)
                      _buildChecklistEditor()
                    else
                      TextField(
                        key: const Key('note_content_input'),
                        controller: _contentController,
                        style: _contentTextStyle(context),
                        decoration: const InputDecoration(
                          hintText: 'Note (type #label to tag inline)',
                          border: InputBorder.none,
                        ),
                        maxLines: null,
                        minLines: 6,
                      ),

                    // 4. Audio Voice Recordings
                    if (_note.audioAttachments.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      ..._note.audioAttachments.map(_buildAudioAttachmentCard),
                    ],

                    // 5. Active Reminders & Labels Chips
                    if (_note.hasReminder || _note.labels.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_note.reminderAt != null)
                            InputChip(
                              avatar: const Icon(Icons.alarm, size: 16),
                              label: Text(
                                KeepDateFormatter.formatReminderChip(
                                  _note.reminderAt!,
                                  _note.reminderRecurrence,
                                ),
                              ),
                              onPressed: _openReminderSheet,
                              onDeleted: () => setState(() {
                                _note = _note.copyWith(
                                  clearReminderAt: true,
                                  reminderRecurrence: 'none',
                                );
                              }),
                            ),
                          if (_note.reminderLocation != null)
                            InputChip(
                              avatar:
                                  const Icon(Icons.place_outlined, size: 16),
                              label: Text(_note.reminderLocation!.name),
                              onPressed: _openReminderSheet,
                              onDeleted: () => setState(() {
                                _note = _note.copyWith(
                                  clearReminderLocation: true,
                                );
                              }),
                            ),
                          ..._note.labels.map(
                            (lbl) => InputChip(
                              label: Text(lbl),
                              onDeleted: () => setState(() {
                                _note = _note.copyWith(
                                  labels: _note.labels
                                      .where((l) => l != lbl)
                                      .toList(),
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
                    ],

                    // 6. URL Link Preview Cards
                    if (_note.linkPreviews.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      ..._note.linkPreviews.map(_buildUrlPreviewCard),
                    ],
                  ],
                ),
              ),

              // Inline `#label` autocomplete bar when typing `#...`
              if (_inlineHashtagQuery != null)
                _buildInlineHashtagBar(allLabels),

              // Rich Text Formatting bar (`A` toggle)
              if (_showFormattingBar && !_note.isChecklist)
                _buildFormattingToolbar(),

              // Bottom Google Keep Action Bar
              _buildBottomBar(bgColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVisualAttachmentsSection() {
    final visuals = _note.visualAttachments;
    return Column(
      children: visuals.map((att) {
        final file = File(att.localPath);
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              GestureDetector(
                onTap: () {
                  if (att.type == AttachmentType.drawing) {
                    _openDrawingCanvas(existingDrawing: att);
                  }
                },
                child: file.existsSync()
                    ? Image.file(
                        file,
                        width: double.infinity,
                        height: 210,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        height: 140,
                        color: Colors.black12,
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  children: [
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => _runOcrOnAttachment(att),
                      icon: const Icon(Icons.document_scanner_outlined, size: 16),
                      label: const Text(
                        'Grab image text',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Remove attachment',
                      icon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () {
                        setState(() {
                          _note = _note.copyWith(
                            attachments: _note.attachments
                                .where((a) => a.id != att.id)
                                .toList(),
                          );
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildChecklistEditor() {
    final unchecked =
        _note.checklistItems.where((i) => !i.isChecked).toList();
    final checked = _note.checklistItems.where((i) => i.isChecked).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: unchecked.length,
          onReorderItem: (oldIndex, newIndex) {
            setState(() {
              final moved = unchecked.removeAt(oldIndex);
              unchecked.insert(newIndex, moved);
              _note = _note.copyWith(
                checklistItems: [...unchecked, ...checked],
              );
            });
          },
          itemBuilder: (context, index) {
            final item = unchecked[index];
            return Padding(
              key: ValueKey(item.id),
              padding: EdgeInsets.only(left: item.indentLevel * 24.0),
              child: Row(
                children: [
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(Icons.drag_indicator, size: 18),
                    ),
                  ),
                  Checkbox(
                    value: item.isChecked,
                    onChanged: (v) {
                      setState(() {
                        final updated = _note.checklistItems.map((c) {
                          if (c.id == item.id) {
                            return c.copyWith(isChecked: v ?? false);
                          }
                          return c;
                        }).toList();
                        _note = _note.copyWith(checklistItems: updated);
                      });
                    },
                  ),
                  Expanded(
                    child: TextFormField(
                      initialValue: item.text,
                      decoration: const InputDecoration(
                        hintText: 'List item',
                        border: InputBorder.none,
                      ),
                      onChanged: (val) {
                        final updated = _note.checklistItems.map((c) {
                          if (c.id == item.id) return c.copyWith(text: val);
                          return c;
                        }).toList();
                        _note = _note.copyWith(checklistItems: updated);
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: item.indentLevel == 0
                        ? 'Indent subtask'
                        : 'Outdent subtask',
                    icon: Icon(
                      item.indentLevel == 0
                          ? Icons.format_indent_increase
                          : Icons.format_indent_decrease,
                      size: 18,
                    ),
                    onPressed: () {
                      setState(() {
                        final updated = _note.checklistItems.map((c) {
                          if (c.id == item.id) {
                            return c.copyWith(
                              indentLevel: c.indentLevel == 0 ? 1 : 0,
                            );
                          }
                          return c;
                        }).toList();
                        _note = _note.copyWith(checklistItems: updated);
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      setState(() {
                        _note = _note.copyWith(
                          checklistItems: _note.checklistItems
                              .where((c) => c.id != item.id)
                              .toList(),
                        );
                      });
                    },
                  ),
                ],
              ),
            );
          },
        ),
        // Add new item row
        Row(
          children: [
            const SizedBox(width: 26),
            const Icon(Icons.add, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const Key('add_checklist_item_input'),
                controller: _newChecklistItemController,
                decoration: const InputDecoration(
                  hintText: 'List item',
                  border: InputBorder.none,
                ),
                onSubmitted: (val) {
                  if (val.trim().isEmpty) return;
                  setState(() {
                    _note = _note.copyWith(
                      checklistItems: [
                        ..._note.checklistItems,
                        ChecklistItem(
                          id: _uuid.v4(),
                          text: val.trim(),
                          sortOrder: _note.checklistItems.length,
                        ),
                      ],
                    );
                    _newChecklistItemController.clear();
                  });
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.check, size: 18),
              onPressed: () {
                final val = _newChecklistItemController.text.trim();
                if (val.isEmpty) return;
                setState(() {
                  _note = _note.copyWith(
                    checklistItems: [
                      ..._note.checklistItems,
                      ChecklistItem(
                        id: _uuid.v4(),
                        text: val,
                        sortOrder: _note.checklistItems.length,
                      ),
                    ],
                  );
                  _newChecklistItemController.clear();
                });
              },
            ),
          ],
        ),
        if (checked.isNotEmpty) ...[
          const Divider(),
          InkWell(
            onTap: () {
              setState(
                  () => _checkedSectionExpanded = !_checkedSectionExpanded);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(
                    _checkedSectionExpanded
                        ? Icons.expand_more
                        : Icons.chevron_right,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${checked.length} Checked item${checked.length == 1 ? '' : 's'}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _note = _note.copyWith(
                          checklistItems: _note.checklistItems
                              .where((c) => !c.isChecked)
                              .toList(),
                        );
                      });
                    },
                    child: const Text('Delete checked'),
                  ),
                ],
              ),
            ),
          ),
          if (_checkedSectionExpanded)
            ...checked.map(
              (item) => Row(
                children: [
                  Checkbox(
                    value: true,
                    onChanged: (v) {
                      setState(() {
                        final updated = _note.checklistItems.map((c) {
                          if (c.id == item.id) {
                            return c.copyWith(isChecked: false);
                          }
                          return c;
                        }).toList();
                        _note = _note.copyWith(checklistItems: updated);
                      });
                    },
                  ),
                  Expanded(
                    child: Text(
                      item.text,
                      style: const TextStyle(
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      setState(() {
                        _note = _note.copyWith(
                          checklistItems: _note.checklistItems
                              .where((c) => c.id != item.id)
                              .toList(),
                        );
                      });
                    },
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildAudioAttachmentCard(NoteAttachment att) {
    final isPlaying = _playingAttachmentId == att.id;
    final secs = (att.durationMs / 1000).round();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: IconButton.filled(
          icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
          onPressed: () async {
            if (isPlaying) {
              await _audioPlayer.stop();
              setState(() => _playingAttachmentId = null);
            } else {
              try {
                await _audioPlayer.setFilePath(att.localPath);
                setState(() => _playingAttachmentId = att.id);
                await _audioPlayer.play();
                setState(() => _playingAttachmentId = null);
              } catch (_) {
                setState(() => _playingAttachmentId = null);
              }
            }
          },
        ),
        title: Text('Voice Recording (${secs}s)'),
        subtitle: att.transcript.isNotEmpty
            ? Text('Transcript: "${att.transcript}"')
            : null,
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          onPressed: () {
            setState(() {
              _note = _note.copyWith(
                attachments:
                    _note.attachments.where((a) => a.id != att.id).toList(),
              );
            });
          },
        ),
      ),
    );
  }

  Widget _buildUrlPreviewCard(UrlMetadata preview) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: const Icon(Icons.public),
        title: Text(
          preview.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          preview.domain,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.open_in_new, size: 18),
        onTap: () async {
          final uri = Uri.tryParse(preview.url);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
      ),
    );
  }

  Widget _buildInlineHashtagBar(List<LabelModel> allLabels) {
    final q = (_inlineHashtagQuery ?? '').toLowerCase();
    final matches = allLabels
        .where((l) => l.name.toLowerCase().contains(q))
        .map((l) => l.name)
        .toList();

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (q.isNotEmpty &&
              !matches.any((m) => m.toLowerCase() == q))
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: Text('Create "#$_inlineHashtagQuery"'),
                onPressed: () =>
                    _applyInlineHashtagLabel(_inlineHashtagQuery!),
              ),
            ),
          ...matches.map(
            (name) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: const Icon(Icons.label_outline, size: 16),
                label: Text(name),
                onPressed: () => _applyInlineHashtagLabel(name),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormattingToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: const Border(top: BorderSide(color: Colors.black12)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            ChoiceChip(
              label: const Text('H1'),
              selected: _headingLevel == 1,
              onSelected: (v) => setState(() => _headingLevel = v ? 1 : 0),
            ),
            const SizedBox(width: 6),
            ChoiceChip(
              label: const Text('H2'),
              selected: _headingLevel == 2,
              onSelected: (v) => setState(() => _headingLevel = v ? 2 : 0),
            ),
            const SizedBox(width: 6),
            FilterChip(
              label: const Text(
                'B',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              selected: _isBold,
              onSelected: (v) => setState(() => _isBold = v),
            ),
            const SizedBox(width: 6),
            FilterChip(
              label: const Text(
                'I',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
              selected: _isItalic,
              onSelected: (v) => setState(() => _isItalic = v),
            ),
            const SizedBox(width: 6),
            FilterChip(
              label: const Text(
                'U',
                style: TextStyle(decoration: TextDecoration.underline),
              ),
              selected: _isUnderline,
              onSelected: (v) => setState(() => _isUnderline = v),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Clear formatting',
              icon: const Icon(Icons.format_clear, size: 20),
              onPressed: () {
                setState(() {
                  _isBold = false;
                  _isItalic = false;
                  _isUnderline = false;
                  _headingLevel = 0;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(Color bgColor) {
    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Add media or checkboxes',
              icon: const Icon(Icons.add_box_outlined),
              onPressed: _showAddAttachmentSheet,
            ),
            IconButton(
              tooltip: 'Color & background theme',
              icon: const Icon(Icons.palette_outlined),
              onPressed: _showColorAndBackgroundSheet,
            ),
            IconButton(
              tooltip: 'Text formatting',
              icon: Icon(
                Icons.text_format,
                color: _showFormattingBar
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              onPressed: () =>
                  setState(() => _showFormattingBar = !_showFormattingBar),
            ),
            IconButton(
              tooltip: 'Undo',
              icon: const Icon(Icons.undo, size: 20),
              onPressed: _undoStack.length > 1 ? _undo : null,
            ),
            IconButton(
              tooltip: 'Redo',
              icon: const Icon(Icons.redo, size: 20),
              onPressed: _redoStack.isNotEmpty ? _redo : null,
            ),
            Expanded(
              child: Text(
                KeepDateFormatter.formatEditedTimestamp(_note.updatedAt),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: 'More options',
              icon: const Icon(Icons.more_vert),
              onPressed: _showMoreActionsSheet,
            ),
          ],
        ),
      ),
    );
  }
}
