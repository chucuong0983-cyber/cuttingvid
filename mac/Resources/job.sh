#!/bin/bash
# Chay trong Terminal:
# bash job.sh TYPE URL DIR FROM TO FROMTXT TOTXT H EXACT SPLITMIN NAME FNEG TNEG TXT TEND   (TYPE: audio | both; TEND=1: "den" = het / hien tai)
export PATH="$HOME/Library/Application Support/StreamerCuttingVid/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
TYPE="$1"; URL="$2"; DIR="$3"; FROM="$4"; TO="$5"; FROMTXT="$6"; TOTXT="$7"
H="$8"; EXACT="$9"; SPLIT="${10}"; NAME="${11}"; FNEG="${12}"; TNEG="${13}"; TXT="${14:-0}"; TEND="${15:-0}"; WMODEL="${16:-fw-fast}"
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
        CV_NOOPEN=1 bash "$HERE/transcribe.sh" "$WMODEL" auto "${parts[@]}"
      fi
      open "$pd"; return
    fi
    echo "${R}Chia nhỏ bị lỗi, file đầy đủ vẫn còn nguyên.${N}"
  fi
  if [ "$TXT" = 1 ]; then echo; echo "${C}Đang tạo phụ đề...${N}"; bash "$HERE/transcribe.sh" "$WMODEL" "$ABSFROM" "$DIR/$1"; fi
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
  # File tam: tieng = <base>.f140.* (khi tai ca hinh) hoac <base>.m4a (chi tieng); hinh = <base>.fNNN.* khac f140
  find_aud() { ls "$base".f140.* "$base".m4a 2>/dev/null | grep -v -e 'ytdl$' -e Frag | head -n1; }
  find_vid() { ls "$base".f*.* 2>/dev/null | grep -v -e '\.f140\.' -e 'ytdl$' -e Frag | head -n1; }
  # So giay hinh da tai: dem goi tin video / fps (doc file dang ghi, khong giai ma)
  vdur() {
    local n r
    n=$(ffprobe -v error -select_streams v:0 -count_packets -show_entries stream=nb_read_packets -of csv=p=0 "$1" 2>/dev/null | tr -dc '0-9')
    r=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 "$1" 2>/dev/null | head -n1)
    awk -v n="${n:-0}" -v r="$r" 'BEGIN { split(r, a, "/"); f = (a[2] > 0) ? a[1] / a[2] : a[1]; if (f <= 0) f = 30; printf "%d", n / f }'
  }
  adur() { # so giay tieng da tai
    local n r
    n=$(ffprobe -v error -select_streams a:0 -count_packets -show_entries stream=nb_read_packets -of csv=p=0 "$1" 2>/dev/null | tr -dc '0-9')
    r=$(ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of csv=p=0 "$1" 2>/dev/null | tr -dc '0-9')
    awk -v n="${n:-0}" -v r="${r:-44100}" 'BEGIN { if (r <= 0) r = 44100; printf "%d", n * 1024 / r }'
  }
  # --- Chia nho dan dan: tai du phan nao cat phan do, tao phu de phan do luon ---
  PROG=0; PNEXT=1; TPID=""
  if [ "${SPLIT:-0}" -gt 0 ] 2>/dev/null; then
    PROG=1
    pbase="$OUTNAME"; [ -n "$NAME" ] && pbase="$NAME"
    pd="$DIR/$pbase (chia nho)"; mkdir -p "$pd"
    printf 'start=%s\nsplit=%s\n' "$FROM" "$SPLIT" > "$pd/.scv_info"
    : > "$pd/.scv_parts.csv"; : > "$pd/.txt_queue"
    echo "${Y}Chia nhỏ mỗi $SPLIT phút: tải đủ phần nào app cắt phần đó ngay (thư mục: $pd)${N}"
  fi
  cut_parts() { # $1 = so giay da co (tinh tu dau live), $2 = 1 neu da tai xong
    local have=$1 fin=$2 ps pe pn pf a v
    while :; do
      ps=$((FROM + (PNEXT - 1) * SPLIT * 60)); [ $ps -ge $TO ] && return
      pe=$((ps + SPLIT * 60)); [ $pe -gt $TO ] && pe=$TO
      [ "$fin" != 1 ] && [ $((pe + 15)) -gt "$have" ] && return
      pn=$(printf '%02d' $PNEXT); pf="$pd/$pbase $pn.$EXT"
      a=$(find_aud); v=$(find_vid)
      if [ "$TYPE" = audio ]; then
        ffmpeg -hide_banner -loglevel error -y -ss "$ps" -i "$a" -t $((pe - ps)) -vn -c:a libmp3lame -q:a 0 "$pf"
      else
        ffmpeg -hide_banner -loglevel error -y -ss "$ps" -i "$v" -ss "$ps" -i "$a" -t $((pe - ps)) -map 0:v:0 -map 1:a:0 "${VENC[@]}" "${AENC[@]}" "$pf"
      fi
      if [ "$(fsize "$pf")" -gt 1000 ]; then
        echo "$pbase $pn.$EXT,$((ps - FROM))" >> "$pd/.scv_parts.csv"
        echo; echo "${G}>> Xong phần $pn ($(fmt $ps) - $(fmt $pe)): $pf${N}"
        [ "$TXT" = 1 ] && echo "$pf" >> "$pd/.txt_queue"
      else
        echo "${R}   Cắt phần $pn bị lỗi${N}"
      fi
      PNEXT=$((PNEXT + 1))
    done
  }
  txt_worker() { # tao phu de tung phan o nen, lan luot tung cai
    [ "$TXT" = 1 ] && [ "$PROG" = 1 ] || return
    if [ -n "$TPID" ] && kill -0 "$TPID" 2>/dev/null; then return; fi
    if [ -n "$TPID" ]; then
      [ -s "$TCUR" ] && [ -s "${TCUR%.*}.txt" ] && echo "${G}>> Xong phụ đề: ${TCUR%.*}.txt${N}"
      TPID=""
    fi
    [ -s "$pd/.txt_queue" ] || return
    TCUR=$(head -n1 "$pd/.txt_queue"); tail -n +2 "$pd/.txt_queue" > "$pd/.txt_queue.t"; mv "$pd/.txt_queue.t" "$pd/.txt_queue"
    echo "${C}>> Đang tạo phụ đề: $(basename "$TCUR") (chạy nền, log: .txt_log)${N}"
    CV_NOOPEN=1 bash "$HERE/transcribe.sh" "$WMODEL" auto "$TCUR" >> "$pd/.txt_log" 2>&1 &
    TPID=$!
  }
  need=$((TO + 20))
  aok=0; vok=0; [ "$TYPE" = audio ] && vok=1; tick=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep 2; tick=$((tick + 1))
    if [ $aok = 0 ]; then
      a=$(find_aud)
      if [ -n "$a" ] && [ "$(fsize "$a")" -ge "$limit" ]; then aok=1; [ $vok = 0 ] && { echo; echo "${C}Tiếng đã đủ, đang đợi phần hình tải tới $(fmt $TO)...${N}"; }; fi
    fi
    if [ $vok = 0 ] && [ $((tick % 15)) = 0 ]; then
      v=$(find_vid)
      if [ -n "$v" ]; then
        d=$(vdur "$v")
        [ "${d:-0}" -ge "$need" ] && vok=1
        [ $aok = 1 ] && [ $vok = 0 ] && echo "${Y}   Hình đã tải tới $(fmt ${d:-0}) / $(fmt $TO)${N}"
      fi
    fi
    if [ "$PROG" = 1 ] && [ $((tick % 30)) = 0 ]; then
      a=$(find_aud); have=0
      if [ -n "$a" ]; then
        have=$(adur "$a")
        if [ "$TYPE" != audio ]; then v=$(find_vid); hv=0; [ -n "$v" ] && hv=$(vdur "$v"); [ "$hv" -lt "$have" ] && have=$hv; fi
        cut_parts "$have" 0
      fi
    fi
    [ "$PROG" = 1 ] && txt_worker
    if [ $aok = 1 ] && [ $vok = 1 ]; then
      echo; echo "${C}Đã tải đủ cả hình và tiếng, đang dừng tải...${N}"
      pkill -TERM -P "$pid" 2>/dev/null
      kill -TERM "$pid" 2>/dev/null
      break
    fi
  done
  wait "$pid" 2>/dev/null
  sleep 2
  aud=$(find_aud)
  vid=$(find_vid)
  src="$vid"; [ "$TYPE" = audio ] && src="$aud"
  echo
  if [ -z "$src" ] || [ "$(fsize "$src")" -lt 10000 ]; then
    echo "${R}Không tải được.${N}"; hints
  elif [ "$PROG" = 1 ]; then
    echo "${C}Cắt các phần còn lại...${N}"
    cut_parts 999999 1
    if [ "$TXT" = 1 ]; then
      echo "${C}Đợi tạo xong phụ đề các phần còn lại (có thể lâu, đừng đóng cửa sổ)...${N}"
      while { [ -n "$TPID" ] && kill -0 "$TPID" 2>/dev/null; } || [ -s "$pd/.txt_queue" ]; do txt_worker; sleep 5; done
      txt_worker
    fi
    rm -f "$base"* "$pd/.txt_queue"
    n=$(ls "$pd"/*."$EXT" 2>/dev/null | wc -l | tr -d ' ')
    echo; echo "${G}XONG! $n phần trong thư mục: $pd${N}"
    [ "$TXT" = 1 ] && echo "${Y}Mỗi phần có file .txt cùng tên (mốc tính theo buổi live).${N}"
    open "$pd"
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
