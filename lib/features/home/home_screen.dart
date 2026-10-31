import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/keep_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/sync/supabase_sync_service.dart';
import '../../domain/models/note_model.dart';
import '../../domain/services/device_services.dart';
import '../../domain/services/keep_providers.dart';
import '../editor/note_editor_screen.dart';
import '../labels/labels_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_migration_screen.dart';
import 'widgets/note_card_widget.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const _uuid = Uuid();
  StreamSubscription<SharedIncomingPayload>? _shareSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Start background geofence listener for active location reminders
      final reminderService = ref.read(keepReminderServiceProvider);
      unawaited(
        reminderService.startGeofenceMonitoring(() {
          return ref.read(allNotesStreamProvider).value ?? const <NoteModel>[];
        }),
      );

      // Listen for "Share to Keep" intents from Android/iOS OS share sheet
      final shareService = ref.read(shareToKeepServiceProvider);
      _shareSub = shareService.incomingShares.listen(_handleIncomingSharedData);
    });
  }

  @override
  void dispose() {
    _shareSub?.cancel();
    super.dispose();
  }

  Future<void> _handleIncomingSharedData(SharedIncomingPayload payload) async {
    final now = DateTime.now();
    final noteId = _uuid.v4();
    final attachments = payload.imagePaths
        .map(
          (path) => NoteAttachment(
            id: _uuid.v4(),
            noteId: noteId,
            type: AttachmentType.image,
            localPath: path,
            createdAt: now,
            updatedAt: now,
          ),
        )
        .toList();

    final sharedNote = NoteModel(
      id: noteId,
      title: payload.title,
      content: payload.text,
      attachments: attachments,
      createdAt: now,
      updatedAt: now,
    );

    await ref.read(keepActionsProvider).saveNote(sharedNote);
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(initialNote: sharedNote),
      ),
    );
  }

  Future<bool> _ensureUnlockedIfProtected(NoteModel note) async {
    if (!note.isLocked) return true;
    final unlocked = ref.read(unlockedNotesSessionProvider);
    if (unlocked.contains(note.id)) return true;

    final bioService = ref.read(keepBiometricServiceProvider);
    final savedPin = await bioService.getSavedPin();

    if (savedPin != null && savedPin.isNotEmpty) {
      if (!mounted) return false;
      final pinCtrl = TextEditingController();
      final verified = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Unlock Protected Note'),
          content: TextField(
            controller: pinCtrl,
            obscureText: true,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Enter Note Lock PIN',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final bioOk = await bioService.authenticateForLockedNote();
                if (ctx.mounted) Navigator.pop(ctx, bioOk);
              },
              child: const Text('Use Biometrics'),
            ),
            FilledButton(
              onPressed: () async {
                final ok = await bioService.verifyPin(pinCtrl.text);
                if (ctx.mounted) Navigator.pop(ctx, ok);
              },
              child: const Text('Unlock'),
            ),
          ],
        ),
      );
      if (verified == true) {
        ref.read(unlockedNotesSessionProvider.notifier).markUnlocked(note.id);
        return true;
      }
      return false;
    }

    final ok = await bioService.authenticateForLockedNote();
    if (ok) {
      ref.read(unlockedNotesSessionProvider.notifier).markUnlocked(note.id);
    }
    return ok;
  }

  Future<void> _onNoteTap(NoteModel note) async {
    final selected = ref.read(selectedNotesProvider);
    if (selected.isNotEmpty) {
      ref.read(selectedNotesProvider.notifier).toggle(note.id);
      return;
    }

    final nav = ref.read(navigationFilterProvider);
    if (nav.section == KeepDrawerSection.trash) {
      _showTrashedNoteDialog(note);
      return;
    }

    final canOpen = await _ensureUnlockedIfProtected(note);
    if (!canOpen || !mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(initialNote: note),
      ),
    );
  }

  void _showTrashedNoteDialog(NoteModel note) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.restore_from_trash_outlined),
              title: const Text('Restore note'),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(keepActionsProvider).restoreFromTrash(note);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_forever_outlined,
                color: Colors.redAccent,
              ),
              title: const Text('Delete forever'),
              onTap: () {
                Navigator.pop(ctx);
                ref.read(keepActionsProvider).deletePermanently(note.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showBatchColorSheet(Set<String> selectedIds) {
    final brightness = Theme.of(context).brightness;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: KeepPalette.colors.map((c) {
              return GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(keepActionsProvider).batchColor(selectedIds, c.id);
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.backgroundFor(brightness),
                    shape: BoxShape.circle,
                    border: Border.all(color: c.borderFor(brightness)),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  void _showBatchLabelSheet(Set<String> selectedIds) {
    final labels =
        ref.read(allLabelsStreamProvider).value ?? const <LabelModel>[];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: labels.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No labels yet.'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LabelsManagementScreen(),
                          ),
                        );
                      },
                      child: const Text('Create Labels'),
                    ),
                  ],
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: labels
                    .map(
                      (l) => ListTile(
                        leading: const Icon(Icons.label_outline),
                        title: Text(l.name),
                        onTap: () {
                          Navigator.pop(ctx);
                          ref
                              .read(keepActionsProvider)
                              .batchAddLabel(selectedIds, l.name);
                        },
                      ),
                    )
                    .toList(),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nav = ref.watch(navigationFilterProvider);
    final isMultiCol = ref.watch(isMultiColumnGridProvider);
    final selectedIds = ref.watch(selectedNotesProvider);
    final filtered = ref.watch(filteredNotesProvider);
    final syncState =
        ref.watch(cloudSyncStateProvider).value ?? const CloudSyncState();

    final crossAxisCount = isMultiCol ? 2 : 1;

    return Scaffold(
      drawer: _buildNavigationDrawer(nav),
      appBar: selectedIds.isNotEmpty
          ? _buildContextualMultiSelectAppBar(selectedIds)
          : _buildFloatingKeepSearchBar(context, nav, isMultiCol, syncState),
      body: CustomScrollView(
        slivers: [
          if (nav.section == KeepDrawerSection.trash &&
              filtered.others.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Notes in Trash are automatically deleted after 7 days.',
                        style: TextStyle(fontSize: 12.5),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          ref.read(keepActionsProvider).emptyTrash(),
                      child: const Text('Empty Trash'),
                    ),
                  ],
                ),
              ),
            ),

          if (filtered.pinned.isEmpty && filtered.others.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyState(nav),
            )
          else ...[
            if (filtered.pinned.isNotEmpty) ...[
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(18, 12, 18, 6),
                  child: Text(
                    'PINNED',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: _buildMasonrySliver(
                  filtered.pinned,
                  crossAxisCount,
                  selectedIds,
                ),
              ),
              if (filtered.others.isNotEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(18, 18, 18, 6),
                    child: Text(
                      'OTHERS',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
            ],
            if (filtered.others.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                sliver: _buildMasonrySliver(
                  filtered.others,
                  crossAxisCount,
                  selectedIds,
                ),
              ),
          ],
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endContained,
      floatingActionButton: FloatingActionButton(
        key: const Key('create_note_fab'),
        tooltip: 'New note',
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const NoteEditorScreen(),
            ),
          );
        },
        child: const Icon(Icons.add, size: 28),
      ),
      bottomNavigationBar: _buildBottomCreationBar(context),
    );
  }

  PreferredSizeWidget _buildFloatingKeepSearchBar(
    BuildContext context,
    NavigationFilterState nav,
    bool isMultiCol,
    CloudSyncState syncState,
  ) {
    final brightness = Theme.of(context).brightness;
    final barColor = brightness == Brightness.dark
        ? AppTheme.keepDarkSearchSurface
        : AppTheme.keepLightSearchSurface;

    return PreferredSize(
      preferredSize: const Size.fromHeight(68),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Material(
            color: barColor,
            borderRadius: BorderRadius.circular(28),
            child: Row(
              children: [
                Builder(
                  builder: (ctx) => IconButton(
                    tooltip: 'Open navigation drawer',
                    icon: const Icon(Icons.menu),
                    onPressed: () => Scaffold.of(ctx).openDrawer(),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    key: const Key('open_search_bar'),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const FacetedSearchScreen(),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        nav.title,
                        style: TextStyle(
                          fontSize: 15.5,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('toggle_grid_mode_button'),
                  tooltip: isMultiCol
                      ? 'Single-column view'
                      : 'Multi-column view',
                  icon: Icon(
                    isMultiCol
                        ? Icons.view_agenda_outlined
                        : Icons.grid_view_outlined,
                  ),
                  onPressed: () =>
                      ref.read(isMultiColumnGridProvider.notifier).toggle(),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: IconButton(
                    key: const Key('open_settings_avatar'),
                    tooltip: 'Account, Cloud Sync & Backup Migration',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsAndMigrationScreen(),
                        ),
                      );
                    },
                    icon: CircleAvatar(
                      radius: 15,
                      backgroundColor: syncState.isAuthenticated
                          ? Colors.green.shade600
                          : Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(
                        syncState.isAuthenticated
                            ? Icons.cloud_done
                            : Icons.person_outline,
                        size: 17,
                        color: syncState.isAuthenticated
                            ? Colors.white
                            : Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildContextualMultiSelectAppBar(Set<String> selectedIds) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () => ref.read(selectedNotesProvider.notifier).clear(),
      ),
      title: Text('${selectedIds.length}'),
      actions: [
        IconButton(
          tooltip: 'Pin / Unpin selected',
          icon: const Icon(Icons.push_pin_outlined),
          onPressed: () =>
              ref.read(keepActionsProvider).batchPin(selectedIds),
        ),
        IconButton(
          tooltip: 'Change color',
          icon: const Icon(Icons.palette_outlined),
          onPressed: () => _showBatchColorSheet(selectedIds),
        ),
        IconButton(
          tooltip: 'Add label',
          icon: const Icon(Icons.label_outline),
          onPressed: () => _showBatchLabelSheet(selectedIds),
        ),
        IconButton(
          tooltip: 'Archive',
          icon: const Icon(Icons.archive_outlined),
          onPressed: () =>
              ref.read(keepActionsProvider).batchArchive(selectedIds),
        ),
        PopupMenuButton<String>(
          onSelected: (val) {
            if (val == 'delete') {
              ref.read(keepActionsProvider).batchTrash(selectedIds);
            } else if (val == 'copy') {
              ref.read(keepActionsProvider).batchDuplicate(selectedIds);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'copy', child: Text('Make a copy')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ],
    );
  }

  Widget _buildMasonrySliver(
    List<NoteModel> notes,
    int crossAxisCount,
    Set<String> selectedIds,
  ) {
    return SliverMasonryGrid.count(
      crossAxisCount: crossAxisCount,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        final isSelected = selectedIds.contains(note.id);

        return DragTarget<int>(
          onWillAcceptWithDetails: (details) => details.data != index,
          onAcceptWithDetails: (details) {
            ref
                .read(keepActionsProvider)
                .reorderNotes(notes, details.data, index);
          },
          builder: (context, candidateData, rejectedData) {
            return Dismissible(
              key: ValueKey('dismiss_${note.id}'),
              direction: note.isTrashed
                  ? DismissDirection.none
                  : DismissDirection.horizontal,
              onDismissed: (_) {
                ref.read(keepActionsProvider).toggleArchive(note);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      note.isArchived ? 'Note unarchived' : 'Note archived',
                    ),
                    action: SnackBarAction(
                      label: 'Undo',
                      onPressed: () =>
                          ref.read(keepActionsProvider).toggleArchive(
                                note.copyWith(isArchived: !note.isArchived),
                              ),
                    ),
                  ),
                );
              },
              child: NoteCardWidget(
                note: note,
                isSelected: isSelected,
                onTap: () => _onNoteTap(note),
                onLongPress: () {
                  ref.read(selectedNotesProvider.notifier).toggle(note.id);
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(NavigationFilterState nav) {
    IconData icon = Icons.lightbulb_outline;
    String message = 'Notes you add appear here';

    switch (nav.section) {
      case KeepDrawerSection.reminders:
        icon = Icons.notifications_none_outlined;
        message = 'Notes with upcoming time or place reminders appear here';
        break;
      case KeepDrawerSection.archive:
        icon = Icons.archive_outlined;
        message = 'Your archived notes appear here';
        break;
      case KeepDrawerSection.trash:
        icon = Icons.delete_outline;
        message = 'No notes in Trash';
        break;
      case KeepDrawerSection.label:
        icon = Icons.label_outline;
        message = 'No notes with this label yet';
        break;
      case KeepDrawerSection.notes:
        break;
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 88,
            color: Colors.grey.withValues(alpha: 0.45),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(
              fontSize: 15,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationDrawer(NavigationFilterState nav) {
    final labels =
        ref.watch(allLabelsStreamProvider).value ?? const <LabelModel>[];

    return NavigationDrawer(
      selectedIndex: _drawerIndexFor(nav),
      onDestinationSelected: (idx) {
        Navigator.pop(context);
        if (idx == 0) {
          ref
              .read(navigationFilterProvider.notifier)
              .selectSection(KeepDrawerSection.notes);
        } else if (idx == 1) {
          ref
              .read(navigationFilterProvider.notifier)
              .selectSection(KeepDrawerSection.reminders);
        }
      },
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 12),
          child: Row(
            children: [
              Icon(Icons.lightbulb, color: AppTheme.keepYellow, size: 28),
              SizedBox(width: 10),
              Text(
                'Keep Notes',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.lightbulb_outline),
          selectedIcon: Icon(Icons.lightbulb),
          label: Text('Notes'),
        ),
        const NavigationDrawerDestination(
          icon: Icon(Icons.notifications_none_outlined),
          selectedIcon: Icon(Icons.notifications),
          label: Text('Reminders'),
        ),
        const Divider(indent: 16, endIndent: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 16, 4),
          child: Row(
            children: [
              const Text(
                'LABELS',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LabelsManagementScreen(),
                    ),
                  );
                },
                child: const Text('Edit'),
              ),
            ],
          ),
        ),
        ...labels.map(
          (lbl) => ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            leading: const Icon(Icons.label_outline),
            title: Text(lbl.name),
            selected: nav.section == KeepDrawerSection.label &&
                nav.selectedLabel == lbl.name,
            onTap: () {
              Navigator.pop(context);
              ref.read(navigationFilterProvider.notifier).selectSection(
                    KeepDrawerSection.label,
                    label: lbl.name,
                  );
            },
          ),
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.add),
          title: const Text('Create new label'),
          onTap: () {
            Navigator.pop(context);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const LabelsManagementScreen(),
              ),
            );
          },
        ),
        const Divider(indent: 16, endIndent: 16),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.archive_outlined),
          title: const Text('Archive'),
          selected: nav.section == KeepDrawerSection.archive,
          onTap: () {
            Navigator.pop(context);
            ref
                .read(navigationFilterProvider.notifier)
                .selectSection(KeepDrawerSection.archive);
          },
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.delete_outline),
          title: const Text('Trash'),
          selected: nav.section == KeepDrawerSection.trash,
          onTap: () {
            Navigator.pop(context);
            ref
                .read(navigationFilterProvider.notifier)
                .selectSection(KeepDrawerSection.trash);
          },
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          leading: const Icon(Icons.settings_outlined),
          title: const Text('Settings, Sync & Migration'),
          onTap: () {
            Navigator.pop(context);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const SettingsAndMigrationScreen(),
              ),
            );
          },
        ),
      ],
    );
  }

  int? _drawerIndexFor(NavigationFilterState nav) {
    if (nav.section == KeepDrawerSection.notes) return 0;
    if (nav.section == KeepDrawerSection.reminders) return 1;
    return null;
  }

  Widget _buildBottomCreationBar(BuildContext context) {
    return BottomAppBar(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            key: const Key('quick_new_checklist_button'),
            tooltip: 'New checklist',
            icon: const Icon(Icons.check_box_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const NoteEditorScreen(startAsChecklist: true),
                ),
              );
            },
          ),
          IconButton(
            key: const Key('quick_new_drawing_button'),
            tooltip: 'New drawing note',
            icon: const Icon(Icons.brush_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const NoteEditorScreen(startWithDrawing: true),
                ),
              );
            },
          ),
          IconButton(
            key: const Key('quick_new_voice_button'),
            tooltip: 'New voice note',
            icon: const Icon(Icons.mic_none_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const NoteEditorScreen(startWithVoice: true),
                ),
              );
            },
          ),
          IconButton(
            key: const Key('quick_new_image_button'),
            tooltip: 'New photo note',
            icon: const Icon(Icons.image_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const NoteEditorScreen(startWithImagePicker: true),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
