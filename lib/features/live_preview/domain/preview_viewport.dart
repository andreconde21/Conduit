/// The device class Live preview emulates.
///
/// The WebView is laid out at [cssWidth] logical pixels and scaled down to
/// fit the tab, so a page's media queries and layout see a tablet or a
/// desktop even on a phone. [userAgent] is sent too, for servers that pick
/// a layout from it. [phone] is the WebView as it is: the phone's own width
/// and user agent.
enum PreviewViewport {
  phone(label: 'Phone', cssWidth: null, userAgent: null),
  tablet(
    label: 'Tablet',
    cssWidth: 820,
    userAgent:
        'Mozilla/5.0 (Linux; Android 14; SM-X710) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
  ),
  desktop(
    label: 'Desktop',
    cssWidth: 1280,
    userAgent:
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
  );

  const PreviewViewport({
    required this.label,
    required this.cssWidth,
    required this.userAgent,
  });

  final String label;

  /// Width the page is laid out at; null for the tab's own width.
  final double? cssWidth;

  /// User agent to send; null for the WebView's default.
  final String? userAgent;

  /// How much the fixed-width page is scaled to fit [availableWidth]
  /// (never enlarged: a tablet layout on a wide screen stays 1:1).
  double scaleFor(double availableWidth) {
    final width = cssWidth;
    if (width == null || availableWidth <= 0 || availableWidth >= width) {
      return 1;
    }
    return availableWidth / width;
  }

  static PreviewViewport fromName(String? name) => PreviewViewport.values
      .firstWhere((value) => value.name == name, orElse: () => phone);
}
