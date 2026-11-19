#!/bin/bash
# Chay trong Terminal:
# bash job.sh TYPE URL DIR FROM TO FROMTXT TOTXT H EXACT SPLITMIN NAME FNEG TNEG TXT TEND   (TYPE: audio | both; TEND=1: "den" = het / hien tai)
export PATH="$HOME/Library/Application Support/StreamerCuttingVid/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
TYPE="$1"; URL="$2"; DIR="$3"; FROM="$4"; TO="$5"; FROMTXT="$6"; TOTXT="$7"
H="$8"; EXACT="$9"; SPLIT="${10}"; NAME="${11}"; FNEG="${12}"; TNEG="${13}"; TXT="${14:-0}"; TEND="${15:-0}"
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/common.sh"
CONF="$HOME/Library/Application Support/StreamerCuttingVid"
mkdir -p "$CONF"; echo $$ > "$CONF/running"
trap 'rm -f "$CONF/running"' EXIT
cd "$DIR" || { echo "Không mở được thư mục: $DIR"; exit 1; }
clear
printf '\033]0;Streamer CuttingVid - cắt %s đến %s\007' "$FROMTXT" "$TOTXT"
EXT=mp4; [ "$TYPE" = audio ] && EXT=mp3
STAMP=$(date +%Y%m%d_%H%M%S)
G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; C=$'\033[36m'; N=$'\033[0m'
FF=(-hide_banner -loglevel error -stats -y)
SAFE=(--sleep-requests 1 --retry-sleep exp=1:30 --retry-sleep fragment:exp=1:30 --fragment-retries 10)
if [ "$EXACT" = 1 ]; then
  VENC=(-c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p); AENC=(-c:a aac -b:a 192k)
else
  VENC=(-c:v copy); AENC=(-c:a copy)
fi

fsize() { stat -f%z "$1" 2>/dev/null || stat -c%s "$1" 2>/dev/null || echo 0; }

done_ok() { # $1 = ten file
  echo; echo "${G}XONG! File: $DIR/$1${N}"
  if [ "${SPLIT:-0}" -gt 0 ] 2>/dev/null; then
    base="$OUTNAME"; [ -n "$NAME" ] && base="$NAME"
    pd="$DIR/$base (chia nho)"; mkdir -p "$pd"
    printf 'start=%s\nsplit=%s\n' "$ABSFROM" "$SPLIT" > "$pd/.scv_info"
    echo "${C}Đang chia nhỏ mỗi phần $SPLIT phút...${N}"
    pat="$pd/${base//%/%%} %02d.$EXT"
    ffmpeg -hide_banner -loglevel error -y -i "$DIR/$1" -map 0 -c copy -f segment -segment_time $((SPLIT * 60)) -segment_start_number 1 -reset_timestamps 1 -segment_list "$pd/.scv_parts.csv" -segment_list_type csv "$pat"
    n=$(ls "$pd" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$n" -gt 0 ]; then
      echo "${G}Đã chia thành $n phần trong thư mục: $pd${N}"
      echo "${Y}Phần số N bắt đầu ở phút (N-1) x $SPLIT tính từ đầu file.${N}"
      if [ "$TXT" = 1 ]; then
        echo; echo "${C}Đang tạo phụ đề cho từng phần...${N}"
        parts=(); for pf in "$pd"/*; do [ -f "$pf" ] && case "$pf" in *.txt|*.srt) ;; *) parts+=("$pf");; esac; done
        bash "$HERE/transcribe.sh" small.en auto "${parts[@]}"
      fi
      open "$pd"; return
    fi
    echo "${R}Chia nhỏ bị lỗi, file đầy đủ vẫn còn nguyên.${N}"
  fi
  if [ "$TXT" = 1 ]; then echo; echo "${C}Đang tạo phụ đề...${N}"; bash "$HERE/transcribe.sh" small.en "$ABSFROM" "$DIR/$1"; fi
  open -R "$DIR/$1"
}
hints() {
  echo "${Y}- Nếu thấy lỗi 429 / \"not a bot\": YouTube đang chặn tạm mạng của bạn. Đợi vài tiếng hoặc đổi mạng (4G) rồi thử lại.${N}"
  echo "${Y}- Có thể streamer tắt tua lại (DVR). Khi đó chỉ lấy được sau khi live xong.${N}"
  echo "${Y}- Thử cập nhật yt-dlp: mở Terminal và chạy  yt-dlp -U${N}"
}

# ---------- Nhan dien nguon ----------
STATUS=""; RTS=""
if [[ "$URL" != http* ]] && [ -f "$URL" ]; then
  STATUS=local
else
  echo "${C}Đang kiểm tra link...${N}"
  info=$(yt-dlp --no-warnings --print live_status --print release_timestamp --print duration "$URL" 2>"$CONF/err.txt")
  STATUS=$(echo "$info" | sed -n 1p | tr -d '[:space:]')
  RTS=$(echo "$info" | sed -n 2p | tr -d '[:space:]')
  VDUR=$(echo "$info" | sed -n 3p | tr -d '[:space:]')
  if [ -z "$STATUS" ] && ! grep -qiE 'not a bot|429|Private video|unavailable|does not exist' "$CONF/err.txt"; then
    echo "${Y}Không đọc được link, đang tự cập nhật yt-dlp rồi thử lại...${N}"
    yt-dlp -U >/dev/null 2>&1
    info=$(yt-dlp --no-warnings --print live_status --print release_timestamp --print duration "$URL" 2>"$CONF/err.txt")
    STATUS=$(echo "$info" | sed -n 1p | tr -d '[:space:]')
    RTS=$(echo "$info" | sed -n 2p | tr -d '[:space:]')
    VDUR=$(echo "$info" | sed -n 3p | tr -d '[:space:]')
  fi
  [ -z "$STATUS" ] && tail -n 4 "$CONF/err.txt"
fi

# ---------- Doi moc so am ----------
OK=1
if [ -n "$STATUS" ] && [ "$TEND" = 1 ]; then   # o "den" de trong
  if [ "$STATUS" = local ]; then
    TO=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$URL" 2>/dev/null | cut -d. -f1)
  elif [ "$STATUS" = is_live ] || [ "$STATUS" = post_live ]; then
    TNEG=1; TO=0
  else
    TO="${VDUR%%.*}"
  fi
  if ! [[ "$TO" =~ ^[0-9]+$ ]]; then echo "${R}Không biết độ dài video. Hãy nhập ô \"đến\".${N}"; OK=0; TO=0; fi
fi
if [ $OK = 1 ] && [ -n "$STATUS" ] && { [ "$FNEG" = 1 ] || [ "$TNEG" = 1 ]; }; then
  if { [ "$STATUS" != is_live ] && [ "$STATUS" != post_live ]; } || ! [[ "$RTS" =~ ^[0-9]+$ ]]; then
    echo "${R}Mốc số âm (-) chỉ dùng được khi video ĐANG LIVE. Video này đã xong: hãy nhập số dương tính từ đầu video.${N}"; OK=0
  else
    EDGE=$(( $(date +%s) - RTS - 8 ))   # YouTube phat cham hon thuc te vai giay
    [ "$FNEG" = 1 ] && FROM=$((EDGE - FROM))
    [ "$TNEG" = 1 ] && TO=$((EDGE - TO))
    [ "$FROM" -lt 0 ] && FROM=0
    echo "${C}Live đã chạy khoảng $(fmt $EDGE). Đổi ra mốc tính từ đầu live: $(fmt $FROM) đến $(fmt $TO)${N}"
    if [ "$TO" -le "$FROM" ]; then echo "${R}Mốc \"đến\" phải sau mốc \"từ\".${N}"; OK=0; fi
  fi
fi
DUR=$((TO - FROM))
SRCOFF=0; [ "$STATUS" = local ] && SRCOFF=$(auto_offset "$URL")
ABSFROM=$((FROM + SRCOFF)); ABSTO=$((TO + SRCOFF))
TAG="$(fmt $ABSFROM | tr : -) den $(fmt $ABSTO | tr : -)"
if [ -n "$NAME" ]; then OUTNAME="$NAME (tu $TAG)"; else OUTNAME="cut $TAG $STAMP"; fi
[ -e "$OUTNAME.$EXT" ] && OUTNAME="$OUTNAME $STAMP"

if [ -z "$STATUS" ]; then
  echo "${R}Không đọc được link. Kiểm tra lại link YouTube.${N}"; hints

elif [ $OK = 0 ]; then
  hints

elif [ "$STATUS" = local ]; then
  # ---- FILE CO SAN TREN MAY ----
  echo "${C}File trên máy: $URL${N}"
  echo "${C}Đang cắt đoạn $(fmt $FROM) đến $(fmt $TO) ...${N}"
  out="$OUTNAME.$EXT"
  if [ "$TYPE" = audio ]; then
    ffmpeg "${FF[@]}" -ss "$FROM" -i "$URL" -t "$DUR" -vn -c:a libmp3lame -q:a 0 "$out"
  else
    SRCH=$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$URL" 2>/dev/null | head -n1 | tr -dc '0-9')
    SRCH=${SRCH:-0}
    if [ "$EXACT" != 1 ] && { [ "$SRCH" -eq 0 ] || [ "$SRCH" -le "$H" ]; }; then
      ffmpeg "${FF[@]}" -ss "$FROM" -i "$URL" -t "$DUR" -map '0:v:0?' -map '0:a:0?' -c copy "$out"
    else
      VF=(); if [ "$SRCH" -gt "$H" ]; then VF=(-vf "scale=-2:$H"); echo "${Y}Thu nhỏ từ ${SRCH}p xuống ${H}p...${N}"; fi
      ffmpeg "${FF[@]}" -ss "$FROM" -i "$URL" -t "$DUR" -map '0:v:0?' -map '0:a:0?' "${VF[@]}" -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -c:a aac -b:a 192k "$out"
    fi
  fi
  if [ "$(fsize "$out")" -gt 1000 ]; then done_ok "$out"; else echo "${R}Cắt file bị lỗi. Chụp màn hình cửa sổ này để kiểm tra.${N}"; fi

elif [ "$STATUS" = is_live ] || [ "$STATUS" = post_live ]; then
  # ---- DANG LIVE: tai tu dau live toi moc "den" (file am thanh lam dong ho), roi cat ----
  base="_tam_scv_$STAMP"
  limit=$((16500 * (TO + 40)))
  sel='140/bestaudio'
  [ "$TYPE" != audio ] && sel="bv*[height<=$H][vcodec^=avc1]+140/bv*[height<=$H]+140/bv*+ba"
  echo "${C}Video ĐANG LIVE.${N}"
  echo "${C}Bước 1/2: tải từ đầu buổi live đến mốc $(fmt $TO) ...${N}"
  echo "${Y}(đoạn càng xa đầu live càng lâu; nếu mốc \"đến\" chưa tới, app sẽ chờ live phát tới đó)${N}"
  yt-dlp --live-from-start "${SAFE[@]}" -f "$sel" --no-part --no-mtime -o "$base.%(ext)s" "$URL" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    sleep 2
    a=$(ls "$base"*.m4a 2>/dev/null | head -n1)
    if [ -n "$a" ] && [ "$(fsize "$a")" -ge "$limit" ]; then
      echo; echo "${C}Đã tải đủ, đang dừng tải...${N}"
      pkill -TERM -P "$pid" 2>/dev/null
      kill -TERM "$pid" 2>/dev/null
      break
    fi
  done
  wait "$pid" 2>/dev/null
  sleep 2
  aud=$(ls -S "$base"*.m4a 2>/dev/null | grep -v -e 'ytdl$' -e Frag | head -n1)
  vid=$(ls -S "$base"*.mp4 "$base"*.webm "$base"*.mkv 2>/dev/null | grep -v -e 'ytdl$' -e Frag | head -n1)
  src="$vid"; [ "$TYPE" = audio ] && src="$aud"
  echo
  if [ -z "$src" ] || [ "$(fsize "$src")" -lt 10000 ]; then
    echo "${R}Không tải được.${N}"; hints
  else
    echo "${C}Bước 2/2: cắt đoạn $(fmt $FROM) đến $(fmt $TO) ...${N}"
    out="$OUTNAME.$EXT"
    if [ "$TYPE" = audio ]; then
      ffmpeg "${FF[@]}" -ss "$FROM" -i "$aud" -t "$DUR" -vn -c:a libmp3lame -q:a 0 "$out"
    elif [ -n "$aud" ]; then
      ffmpeg "${FF[@]}" -ss "$FROM" -i "$vid" -ss "$FROM" -i "$aud" -t "$DUR" -map 0:v:0 -map 1:a:0 "${VENC[@]}" "${AENC[@]}" "$out"
    else
      ffmpeg "${FF[@]}" -ss "$FROM" -i "$vid" -t "$DUR" "${VENC[@]}" "${AENC[@]}" "$out"
    fi
    if [ "$(fsize "$out")" -gt 1000 ]; then
      rm -f "$base"*
      done_ok "$out"
    else
      echo "${R}Cắt file bị lỗi. Chụp màn hình cửa sổ này để kiểm tra.${N}"
    fi
  fi

else
  # ---- VIDEO THUONG / LIVE DA XONG: chi tai dung doan ----
  echo "${C}Video thường / live đã xong. Đang tải đoạn $(fmt $FROM) đến $(fmt $TO) ...${N}"
  o="${OUTNAME//%/%%}.%(ext)s"
  sec="*$FROM-$TO"
  FK=(); [ "$EXACT" = 1 ] && FK=(--force-keyframes-at-cuts)
  if [ "$TYPE" = audio ]; then
    yt-dlp -N 3 "${SAFE[@]}" -x --audio-format mp3 --audio-quality 0 --no-mtime --download-sections "$sec" -o "$o" "$URL"
  else
    yt-dlp -N 3 "${SAFE[@]}" "${FK[@]}" -f "bv*[height<=$H][vcodec^=avc1]+ba[ext=m4a]/bv*[height<=$H]+ba/b" --merge-output-format mp4 --no-mtime --download-sections "$sec" -o "$o" "$URL"
  fi
  f="$OUTNAME.$EXT"
  if [ -s "$f" ]; then done_ok "$f"; else echo "${R}Không tải được.${N}"; hints; fi
fi
echo
echo "Có thể đóng cửa sổ Terminal này."
