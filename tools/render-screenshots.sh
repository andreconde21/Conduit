#!/usr/bin/env bash
# Renders the README screenshots into docs/screenshots/ from the real app
# widgets with demo data (test/screenshots/readme_screenshots_test.dart),
# then shrinks any PNG over 400 KB to a 256-colour palette.
set -euo pipefail
cd "$(dirname "$0")/.."

flutter test --run-skipped --tags screenshots test/screenshots

python3 - <<'PY'
import os, glob
from PIL import Image
limit = 400 * 1024
for path in sorted(glob.glob('docs/screenshots/*.png')):
    if os.path.getsize(path) > limit:
        Image.open(path).convert('RGB').quantize(colors=256, method=Image.Quantize.MEDIANCUT).save(path, optimize=True)
    print(f'{path}: {os.path.getsize(path) // 1024} KB')
PY
