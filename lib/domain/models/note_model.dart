import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/utils/url_utils.dart';

enum AttachmentType { image, drawing, audio }

enum SyncStatus { synced, pendingUpsert, pendingDelete }

class ChecklistItem {
  final String id;
  final String text;
  final bool isChecked;
  final int indentLevel; // 0 = root item, 1 = indented subtask
  final int sortOrder;

  const ChecklistItem({
    required this.id,
    required this.text,
    this.isChecked = false,
    this.indentLevel = 0,
    this.sortOrder = 0,
  });

  ChecklistItem copyWith({
    String? id,
    String? text,
    bool? isChecked,
    int? indentLevel,
    int? sortOrder,
  }) {
    return ChecklistItem(
      id: id ?? this.id,
      text: text ?? this.text,
      isChecked: isChecked ?? this.isChecked,
      indentLevel: indentLevel ?? this.indentLevel,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'isChecked': isChecked,
        'indentLevel': indentLevel,
        'sortOrder': sortOrder,
      };

  factory ChecklistItem.fromJson(Map<String, dynamic> json) => ChecklistItem(
        id: json['id'] as String? ?? '',
        text: json['text'] as String? ?? '',
        isChecked: json['isChecked'] as bool? ?? false,
        indentLevel: (json['indentLevel'] as num?)?.toInt() ?? 0,
        sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      );
}

class RichTextSpanRule {
  final int start;
  final int end;
  final bool isBold;
  final bool isItalic;
  final bool isUnderline;
  final int headingLevel; // 0 = normal, 1 = H1, 2 = H2

  const RichTextSpanRule({
    required this.start,
    required this.end,
    this.isBold = false,
    this.isItalic = false,
    this.isUnderline = false,
    this.headingLevel = 0,
  });

  Map<String, dynamic> toJson() => {
        'start': start,
        'end': end,
        'isBold': isBold,
        'isItalic': isItalic,
        'isUnderline': isUnderline,
        'headingLevel': headingLevel,
      };

  factory RichTextSpanRule.fromJson(Map<String, dynamic> json) =>
      RichTextSpanRule(
        start: (json['start'] as num?)?.toInt() ?? 0,
        end: (json['end'] as num?)?.toInt() ?? 0,
        isBold: json['isBold'] as bool? ?? false,
        isItalic: json['isItalic'] as bool? ?? false,
        isUnderline: json['isUnderline'] as bool? ?? false,
        headingLevel: (json['headingLevel'] as num?)?.toInt() ?? 0,
      );
}

class DrawingStroke {
  final List<Offset> points;
  final int colorValue;
  final double strokeWidth;
  final String tool; // 'pen', 'marker', 'highlighter', 'eraser'

  const DrawingStroke({
    required this.points,
    required this.colorValue,
    required this.strokeWidth,
    this.tool = 'pen',
  });

  Map<String, dynamic> toJson() => {
        'points': points.map((p) => {'dx': p.dx, 'dy': p.dy}).toList(),
        'colorValue': colorValue,
        'strokeWidth': strokeWidth,
        'tool': tool,
      };

  factory DrawingStroke.fromJson(Map<String, dynamic> json) {
    final rawPoints = (json['points'] as List<dynamic>? ?? []);
    return DrawingStroke(
      points: rawPoints.map((e) {
        final m = e as Map<String, dynamic>;
        return Offset(
          (m['dx'] as num?)?.toDouble() ?? 0,
          (m['dy'] as num?)?.toDouble() ?? 0,
        );
      }).toList(),
      colorValue: (json['colorValue'] as num?)?.toInt() ?? 0xFF000000,
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 4.0,
      tool: json['tool'] as String? ?? 'pen',
    );
  }
}

class NoteAttachment {
  final String id;
  final String noteId;
  final AttachmentType type;
  final String localPath;
  final String? remoteStoragePath;
  final String ocrText;
  final String transcript;
  final int durationMs;
  final List<DrawingStroke> strokes;
  final String drawingGrid; // 'none', 'dots', 'lines', 'grid'
  final DateTime createdAt;
  final DateTime updatedAt;

  const NoteAttachment({
    required this.id,
    required this.noteId,
    required this.type,
    required this.localPath,
    this.remoteStoragePath,
    this.ocrText = '',
    this.transcript = '',
    this.durationMs = 0,
    this.strokes = const [],
    this.drawingGrid = 'dots',
    required this.createdAt,
    required this.updatedAt,
  });

  NoteAttachment copyWith({
    String? id,
    String? noteId,
    AttachmentType? type,
    String? localPath,
    String? remoteStoragePath,
    String? ocrText,
    String? transcript,
    int? durationMs,
    List<DrawingStroke>? strokes,
    String? drawingGrid,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NoteAttachment(
      id: id ?? this.id,
      noteId: noteId ?? this.noteId,
      type: type ?? this.type,
      localPath: localPath ?? this.localPath,
      remoteStoragePath: remoteStoragePath ?? this.remoteStoragePath,
      ocrText: ocrText ?? this.ocrText,
      transcript: transcript ?? this.transcript,
      durationMs: durationMs ?? this.durationMs,
      strokes: strokes ?? this.strokes,
      drawingGrid: drawingGrid ?? this.drawingGrid,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMetadataJson() => {
        'ocrText': ocrText,
        'transcript': transcript,
        'durationMs': durationMs,
        'strokes': strokes.map((s) => s.toJson()).toList(),
        'drawingGrid': drawingGrid,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        'noteId': noteId,
        'type': type.name,
        'localPath': localPath,
        'remoteStoragePath': remoteStoragePath,
        'metadata': toMetadataJson(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory NoteAttachment.fromJson(Map<String, dynamic> json) {
    final meta = (json['metadata'] as Map<String, dynamic>?) ?? {};
    final rawStrokes = meta['strokes'] as List<dynamic>? ?? [];
    final typeStr = json['type'] as String? ?? 'image';
    final parsedType = AttachmentType.values.firstWhere(
      (e) => e.name == typeStr,
      orElse: () => AttachmentType.image,
    );
    return NoteAttachment(
      id: json['id'] as String? ?? '',
      noteId: (json['noteId'] ?? json['note_id']) as String? ?? '',
      type: parsedType,
      localPath: (json['localPath'] ?? json['local_path']) as String? ?? '',
      remoteStoragePath:
          (json['remoteStoragePath'] ?? json['remote_storage_path']) as String?,
      ocrText: meta['ocrText'] as String? ?? '',
      transcript: meta['transcript'] as String? ?? '',
      durationMs: (meta['durationMs'] as num?)?.toInt() ?? 0,
      strokes: rawStrokes
          .map((e) => DrawingStroke.fromJson(e as Map<String, dynamic>))
          .toList(),
      drawingGrid: meta['drawingGrid'] as String? ?? 'dots',
      createdAt: DateTime.tryParse(
              (json['createdAt'] ?? json['created_at']) as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(
              (json['updatedAt'] ?? json['updated_at']) as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class ReminderLocation {
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  const ReminderLocation({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 200.0,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters,
      };

  factory ReminderLocation.fromJson(Map<String, dynamic> json) =>
      ReminderLocation(
        name: json['name'] as String? ?? '',
        address: json['address'] as String? ?? '',
        latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
        longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
        radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 200.0,
      );
}

class LabelModel {
  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;

  const LabelModel({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = SyncStatus.pendingUpsert,
  });

  LabelModel copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
  }) {
    return LabelModel(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory LabelModel.fromJson(Map<String, dynamic> json) => LabelModel(
        id: json['id'] as String,
        name: json['name'] as String,
        createdAt: DateTime.tryParse(
                (json['createdAt'] ?? json['created_at']) as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(
                (json['updatedAt'] ?? json['updated_at']) as String? ?? '') ??
            DateTime.now(),
        syncStatus: SyncStatus.synced,
      );
}

class NoteModel {
  final String id;
  final String? userId;
  final String title;
  final String content;
  final List<RichTextSpanRule> richSpans;
  final bool isChecklist;
  final List<ChecklistItem> checklistItems;
  final String colorId;
  final String backgroundTheme;
  final bool isPinned;
  final bool isArchived;
  final bool isTrashed;
  final DateTime? trashedAt;
  final bool isLocked;
  final double sortOrder;
  final DateTime? reminderAt;
  final String reminderRecurrence; // 'none', 'daily', 'weekly', 'monthly'
  final ReminderLocation? reminderLocation;
  final List<UrlMetadata> linkPreviews;
  final List<String> labels; // Label names
  final List<NoteAttachment> attachments;
  final DateTime createdAt;
  final DateTime updatedAt;
  final SyncStatus syncStatus;

  const NoteModel({
    required this.id,
    this.userId,
    this.title = '',
    this.content = '',
    this.richSpans = const [],
    this.isChecklist = false,
    this.checklistItems = const [],
    this.colorId = 'default',
    this.backgroundTheme = 'none',
    this.isPinned = false,
    this.isArchived = false,
    this.isTrashed = false,
    this.trashedAt,
    this.isLocked = false,
    this.sortOrder = 0.0,
    this.reminderAt,
    this.reminderRecurrence = 'none',
    this.reminderLocation,
    this.linkPreviews = const [],
    this.labels = const [],
    this.attachments = const [],
    required this.createdAt,
    required this.updatedAt,
    this.syncStatus = SyncStatus.pendingUpsert,
  });

  bool get isEmpty {
    final hasTitle = title.trim().isNotEmpty;
    final hasContent = content.trim().isNotEmpty;
    final hasList = checklistItems.any((i) => i.text.trim().isNotEmpty);
    final hasMedia = attachments.isNotEmpty;
    return !hasTitle && !hasContent && !hasList && !hasMedia;
  }

  bool get hasReminder => reminderAt != null || reminderLocation != null;

  List<NoteAttachment> get visualAttachments => attachments
      .where(
          (a) => a.type == AttachmentType.image || a.type == AttachmentType.drawing)
      .toList();

  List<NoteAttachment> get audioAttachments =>
      attachments.where((a) => a.type == AttachmentType.audio).toList();

  String get searchableText {
    final buffer = StringBuffer();
    buffer.writeln(title);
    buffer.writeln(content);
    for (final item in checklistItems) {
      buffer.writeln(item.text);
    }
    for (final label in labels) {
      buffer.writeln(label);
    }
    for (final att in attachments) {
      if (att.ocrText.isNotEmpty) buffer.writeln(att.ocrText);
      if (att.transcript.isNotEmpty) buffer.writeln(att.transcript);
    }
    if (reminderLocation != null) {
      buffer.writeln(reminderLocation!.name);
      buffer.writeln(reminderLocation!.address);
    }
    return buffer.toString();
  }

  NoteModel copyWith({
    String? id,
    String? userId,
    String? title,
    String? content,
    List<RichTextSpanRule>? richSpans,
    bool? isChecklist,
    List<ChecklistItem>? checklistItems,
    String? colorId,
    String? backgroundTheme,
    bool? isPinned,
    bool? isArchived,
    bool? isTrashed,
    DateTime? trashedAt,
    bool clearTrashedAt = false,
    bool? isLocked,
    double? sortOrder,
    DateTime? reminderAt,
    bool clearReminderAt = false,
    String? reminderRecurrence,
    ReminderLocation? reminderLocation,
    bool clearReminderLocation = false,
    List<UrlMetadata>? linkPreviews,
    List<String>? labels,
    List<NoteAttachment>? attachments,
    DateTime? createdAt,
    DateTime? updatedAt,
    SyncStatus? syncStatus,
  }) {
    return NoteModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      content: content ?? this.content,
      richSpans: richSpans ?? this.richSpans,
      isChecklist: isChecklist ?? this.isChecklist,
      checklistItems: checklistItems ?? this.checklistItems,
      colorId: colorId ?? this.colorId,
      backgroundTheme: backgroundTheme ?? this.backgroundTheme,
      isPinned: isPinned ?? this.isPinned,
      isArchived: isArchived ?? this.isArchived,
      isTrashed: isTrashed ?? this.isTrashed,
      trashedAt: clearTrashedAt ? null : (trashedAt ?? this.trashedAt),
      isLocked: isLocked ?? this.isLocked,
      sortOrder: sortOrder ?? this.sortOrder,
      reminderAt: clearReminderAt ? null : (reminderAt ?? this.reminderAt),
      reminderRecurrence: reminderRecurrence ?? this.reminderRecurrence,
      reminderLocation: clearReminderLocation
          ? null
          : (reminderLocation ?? this.reminderLocation),
      linkPreviews: linkPreviews ?? this.linkPreviews,
      labels: labels ?? this.labels,
      attachments: attachments ?? this.attachments,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncStatus: syncStatus ?? this.syncStatus,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'title': title,
        'content': content,
        'rich_spans': richSpans.map((s) => s.toJson()).toList(),
        'is_checklist': isChecklist,
        'checklist_items': checklistItems.map((c) => c.toJson()).toList(),
        'color_id': colorId,
        'background_theme': backgroundTheme,
        'is_pinned': isPinned,
        'is_archived': isArchived,
        'is_trashed': isTrashed,
        'trashed_at': trashedAt?.toIso8601String(),
        'is_locked': isLocked,
        'sort_order': sortOrder,
        'reminder_at': reminderAt?.toIso8601String(),
        'reminder_recurrence': reminderRecurrence,
        'reminder_location': reminderLocation?.toJson(),
        'link_previews': linkPreviews.map((l) => l.toJson()).toList(),
        'labels': labels,
        'attachments': attachments.map((a) => a.toJson()).toList(),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  Map<String, dynamic> toSupabaseRow(String authenticatedUserId) => {
        'id': id,
        'user_id': authenticatedUserId,
        'title': title,
        'content': content,
        'rich_spans': richSpans.map((s) => s.toJson()).toList(),
        'is_checklist': isChecklist,
        'checklist_items': checklistItems.map((c) => c.toJson()).toList(),
        'color_id': colorId,
        'background_theme': backgroundTheme,
        'is_pinned': isPinned,
        'is_archived': isArchived,
        'is_trashed': isTrashed,
        'trashed_at': trashedAt?.toIso8601String(),
        'is_locked': isLocked,
        'sort_order': sortOrder,
        'reminder_at': reminderAt?.toIso8601String(),
        'reminder_recurrence': reminderRecurrence,
        'reminder_location': reminderLocation?.toJson(),
        'link_previews': linkPreviews.map((l) => l.toJson()).toList(),
        'labels': labels,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory NoteModel.fromJson(Map<String, dynamic> json) {
    List<dynamic> decodeList(dynamic val) {
      if (val == null) return [];
      if (val is List) return val;
      if (val is String && val.isNotEmpty) {
        try {
          return jsonDecode(val) as List<dynamic>;
        } catch (_) {
          return [];
        }
      }
      return [];
    }

    Map<String, dynamic>? decodeMap(dynamic val) {
      if (val == null) return null;
      if (val is Map<String, dynamic>) return val;
      if (val is String && val.isNotEmpty) {
        try {
          return jsonDecode(val) as Map<String, dynamic>;
        } catch (_) {
          return null;
        }
      }
      return null;
    }

    final rawChecklist = decodeList(json['checklist_items']);
    final rawSpans = decodeList(json['rich_spans']);
    final rawPreviews = decodeList(json['link_previews']);
    final rawLabels = decodeList(json['labels']);
    final rawAttachments = decodeList(json['attachments']);
    final rawLocation = decodeMap(json['reminder_location']);

    return NoteModel(
      id: json['id'] as String,
      userId: json['user_id'] as String?,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      richSpans: rawSpans
          .map((e) => RichTextSpanRule.fromJson(e as Map<String, dynamic>))
          .toList(),
      isChecklist: json['is_checklist'] == true || json['is_checklist'] == 1,
      checklistItems: rawChecklist
          .map((e) => ChecklistItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      colorId: json['color_id'] as String? ?? 'default',
      backgroundTheme: json['background_theme'] as String? ?? 'none',
      isPinned: json['is_pinned'] == true || json['is_pinned'] == 1,
      isArchived: json['is_archived'] == true || json['is_archived'] == 1,
      isTrashed: json['is_trashed'] == true || json['is_trashed'] == 1,
      trashedAt: json['trashed_at'] != null
          ? DateTime.tryParse(json['trashed_at'] as String)
          : null,
      isLocked: json['is_locked'] == true || json['is_locked'] == 1,
      sortOrder: (json['sort_order'] as num?)?.toDouble() ?? 0.0,
      reminderAt: json['reminder_at'] != null
          ? DateTime.tryParse(json['reminder_at'] as String)
          : null,
      reminderRecurrence: json['reminder_recurrence'] as String? ?? 'none',
      reminderLocation:
          rawLocation != null ? ReminderLocation.fromJson(rawLocation) : null,
      linkPreviews: rawPreviews
          .map((e) => UrlMetadata.fromJson(e as Map<String, dynamic>))
          .toList(),
      labels: rawLabels.map((e) => e.toString()).toList(),
      attachments: rawAttachments
          .map((e) => NoteAttachment.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
      syncStatus: SyncStatus.synced,
    );
  }

  /// Exports the note to Markdown with YAML frontmatter for portable migration.
  String toMarkdown() {
    final sb = StringBuffer();
    sb.writeln('---');
    sb.writeln('id: $id');
    sb.writeln('title: "${title.replaceAll('"', '\\"')}"');
    sb.writeln('color: $colorId');
    sb.writeln('theme: $backgroundTheme');
    sb.writeln('pinned: $isPinned');
    sb.writeln('archived: $isArchived');
    sb.writeln('trashed: $isTrashed');
    if (labels.isNotEmpty) {
      sb.writeln('labels: [${labels.map((l) => '"$l"').join(', ')}]');
    }
    sb.writeln('created_at: ${createdAt.toIso8601String()}');
    sb.writeln('updated_at: ${updatedAt.toIso8601String()}');
    sb.writeln('---');
    sb.writeln();
    if (title.isNotEmpty) {
      sb.writeln('# $title');
      sb.writeln();
    }
    if (isChecklist) {
      for (final item in checklistItems) {
        final indent = item.indentLevel > 0 ? '  ' : '';
        final mark = item.isChecked ? 'x' : ' ';
        sb.writeln('$indent- [$mark] ${item.text}');
      }
    } else if (content.isNotEmpty) {
      sb.writeln(content);
    }
    if (attachments.isNotEmpty) {
      sb.writeln();
      sb.writeln('## Attachments');
      for (final att in attachments) {
        final fileName = att.localPath.split('/').last;
        if (att.type == AttachmentType.audio) {
          sb.writeln('- [Audio ($fileName)](../media/$fileName)');
          if (att.transcript.isNotEmpty) {
            sb.writeln('  > Transcript: ${att.transcript}');
          }
        } else {
          sb.writeln('![${att.type.name}](../media/$fileName)');
          if (att.ocrText.isNotEmpty) {
            sb.writeln('  > OCR: ${att.ocrText}');
          }
        }
      }
    }
    return sb.toString();
  }
}
