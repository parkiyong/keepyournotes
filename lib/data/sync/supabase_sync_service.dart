import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/models/note_model.dart';
import '../local/keep_database.dart';

class CloudSyncState {
  final bool isConfigured;
  final bool isAuthenticated;
  final String? userEmail;
  final String? userId;
  final bool isSyncing;
  final DateTime? lastSyncedAt;
  final String? errorMessage;
  final String supabaseUrl;

  const CloudSyncState({
    this.isConfigured = false,
    this.isAuthenticated = false,
    this.userEmail,
    this.userId,
    this.isSyncing = false,
    this.lastSyncedAt,
    this.errorMessage,
    this.supabaseUrl = '',
  });

  CloudSyncState copyWith({
    bool? isConfigured,
    bool? isAuthenticated,
    String? userEmail,
    bool clearUser = false,
    String? userId,
    bool? isSyncing,
    DateTime? lastSyncedAt,
    String? errorMessage,
    bool clearError = false,
    String? supabaseUrl,
  }) {
    return CloudSyncState(
      isConfigured: isConfigured ?? this.isConfigured,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      userEmail: clearUser ? null : (userEmail ?? this.userEmail),
      userId: clearUser ? null : (userId ?? this.userId),
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      supabaseUrl: supabaseUrl ?? this.supabaseUrl,
    );
  }
}

/// Manages Guest-first optional Supabase Authentication, Outbox Queue Push,
/// Last-Write-Wins (LWW) Pull, Storage media upload/download, and Realtime subscriptions.
class SupabaseSyncService {
  static const String _prefUrlKey = 'keep_supabase_url';
  static const String _prefAnonKey = 'keep_supabase_anon_key';
  static const String _storageBucket = 'keep-attachments';

  final KeepDatabase _db;
  SupabaseClient? _client;
  RealtimeChannel? _realtimeChannel;
  StreamSubscription<AuthState>? _authSub;

  final StreamController<CloudSyncState> _stateController =
      StreamController<CloudSyncState>.broadcast();
  CloudSyncState _state = const CloudSyncState();

  CloudSyncState get currentState => _state;
  Stream<CloudSyncState> get stateStream => _stateController.stream;

  SupabaseSyncService(this._db);

  void _emit(CloudSyncState next) {
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    const envUrl = String.fromEnvironment('SUPABASE_URL');
    const envKey = String.fromEnvironment('SUPABASE_ANON_KEY');

    final url = (prefs.getString(_prefUrlKey) ?? envUrl).trim();
    final anonKey = (prefs.getString(_prefAnonKey) ?? envKey).trim();

    if (url.isNotEmpty && anonKey.isNotEmpty) {
      await configureClient(url: url, anonKey: anonKey, saveToPrefs: false);
    } else {
      _emit(_state.copyWith(isConfigured: false, isAuthenticated: false));
    }
  }

  Future<void> configureClient({
    required String url,
    required String anonKey,
    bool saveToPrefs = true,
  }) async {
    final cleanUrl = url.trim();
    final cleanKey = anonKey.trim();

    if (cleanUrl.isEmpty || cleanKey.isEmpty) {
      throw ArgumentError('Supabase URL and Anon Key cannot be empty.');
    }

    if (saveToPrefs) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefUrlKey, cleanUrl);
      await prefs.setString(_prefAnonKey, cleanKey);
    }

    await _authSub?.cancel();
    await _realtimeChannel?.unsubscribe();

    _client = SupabaseClient(cleanUrl, cleanKey);
    final user = _client!.auth.currentUser;

    _emit(
      _state.copyWith(
        isConfigured: true,
        supabaseUrl: cleanUrl,
        isAuthenticated: user != null,
        userEmail: user?.email,
        userId: user?.id,
        clearError: true,
      ),
    );

    _authSub = _client!.auth.onAuthStateChange.listen((data) {
      final sessionUser = data.session?.user;
      _emit(
        _state.copyWith(
          isAuthenticated: sessionUser != null,
          userEmail: sessionUser?.email,
          userId: sessionUser?.id,
          clearUser: sessionUser == null,
        ),
      );
      if (sessionUser != null) {
        _subscribeRealtime();
        unawaited(syncNow());
      } else {
        _realtimeChannel?.unsubscribe();
      }
    });

    if (user != null) {
      _subscribeRealtime();
      unawaited(syncNow());
    }
  }

  Future<void> signUpWithEmail(String email, String password) async {
    final client = _requireClient();
    _emit(_state.copyWith(isSyncing: true, clearError: true));
    try {
      final res = await client.auth.signUp(
        email: email.trim(),
        password: password,
      );
      final user = res.user;
      _emit(
        _state.copyWith(
          isSyncing: false,
          isAuthenticated: user != null,
          userEmail: user?.email,
          userId: user?.id,
        ),
      );
      if (user != null) {
        await syncNow();
      }
    } catch (e) {
      _emit(_state.copyWith(isSyncing: false, errorMessage: e.toString()));
      rethrow;
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    final client = _requireClient();
    _emit(_state.copyWith(isSyncing: true, clearError: true));
    try {
      final res = await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final user = res.user;
      _emit(
        _state.copyWith(
          isSyncing: false,
          isAuthenticated: user != null,
          userEmail: user?.email,
          userId: user?.id,
        ),
      );
      if (user != null) {
        await syncNow();
      }
    } catch (e) {
      _emit(_state.copyWith(isSyncing: false, errorMessage: e.toString()));
      rethrow;
    }
  }

  Future<void> signOut() async {
    final client = _client;
    if (client != null) {
      await client.auth.signOut();
    }
    await _realtimeChannel?.unsubscribe();
    _emit(
      _state.copyWith(
        isAuthenticated: false,
        clearUser: true,
        clearError: true,
      ),
    );
  }

  SupabaseClient _requireClient() {
    if (_client == null) {
      throw StateError(
        'Supabase is not configured yet. Please add your Supabase URL and Anon Key in Cloud Sync settings.',
      );
    }
    return _client!;
  }

  /// Performs a full bidirectional Offline-First Sync:
  /// 1. Push pending deletions (notes & labels)
  /// 2. Push pending local labels
  /// 3. Upload local attachments to Supabase Storage & push pending local notes
  /// 4. Pull remote labels & notes and resolve via Last-Write-Wins (`updated_at`)
  Future<void> syncNow() async {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;
    if (_state.isSyncing) return;

    _emit(_state.copyWith(isSyncing: true, clearError: true));

    try {
      // 1. Push pending deletions
      final deletions = await _db.getPendingDeletions();
      for (final del in deletions) {
        final id = del['id']!;
        final type = del['entity_type']!;
        if (type == 'note') {
          await client.from('notes').delete().eq('id', id).eq('user_id', user.id);
        } else if (type == 'label') {
          await client.from('labels').delete().eq('id', id).eq('user_id', user.id);
        }
        await _db.clearPendingDeletion(id);
      }

      // 2. Push pending labels
      final pendingLabels = await _db.getPendingLabels();
      for (final label in pendingLabels) {
        await client.from('labels').upsert({
          'id': label.id,
          'user_id': user.id,
          'name': label.name,
          'created_at': label.createdAt.toIso8601String(),
          'updated_at': label.updatedAt.toIso8601String(),
        });
        await _db.markLabelSynced(label.id);
      }

      // 3. Push pending notes & upload attachments
      final pendingNotes = await _db.getPendingNotes();
      for (final note in pendingNotes) {
        final syncedAttachments = <NoteAttachment>[];
        for (final att in note.attachments) {
          var updatedAtt = att;
          if (att.remoteStoragePath == null && att.localPath.isNotEmpty) {
            final file = File(att.localPath);
            if (await file.exists()) {
              final ext = p.extension(att.localPath);
              final storagePath = '${user.id}/${note.id}/${att.id}$ext';
              await client.storage.from(_storageBucket).upload(
                    storagePath,
                    file,
                    fileOptions: const FileOptions(upsert: true),
                  );
              updatedAtt = att.copyWith(remoteStoragePath: storagePath);
            }
          }
          syncedAttachments.add(updatedAtt);
        }

        final noteToPush = note.copyWith(
          userId: user.id,
          attachments: syncedAttachments,
        );

        await client.from('notes').upsert(noteToPush.toSupabaseRow(user.id));

        for (final att in syncedAttachments) {
          await client.from('note_attachments').upsert({
            'id': att.id,
            'note_id': note.id,
            'user_id': user.id,
            'type': att.type.name,
            'remote_storage_path': att.remoteStoragePath,
            'metadata': att.toMetadataJson(),
            'created_at': att.createdAt.toIso8601String(),
            'updated_at': att.updatedAt.toIso8601String(),
          });
        }

        await _db.upsertNote(
          noteToPush.copyWith(syncStatus: SyncStatus.synced),
          fromRemoteSync: true,
        );
      }

      // 4. Pull remote labels (Last-Write-Wins)
      final remoteLabels = await client
          .from('labels')
          .select()
          .eq('user_id', user.id);
      for (final row in remoteLabels) {
        final remoteLabel = LabelModel.fromJson(row);
        await _db.upsertLabel(remoteLabel, fromRemoteSync: true);
      }

      // 5. Pull remote notes & attachments (Last-Write-Wins on updated_at)
      final remoteNotes = await client
          .from('notes')
          .select()
          .eq('user_id', user.id);
      final remoteAttachments = await client
          .from('note_attachments')
          .select()
          .eq('user_id', user.id);

      final attachmentsByNoteId = <String, List<Map<String, dynamic>>>{};
      for (final rawAtt in remoteAttachments) {
        final noteId = rawAtt['note_id'] as String? ?? '';
        attachmentsByNoteId.putIfAbsent(noteId, () => []).add(rawAtt);
      }

      final appDir = await getApplicationDocumentsDirectory();
      final mediaDir = Directory(p.join(appDir.path, 'keep_media'));
      if (!await mediaDir.exists()) {
        await mediaDir.create(recursive: true);
      }

      for (final row in remoteNotes) {
        final noteId = row['id'] as String;
        final localNote = await _db.getNoteById(noteId);
        final remoteUpdatedAt =
            DateTime.tryParse(row['updated_at'] as String? ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0);

        if (localNote == null ||
            remoteUpdatedAt.isAfter(localNote.updatedAt)) {
          final noteAtts = <NoteAttachment>[];
          final rawList = attachmentsByNoteId[noteId] ?? [];
          for (final rawAtt in rawList) {
            var att = NoteAttachment.fromJson(rawAtt);
            if ((att.localPath.isEmpty || !await File(att.localPath).exists()) &&
                att.remoteStoragePath != null) {
              try {
                final bytes = await client.storage
                    .from(_storageBucket)
                    .download(att.remoteStoragePath!);
                final fileName = p.basename(att.remoteStoragePath!);
                final localFile = File(p.join(mediaDir.path, fileName));
                await localFile.writeAsBytes(bytes);
                att = att.copyWith(localPath: localFile.path);
              } catch (_) {
                // Keep attachment metadata even if file download fails temporarily
              }
            }
            noteAtts.add(att);
          }

          final mergedNote = NoteModel.fromJson(row).copyWith(
            attachments: noteAtts,
            syncStatus: SyncStatus.synced,
          );
          await _db.upsertNote(mergedNote, fromRemoteSync: true);
        }
      }

      _emit(
        _state.copyWith(
          isSyncing: false,
          lastSyncedAt: DateTime.now(),
          clearError: true,
        ),
      );
    } catch (e) {
      _emit(
        _state.copyWith(
          isSyncing: false,
          errorMessage: e.toString(),
        ),
      );
    }
  }

  void _subscribeRealtime() {
    final client = _client;
    final user = client?.auth.currentUser;
    if (client == null || user == null) return;

    _realtimeChannel?.unsubscribe();
    _realtimeChannel = client
        .channel('public:keep_sync_${user.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notes',
          callback: (payload) {
            unawaited(syncNow());
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'labels',
          callback: (payload) {
            unawaited(syncNow());
          },
        )
        .subscribe();
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _realtimeChannel?.unsubscribe();
    await _stateController.close();
  }
}
