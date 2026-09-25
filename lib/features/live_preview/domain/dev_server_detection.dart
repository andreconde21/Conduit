import 'dart:convert';

import 'package:conduit/features/live_preview/domain/listening_ports.dart';

/// Where a "Preview ready" offer came from.
enum DevServerOfferSource {
  /// A new listening port (the companion's `ports`, else `ss`).
  listening,

  /// A dev server URL printed in the terminal ("Local: http://…:5173/").
  output,
}

/// A dev server the phone can offer to open in Live preview.
class DevServerOffer {
  const DevServerOffer({
    required this.port,
    required this.source,
    this.path = '/',
    this.label,
    this.cwd,
  });

  final int port;

  /// Path (and query) to open, from a printed URL; `/` otherwise.
  final String path;

  /// What the server is (`vite`, `next`, …), or its process name.
  final String? label;

  /// The server's working directory on the host, when the companion knows.
  final String? cwd;
  final DevServerOfferSource source;

  /// "Preview ready · :5173 · vite".
  String get chipText =>
      'Preview ready · :$port${label == null ? '' : ' · $label'}';

  /// Combines what two sources know about the same port: the printed URL's
  /// path, the companion's label and cwd.
  DevServerOffer mergedWith(DevServerOffer other) => DevServerOffer(
    port: port,
    source: source,
    path: path != '/' ? path : other.path,
    label: label ?? other.label,
    cwd: cwd ?? other.cwd,
  );

  @override
  bool operator ==(Object other) =>
      other is DevServerOffer &&
      other.port == port &&
      other.path == path &&
      other.label == label &&
      other.cwd == cwd &&
      other.source == source;

  @override
  int get hashCode => Object.hash(port, path, label, cwd, source);

  @override
  String toString() => 'DevServerOffer(:$port$path, $label, $source)';
}

/// Ports that are never a dev server: SSH, mail, DNS, portmapper, CUPS,
/// LLMNR. Mosh is UDP, so it never shows in a TCP listing.
const devServerIgnoredPorts = {22, 25, 53, 111, 631, 5355};

/// Processes whose listeners are never offered.
const devServerIgnoredProcesses = {
  'sshd',
  'systemd-resolve',
  'systemd-resolved',
  'dnsmasq',
  'docker-proxy',
  'dockerd',
  'containerd',
  'cupsd',
  'master',
  'exim4',
  'postfix',
  'mosh-server',
  'tailscaled',
  'avahi-daemon',
  'chronyd',
  'rpcbind',
  'named',
  'unbound',
};

/// First port of Linux's ephemeral range: listeners above it are
/// debuggers, language servers and IPC far more often than dev servers.
const devServerEphemeralStart = 32768;

/// Whether a listener from plain `ss` (the fallback without the companion)
/// could be a dev server the user started. Without `-p` visibility (another
/// user's or root's socket) 80 and 443 are assumed to be the system's web
/// server.
bool isDevServerCandidate(ListeningPort port) {
  if (devServerIgnoredPorts.contains(port.port)) return false;
  if (port.port >= devServerEphemeralStart) return false;
  final process = port.process;
  if (process != null && devServerIgnoredProcesses.contains(process)) {
    return false;
  }
  if ((port.port == 80 || port.port == 443) && process == null) return false;
  return true;
}

/// One `conductore-hostd ports` reply.
class CompanionPortsReply {
  const CompanionPortsReply({required this.seq, required this.offers});

  /// Pass back as `--since` to get only newer ports.
  final int seq;
  final List<DevServerOffer> offers;
}

/// The `ports` command, with only ports newer than [since] when given.
String companionPortsArguments({int? since}) =>
    since == null ? 'ports' : 'ports --since $since';

/// Parses `conductore-hostd ports` output. Null for anything that is not a
/// ports reply (an older companion's "unknown command", a broken install),
/// which makes the caller fall back to `ss`.
CompanionPortsReply? parseCompanionPorts(String stdout) {
  Object? decoded;
  try {
    decoded = jsonDecode(stdout.trim());
  } on FormatException {
    return null;
  }
  if (decoded is! Map) return null;
  final seq = decoded['seq'];
  final ports = decoded['ports'];
  if (seq is! num || ports is! List) return null;
  final offers = <DevServerOffer>[];
  for (final entry in ports) {
    if (entry is! Map) continue;
    final port = entry['port'];
    if (port is! num || port < 1 || port > 65535) continue;
    final label = entry['label'] ?? entry['process'];
    final cwd = entry['cwd'];
    offers.add(
      DevServerOffer(
        port: port.toInt(),
        source: DevServerOfferSource.listening,
        label: label is String && label.isNotEmpty ? label : null,
        cwd: cwd is String && cwd.isNotEmpty ? cwd : null,
      ),
    );
  }
  offers.sort((a, b) => a.port.compareTo(b.port));
  return CompanionPortsReply(seq: seq.toInt(), offers: offers);
}

/// Listeners in [current] that were not in [previous] (compared by port).
List<ListeningPort> newListeningPorts(
  Iterable<ListeningPort> previous,
  Iterable<ListeningPort> current,
) {
  final known = {for (final port in previous) port.port};
  return [
    for (final port in current)
      if (!known.contains(port.port)) port,
  ];
}

// A loopback URL with an explicit port. 0.0.0.0 and [::] are what servers
// bound to every interface print.
final _loopbackUrl = RegExp(
  r'https?://(?:localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1?\]):(\d{2,5})'
  r"(/[A-Za-z0-9\-._~/?#\[\]@!$&'()*+,;=%]*)?",
  caseSensitive: false,
);

// Words dev servers put on the line that announces their URL: Vite and CRA
// "Local:", Next "- Local:", Django "Starting development server at",
// Flask "Running on", Uvicorn "running on", Python "Serving HTTP on", and
// the generic "listening on", "ready on", "available at", "started".
final _announcement = RegExp(
  r'\b(local|running|listening|serving|server|ready|available|started|'
  r'app|preview|network)\b',
  caseSensitive: false,
);

// Framework markers near the URL, first match wins.
final _frameworks = <(RegExp, String)>[
  (RegExp(r'\bVITE\b\s*v?\d', caseSensitive: false), 'vite'),
  (RegExp(r'Next\.js'), 'next'),
  (RegExp(r'\bAstro\b'), 'astro'),
  (RegExp(r'\bNuxt\b'), 'nuxt'),
  (RegExp(r'Storybook'), 'storybook'),
  (RegExp(r'Angular|ng serve'), 'angular'),
  (RegExp(r'You can now view .* in the browser'), 'create-react-app'),
  (RegExp(r'webpack', caseSensitive: false), 'webpack'),
  (RegExp(r'Starting development server|Django'), 'django'),
  (RegExp(r'Serving Flask app|\bFlask\b'), 'flask'),
  (RegExp(r'Uvicorn'), 'uvicorn'),
  (RegExp(r'Serving HTTP on'), 'python http.server'),
  (RegExp(r'\bRails\b|\bPuma\b'), 'rails'),
  (RegExp(r'\bExpo\b|Metro'), 'expo'),
];

/// Dev server URLs announced on screen: one offer per port, in screen
/// order. A line qualifies when a loopback URL with a port comes after an
/// announcement word ("Local:", "running on", …), so a typed
/// `curl http://localhost:3000` does not; the label comes from a framework
/// banner on that line or up to six lines above.
List<DevServerOffer> detectDevServerUrls(List<String> lines) {
  final offers = <int, DevServerOffer>{};
  for (var row = 0; row < lines.length; row++) {
    final line = lines[row];
    for (final match in _loopbackUrl.allMatches(line)) {
      final before = line.substring(0, match.start);
      if (!_announcement.hasMatch(before)) continue;
      final port = int.tryParse(match.group(1)!);
      if (port == null || port < 1 || port > 65535) continue;
      if (devServerIgnoredPorts.contains(port) || offers.containsKey(port)) {
        continue;
      }
      offers[port] = DevServerOffer(
        port: port,
        source: DevServerOfferSource.output,
        path: _cleanPath(match.group(2)),
        label: _frameworkNear(lines, row),
      );
    }
  }
  return offers.values.toList();
}

String _cleanPath(String? raw) {
  if (raw == null || raw.isEmpty) return '/';
  var end = raw.length;
  while (end > 1 && ".,;:!?)'\"]".contains(raw[end - 1])) {
    end--;
  }
  final path = raw.substring(0, end);
  return path.startsWith('/') ? path : '/';
}

String? _frameworkNear(List<String> lines, int row) {
  for (var index = row; index >= 0 && index >= row - 6; index--) {
    for (final (pattern, label) in _frameworks) {
      if (pattern.hasMatch(lines[index])) return label;
    }
  }
  return null;
}
