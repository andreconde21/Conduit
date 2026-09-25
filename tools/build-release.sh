#!/usr/bin/env bash
# Builds signed release APKs from a clean tree and refuses to hand out an APK
# whose compiled Dart code is stale.
#
# Why: an incremental `flutter build apk --flavor full` once kept packaging the
# libapp.so from an earlier build (Gradle judged its merge/strip steps up to
# date), so several previews shipped identical app code with only a new
# version number. A clean build plus the checks below prevent that.
#
# Usage: tools/build-release.sh [previous-release.apk]
#   The optional APK is the last published release; the new arm64 build must
#   not contain byte-identical app code.
set -euo pipefail
cd "$(dirname "$0")/.."

previous="${1:-}"

flutter clean >/dev/null
flutter pub get >/dev/null
flutter build apk --release --flavor full --split-per-abi

apk=build/app/outputs/flutter-apk/app-arm64-v8a-full-release.apk
python3 - "$apk" "$previous" <<'EOF'
import hashlib, sys, zipfile

apk, previous = sys.argv[1], sys.argv[2]
code = zipfile.ZipFile(apk).read('lib/arm64-v8a/libapp.so')

# Strings that only exist in current sources; Dart stores a string with
# non-Latin-1 characters as UTF-16, so check both encodings.
def present(text):
    return text.encode('latin1') in code or text.encode('utf-16-le') in code

required = ['Conductore', 'Agent hooks']
missing = [text for text in required if not present(text)]
if missing:
    sys.exit(f'stale build: {apk} lacks {missing}')

if previous:
    old = zipfile.ZipFile(previous).read('lib/arm64-v8a/libapp.so')
    if hashlib.sha256(old).digest() == hashlib.sha256(code).digest():
        sys.exit(f'stale build: app code is identical to {previous}')

print(f'verified {apk}: libapp.so {len(code)} bytes, '
      f'sha256 {hashlib.sha256(code).hexdigest()[:16]}')
EOF
