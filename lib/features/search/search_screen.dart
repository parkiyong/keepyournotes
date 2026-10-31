import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../core/constants/keep_colors.dart';
import '../../domain/models/note_model.dart';
import '../../domain/services/keep_providers.dart';
import '../editor/note_editor_screen.dart';
import '../home/widgets/note_card_widget.dart';

enum SearchTypeFilter {
  lists,
  images,
  drawings,
  audio,
  reminders,
  urls,
}

class FacetedSearchScreen extends ConsumerStatefulWidget {
  const FacetedSearchScreen({super.key});

  @override
  ConsumerState<FacetedSearchScreen> createState() =>
      _FacetedSearchScreenState();
}

class _FacetedSearchScreenState extends ConsumerState<FacetedSearchScreen> {
  final TextEditingController _queryController = TextEditingController();
  String _query = '';
  SearchTypeFilter? _typeFilter;
  String? _labelFilter;
  String? _colorFilter;
  List<NoteModel>? _ftsMatches;

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _updateSearch(String value) async {
    setState(() => _query = value);
    if (value.trim().isEmpty) {
      setState(() => _ftsMatches = null);
      return;
    }
    final results =
        await ref.read(keepDatabaseProvider).searchNotes(value.trim());
    if (!mounted) return;
    setState(() => _ftsMatches = results);
  }

  bool get _hasAnyFilter =>
      _query.trim().isNotEmpty ||
      _typeFilter != null ||
      _labelFilter != null ||
      _colorFilter != null;

  List<NoteModel> _computeFiltered(List<NoteModel> allNotes) {
    final base = _ftsMatches ?? allNotes.where((n) => !n.isTrashed).toList();
    return base.where((note) {
      if (note.isTrashed) return false;
      if (_typeFilter != null) {
        switch (_typeFilter!) {
          case SearchTypeFilter.lists:
            if (!note.isChecklist) return false;
            break;
          case SearchTypeFilter.images:
            if (!note.attachments.any((a) => a.type == AttachmentType.image)) {
              return false;
            }
            break;
          case SearchTypeFilter.drawings:
            if (!note.attachments
                .any((a) => a.type == AttachmentType.drawing)) {
              return false;
            }
            break;
          case SearchTypeFilter.audio:
            if (!note.attachments.any((a) => a.type == AttachmentType.audio)) {
              return false;
            }
            break;
          case SearchTypeFilter.reminders:
            if (!note.hasReminder) return false;
            break;
          case SearchTypeFilter.urls:
            if (note.linkPreviews.isEmpty) return false;
            break;
        }
      }
      if (_labelFilter != null && !note.labels.contains(_labelFilter)) {
        return false;
      }
      if (_colorFilter != null && note.colorId != _colorFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(allNotesStreamProvider);
    final labelsAsync = ref.watch(allLabelsStreamProvider);
    final allNotes = notesAsync.value ?? const <NoteModel>[];
    final allLabels = labelsAsync.value ?? const <LabelModel>[];
    final brightness = Theme.of(context).brightness;

    final filtered = _computeFiltered(allNotes);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          key: const Key('faceted_search_input'),
          controller: _queryController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search your notes',
            border: InputBorder.none,
          ),
          onChanged: _updateSearch,
        ),
        actions: [
          if (_hasAnyFilter)
            IconButton(
              tooltip: 'Clear filters',
              icon: const Icon(Icons.clear),
              onPressed: () {
                _queryController.clear();
                setState(() {
                  _query = '';
                  _typeFilter = null;
                  _labelFilter = null;
                  _colorFilter = null;
                  _ftsMatches = null;
                });
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (_typeFilter != null ||
              _labelFilter != null ||
              _colorFilter != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Wrap(
                spacing: 8,
                children: [
                  if (_typeFilter != null)
                    InputChip(
                      label: Text('Type: ${_typeFilter!.name}'),
                      onDeleted: () => setState(() => _typeFilter = null),
                    ),
                  if (_labelFilter != null)
                    InputChip(
                      label: Text('Label: $_labelFilter'),
                      onDeleted: () => setState(() => _labelFilter = null),
                    ),
                  if (_colorFilter != null)
                    InputChip(
                      label:
                          Text('Color: ${KeepPalette.byId(_colorFilter!).label}'),
                      onDeleted: () => setState(() => _colorFilter = null),
                    ),
                ],
              ),
            ),
          Expanded(
            child: !_hasAnyFilter
                ? _buildFacetsOverview(allLabels, brightness)
                : filtered.isEmpty
                    ? const Center(
                        child: Text('No matching notes found.'),
                      )
                    : MasonryGridView.count(
                        padding: const EdgeInsets.all(12),
                        crossAxisCount: 2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final note = filtered[index];
                          return NoteCardWidget(
                            note: note,
                            isSelected: false,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      NoteEditorScreen(initialNote: note),
                                ),
                              );
                            },
                            onLongPress: () {},
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFacetsOverview(
    List<LabelModel> labels,
    Brightness brightness,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Types',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _TypeFacetCard(
              icon: Icons.check_box_outlined,
              label: 'Lists',
              onTap: () => setState(() => _typeFilter = SearchTypeFilter.lists),
            ),
            _TypeFacetCard(
              icon: Icons.image_outlined,
              label: 'Images',
              onTap: () =>
                  setState(() => _typeFilter = SearchTypeFilter.images),
            ),
            _TypeFacetCard(
              icon: Icons.brush_outlined,
              label: 'Drawings',
              onTap: () =>
                  setState(() => _typeFilter = SearchTypeFilter.drawings),
            ),
            _TypeFacetCard(
              icon: Icons.mic_none_outlined,
              label: 'Audio',
              onTap: () => setState(() => _typeFilter = SearchTypeFilter.audio),
            ),
            _TypeFacetCard(
              icon: Icons.notifications_none_outlined,
              label: 'Reminders',
              onTap: () =>
                  setState(() => _typeFilter = SearchTypeFilter.reminders),
            ),
            _TypeFacetCard(
              icon: Icons.link_outlined,
              label: 'URLs',
              onTap: () => setState(() => _typeFilter = SearchTypeFilter.urls),
            ),
          ],
        ),
        if (labels.isNotEmpty) ...[
          const SizedBox(height: 24),
          const Text(
            'Labels',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: labels.map((l) {
              return ActionChip(
                avatar: const Icon(Icons.label_outline, size: 16),
                label: Text(l.name),
                onPressed: () => setState(() => _labelFilter = l.name),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 24),
        const Text(
          'Colors',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: KeepPalette.colors.map((c) {
            return GestureDetector(
              onTap: () => setState(() => _colorFilter = c.id),
              child: Tooltip(
                message: c.label,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: c.backgroundFor(brightness),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: c.borderFor(brightness),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _TypeFacetCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _TypeFacetCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 104,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
