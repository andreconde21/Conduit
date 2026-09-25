import 'dart:io';

import 'package:conduit/features/hosts/domain/saved_host.dart';

/// Words from the saved machines that crash reports must never carry:
/// labels, addresses, users, secrets, tags, tmux names, directories and
/// snippets. Read fresh for every report, so a machine added a minute ago
/// is covered.
Iterable<String> savedHostTerms(Iterable<SavedHost> hosts) sync* {
  for (final host in hosts) {
    yield host.name;
    yield host.host;
    yield host.username;
    yield host.password;
    yield host.passphrase;
    yield* host.tags;
    if (host.tmuxSessionName != defaultTmuxSessionName) {
      yield host.tmuxSessionName;
    }
    yield host.tmuxStartDirectory;
    yield host.shareInboxDirectory;
    for (final key in host.hardwareKeys) {
      yield key.label;
      yield key.passphrase;
    }
    for (final snippet in host.snippets) {
      yield snippet.label;
      yield snippet.text;
    }
  }
}

/// This device's own name and account, which show up in paths and in
/// "This computer".
Iterable<String> deviceTerms() sync* {
  try {
    yield Platform.localHostname;
    final env = Platform.environment;
    for (final key in const ['USER', 'USERNAME', 'LOGNAME']) {
      if (env[key] case final value?) yield value;
    }
  } on Object {
    // Not available on this platform.
  }
}
