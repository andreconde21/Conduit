/// Finds http(s) links in terminal output so they can be tapped.
///
/// Rules:
/// - only `http://` and `https://` links (case-insensitive scheme), made of
///   printable ASCII URL characters: anything else (spaces, quotes, `<>`,
///   backticks, box-drawing borders of TUIs) ends the link;
/// - trailing sentence punctuation (`.,;:!?`) and quotes are dropped, and a
///   trailing `)` or `]` only stays when the link opened one ("see
///   (https://x.dev/a)" vs. "https://en.wikipedia.org/wiki/Dart_(lang)");
/// - a link must have a host after the scheme.
///
/// [text] is one logical line (soft-wrapped rows already joined) and
/// [column] the tapped index into it; returns the link under it, or null.
String? terminalUrlAt(String text, int column) {
  if (column < 0 || column >= text.length) {
    return null;
  }
  for (final match in _urlPattern.allMatches(text)) {
    if (match.start > column) {
      break;
    }
    final url = _trimUrl(match.group(0)!);
    if (column < match.start + url.length && _hasHost(url)) {
      return url;
    }
  }
  return null;
}

/// Every link in [text], in order (same rules as [terminalUrlAt]).
List<String> terminalUrlsIn(String text) => [
  for (final match in _urlPattern.allMatches(text))
    if (_hasHost(_trimUrl(match.group(0)!))) _trimUrl(match.group(0)!),
];

/// The remote port a link points at when it names the host itself
/// (`localhost`, `127.0.0.1`, `0.0.0.0`, `[::1]`) over plain http, which
/// is what the live preview can forward; null for anything else.
int? loopbackPreviewPort(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme.toLowerCase() != 'http' || !uri.hasPort) {
    return null;
  }
  const loopbackHosts = {'localhost', '127.0.0.1', '0.0.0.0', '::1'};
  if (!loopbackHosts.contains(uri.host.toLowerCase())) {
    return null;
  }
  return uri.port;
}

/// The path (with query) of a link, for the live preview address bar.
String previewPathOf(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    return '/';
  }
  final path = uri.path.isEmpty ? '/' : uri.path;
  return uri.hasQuery ? '$path?${uri.query}' : path;
}

final _urlPattern = RegExp(
  r"[hH][tT][tT][pP][sS]?://[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]+",
);

String _trimUrl(String url) {
  var end = url.length;
  while (end > 0) {
    final char = url[end - 1];
    if (".,;:!?'\"".contains(char)) {
      end--;
      continue;
    }
    if (char == ')' || char == ']') {
      final open = char == ')' ? '(' : '[';
      final body = url.substring(0, end);
      final opens = open.allMatches(body).length;
      final closes = char.allMatches(body).length;
      if (closes > opens) {
        end--;
        continue;
      }
    }
    break;
  }
  return url.substring(0, end);
}

bool _hasHost(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && uri.host.isNotEmpty;
}
