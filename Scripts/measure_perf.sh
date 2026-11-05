#!/bin/bash
# Usage: measure_perf.sh <label> [extra app args...]
# Launches build/GlassCount.app with an isolated data dir, waits for warm-up, then reports
# average CPU over a 30 s window (delta of accumulated CPU time / wall time) and RSS.
set -u
cd "$(dirname "$0")/.."
LABEL=$1; shift
DIR=$(mktemp -d)
cputime() { ps -o time= -p "$1" | awk -F'[:.]' '{ if (NF==3) print $1*60+$2+$3/100; else print $1*3600+$2*60+$3+$4/100 }'; }
open -n build/GlassCount.app --args --data-dir "$DIR" --no-system-notifications "$@"
sleep 12
PID=$(pgrep -f "GlassCount.app/Contents/MacOS" | head -1)
[ -z "$PID" ] && { echo "$LABEL: process not running"; exit 1; }
C1=$(cputime $PID); sleep 30; C2=$(cputime $PID)
RSS=$(ps -o rss= -p $PID); 
echo "$LABEL: avgCPU=$(echo "($C2-$C1)/30*100" | bc -l | xargs printf '%.2f')%  rss=$((RSS/1024))MB  footprint=$(footprint $PID 2>/dev/null | grep -i 'phys_footprint:' | head -1)"
pkill -f "GlassCount.app/Contents/MacOS"
