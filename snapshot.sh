#!/usr/bin/env bash
# Snapshot the current Muze web app into versions/<NN>-<slug>/
# Usage: ./snapshot.sh <NN-slug> "One-line description"
set -euo pipefail
cd "$(dirname "$0")"

NAME="${1:?usage: snapshot.sh <NN-slug> \"description\"}"
DESC="${2:-}"
DEST="versions/$NAME"

mkdir -p "$DEST"
# Self-contained copy of the runnable web app
cp -R index.html guide.html errors.html manifest.json icon.svg "$DEST/" 2>/dev/null || true
cp -R js css "$DEST/"

# Syntax-check the snapshot's JS so we never freeze a broken build
bad=0
for f in "$DEST"/js/*.js; do
  node --check "$f" 2>/dev/null || { echo "WARN: syntax error in $f"; bad=$((bad+1)); }
done

cat > "$DEST/VERSION.txt" <<EOF
$NAME
$DESC
snapshot: $(date '+%Y-%m-%d %H:%M:%S')
js syntax errors: $bad
EOF

echo "Snapshot -> $DEST  (js errors: $bad)"
