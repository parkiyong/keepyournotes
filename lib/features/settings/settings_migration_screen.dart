import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/sync/supabase_sync_service.dart';
import '../../domain/services/keep_providers.dart';

class SettingsAndMigrationScreen extends ConsumerStatefulWidget {
  const SettingsAndMigrationScreen({super.key});

  @override
  ConsumerState<SettingsAndMigrationScreen> createState() =>
      _SettingsAndMigrationScreenState();
}

class _SettingsAndMigrationScreenState
    extends ConsumerState<SettingsAndMigrationScreen> {
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _anonKeyController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();

  bool _isExporting = false;
  bool _isImporting = false;
  String? _statusBanner;

  @override
  void initState() {
    super.initState();
    final syncState = ref.read(supabaseSyncServiceProvider).currentState;
    _urlController.text = syncState.supabaseUrl;
    _loadPin();
  }

  Future<void> _loadPin() async {
    final pin = await ref.read(keepBiometricServiceProvider).getSavedPin();
    if (mounted && pin != null) {
      setState(() => _pinController.text = pin);
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    _anonKeyController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _saveSupabaseConfig() async {
    try {
      await ref.read(supabaseSyncServiceProvider).configureClient(
            url: _urlController.text,
            anonKey: _anonKeyController.text,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Supabase configuration saved.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Configuration error: $e')),
        );
      }
    }
  }

  Future<void> _exportAllData() async {
    setState(() {
      _isExporting = true;
      _statusBanner = null;
    });
    try {
      final result =
          await ref.read(keepMigrationServiceProvider).exportFullBackupZip();
      if (!mounted) return;
      setState(() {
        _statusBanner =
            'Exported ${result.notesProcessed} notes, ${result.labelsProcessed} labels, and ${result.attachmentsProcessed} media files to ${result.archivePath}';
      });
      if (result.archivePath != null) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(result.archivePath!)],
            subject: 'Keep Your Notes Full Backup Bundle',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusBanner = 'Export failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _importDataFromFile() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip', 'json'],
    );
    if (picked.isEmpty || picked.first.path == null) return;

    setState(() {
      _isImporting = true;
      _statusBanner = null;
    });

    try {
      final file = File(picked.first.path!);
      final result =
          await ref.read(keepMigrationServiceProvider).importBackupFile(file);
      if (!mounted) return;
      setState(() {
        _statusBanner =
            'Imported ${result.notesProcessed} notes, ${result.labelsProcessed} labels, and ${result.attachmentsProcessed} media attachments!';
      });
    } catch (e) {
      if (mounted) {
        setState(() => _statusBanner = 'Import error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final syncAsync = ref.watch(cloudSyncStateProvider);
    final syncState = syncAsync.value ?? const CloudSyncState();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings, Sync & Migration'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_statusBanner != null) ...[
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_statusBanner!)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 1. APPEARANCE
          const Text(
            'Display & Appearance',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.brightness_auto),
                label: Text('System'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('Dark'),
              ),
            ],
            selected: {themeMode},
            onSelectionChanged: (selection) {
              ref
                  .read(themeModeProvider.notifier)
                  .setThemeMode(selection.first);
            },
          ),
          const Divider(height: 32),

          // 2. DATA MIGRATION (FULL EXPORT & IMPORT)
          const Text(
            'Data Migration & Portable Backup',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Export all notes, checklists, labels, images, drawings, and voice memos into a portable ZIP archive (JSON + Markdown + Media), or restore from a Backup ZIP / Google Keep Takeout archive.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: const Key('export_backup_button'),
                  onPressed: _isExporting ? null : _exportAllData,
                  icon: _isExporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.archive_outlined),
                  label: const Text('Export All Data (ZIP)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('import_backup_button'),
                  onPressed: _isImporting ? null : _importDataFromFile,
                  icon: _isImporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.unarchive_outlined),
                  label: const Text('Import ZIP / Takeout'),
                ),
              ),
            ],
          ),
          const Divider(height: 32),

          // 3. BIOMETRIC / FALLBACK PIN LOCK
          const Text(
            'Note Privacy & Biometric Lock',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Protected notes use Face ID / Fingerprint when available, or this fallback PIN.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Fallback Lock PIN',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed: () async {
                  await ref
                      .read(keepBiometricServiceProvider)
                      .setFallbackPin(_pinController.text);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Note lock PIN updated.')),
                  );
                },
                child: const Text('Save PIN'),
              ),
            ],
          ),
          const Divider(height: 32),

          // 4. SUPABASE CLOUD SYNC (GUEST-FIRST + OPTIONAL ACCOUNT)
          Row(
            children: [
              const Text(
                'Supabase Cloud Sync',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Chip(
                avatar: Icon(
                  syncState.isAuthenticated
                      ? Icons.cloud_done_outlined
                      : Icons.offline_pin_outlined,
                  size: 16,
                ),
                label: Text(
                  syncState.isAuthenticated
                      ? 'Synced (${syncState.userEmail ?? "Signed In"})'
                      : 'Guest (Local Offline-First)',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              labelText: 'Supabase Project URL',
              hintText: 'https://your-project.supabase.co',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _anonKeyController,
            decoration: const InputDecoration(
              labelText: 'Supabase Anon Key',
              hintText: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _saveSupabaseConfig,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save Supabase Endpoint'),
            ),
          ),
          const SizedBox(height: 16),
          if (syncState.isAuthenticated) ...[
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: syncState.isSyncing
                        ? null
                        : () => ref.read(supabaseSyncServiceProvider).syncNow(),
                    icon: const Icon(Icons.sync),
                    label: Text(
                      syncState.isSyncing ? 'Syncing...' : 'Sync Now',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(supabaseSyncServiceProvider).signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign Out (Stay Local)'),
                ),
              ],
            ),
          ] else ...[
            const Text(
              'Sign In or Create Account to Sync Across Devices',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      try {
                        await ref
                            .read(supabaseSyncServiceProvider)
                            .signInWithEmail(
                              _emailController.text,
                              _passwordController.text,
                            );
                      } catch (_) {}
                    },
                    child: const Text('Sign In & Sync'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      try {
                        await ref
                            .read(supabaseSyncServiceProvider)
                            .signUpWithEmail(
                              _emailController.text,
                              _passwordController.text,
                            );
                      } catch (_) {}
                    },
                    child: const Text('Create Account'),
                  ),
                ),
              ],
            ),
          ],
          if (syncState.errorMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              syncState.errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
