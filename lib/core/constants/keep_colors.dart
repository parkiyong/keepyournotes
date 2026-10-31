import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Authentic 12 Google Keep note colors with adaptive Light & Dark mode palettes,
/// plus 9 custom illustrated background canvas themes.
class KeepPaletteColor {
  final String id;
  final String label;
  final Color lightBackground;
  final Color darkBackground;
  final Color lightBorder;
  final Color darkBorder;

  const KeepPaletteColor({
    required this.id,
    required this.label,
    required this.lightBackground,
    required this.darkBackground,
    required this.lightBorder,
    required this.darkBorder,
  });

  Color backgroundFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkBackground : lightBackground;

  Color borderFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkBorder : lightBorder;
}

class KeepBackgroundTheme {
  final String id;
  final String label;
  final IconData icon;
  final Color lightAccent;
  final Color darkAccent;

  const KeepBackgroundTheme({
    required this.id,
    required this.label,
    required this.icon,
    required this.lightAccent,
    required this.darkAccent,
  });
}

class KeepPalette {
  static const List<KeepPaletteColor> colors = [
    KeepPaletteColor(
      id: 'default',
      label: 'Default',
      lightBackground: Color(0xFFFFFFFF),
      darkBackground: Color(0xFF202124),
      lightBorder: Color(0xFFE0E0E0),
      darkBorder: Color(0xFF5F6368),
    ),
    KeepPaletteColor(
      id: 'coral',
      label: 'Coral',
      lightBackground: Color(0xFFFAAFA8),
      darkBackground: Color(0xFF77172E),
      lightBorder: Color(0xFFF28B82),
      darkBorder: Color(0xFF8C2A3C),
    ),
    KeepPaletteColor(
      id: 'peach',
      label: 'Peach',
      lightBackground: Color(0xFFF39F76),
      darkBackground: Color(0xFF692B17),
      lightBorder: Color(0xFFFBBC04),
      darkBorder: Color(0xFF823A22),
    ),
    KeepPaletteColor(
      id: 'sand',
      label: 'Sand',
      lightBackground: Color(0xFFFFF8B8),
      darkBackground: Color(0xFF7C4A03),
      lightBorder: Color(0xFFFBF476),
      darkBorder: Color(0xFF935B09),
    ),
    KeepPaletteColor(
      id: 'mint',
      label: 'Mint',
      lightBackground: Color(0xFFE2F6D3),
      darkBackground: Color(0xFF264D3B),
      lightBorder: Color(0xFFCCFF90),
      darkBorder: Color(0xFF34654E),
    ),
    KeepPaletteColor(
      id: 'sage',
      label: 'Sage',
      lightBackground: Color(0xFFBAF0E8),
      darkBackground: Color(0xFF0C625D),
      lightBorder: Color(0xFFA7FFEB),
      darkBorder: Color(0xFF157B75),
    ),
    KeepPaletteColor(
      id: 'fog',
      label: 'Fog',
      lightBackground: Color(0xFFD4E4ED),
      darkBackground: Color(0xFF256377),
      lightBorder: Color(0xFFCBF0F8),
      darkBorder: Color(0xFF317A91),
    ),
    KeepPaletteColor(
      id: 'storm',
      label: 'Storm',
      lightBackground: Color(0xFFAECCDC),
      darkBackground: Color(0xFF284255),
      lightBorder: Color(0xFFAECBFA),
      darkBorder: Color(0xFF36566E),
    ),
    KeepPaletteColor(
      id: 'dusk',
      label: 'Dusk',
      lightBackground: Color(0xFFD3BFDB),
      darkBackground: Color(0xFF472E5B),
      lightBorder: Color(0xFFD7AEFB),
      darkBorder: Color(0xFF5D3D75),
    ),
    KeepPaletteColor(
      id: 'blossom',
      label: 'Blossom',
      lightBackground: Color(0xFFF6E2DD),
      darkBackground: Color(0xFF6C394F),
      lightBorder: Color(0xFFFDCFE8),
      darkBorder: Color(0xFF854862),
    ),
    KeepPaletteColor(
      id: 'clay',
      label: 'Clay',
      lightBackground: Color(0xFFE9E3D4),
      darkBackground: Color(0xFF4B443A),
      lightBorder: Color(0xFFE6C9A8),
      darkBorder: Color(0xFF61584B),
    ),
    KeepPaletteColor(
      id: 'chalk',
      label: 'Chalk',
      lightBackground: Color(0xFFEFEFF1),
      darkBackground: Color(0xFF232427),
      lightBorder: Color(0xFFDADCE0),
      darkBorder: Color(0xFF44474D),
    ),
  ];

  static const List<KeepBackgroundTheme> themes = [
    KeepBackgroundTheme(
      id: 'none',
      label: 'None',
      icon: Icons.hide_image_outlined,
      lightAccent: Colors.transparent,
      darkAccent: Colors.transparent,
    ),
    KeepBackgroundTheme(
      id: 'groceries',
      label: 'Groceries',
      icon: Icons.shopping_basket_outlined,
      lightAccent: Color(0xFF2E7D32),
      darkAccent: Color(0xFF81C784),
    ),
    KeepBackgroundTheme(
      id: 'food',
      label: 'Food',
      icon: Icons.restaurant_outlined,
      lightAccent: Color(0xFFE65100),
      darkAccent: Color(0xFFFFB74D),
    ),
    KeepBackgroundTheme(
      id: 'music',
      label: 'Music',
      icon: Icons.music_note_outlined,
      lightAccent: Color(0xFF6A1B9A),
      darkAccent: Color(0xFFCE93D8),
    ),
    KeepBackgroundTheme(
      id: 'recipes',
      label: 'Recipes',
      icon: Icons.menu_book_outlined,
      lightAccent: Color(0xFFC62828),
      darkAccent: Color(0xFFEF9A9A),
    ),
    KeepBackgroundTheme(
      id: 'notes',
      label: 'Notes',
      icon: Icons.lightbulb_outline,
      lightAccent: Color(0xFFF9A825),
      darkAccent: Color(0xFFFFF176),
    ),
    KeepBackgroundTheme(
      id: 'places',
      label: 'Places',
      icon: Icons.place_outlined,
      lightAccent: Color(0xFF0277BD),
      darkAccent: Color(0xFF81D4FA),
    ),
    KeepBackgroundTheme(
      id: 'travel',
      label: 'Travel',
      icon: Icons.flight_takeoff_outlined,
      lightAccent: Color(0xFF00695C),
      darkAccent: Color(0xFF80CBC4),
    ),
    KeepBackgroundTheme(
      id: 'video',
      label: 'Video',
      icon: Icons.movie_outlined,
      lightAccent: Color(0xFF283593),
      darkAccent: Color(0xFF9FA8DA),
    ),
    KeepBackgroundTheme(
      id: 'celebration',
      label: 'Celebration',
      icon: Icons.celebration_outlined,
      lightAccent: Color(0xFFAD1457),
      darkAccent: Color(0xFFF48FB1),
    ),
  ];

  static KeepPaletteColor byId(String id) {
    return colors.firstWhere(
      (c) => c.id == id,
      orElse: () => colors.first,
    );
  }

  static KeepBackgroundTheme themeById(String id) {
    return themes.firstWhere(
      (t) => t.id == id,
      orElse: () => themes.first,
    );
  }
}

/// Decorative watermark canvas painter for Google Keep background themes.
class KeepThemeBackgroundPainter extends CustomPainter {
  final String themeId;
  final Brightness brightness;

  KeepThemeBackgroundPainter({
    required this.themeId,
    required this.brightness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (themeId == 'none') return;
    final theme = KeepPalette.themeById(themeId);
    final baseColor = brightness == Brightness.dark
        ? theme.darkAccent.withValues(alpha: 0.12)
        : theme.lightAccent.withValues(alpha: 0.10);

    final paint = Paint()
      ..color = baseColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final fillPaint = Paint()
      ..color = baseColor.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;

    // Subtle decorative motif in bottom-right corner and top-right edge
    final center = Offset(size.width - 36, size.height - 36);
    canvas.drawCircle(center, 44, fillPaint);
    canvas.drawCircle(center, 44, paint);
    canvas.drawCircle(Offset(size.width - 86, size.height - 18), 22, paint);
    canvas.drawCircle(Offset(size.width - 18, size.height - 92), 18, paint);

    // Subtle geometric rays based on theme hash
    final seed = themeId.codeUnits.fold<int>(0, (a, b) => a + b);
    final rng = math.Random(seed);
    for (var i = 0; i < 5; i++) {
      final dx = size.width - 20 - rng.nextDouble() * 110;
      final dy = size.height - 15 - rng.nextDouble() * 80;
      final r = 4.0 + rng.nextDouble() * 8.0;
      canvas.drawCircle(Offset(dx, dy), r, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant KeepThemeBackgroundPainter oldDelegate) {
    return oldDelegate.themeId != themeId ||
        oldDelegate.brightness != brightness;
  }
}
