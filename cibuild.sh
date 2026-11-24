#!/bin/bash
set -e
root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
python=python3
if [ -n "${MSYSTEM:-}" ]; then
    python=/usr/bin/python3
fi
exec "${PYTHON:-${python}}" -B "${root}/native_build/main.py" "$@"
