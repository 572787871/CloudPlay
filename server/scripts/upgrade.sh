#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
# Review upstream releases and edit IMAGES in install.py to choose a new version.
python3 scripts/backup.py
python3 scripts/install.py "$@"
python3 scripts/verify.py
