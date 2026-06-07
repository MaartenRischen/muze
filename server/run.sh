#!/usr/bin/env bash
# Launch the Muze · Magenta RT2 streaming server.
# Uses the local venv if present, otherwise the system python.
#
#   ./run.sh                       # auto: real model if downloaded, else mock
#   ./run.sh --engine mock         # force the no-weights numpy mock
#   ./run.sh --model mrt2_base     # bigger/better model (M-Pro/Max class)
#   ./run.sh --serve-web           # also host the Muze web app on the same origin
set -euo pipefail
cd "$(dirname "$0")"

PY=".venv/bin/python"
[ -x "$PY" ] || PY="python3"

exec "$PY" magenta_server.py --serve-web "$@"
