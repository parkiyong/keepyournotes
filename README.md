# Keep Notes — Google Keep Clone for Android & iOS

An offline-first, cross-platform Google Keep clone built with **Flutter (Dart 3)**, **Drift (SQLite + FTS5)**, **Riverpod**, and **Supabase (Auth, Postgres RLS, Realtime & Storage)**.

## Features

- **Authentic Material 3 Google Keep UI**:
  - 12 adaptive Light/Dark mode note colors and 9 decorative background canvas themes (`Groceries`, `Food`, `Music`, `Recipes`, `Notes`, `Places`, `Travel`, `Video`, `Celebration`).
  - 2-column Masonry staggered grid & 1-column list toggle, Pinned vs. Others sections, Hero card transitions, swipe-to-archive, drag-and-drop card reordering, and long-press multi-select batch action bar.
- **Rich Note Creation & Media**:
  - **Checklists**: Drag-to-reorder items, 1-level subtask indentation, collapsible checked items section.
  - **Rich Text Formatting**: Bold, Italic, Underline, H1/H2 headers, Undo/Redo history stack, and inline `#label` autocomplete.
  - **Freehand Drawing Canvas**: Pen, Marker, Highlighter, and Eraser with dot/line/square grids; vector strokes are saved alongside the exported PNG so drawings remain re-editable.
  - **Image Attachments & On-Device OCR**: Capture from Camera or Gallery and run **"Grab image text"** powered by Google ML Kit (`google_mlkit_text_recognition`).
  - **Voice Memos & Live Speech-to-Text**: Record `.m4a` voice clips with simultaneous on-device speech recognition (`record`, `speech_to_text`, `just_audio`).
  - **URL Link Previews**: Automatically extracts URLs from notes and renders clickable preview cards.
- **Time & Location Reminders**:
  - Scheduled local notifications with Daily/Weekly/Monthly recurrence (`flutter_local_notifications`).
  - Interactive OpenStreetMap + Nominatim place picker (`flutter_map`) and background/foreground geofence monitoring (`geolocator`) with zero API keys required.
- **Privacy, Sharing & Full Data Migration**:
  - **Biometric / PIN Note Lock**: Protect individual notes with Face ID / Fingerprint (`local_auth`) or fallback PIN.
  - **Share to Keep & OS Share Sheet**: Receive shared text, links, and images from other Android/iOS apps, or share notes out via the native share sheet.
  - **Portable Backup & Google Takeout Migration**: Export all notes, labels, Markdown files, and media attachments into a single `.zip` bundle, and restore/import from either a Backup `.zip` or a **Google Takeout (Keep)** `.zip`/`.json` archive.

## Quick Start

1. **Run the app (Guest-first offline mode works immediately)**:
   ```bash
   flutter pub get
   flutter run
   ```

2. **Connect Supabase Cloud Sync (Optional)**:
   - Run the SQL migration in [20261031000000_initial_keep_schema.sql](file:///home/widi/GitHub/gkeep/supabase/migrations/20261031000000_initial_keep_schema.sql) in your Supabase SQL Editor.
   - Open **Settings, Sync & Migration** inside the app (top-right avatar or navigation drawer) and enter your **Supabase Project URL** and **Anon Key**, or pass them via `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`.

3. **Run Static Analysis & Tests**:
   ```bash
   flutter analyze
   flutter test
   ```
