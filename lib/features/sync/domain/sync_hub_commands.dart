import 'package:conduit/features/sync/domain/sync_hub.dart';

/// The shell commands the hub runs, built as exact strings so tests can
/// pin them. They need only POSIX sh, mkdir, mv, grep, tail and find, which
/// Linux and macOS hosts have.
abstract final class SyncHubCommands {
  /// Relative to the home directory (SFTP paths resolve from there too).
  static const directory = '.conductore/sync';
  static const _dir = r'"$HOME/.conductore/sync"';
  static const _authorizedKeys = r'"$HOME/.ssh/authorized_keys"';
  static const deviceComment = 'conductore-device';

  static final _id = RegExp(r'^[a-f0-9]{32}$');
  static final _keyType = RegExp(
    r'^(ssh-ed25519|ssh-rsa|ecdsa-sha2-[a-z0-9-]+)$',
  );
  static final _keyData = RegExp(r'^[A-Za-z0-9+/]{40,}={0,2}$');

  /// Vault and device ids are 32 lowercase hex characters; nothing else
  /// ever reaches a command line.
  static bool isValidId(String id) => _id.hasMatch(id);

  static String _checkedId(String id) {
    if (!isValidId(id)) throw ArgumentError.value(id, 'id', 'not a sync id');
    return id;
  }

  /// POSIX single-quoting.
  static String quote(String value) => "'${value.replaceAll("'", r"'\''")}'";

  static String bundlePath(String vaultId) =>
      '$directory/${_checkedId(vaultId)}.bundle';

  static String metaPath(String vaultId) =>
      '$directory/${_checkedId(vaultId)}.meta';

  /// Upload name for this device's bundle or meta before the commit
  /// renames it into place.
  static String uploadPath(String vaultId, String deviceId, String kind) =>
      '$directory/${_checkedId(vaultId)}.$kind.${_checkedId(deviceId)}.tmp';

  static String prepare() =>
      'umask 077 && mkdir -p $_dir && chmod 700 "\$HOME/.conductore" $_dir';

  static String readMeta(String vaultId) =>
      'cat "\$HOME/${metaPath(vaultId)}" 2>/dev/null || true';

  static String listVaults() =>
      'cd $_dir 2>/dev/null || exit 0; '
      'for f in *.meta; do [ -f "\$f" ] && echo "\${f%.meta}"; done; true';

  /// Moves this device's uploads into place if the meta version is still
  /// [expectedVersion]: exit 0 when committed, 3 when another device won
  /// the race, 75 when the lock stayed busy. A lock older than two
  /// minutes (a push that died halfway) is broken.
  static String commit(String vaultId, String deviceId, int expectedVersion) {
    final v = _checkedId(vaultId);
    final bundleTmp = '$v.bundle.${_checkedId(deviceId)}.tmp';
    final metaTmp = '$v.meta.$deviceId.tmp';
    return [
      'cd $_dir || exit 4',
      'if [ -n "\$(find $v.lock -maxdepth 0 -mmin +2 2>/dev/null)" ]; '
          'then rmdir $v.lock 2>/dev/null; fi',
      'i=0',
      'until mkdir $v.lock 2>/dev/null; do '
          'i=\$((i+1)); [ "\$i" -ge 10 ] && exit 75; sleep 1; done',
      'cur=0',
      'if [ -f $v.meta ]; then '
          'cur=\$(sed -n \'s/^{"version":\\([0-9][0-9]*\\).*/\\1/p\' $v.meta); '
          '[ -n "\$cur" ] || cur=unknown; fi',
      'if [ "\$cur" != "$expectedVersion" ]; then '
          'rm -f $bundleTmp $metaTmp; rmdir $v.lock; exit 3; fi',
      'mv -f $bundleTmp $v.bundle && mv -f $metaTmp $v.meta',
      'status=\$?',
      'rmdir $v.lock',
      'exit \$status',
    ].join('\n');
  }

  static String deleteVault(String vaultId) {
    final v = _checkedId(vaultId);
    return 'cd $_dir 2>/dev/null || exit 0; rm -f $v.bundle $v.meta; '
        'rm -f $v.*.tmp; rmdir $v.lock 2>/dev/null; true';
  }

  /// A device name safe for a key comment: letters, digits, space, dot,
  /// dash and underscore, at most 40 characters.
  static String sanitizeDeviceName(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final short = cleaned.length > 40
        ? cleaned.substring(0, 40).trim()
        : cleaned;
    return short.isEmpty ? 'device' : short;
  }

  /// `(type, base64)` of an OpenSSH public key, or throws for anything
  /// else (so a malformed key never becomes a grep pattern).
  static (String, String) splitPublicKey(String publicKey) {
    final parts = publicKey.trim().split(RegExp(r'\s+'));
    if (parts.length < 2 ||
        !_keyType.hasMatch(parts[0]) ||
        !_keyData.hasMatch(parts[1])) {
      throw ArgumentError.value(publicKey, 'publicKey', 'not an SSH key');
    }
    return (parts[0], parts[1]);
  }

  static String authorizedKeyLine(String publicKey, String name) {
    final (type, data) = splitPublicKey(publicKey);
    return '$type $data $deviceComment ${sanitizeDeviceName(name)}';
  }

  /// Appends the device's key unless its key material is already there,
  /// first ending an unterminated last line so the keys never run together.
  static String addAuthorizedKey(String publicKey, String name) {
    final (_, data) = splitPublicKey(publicKey);
    final line = authorizedKeyLine(publicKey, name);
    const f = _authorizedKeys;
    return [
      'umask 077',
      r'mkdir -p "$HOME/.ssh"',
      'touch $f',
      'if grep -qF ${quote(data)} $f; then exit 0; fi',
      'if [ -s $f ] && [ -n "\$(tail -c 1 $f)" ]; then printf \'\\n\' >> $f; fi',
      "printf '%s\\n' ${quote(line)} >> $f",
    ].join('\n');
  }

  /// Drops every line carrying the key material, keeping the file's
  /// permissions (rewritten in place, not replaced).
  static String removeAuthorizedKey(String publicKey) {
    final (_, data) = splitPublicKey(publicKey);
    const f = _authorizedKeys;
    const tmp = r'"$HOME/.ssh/authorized_keys.conductore.tmp"';
    return [
      '[ -f $f ] || exit 0',
      'grep -qF ${quote(data)} $f || exit 0',
      '{ grep -vF ${quote(data)} $f || true; } > $tmp',
      'cat $tmp > $f',
      'rm -f $tmp',
    ].join('\n');
  }

  static String listAuthorizedKeys() =>
      'grep -F ${quote(deviceComment)} $_authorizedKeys 2>/dev/null || true';

  static List<AuthorizedDeviceKey> parseAuthorizedKeys(String output) {
    final keys = <AuthorizedDeviceKey>[];
    for (final line in output.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      final marker = parts.indexOf(deviceComment);
      if (marker < 2) continue;
      final type = parts[marker - 2];
      final data = parts[marker - 1];
      if (!_keyType.hasMatch(type) || !_keyData.hasMatch(data)) continue;
      keys.add(
        AuthorizedDeviceKey(
          publicKey: '$type $data',
          name: parts.skip(marker + 1).join(' '),
        ),
      );
    }
    return keys;
  }
}
