#!/bin/bash

CONFIG_FILE="Helpers/config.json"
ROSTER_FILE="Helpers/assets.csv"
LOG_DIR="reports"
ATTEND_LOG="$LOG_DIR/attendance.log"
ABSENT_LOG="$LOG_DIR/absent.log"

if [ ! -d "$LOG_DIR" ]; then
    mkdir "$LOG_DIR"
fi

if [ ! -f "$ROSTER_FILE" ]; then
    echo "ERROR: Roster file not found: $ROSTER_FILE" >&2
    exit 1
fi

TOTAL_SESSIONS=$(grep -o '"total_sessions"[[:space:]]*:[[:space:]*[0-9]*' "$CONFIG_FILE" 2>/dev/null | grep -o '[0-9]*')
[ -z "$TOTAL_SESSIONS" ] && TOTAL_SESSIONS=10

WARNING_THRESH=$(grep -o '"warning"[[:space:]]*:[[:space:]]*[0-9]*' "$CONFIG_FILE" 2>/dev/null | grep -o '[0-9]*')
[ -z "$WARNING_THRESH" ] && WARNING_THRESH=70

FAILURE_THRESH=$(grep -o '"failure"[[:space:]]*:[[:space:]]*[0-9]*' "$CONFIG_FILE" 2>/dev/null | grep -o '[0-9]*')
[ -z "$FAILURE_THRESH" ] && FAILURE_THRESH=50

RUN_MODE=$(grep -o '"run_mode"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f4)
[ -z "$RUN_MODE" ] && RUN_MODE="dry_run"

TOTAL_STUDENTS=$(tail -n +2 "$ROSTER_FILE" | grep -v '^[[:space:]]*$' | wc -l)

TODAY=$(date +%Y-%m-%d)
TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S,%3N")

SESSION_HEADER="=== Session recorded $TIMESTAMP | total_sessions=$TOTAL_SESSIONS | mode=$RUN_MODE ==="
echo "$SESSION_HEADER" >> "$ATTEND_LOG"
echo "$SESSION_HEADER" >> "$ABSENT_LOG"

echo ""
echo "Today's session: $TOTAL_STUDENTS students, total_sessions=$TOTAL_SESSIONS"
echo ""

marked_count=0
absent_count=0

# Use awk to process CSV fields safely based on header positions
while IFS=',' read -r name email attend absent
do
    # Clean quotes and carriage returns
    name=$(echo "$name" | tr -d '"' | tr -d '\r' | xargs)
    email=$(echo "$email" | tr -d '"' | tr -d '\r' | xargs)
    attend=$(echo "$attend" | tr -d '"' | tr -d '\r' | xargs)

    [ -z "$name" ] || [ "$name" = "Names" ] && continue
    [[ ! "$attend" =~ ^[0-9]+$ ]] && attend=0

    while true; do
        read -p "Mark $name <$email> - [P]resent or [A]bsent? " answer </dev/tty
        answer=$(echo "$answer" | tr -d '\r' | tr '[:upper:]' '[:lower:]' | xargs)
        
        if [ "$answer" = "p" ] || [ "$answer" = "present" ] || [ "$answer" = "y" ] || [ "$answer" = "yes" ]; then
            present=true
            break
        elif [ "$answer" = "a" ] || [ "$answer" = "absent" ] || [ "$answer" = "n" ] || [ "$answer" = "no" ]; then
            present=false
            break
        else
            echo "  Please enter 'P' for present or 'A' for absent."
        fi
    done

    if [ "$present" = true ]; then
        status="PRESENT"
        new_attend=$((attend + 1))
    else
        status="ABSENT"
        new_attend=$attend
        absent_count=$((absent_count + 1))
    fi

    pct=$(awk "BEGIN { printf \"%.1f\", ($new_attend / $TOTAL_SESSIONS) * 100 }")

    level=""
    label=""
    is_failure=$(awk "BEGIN {print ($pct < $FAILURE_THRESH) ? 1 : 0}")
    is_warning=$(awk "BEGIN {print ($pct < $WARNING_THRESH) ? 1 : 0}")

    if [ "$is_failure" -eq 1 ]; then
        level="URGENT"
        label="below the failure threshold - will fail this class"
    elif [ "$is_warning" -eq 1 ]; then
        level="WARNING"
        label="below the warning threshold - please be careful"
    fi

    if [ -n "$level" ]; then
        echo "  -> ${pct}% attendance | $level: $label"
        suffix=" | $level: $label"
    else
        echo "  -> ${pct}% attendance | on track"
        suffix=""
    fi

    line="[$TIMESTAMP] $name <$email>: $status - attended $new_attend/$TOTAL_SESSIONS = ${pct}%${suffix}"
    echo "$line" >> "$ATTEND_LOG"

    if [ "$present" = false ]; then
        absent_line="[$TODAY] $name <$email> - absent (now ${pct}% attendance)${suffix}"
        echo "$absent_line" >> "$ABSENT_LOG"
        if [ "$RUN_MODE" = "live" ] && [ -n "$level" ]; then
            echo "  Logged alert for $name"
        fi
    fi

    marked_count=$((marked_count + 1))

done < <(tail -n +2 "$ROSTER_FILE")

echo ""
echo "Done. Marked $marked_count students, $absent_count absent. Logs: $ATTEND_LOG, $ABSENT_LOG"
