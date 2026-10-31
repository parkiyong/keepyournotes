import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/note_model.dart';
import '../../domain/services/keep_providers.dart';

class LabelsManagementScreen extends ConsumerStatefulWidget {
  const LabelsManagementScreen({super.key});

  @override
  ConsumerState<LabelsManagementScreen> createState() =>
      _LabelsManagementScreenState();
}

class _LabelsManagementScreenState
    extends ConsumerState<LabelsManagementScreen> {
  final TextEditingController _newLabelController = TextEditingController();
  final FocusNode _newLabelFocus = FocusNode();

  @override
  void dispose() {
    _newLabelController.dispose();
    _newLabelFocus.dispose();
    super.dispose();
  }

  Future<void> _createNewLabel() async {
    final name = _newLabelController.text.trim();
    if (name.isEmpty) return;
    await ref.read(keepActionsProvider).createLabel(name);
    _newLabelController.clear();
  }

  Future<void> _showRenameDialog(LabelModel label) async {
    final controller = TextEditingController(text: label.name);
    final updated = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter label name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (updated != null && updated.isNotEmpty && updated != label.name) {
      await ref
          .read(keepActionsProvider)
          .renameLabel(label.id, label.name, updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final labelsAsync = ref.watch(allLabelsStreamProvider);
    final labels = labelsAsync.value ?? const <LabelModel>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit labels'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _newLabelFocus.requestFocus(),
                ),
                Expanded(
                  child: TextField(
                    key: const Key('create_label_input'),
                    controller: _newLabelController,
                    focusNode: _newLabelFocus,
                    decoration: const InputDecoration(
                      hintText: 'Create new label',
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _createNewLabel(),
                  ),
                ),
                IconButton(
                  key: const Key('confirm_create_label_button'),
                  icon: const Icon(Icons.check),
                  onPressed: _createNewLabel,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: labels.isEmpty
                ? const Center(
                    child: Text(
                      'No labels yet. Add one above or type #label in any note.',
                    ),
                  )
                : ListView.builder(
                    itemCount: labels.length,
                    itemBuilder: (context, index) {
                      final label = labels[index];
                      return ListTile(
                        leading: const Icon(Icons.label_outline),
                        title: Text(label.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Rename label',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _showRenameDialog(label),
                            ),
                            IconButton(
                              tooltip: 'Delete label',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => ref
                                  .read(keepActionsProvider)
                                  .deleteLabel(label.id, label.name),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
