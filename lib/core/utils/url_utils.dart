import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class UrlMetadata {
  final String url;
  final String title;
  final String description;
  final String domain;

  const UrlMetadata({
    required this.url,
    required this.title,
    required this.description,
    required this.domain,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'description': description,
        'domain': domain,
      };

  factory UrlMetadata.fromJson(Map<String, dynamic> json) => UrlMetadata(
        url: json['url'] as String? ?? '',
        title: json['title'] as String? ?? '',
        description: json['description'] as String? ?? '',
        domain: json['domain'] as String? ?? '',
      );
}

class UrlUtils {
  static final RegExp _urlRegex = RegExp(
    r'(https?:\/\/[^\s/$.?#].[^\s]*)',
    caseSensitive: false,
  );

  /// Extracts all unique HTTP/HTTPS URLs from plain text or checklist items.
  static List<String> extractUrls(String text) {
    final matches = _urlRegex.allMatches(text);
    final urls = <String>{};
    for (final m in matches) {
      final raw = m.group(0);
      if (raw != null && raw.isNotEmpty) {
        final cleaned = raw.replaceAll(RegExp(r'[.,;:!?)\]]+$'), '');
        urls.add(cleaned);
      }
    }
    return urls.toList();
  }

  /// Fetches lightweight OpenGraph / `<title>` metadata for a URL with fallback.
  static Future<UrlMetadata> fetchPreview(String url) async {
    final uri = Uri.tryParse(url);
    final domain = uri?.host.replaceFirst('www.', '') ?? url;

    try {
      final response = await http
          .get(
            Uri.parse(url),
            headers: const {'User-Agent': 'Mozilla/5.0 (KeepClone Preview)'},
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final body = response.body;
        final ogTitle = _extractMeta(body, 'og:title') ??
            _extractTag(body, 'title') ??
            domain;
        final ogDesc = _extractMeta(body, 'og:description') ??
            _extractMeta(body, 'description') ??
            url;
        return UrlMetadata(
          url: url,
          title: _cleanHtml(ogTitle).trim(),
          description: _cleanHtml(ogDesc).trim(),
          domain: domain,
        );
      }
    } catch (_) {
      // Fallback to domain-based preview when offline or blocked by CORS/timeout
    }

    return UrlMetadata(
      url: url,
      title: domain,
      description: url,
      domain: domain,
    );
  }

  static String? _extractMeta(String html, String property) {
    final pattern = RegExp(
      '<meta[^>]+(?:property|name)=["\']$property["\'][^>]+content=["\']([^"\']+)["\']',
      caseSensitive: false,
    );
    final m = pattern.firstMatch(html);
    if (m != null) return m.group(1);

    final reversePattern = RegExp(
      '<meta[^>]+content=["\']([^"\']+)["\'][^>]+(?:property|name)=["\']$property["\']',
      caseSensitive: false,
    );
    return reversePattern.firstMatch(html)?.group(1);
  }

  static String? _extractTag(String html, String tag) {
    final pattern = RegExp(
      '<$tag[^>]*>([^<]+)</$tag>',
      caseSensitive: false,
    );
    return pattern.firstMatch(html)?.group(1);
  }

  static String _cleanHtml(String input) {
    return input
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}

class KeepDateFormatter {
  static String formatEditedTimestamp(DateTime dt) {
    final now = DateTime.now();
    final local = dt.toLocal();
    final isToday = now.year == local.year &&
        now.month == local.month &&
        now.day == local.day;
    if (isToday) {
      return 'Edited ${DateFormat.jm().format(local)}';
    }
    if (now.year == local.year) {
      return 'Edited ${DateFormat('MMM d').format(local)}';
    }
    return 'Edited ${DateFormat('MMM d, y').format(local)}';
  }

  static String formatReminderChip(DateTime dt, String recurrence) {
    final now = DateTime.now();
    final local = dt.toLocal();
    final isToday = now.year == local.year &&
        now.month == local.month &&
        now.day == local.day;
    final tomorrow = now.add(const Duration(days: 1));
    final isTomorrow = tomorrow.year == local.year &&
        tomorrow.month == local.month &&
        tomorrow.day == local.day;

    String base;
    if (isToday) {
      base = 'Today, ${DateFormat.jm().format(local)}';
    } else if (isTomorrow) {
      base = 'Tomorrow, ${DateFormat.jm().format(local)}';
    } else {
      base = DateFormat('MMM d, h:mm a').format(local);
    }

    if (recurrence != 'none' && recurrence.isNotEmpty) {
      return '$base (${recurrence[0].toUpperCase()}${recurrence.substring(1)})';
    }
    return base;
  }
}
