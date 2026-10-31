import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/note_model.dart';

/// 1. On-Device OCR Service ("Grab image text" using Google ML Kit)
class KeepOcrService {
  Future<String> extractTextFromImage(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      return '';
    }
    final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final recognized = await textRecognizer.processImage(inputImage);
      return recognized.text.trim();
    } catch (_) {
      return '';
    } finally {
      await textRecognizer.close();
    }
  }
}

/// 2. Voice Memo Recording & Live On-Device Speech-to-Text Service
class KeepVoiceService {
  final AudioRecorder _recorder = AudioRecorder();
  final stt.SpeechToText _speech = stt.SpeechToText();
  DateTime? _recordingStartedAt;
  String _latestTranscript = '';

  bool get isSpeechAvailable => _speech.isAvailable;

  Future<String?> startRecording({
    required void Function(String liveText) onTranscriptUpdate,
  }) async {
    final hasMicPermission = await _recorder.hasPermission();
    if (!hasMicPermission) {
      return null;
    }

    _latestTranscript = '';
    _recordingStartedAt = DateTime.now();

    final dir = await getApplicationDocumentsDirectory();
    final mediaDir = Directory(p.join(dir.path, 'keep_media'));
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }

    final filePath = p.join(
      mediaDir.path,
      'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
      path: filePath,
    );

    // Attempt simultaneous on-device Speech-to-Text transcription
    try {
      final speechReady = await _speech.initialize();
      if (speechReady) {
        await _speech.listen(
          onResult: (result) {
            _latestTranscript = result.recognizedWords;
            onTranscriptUpdate(_latestTranscript);
          },
        );
      }
    } catch (_) {
      // Speech recognition is optional if device lacks offline pack
    }

    return filePath;
  }

  Future<({String? path, int durationMs, String transcript})> stopRecording() async {
    try {
      if (_speech.isListening) {
        await _speech.stop();
      }
    } catch (_) {}

    final path = await _recorder.stop();
    final elapsedMs = _recordingStartedAt != null
        ? DateTime.now().difference(_recordingStartedAt!).inMilliseconds
        : 0;
    return (
      path: path,
      durationMs: elapsedMs,
      transcript: _latestTranscript.trim(),
    );
  }

  Future<void> dispose() async {
    await _recorder.dispose();
  }
}

/// 3. Biometric & PIN Note Lock Service
class KeepBiometricService {
  static const String _pinPrefKey = 'keep_note_lock_fallback_pin';
  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> canUseBiometrics() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateForLockedNote() async {
    try {
      final supported = await canUseBiometrics();
      if (!supported) {
        return true;
      }
      return await _auth.authenticate(
        localizedReason: 'Authenticate to view or unlock this protected note',
      );
    } catch (_) {
      return false;
    }
  }

  Future<String?> getSavedPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pinPrefKey);
  }

  Future<void> setFallbackPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinPrefKey, pin.trim());
  }

  Future<bool> verifyPin(String input) async {
    final saved = await getSavedPin();
    if (saved == null || saved.isEmpty) return true;
    return saved == input.trim();
  }
}

/// 4. Time & Location (OpenStreetMap + Nominatim + Geofence) Reminder Service
class NominatimPlaceResult {
  final String displayName;
  final String shortName;
  final double latitude;
  final double longitude;

  const NominatimPlaceResult({
    required this.displayName,
    required this.shortName,
    required this.latitude,
    required this.longitude,
  });
}

class KeepReminderService {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  StreamSubscription<Position>? _geofenceSubscription;
  final Set<String> _triggeredLocationNotes = {};
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    try {
      await _notifications.initialize(settings: settings);
      _initialized = true;
    } catch (_) {
      // Safe fallback in headless unit test environments
    }
  }

  Future<void> scheduleNoteReminder(NoteModel note) async {
    if (!_initialized) await initialize();
    if (!_initialized) return;

    final notificationId = note.id.hashCode.abs() % 2147483647;
    await _notifications.cancel(id: notificationId);

    if (note.isTrashed || note.reminderAt == null) return;
    final targetTime = note.reminderAt!;
    if (targetTime.isBefore(DateTime.now()) &&
        note.reminderRecurrence == 'none') {
      return;
    }

    DateTimeComponents? matchComponents;
    switch (note.reminderRecurrence) {
      case 'daily':
        matchComponents = DateTimeComponents.time;
        break;
      case 'weekly':
        matchComponents = DateTimeComponents.dayOfWeekAndTime;
        break;
      case 'monthly':
        matchComponents = DateTimeComponents.dayOfMonthAndTime;
        break;
      default:
        matchComponents = null;
    }

    try {
      final scheduledDate = tz.TZDateTime.from(
        targetTime.isAfter(DateTime.now())
            ? targetTime
            : DateTime.now().add(const Duration(minutes: 1)),
        tz.local,
      );

      await _notifications.zonedSchedule(
        id: notificationId,
        title: note.title.isNotEmpty ? note.title : 'Keep Note Reminder',
        body: note.isChecklist
            ? '${note.checklistItems.length} checklist items'
            : (note.content.isNotEmpty ? note.content : 'Tap to open your note'),
        scheduledDate: scheduledDate,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'keep_reminders_channel',
            'Note Reminders',
            channelDescription: 'Time and location reminders for Keep notes',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: matchComponents,
      );
    } catch (_) {
      // Ignore on unsupported desktop/test platforms
    }
  }

  Future<void> cancelNoteReminder(String noteId) async {
    if (!_initialized) return;
    final notificationId = noteId.hashCode.abs() % 2147483647;
    try {
      await _notifications.cancel(id: notificationId);
    } catch (_) {}
  }

  /// Evaluates active location-based reminders whenever position updates.
  Future<void> startGeofenceMonitoring(List<NoteModel> Function() getActiveNotes) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        return;
      }

      await _geofenceSubscription?.cancel();
      _geofenceSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 35,
        ),
      ).listen((position) async {
        final notes = getActiveNotes();
        for (final note in notes) {
          final loc = note.reminderLocation;
          if (loc == null || note.isTrashed || note.isArchived) continue;

          final distance = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            loc.latitude,
            loc.longitude,
          );

          if (distance <= loc.radiusMeters &&
              !_triggeredLocationNotes.contains(note.id)) {
            _triggeredLocationNotes.add(note.id);
            await _showImmediateLocationNotification(note, loc);
          } else if (distance > loc.radiusMeters * 1.4) {
            _triggeredLocationNotes.remove(note.id);
          }
        }
      });
    } catch (_) {}
  }

  Future<void> _showImmediateLocationNotification(
    NoteModel note,
    ReminderLocation loc,
  ) async {
    if (!_initialized) await initialize();
    if (!_initialized) return;
    final notificationId = (note.id.hashCode.abs() + 999) % 2147483647;
    try {
      await _notifications.show(
        id: notificationId,
        title: note.title.isNotEmpty ? note.title : 'Arrived at ${loc.name}',
        body: 'Location reminder near ${loc.name}',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'keep_location_channel',
            'Location Reminders',
            channelDescription: 'Geofence notifications for Keep notes',
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (_) {}
  }

  /// Searches places using OpenStreetMap Nominatim API (zero API key required).
  Future<List<NominatimPlaceResult>> searchPlaces(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    try {
      final uri = Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        {
          'q': trimmed,
          'format': 'jsonv2',
          'limit': '6',
          'addressdetails': '1',
        },
      );
      final response = await http.get(
        uri,
        headers: const {'User-Agent': 'KeepCloneFlutterApp/1.0'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List<dynamic>;
        return list.map((item) {
          final m = item as Map<String, dynamic>;
          final display = m['display_name'] as String? ?? trimmed;
          final name = (m['name'] as String?)?.isNotEmpty == true
              ? m['name'] as String
              : display.split(',').first.trim();
          return NominatimPlaceResult(
            displayName: display,
            shortName: name,
            latitude: double.tryParse(m['lat']?.toString() ?? '') ?? 0.0,
            longitude: double.tryParse(m['lon']?.toString() ?? '') ?? 0.0,
          );
        }).toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> dispose() async {
    await _geofenceSubscription?.cancel();
  }
}

/// 5. Native "Share to Keep" Receiver Service
class SharedIncomingPayload {
  final String title;
  final String text;
  final List<String> imagePaths;

  const SharedIncomingPayload({
    required this.title,
    required this.text,
    required this.imagePaths,
  });
}

class ShareToKeepService {
  static const MethodChannel _channel =
      MethodChannel('com.gkeep.app/share_intent');

  final StreamController<SharedIncomingPayload> _controller =
      StreamController<SharedIncomingPayload>.broadcast();

  Stream<SharedIncomingPayload> get incomingShares => _controller.stream;

  Future<void> initialize() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedData' && call.arguments is Map) {
        final parsed = _parseMap(Map<Object?, Object?>.from(call.arguments as Map));
        if (parsed != null) {
          _controller.add(parsed);
        }
      }
    });

    try {
      final initial = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getInitialSharedData',
      );
      if (initial != null) {
        final parsed = _parseMap(initial);
        if (parsed != null) {
          _controller.add(parsed);
        }
      }
    } catch (_) {}
  }

  SharedIncomingPayload? _parseMap(Map<Object?, Object?> raw) {
    final title = (raw['title'] as String? ?? '').trim();
    final text = (raw['text'] as String? ?? '').trim();
    final images = (raw['images'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .where((s) => s.isNotEmpty)
        .toList();
    if (title.isEmpty && text.isEmpty && images.isEmpty) return null;
    return SharedIncomingPayload(
      title: title,
      text: text,
      imagePaths: images,
    );
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
