import 'dart:convert';

import 'package:crypto/crypto.dart';

/// JSON with object keys sorted at every level, so equal values always
/// encode (and hash) the same way whatever order they were built in.
String canonicalJson(Object? value) => jsonEncode(_sorted(value));

/// SHA-256 of [canonicalJson], hex. Null (a missing value) hashes to null.
String? valueHash(Object? value) {
  if (value == null) return null;
  return sha256.convert(utf8.encode(canonicalJson(value))).toString();
}

Object? _sorted(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in keys) key: _sorted(value[key])};
  }
  if (value is List) {
    return [for (final item in value) _sorted(item)];
  }
  return value;
}
