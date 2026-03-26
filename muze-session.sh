#!/bin/bash
# ============================================================
# MUZE Autonomous Improvement Session
# Runs 1 AM — 8 AM, 30-min cycles with versioned snapshots
# ============================================================

DESKTOP="$HOME/Desktop"
WORKING="$DESKTOP/Muze-sprint"
SOURCE="$HOME/code/Muze"
MISSION="$SOURCE/muze-mission.md"
LOGFILE="$DESKTOP/muze-session-log.txt"
LOCKFILE="/tmp/muze-session.lock"
CLAUDE="$HOME/.local/bin/claude"
END_HOUR=8
CYCLE_SECONDS=1800    # 30 minutes per cycle
SESSION_SECONDS=1500  # 25 minutes max per Claude session

# ---- Prevent overlapping sessions ----
if [ -f "$LOCKFILE" ] && kill -0 "$(cat "$LOCKFILE" 2>/dev/null)" 2>/dev/null; then
    echo "$(date): Session already running, exiting" >> "$LOGFILE"
    exit 1
fi
echo $$ > "$LOCKFILE"
trap 'rm -f "$LOCKFILE"; kill 0 2>/dev/null' EXIT

# ---- Keep Mac awake for the duration ----
caffeinate -dimsu -w $$ &

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" | tee -a "$LOGFILE"
}

log "==========================================="
log "  MUZE IMPROVEMENT SESSION START"
log "==========================================="

# ---- Verify Claude CLI works ----
if ! "$CLAUDE" --version > /dev/null 2>&1; then
    log "ERROR: Claude CLI not working at $CLAUDE"
    exit 1
fi
log "Claude CLI: $("$CLAUDE" --version)"

# ---- Capture starting usage for budget tracking ----
# The agent will check this against live usage via Chrome
# We store it so every session in tonight's loop knows the baseline
NIGHT_START_USAGE_FILE="$WORKING/.night_start_usage"
if [ ! -f "$NIGHT_START_USAGE_FILE" ]; then
    # First session of the night — agent will record actual % via Chrome
    # Default to "unknown" — agent must check and record it
    echo "unknown" > "$NIGHT_START_USAGE_FILE"
    log "Night start usage: will be recorded by first session via Chrome"
else
    log "Night start usage file exists: $(cat "$NIGHT_START_USAGE_FILE")"
fi
NIGHT_START_USAGE=$(cat "$NIGHT_START_USAGE_FILE")

# ---- Initialize working directory (first run only) ----
if [ ! -d "$WORKING" ]; then
    cp -r "$SOURCE" "$WORKING"
    rm -rf "$WORKING/.git" "$WORKING/.DS_Store" "$WORKING/research" "$WORKING/muze-session.sh" "$WORKING/muze-mission.md"
    log "Created working directory from source"
fi

# ---- Ensure PROGRESS.md exists ----
if [ ! -f "$WORKING/PROGRESS.md" ]; then
    cat > "$WORKING/PROGRESS.md" << 'EOF'
# MUZE Improvement Progress

## Design Principles
- GarageBand model: simple surface, infinite depth for pros
- Keep ALL existing features, add toggleable alternatives
- Always update tutorials after changes
- Primary: Chrome | Secondary: Safari, Desktop
- Splitting into multiple files (CSS, JS modules) is encouraged

## Completed Sessions
(none yet)

## Known Starting Features
- Camera-based instrument with Tone.js audio engine
- Touch drum zones (hat, snare, kick) with visual feedback
- Chord buttons bar at bottom
- Head tracking for filter/effect control
- Hand openness controls portamento/staccato
- Riser effect (hold + swipe up) with drum ducking
- Tape stop effect
- Video recording with audio capture
- Freeze button (locks current state)
- Multi-track recording output
- Drums tab with individual kick/snare/hat volume sliders
- Mode/scale selection HUD
- Start screen with title

## Next Priorities
Start with these, in order:
1. Polish UI/UX — improve visual design, animations, spacing
2. Improve code quality — refactor, organize, split files
3. Enhance audio — better synthesis, effects, mixing
4. Add customization — settings panel, presets, toggles
5. Expand tutorials — multiple levels, comprehensive guides
EOF
    log "Created initial PROGRESS.md"
fi

# ---- Ensure CHANGELOG.md exists ----
if [ ! -f "$WORKING/CHANGELOG.md" ]; then
    echo "# MUZE Changelog" > "$WORKING/CHANGELOG.md"
    echo "" >> "$WORKING/CHANGELOG.md"
    log "Created CHANGELOG.md"
fi

# ---- Version helper: find highest existing version number ----
next_ver() {
    local max=0
    for d in "$DESKTOP"/Muze-v[0-9]*; do
        [ -d "$d" ] || continue
        local num=$(basename "$d" | sed 's/^Muze-v//' | sed 's/^0*//')
        num=${num%%[^0-9]*}
        [ -n "$num" ] && [ "$num" -gt "$max" ] 2>/dev/null && max=$num
    done
    echo $((max + 1))
}

# ---- Main loop: 30-minute cycles ----
while true; do
    HOUR=$(date +%H | sed 's/^0//')

    # Stop if past end hour (but not if it's still "tonight" before midnight)
    if [ "$HOUR" -ge "$END_HOUR" ] && [ "$HOUR" -lt 20 ]; then
        log "Reached ${END_HOUR}:00 -- stopping for the night"
        break
    fi

    # Stop if agent flagged credits are low
    if [ -f "$WORKING/STOP" ]; then
        log "STOP file found -- agent signaled credits running low"
        rm -f "$WORKING/STOP"
        break
    fi

    CYCLE_START=$SECONDS

    # ---- Determine version ----
    VER=$(next_ver)
    VTAG=$(printf 'v%02d' "$VER")
    VDIR="$DESKTOP/Muze-$VTAG"

    # ---- Pre-session snapshot ----
    cp -r "$WORKING" "$VDIR"
    log "Snapshot saved: Muze-$VTAG"

    # ---- Compute time context for the agent ----
    NOW_H=$(date +%H | sed 's/^0//')
    NOW_M=$(date +%M | sed 's/^0//')
    if [ "$NOW_H" -lt "$END_HOUR" ]; then
        REMAINING=$(( (END_HOUR - NOW_H) * 60 - NOW_M ))
    else
        REMAINING=$(( (24 - NOW_H + END_HOUR) * 60 - NOW_M ))
    fi

    # ---- Build session prompt ----
    SESSION_PROMPT="$(cat "$MISSION")

--- SESSION CONTEXT ---
Version tag: $VTAG (this is session #$VER tonight)
Current time: $(date '+%H:%M %Z')
Session timeout: 25 minutes — budget your time wisely
Night ends at: ${END_HOUR}:00
Minutes remaining tonight: ~${REMAINING}
Working directory: $WORKING
NIGHT_START_USAGE: $NIGHT_START_USAGE
Budget per night: ~12% increase max. STOP if you exceed this.
If NIGHT_START_USAGE is 'unknown', you MUST check usage via Chrome immediately and write the percentage to $NIGHT_START_USAGE_FILE
---

Remember: Read PROGRESS.md first. Update it and CHANGELOG.md when done."

    # ---- Launch Claude Code session ----
    log "Starting Claude session for $VTAG..."
    cd "$WORKING"

    "$CLAUDE" -p "$SESSION_PROMPT" \
        --model opus \
        --effort max \
        --chrome \
        --dangerously-skip-permissions \
        --add-dir "$DESKTOP" \
        --name "muze-$VTAG" \
        >> "$LOGFILE" 2>&1 &

    CLAUDE_PID=$!

    # ---- Wait up to 25 minutes ----
    WAITED=0
    while kill -0 "$CLAUDE_PID" 2>/dev/null && [ "$WAITED" -lt "$SESSION_SECONDS" ]; do
        sleep 15
        WAITED=$((WAITED + 15))
    done

    # Kill if still running after timeout
    if kill -0 "$CLAUDE_PID" 2>/dev/null; then
        kill "$CLAUDE_PID" 2>/dev/null
        wait "$CLAUDE_PID" 2>/dev/null
        log "Session $VTAG killed after ${SESSION_SECONDS}s timeout"
    else
        wait "$CLAUDE_PID" 2>/dev/null
        EXIT_CODE=$?
        log "Session $VTAG completed (exit $EXIT_CODE)"
    fi

    # ---- Pad cycle to 30 minutes total ----
    CYCLE_ELAPSED=$((SECONDS - CYCLE_START))
    WAIT_REMAINING=$((CYCLE_SECONDS - CYCLE_ELAPSED))
    if [ "$WAIT_REMAINING" -gt 0 ]; then
        log "Waiting ${WAIT_REMAINING}s to pad cycle to 30 min..."
        sleep "$WAIT_REMAINING"
    fi
done

# ---- Final snapshot ----
FINAL_VER=$(next_ver)
FINAL_TAG=$(printf 'v%02d' "$FINAL_VER")
cp -r "$WORKING" "$DESKTOP/Muze-$FINAL_TAG"
log "Final snapshot: Muze-$FINAL_TAG"

# ---- Clean up night-start usage so tomorrow starts fresh ----
rm -f "$WORKING/.night_start_usage"

log "==========================================="
log "  MUZE IMPROVEMENT SESSION END"
log "==========================================="
