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
