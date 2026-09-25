#!/usr/bin/env python3
"""Refuses a release APK or AAB whose compiled Dart code is stale.

Why: an incremental `flutter build apk --flavor full` once kept packaging
the libapp.so from an earlier build (Gradle judged its merge/strip steps up
to date), so several previews shipped identical app code with only a new
version number. tools/build-release.sh and the release workflow run this on
every artifact they publish.

Usage: tools/verify-release-build.py BUILD [PREVIOUS]
  BUILD     an .apk or .aab; its arm64-v8a libapp.so must contain strings
            that only exist in current sources
  PREVIOUS  optional .apk or .aab of the last published release; the new
            app code must not be byte-identical to it
"""
import hashlib
import sys
import zipfile

REQUIRED = ['Conductore', 'Agent hooks']


def app_code(path):
    """The arm64 libapp.so of an APK (lib/...) or an AAB (base/lib/...)."""
    with zipfile.ZipFile(path) as archive:
        for name in ('lib/arm64-v8a/libapp.so', 'base/lib/arm64-v8a/libapp.so'):
            if name in archive.namelist():
                return archive.read(name)
    sys.exit(f'{path}: no arm64-v8a libapp.so inside')


def present(code, text):
    # Dart stores a string with non-Latin-1 characters as UTF-16.
    return text.encode('latin1') in code or text.encode('utf-16-le') in code


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    build = sys.argv[1]
    previous = sys.argv[2] if len(sys.argv) == 3 else ''
    code = app_code(build)
    missing = [text for text in REQUIRED if not present(code, text)]
    if missing:
        sys.exit(f'stale build: {build} lacks {missing}')
    digest = hashlib.sha256(code).hexdigest()
    if previous:
        if hashlib.sha256(app_code(previous)).hexdigest() == digest:
            sys.exit(f'stale build: app code is identical to {previous}')
    print(f'verified {build}: libapp.so {len(code)} bytes, sha256 {digest[:16]}')


if __name__ == '__main__':
    main()
