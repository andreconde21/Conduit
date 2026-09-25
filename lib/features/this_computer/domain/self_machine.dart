import 'dart:convert';
import 'dart:io';

import 'package:conduit/features/hosts/domain/saved_host.dart';
import 'package:conduit/features/terminal/domain/host_key_verifier.dart';
import 'package:crypto/crypto.dart';

/// What identifies the device the app runs on as an SSH target: the names
/// and addresses other devices may have saved for it, and the fingerprints
/// of its own SSH host keys.
class DeviceIdentity {
  DeviceIdentity({
    Iterable<String> addresses = const [],
    Iterable<String> hostKeyFingerprints = const [],
  }) : addresses = {
         for (final address in addresses)
           if (normalizeMachineAddress(address) case final normalized
               when normalized.isNotEmpty)
             normalized,
       },
       hostKeyFingerprints = {
         for (final fingerprint in hostKeyFingerprints)
           if (fingerprint.isNotEmpty) fingerprint.toLowerCase(),
       };

  static final empty = DeviceIdentity();

  /// Lower-case IPs and host names ([normalizeMachineAddress]).
  final Set<String> addresses;

  /// Lower-case fingerprints, in the app's trusted-key format
  /// ([hostKeyFingerprint]).
  final Set<String> hostKeyFingerprints;
}

/// Which of a device's signals said a saved machine is the device itself.
enum SelfMachineSignal {
  /// Its trusted host key is one of this device's own host keys.
  hostKey,

  /// Its address or name is one of this device's.
  address,
}

/// A saved machine that is the device the app runs on.
class SelfMachineMatch {
  const SelfMachineMatch(this.host, this.signal);

  final SavedHost host;
  final SelfMachineSignal signal;
}

/// [address] as [DeviceIdentity] compares it: trimmed, lower case, without
/// IPv6 brackets or zone, without a trailing dot, and IPs in their
/// canonical form (so `FD7A:115C:A1E0:0::1` equals `fd7a:115c:a1e0::1`).
String normalizeMachineAddress(String address) {
  var value = address.trim().toLowerCase();
  if (value.startsWith('[') && value.endsWith(']')) {
    value = value.substring(1, value.length - 1);
  }
  final zone = value.indexOf('%');
  if (zone > 0 && value.contains(':')) value = value.substring(0, zone);
  while (value.endsWith('.')) {
    value = value.substring(0, value.length - 1);
  }
  final ip = InternetAddress.tryParse(value);
  if (ip == null) return value;
  return ip.type == InternetAddressType.IPv6
      ? _canonicalIpv6(ip.rawAddress)
      : ip.address;
}

/// [raw] (16 bytes) as RFC 5952 writes it: lower-case groups without
/// leading zeros, the longest run of zero groups as `::`.
String _canonicalIpv6(List<int> raw) {
  final groups = [for (var i = 0; i < 16; i += 2) (raw[i] << 8) | raw[i + 1]];
  var bestStart = -1;
  var bestLength = 1;
  for (var i = 0; i < groups.length;) {
    if (groups[i] != 0) {
      i += 1;
      continue;
    }
    var end = i;
    while (end < groups.length && groups[end] == 0) {
      end += 1;
    }
    if (end - i > bestLength) {
      bestStart = i;
      bestLength = end - i;
    }
    i = end;
  }
  String hex(Iterable<int> part) =>
      part.map((group) => group.toRadixString(16)).join(':');
  if (bestStart < 0) return hex(groups);
  return '${hex(groups.take(bestStart))}::'
      '${hex(groups.skip(bestStart + bestLength))}';
}

/// The fingerprint the app stores for a host key (see the SSH client's
/// host-key check): `MD5:` and the colon-separated MD5 of the key blob.
/// [publicKeyLine] is an OpenSSH public key (`ssh-ed25519 AAAA… comment`),
/// as in `/etc/ssh/ssh_host_ed25519_key.pub`; null when it is not one.
String? hostKeyFingerprint(String publicKeyLine) {
  final parts = publicKeyLine.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return null;
  try {
    final blob = base64.decode(parts[1]);
    if (blob.isEmpty) return null;
    final hex = [
      for (final byte in md5.convert(blob).bytes)
        byte.toRadixString(16).padLeft(2, '0'),
    ];
    return 'MD5:${hex.join(':')}';
  } on FormatException {
    return null;
  }
}

/// The saved machine among [hosts] that is this device, or null.
///
/// The host key decides when both sides know one: a machine whose trusted
/// key ([trustedKeys], by `host:port`) is one of this device's keys is this
/// device, and one whose key is not is another machine, whatever its
/// address says (a container or VM behind a forwarded port). Otherwise its
/// address must be one of this device's, on the SSH port 22: another port
/// on this device is more likely a forward to something else.
///
/// Local shells never match. With several matches the first in [hosts]
/// order wins, host-key matches before address ones.
SelfMachineMatch? findSelfMachine(
  List<SavedHost> hosts,
  DeviceIdentity identity, {
  List<HostKeyRecord> trustedKeys = const [],
}) {
  if (identity.addresses.isEmpty && identity.hostKeyFingerprints.isEmpty) {
    return null;
  }
  final keysByEndpoint = <String, List<String>>{};
  for (final record in trustedKeys) {
    final endpoint = '${normalizeMachineAddress(record.host)}:${record.port}';
    (keysByEndpoint[endpoint] ??= []).add(record.fingerprint.toLowerCase());
  }
  SelfMachineMatch? byAddress;
  for (final host in hosts) {
    if (host.isLocal || host.isThisComputer) continue;
    final address = normalizeMachineAddress(host.host);
    if (address.isEmpty) continue;
    final trusted = keysByEndpoint['$address:${host.port}'] ?? const [];
    if (trusted.isNotEmpty && identity.hostKeyFingerprints.isNotEmpty) {
      if (trusted.any(identity.hostKeyFingerprints.contains)) {
        return SelfMachineMatch(host, SelfMachineSignal.hostKey);
      }
      continue;
    }
    if (byAddress == null &&
        host.port == 22 &&
        identity.addresses.contains(address)) {
      byAddress = SelfMachineMatch(host, SelfMachineSignal.address);
    }
  }
  return byAddress;
}
