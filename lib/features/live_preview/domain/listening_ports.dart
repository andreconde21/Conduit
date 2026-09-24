/// A TCP port something on the host is listening on.
class ListeningPort {
  const ListeningPort({required this.port, this.address = '', this.process});

  final int port;

  /// The bound address as printed by `ss` (`0.0.0.0`, `*`, `127.0.0.1`, …).
  final String address;

  /// Process name when `ss -p` could see it (own processes only).
  final String? process;

  /// Loopback-only listeners are still reachable: the forward connects
  /// from the host itself.
  String get label => process == null ? '$port' : '$port · $process';

  @override
  bool operator ==(Object other) =>
      other is ListeningPort &&
      other.port == port &&
      other.address == address &&
      other.process == process;

  @override
  int get hashCode => Object.hash(port, address, process);

  @override
  String toString() => 'ListeningPort($address:$port, $process)';
}

/// Command that lists listening TCP sockets without headers. `-p` adds the
/// owning process for sockets the SSH user owns; other users' sockets are
/// still listed, just without a name.
const listeningPortsCommand = 'ss -ltnpH 2>/dev/null || ss -ltnH';

final _usersPattern = RegExp(r'users:\(\("([^"]+)"');

/// Parses `ss -ltnH` (optionally `-p`) output into unique ports, lowest
/// first. IPv4 and IPv6 listeners on the same port collapse into one entry.
List<ListeningPort> parseListeningPorts(String output) {
  final byPort = <int, ListeningPort>{};
  for (final rawLine in output.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    final fields = line.split(RegExp(r'\s+'));
    // With -H the columns are: State Recv-Q Send-Q Local Peer [Process].
    // Some builds omit State when filtering with -l; find the first field
    // that looks like an address:port instead of relying on the index.
    String? local;
    for (final field in fields) {
      if (field.contains(':') && int.tryParse(field.split(':').last) != null) {
        local = field;
        break;
      }
    }
    if (local == null) {
      continue;
    }
    final separator = local.lastIndexOf(':');
    final port = int.tryParse(local.substring(separator + 1));
    if (port == null) {
      continue;
    }
    var address = local.substring(0, separator);
    if (address.startsWith('[') && address.endsWith(']')) {
      address = address.substring(1, address.length - 1);
    }
    final process = _usersPattern.firstMatch(line)?.group(1);
    final existing = byPort[port];
    if (existing == null || (existing.process == null && process != null)) {
      byPort[port] = ListeningPort(
        port: port,
        address: address,
        process: process ?? existing?.process,
      );
    }
  }
  final ports = byPort.values.toList()
    ..sort((a, b) => a.port.compareTo(b.port));
  return ports;
}
