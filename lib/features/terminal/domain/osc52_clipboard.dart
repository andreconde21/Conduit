import 'dart:convert';

/// Largest decoded clipboard payload accepted from the remote (1 MiB).
const osc52MaxBytes = 1024 * 1024;

/// Decodes the arguments of an OSC 52 ("manipulate selection data")
/// sequence, `ESC ] 52 ; <selection> ; <base64> BEL|ST`, as surfaced by the
/// terminal emulator: [args] is everything after the `52`, split on `;`.
///
/// Returns the text to put on the phone clipboard, or null when the
/// sequence must be ignored:
/// - a read request (`?`): answering would hand the phone clipboard to
///   whatever runs on the remote, so it is never honored;
/// - an empty payload (xterm's "clear selection"): the phone clipboard is
///   left alone rather than wiped by the remote;
/// - a payload over [maxBytes] once decoded, or one that is not valid
///   base64.
String? decodeOsc52Payload(List<String> args, {int maxBytes = osc52MaxBytes}) {
  if (args.isEmpty) {
    return null;
  }
  // `52;c;<data>` is the normal shape; `52;<data>` (selection omitted) is
  // tolerated. The data is always the last argument: base64 has no `;`.
  final raw = args.length == 1 ? args.first : args.last;
  final data = raw.replaceAll(RegExp(r'\s'), '');
  if (data.isEmpty || data == '?') {
    return null;
  }
  // Reject oversize payloads before decoding: 4 base64 chars per 3 bytes.
  if (data.length > ((maxBytes + 2) ~/ 3) * 4) {
    return null;
  }
  final List<int> bytes;
  try {
    bytes = base64.decode(base64.normalize(data));
  } on FormatException {
    return null;
  }
  if (bytes.isEmpty || bytes.length > maxBytes) {
    return null;
  }
  return utf8.decode(bytes, allowMalformed: true);
}
