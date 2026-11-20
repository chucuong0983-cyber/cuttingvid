#!/bin/bash
# Ham dung chung cho job.sh va transcribe.sh

fmt() { printf '%02d:%02d:%02d' $(($1 / 3600)) $(($1 % 3600 / 60)) $(($1 % 60)); }

# Moc bat dau (giay, tinh tu dau buoi live) cua 1 file do app tao ra.
#  - Phan chia nho: doc .scv_info trong thu muc "(chia nho)" -> start + (N-1) x so phut
#  - Ten co "(tu HH-MM-SS den ...)" hoac "cut HH-MM-SS den ..." -> HH:MM:SS
#  - Khong nhan ra -> 0
auto_offset() {
  local f="$1" dir bn st sp n re
  dir=$(dirname "$f"); bn=$(basename "$f")
  if [ -f "$dir/.scv_info" ]; then
    st=$(sed -n 's/^start=//p' "$dir/.scv_info" | head -n1)
    sp=$(sed -n 's/^split=//p' "$dir/.scv_info" | head -n1)
    # Moc bat dau that cua tung phan (ffmpeg ghi khi chia nho) -> chinh xac tung phan giay
    if [ -f "$dir/.scv_parts.csv" ]; then
      local t; t=$(awk -F, -v f="$bn" '$1 == f { printf "%d", $2 + 0.5; exit }' "$dir/.scv_parts.csv")
      if [ -n "$t" ]; then echo $(( ${st:-0} + t )); return; fi
    fi
    re=' ([0-9]+)\.[A-Za-z0-9]+$'
    if [[ "$bn" =~ $re ]]; then
      n=$((10#${BASH_REMATCH[1]}))
      echo $(( ${st:-0} + (n - 1) * ${sp:-0} * 60 )); return
    fi
  fi
  re='(tu|cut) ([0-9]+)-([0-9]{2})-([0-9]{2}) den'
  if [[ "$bn" =~ $re ]]; then
    echo $((10#${BASH_REMATCH[2]} * 3600 + 10#${BASH_REMATCH[3]} * 60 + 10#${BASH_REMATCH[4]})); return
  fi
  echo 0
}

# ---------- Tien do cho cua so app ----------
CVCONF="$HOME/Library/Application Support/StreamerCuttingVid"
# P PCT "nhan" "chi tiet": PCT 0-100, -1 = chua biet %, -2 = loi. Ghi vao progress.main (hoac .txt khi CV_PSLOT=txt)
P() {
  local f="$CVCONF/progress.${CV_PSLOT:-main}"
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" > "$f.t" 2>/dev/null && mv -f "$f.t" "$f"
}
# Ghi duong dan ket qua (de nut "Mo thu muc" trong app mo dung cho)
PRESULT() { printf '%s\n' "$1" > "$CVCONF/progress.result" 2>/dev/null; }
# Doc output cua yt-dlp / ffmpeg: in dong thuong, cap nhat % theo "xx%" hoac "time=HH:MM:SS" / tong so giay
ppipe() { # $1 nhan, $2 tong so giay (0 = chi theo %)
  local lab="$1" tot="${2:-0}" line pct last=-99 lastp=-99 re1='time=([0-9]+):([0-9]{2}):([0-9]{2})' re2='([0-9]+)(\.[0-9]+)?%'
  tr '\r' '\n' | { lp=""; while IFS= read -r line; do
    pct=""
    if [[ "$line" =~ $re1 ]] && [ "$tot" -gt 0 ] 2>/dev/null; then
      pct=$(( (10#${BASH_REMATCH[1]} * 3600 + 10#${BASH_REMATCH[2]} * 60 + 10#${BASH_REMATCH[3]}) * 100 / tot ))
    elif [[ "$line" == *'[download]'* ]] && [[ "$line" =~ $re2 ]]; then
      pct=${BASH_REMATCH[1]}
    fi
    if [ -z "$pct" ]; then [ -n "$line" ] && printf '%s\n' "$line"; continue; fi
    [ "$pct" -gt 100 ] && pct=100
    lp=$pct
    if [ $SECONDS -ge $((last + 1)) ]; then last=$SECONDS; P "$pct" "$lab" "$3"; fi
    if [ $SECONDS -ge $((lastp + 10)) ]; then lastp=$SECONDS; printf '%s\n' "$line"; fi
  done; [ -n "$lp" ] && P "$lp" "$lab" "$3"; }
}
