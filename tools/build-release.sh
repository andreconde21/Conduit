#!/usr/bin/env bash
# Builds signed release APKs from a clean tree and refuses to hand out an APK
# whose compiled Dart code is stale.
#
# Why: an incremental `flutter build apk --flavor full` once kept packaging the
# libapp.so from an earlier build (Gradle judged its merge/strip steps up to
# date), so several previews shipped identical app code with only a new
# version number. A clean build plus tools/verify-release-build.py (shared
# with .github/workflows/release.yml) prevent that.
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
tools/verify-release-build.py "$apk" ${previous:+"$previous"}
