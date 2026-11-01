# Keep Your Notes — Google Keep Clone for Android & iOS

<p align="center">
  <img src="assets/icon/app_icon.png" alt="Keep Your Notes Icon" width="110" />
</p>

**Keep Your Notes** (`gkeep`) is an offline-first, cross-platform Google Keep clone built with **Flutter (Dart 3)**, **Drift (SQLite + FTS5)**, **Riverpod**, and **Supabase (Auth, Postgres RLS, Realtime & Storage)**.

It works immediately out of the box in **Guest-first offline mode** and supports optional real-time multi-device cloud synchronization via Supabase, plus lossless data export and direct import from **Google Takeout (Keep)** archives.

---

## Key Features

### Authentic Material 3 Google Keep Experience
- **Adaptive Palettes & Canvas Themes**: 12 adaptive Light/Dark mode note colors and 9 custom decorative background themes (`Groceries`, `Food`, `Music`, `Recipes`, `Notes`, `Places`, `Travel`, `Video`, `Celebration`).
- **Flexible Layouts & Organization**:
  - Toggle between a **2-column Masonry staggered grid** and a **1-column list view**.
  - Dedicated **Pinned** and **Others** sections with drag-and-drop card reordering.
  - Smooth `Hero` card transitions, swipe-to-archive gestures, and a long-press multi-select batch action bar (pin, color, label, archive, delete, copy, share).
- **Instant Full-Text & Faceted Search**: Powered by **SQLite FTS5**, with one-tap filter chips for Note Types (Checklists, Images, Drawings, Audio, Reminders, URLs), Labels, and Colors.
- **Lifecycle Views**: Dedicated views for **Notes**, **Reminders**, **Labels**, **Archive**, and **Trash** (with automatic 7-day purge of expired trashed notes).

### Rich Note Creation & Multimodal Attachments
- **Interactive Checklists**: Drag-to-reorder checklist items, 1-level subtask indentation, and a collapsible completed items section.
- **Rich Text Formatting**: Bold, Italic, Underline, H1/H2 headers, full Undo/Redo history stack, and inline `#label` autocomplete.
- **Freehand Drawing Studio**: Vector drawing canvas supporting Pen, Marker, Highlighter, and Eraser tools with customizable stroke widths, colors, and background grids (`None`, `Dots`, `Lines`, `Squares`). Saves both vector stroke JSON and raster PNG so drawings remain re-editable anytime.
- **Image Attachments & On-Device OCR**: Attach photos from the Camera or Gallery and extract text offline with **"Grab image text"** powered by Google ML Kit (`google_mlkit_text_recognition`).
- **Voice Memos & Live Speech-to-Text**: Record `.m4a` voice notes with simultaneous on-device live transcription (`record`, `speech_to_text`, `just_audio`).
- **Automatic URL Previews**: Extracts HTTP/HTTPS links from note bodies and renders interactive preview cards.

### Time & Location Reminders
- **Time Reminders**: Schedule local notifications (`flutter_local_notifications` + `timezone`) with quick presets or custom date/time and optional recurrence (`None`, `Daily`, `Weekly`, `Monthly`).
- **Location Geofence Reminders**: Pick any place using the interactive **OpenStreetMap + Nominatim** map sheet (`flutter_map`) with zero API keys required, and trigger notifications on arrival via `geolocator`.

### Privacy, Sharing & Data Portability
- **Biometric / PIN Note Lock**: Lock sensitive notes behind Face ID / Fingerprint (`local_auth`) or a custom 4-digit PIN.
- **OS Share Sheet**: Share notes and media out to other apps (`share_plus`) or receive shared content into Keep.
- **Full ZIP Backup & Google Takeout Migration**:
  - **Export**: Bundles all notes, labels, human-readable Markdown files (`markdown/*.md`), and media attachments (`media/*`) into a single portable `.zip` archive alongside `keep_backup.json`.
  - **Import**: Restore from a native Keep Backup `.zip` or migrate directly from a **Google Takeout (Keep)** `.zip` or `.json` export.

---

## Tech Stack

| Layer | Technology |
| :--- | :--- |
| **Framework** | Flutter (Dart `^3.13.2`, Material 3) |
| **State Management** | `flutter_riverpod` |
| **Local Database** | `drift` + `sqlite3` (SQLite with `FTS5` virtual table) |
| **Cloud Backend (Optional)** | `supabase_flutter` (Auth, Postgres RLS, Realtime, Storage) |
| **OCR & Speech** | `google_mlkit_text_recognition`, `speech_to_text`, `record`, `just_audio` |
| **Maps & Geofencing** | `flutter_map`, `latlong2`, `geolocator` (OpenStreetMap + Nominatim) |
| **Security & Notifications** | `local_auth`, `flutter_local_notifications`, `timezone` |
| **Backup & Archiving** | `archive`, `file_picker`, `share_plus` |

---

## Project Structure

```text
gkeep/
├── assets/
│   └── icon/
│       └── app_icon.png                  # App launcher icon asset
├── lib/
│   ├── main.dart                         # App entry point & service initialization
│   ├── app.dart                          # MaterialApp & theme configuration
│   ├── core/
│   │   ├── constants/keep_colors.dart    # Adaptive light/dark note colors & canvas themes
│   │   ├── theme/app_theme.dart          # Material 3 light & dark themes
│   │   └── utils/url_utils.dart          # URL extraction helpers
│   ├── data/
│   │   ├── local/keep_database.dart      # Drift SQLite + FTS5 database & DAO queries
│   │   ├── migration/                    # Portable ZIP backup & Google Takeout importer
│   │   └── sync/supabase_sync_service.dart # Outbox queue push, LWW pull & Realtime sync
│   ├── domain/
│   │   ├── models/note_model.dart        # Note, ChecklistItem, RichTextSpan, Attachment, Label models
│   │   └── services/                     # Riverpod providers & device services (OCR, Audio, Biometrics, Notifications)
│   └── features/
│       ├── drawing/                      # Re-editable vector drawing canvas screen
│       ├── editor/                       # Rich note & checklist editor screen
│       ├── home/                         # Masonry grid, list view, drawer & note cards
│       ├── labels/                       # Label management screen
│       ├── reminders/                    # Time & OpenStreetMap location reminder picker
│       ├── search/                       # FTS5 search & multi-faceted filter screen
│       └── settings/                     # Cloud Sync config, Auth & Backup/Takeout migration screen
├── supabase/
│   └── migrations/
│       └── 20261031000000_initial_keep_schema.sql # Postgres tables, RLS policies, Realtime & Storage bucket
└── test/
    └── widget_test.dart                  # Database, migration & widget test suite
```

---

## Getting Started

### Prerequisites
- **Flutter SDK** (Dart `^3.13.2`)
- Android Studio / Android SDK (for Android builds) or Xcode (for iOS builds)

### 1. Install Dependencies & Run (Offline-First Mode)
No cloud credentials or API keys are required to run the app locally:

```bash
flutter pub get
flutter run
```

### 2. Configure Supabase Cloud Sync (Optional)
If you want multi-device synchronization and cloud media backup:

1. Create a new project on [Supabase](https://supabase.com/).
2. Open the **SQL Editor** in your Supabase dashboard and run the migration script:
   - [`supabase/migrations/20261031000000_initial_keep_schema.sql`](supabase/migrations/20261031000000_initial_keep_schema.sql)
   - This creates the `notes`, `note_attachments`, and `labels` tables, enables Row-Level Security (RLS), adds tables to `supabase_realtime`, and provisions the private `keep-attachments` storage bucket.
3. Connect the app to your Supabase project using either method:
   - **In-App Configuration**: Open the app → tap the top-right sync/profile icon (or open **Settings, Sync & Migration** from the drawer) → enter your **Supabase Project URL** and **Supabase Anon Key** → sign up or sign in.
   - **Compile-Time Defines**: Pass credentials at launch or build time:
     ```bash
     flutter run \
       --dart-define=SUPABASE_URL=https://your-project.supabase.co \
       --dart-define=SUPABASE_ANON_KEY=your-anon-key
     ```

### 3. Build for Production (Android)
Android release builds are pre-configured with Core Library Desugaring, MultiDex, adaptive launcher icons, and ProGuard rules for Google ML Kit:

```bash
flutter build apk --release
```

---

## Offline-First & Cloud Sync Architecture

1. **Single Source of Truth**: The UI exclusively reads and watches reactive streams from the local `KeepDatabase` (`gkeep_offline.sqlite`). Every create, edit, reorder, or trash action mutates local SQLite first with zero network latency.
2. **Outbox Queue (`sync_status`)**: Local mutations mark records as `pendingUpsert`, and hard deletions are recorded in `deleted_records`.
3. **Last-Write-Wins (LWW) & Realtime Sync**: When authenticated with Supabase, `SupabaseSyncService` pushes pending local mutations, uploads attachment files to the `keep-attachments` storage bucket, reconciles remote records by comparing `updated_at` timestamps, and listens to Postgres Realtime channels for live multi-device updates.

---

## Static Analysis & Testing

Run the analyzer and test suite:

```bash
flutter analyze
flutter test
```
