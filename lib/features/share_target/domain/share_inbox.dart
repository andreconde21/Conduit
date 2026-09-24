import 'package:conduit/features/share_target/domain/shared_payload.dart';

/// Where shared files land on a host when the host has no own setting.
const defaultShareInboxDirectory = '~/conductore-inbox';

/// Turns the per-host inbox setting into an absolute remote directory.
///
/// SFTP has no notion of `~`, so the home directory resolved from the live
/// session is substituted: `''` and `~` mean the default inbox under home,
/// `~/x` and bare relative paths are taken relative to home, and absolute
/// paths are used as given. Trailing slashes are dropped.
String resolveShareInboxPath({
  required String configured,
  required String home,
}) {
  final trimmedHome = _stripTrailingSlash(home.trim());
  final base = trimmedHome.isEmpty ? '/' : trimmedHome;
  var value = configured.trim();
  if (value.isEmpty) {
    value = defaultShareInboxDirectory;
  }
  value = _stripTrailingSlash(value);
  if (value == '~') {
    return base;
  }
  if (value.startsWith('~/')) {
    return _join(base, value.substring(2));
  }
  if (value.startsWith('/')) {
    return value;
  }
  return _join(base, value);
}

/// Reduces a display name to something safe as a single remote path segment.
String sanitizeShareFileName(String name) {
  var cleaned = name
      .replaceAll(RegExp(r'[\\/\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  while (cleaned.startsWith('.')) {
    cleaned = cleaned.substring(1);
  }
  return cleaned.isEmpty ? 'shared' : cleaned;
}

/// Picks a name that does not collide with [existing] by inserting a
/// counter before the extension: `photo.jpg` -> `photo (2).jpg`.
String uniqueShareFileName(String name, Set<String> existing) {
  if (!existing.contains(name)) {
    return name;
  }
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final extension = dot > 0 ? name.substring(dot) : '';
  for (var counter = 2; ; counter += 1) {
    final candidate = '$stem ($counter)$extension';
    if (!existing.contains(candidate)) {
      return candidate;
    }
  }
}

/// The remote path a shared file is written to.
String shareRemotePath(String inbox, String fileName) => _join(inbox, fileName);

/// The Chat composer draft for a delivered share: shared text verbatim,
/// then one remote path per line so the user can add instructions above or
/// below. Nothing is quoted; paths with spaces are still readable by an
/// agent and the user can edit before sending.
String buildShareDraft({String? text, List<String> remotePaths = const []}) {
  final sections = <String>[];
  if (text != null && text.trim().isNotEmpty) {
    sections.add(text.trim());
  }
  if (remotePaths.isNotEmpty) {
    sections.add(remotePaths.join('\n'));
  }
  return sections.join('\n\n');
}

/// Appends a share draft to whatever the user already had in the composer.
String mergeShareDraft(String existing, String addition) {
  if (existing.trim().isEmpty) {
    return addition;
  }
  if (addition.isEmpty) {
    return existing;
  }
  final separator = existing.endsWith('\n') ? '\n' : '\n\n';
  return '$existing$separator$addition';
}

/// Remote names for a payload's files, deduplicated against the inbox
/// listing and against each other.
List<String> planShareFileNames(
  List<SharedFile> files,
  Set<String> existingNames,
) {
  final taken = Set<String>.from(existingNames);
  final names = <String>[];
  for (final file in files) {
    final name = uniqueShareFileName(sanitizeShareFileName(file.name), taken);
    taken.add(name);
    names.add(name);
  }
  return names;
}

String _stripTrailingSlash(String value) {
  var result = value;
  while (result.length > 1 && result.endsWith('/')) {
    result = result.substring(0, result.length - 1);
  }
  return result;
}

String _join(String parent, String child) {
  if (child.isEmpty) {
    return parent;
  }
  return parent == '/' ? '/$child' : '$parent/$child';
}
