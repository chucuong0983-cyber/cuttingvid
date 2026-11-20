#!/bin/bash
# Chay 1 luot o nen cho cua so app: bash run.sh <lenh ...>
# Khoa 1 luot (file running = PID nhom tien trinh), xoa tien do cu, bao xong vao progress.done
CONF="$HOME/Library/Application Support/StreamerCuttingVid"
mkdir -p "$CONF"; rm -f "$CONF"/progress.*
echo $$ > "$CONF/running"; export CV_RUNNER=1
trap 'rm -f "$CONF/running"' EXIT
"$@"; rc=$?
echo "$rc" > "$CONF/progress.done"
