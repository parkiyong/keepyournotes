import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/keep_colors.dart';
import '../../../core/utils/url_utils.dart';
import '../../../domain/models/note_model.dart';
import '../../../domain/services/keep_providers.dart';

class NoteCardWidget extends ConsumerWidget {
  final NoteModel note;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const NoteCardWidget({
    super.key,
    required this.note,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brightness = Theme.of(context).brightness;
    final paletteColor = KeepPalette.byId(note.colorId);
    final bgColor = paletteColor.backgroundFor(brightness);
    final borderColor = isSelected
        ? Theme.of(context).colorScheme.primary
        : paletteColor.borderFor(brightness);

    final unlockedIds = ref.watch(unlockedNotesSessionProvider);
    final isLockedHidden = note.isLocked && !unlockedIds.contains(note.id);

    final visuals = note.visualAttachments;
    final uncheckedItems =
        note.checklistItems.where((i) => !i.isChecked).take(6).toList();
    final checkedCount =
        note.checklistItems.where((i) => i.isChecked).length;

    return Hero(
      tag: 'note_hero_${note.id}',
      child: Material(
        color: bgColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: borderColor,
            width: isSelected ? 2.4 : 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: CustomPaint(
            painter: KeepThemeBackgroundPainter(
              themeId: note.backgroundTheme,
              brightness: brightness,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isLockedHidden && visuals.isNotEmpty)
                  _buildVisualCollage(visuals),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: isLockedHidden
                      ? _buildLockedPlaceholder(context)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (note.title.isNotEmpty) ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      note.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15.5,
                                      ),
                                    ),
                                  ),
                                  if (note.isLocked)
                                    const Padding(
                                      padding: EdgeInsets.only(left: 4),
                                      child: Icon(
                                        Icons.lock_open_outlined,
                                        size: 15,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                            ],
                            if (note.isChecklist) ...[
                              ...uncheckedItems.map(
                                (item) => Padding(
                                  padding: EdgeInsets.only(
                                    left: item.indentLevel * 14.0,
                                    bottom: 4,
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.check_box_outline_blank,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          item.text,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 13.5),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (checkedCount > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    '+ $checkedCount checked item${checkedCount == 1 ? '' : 's'}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.color,
                                    ),
                                  ),
                                ),
                            ] else if (note.content.isNotEmpty) ...[
                              Text(
                                note.content,
                                maxLines: 8,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                              ),
                            ],
                            if (_hasMetadataChips) ...[
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  if (note.reminderAt != null)
                                    _SmallBadgeChip(
                                      icon: Icons.alarm,
                                      label: KeepDateFormatter.formatReminderChip(
                                        note.reminderAt!,
                                        note.reminderRecurrence,
                                      ),
                                    ),
                                  if (note.reminderLocation != null)
                                    _SmallBadgeChip(
                                      icon: Icons.place_outlined,
                                      label: note.reminderLocation!.name,
                                    ),
                                  if (note.audioAttachments.isNotEmpty)
                                    _SmallBadgeChip(
                                      icon: Icons.mic_none,
                                      label:
                                          '${note.audioAttachments.length} audio',
                                    ),
                                  ...note.labels.map(
                                    (lbl) => _SmallBadgeChip(
                                      label: lbl,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (note.linkPreviews.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: brightness == Brightness.dark
                                      ? Colors.white.withValues(alpha: 0.06)
                                      : Colors.black.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.link, size: 15),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        note.linkPreviews.first.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _hasMetadataChips =>
      note.reminderAt != null ||
      note.reminderLocation != null ||
      note.audioAttachments.isNotEmpty ||
      note.labels.isNotEmpty;

  Widget _buildLockedPlaceholder(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (note.title.isNotEmpty) ...[
          Text(
            note.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
          ),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            Icon(
              Icons.lock_outline,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Locked note • Tap to authenticate',
                style: TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildVisualCollage(List<NoteAttachment> visuals) {
    final first = visuals.first;
    final file = File(first.localPath);

    return SizedBox(
      height: 135,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (first.localPath.isNotEmpty && file.existsSync())
            Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallbackMediaTile(first),
            )
          else
            _fallbackMediaTile(first),
          if (visuals.length > 1)
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '+${visuals.length - 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fallbackMediaTile(NoteAttachment att) {
    return Container(
      color: Colors.black12,
      alignment: Alignment.center,
      child: Icon(
        att.type == AttachmentType.drawing
            ? Icons.gesture_outlined
            : Icons.image_outlined,
        size: 32,
      ),
    );
  }
}

class _SmallBadgeChip extends StatelessWidget {
  final IconData? icon;
  final String label;

  const _SmallBadgeChip({
    this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: brightness == Brightness.dark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
