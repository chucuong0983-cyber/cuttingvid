#!/bin/bash
# Tao phu de bang whisper.cpp (chay tren may, khong can mang tru lan dau tai model).
# bash transcribe.sh MODEL OFFSET file1 [file2 ...]
#   MODEL : groq (Groq API, can key) | fw-fast | fw-acc (faster-whisper tren may) | base.en | small.en (whisper.cpp)
#           Khong dung duoc engine da chon -> tu quay ve whisper.cpp
#   OFFSET: so giay cong vao moc trong txt, hoac "auto" (tu doan theo ten file / thu muc chia nho)
# Ra 2 file canh file goc: <ten>.txt  ([HH:MM:SS] cau noi, moc tinh tu dau buoi live)
#                          <ten>.srt  (moc tinh tu dau file, dung cho CapCut)
export PATH="$HOME/Library/Application Support/StreamerCuttingVid/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/common.sh"
MODEL="${1:-fw-fast}"; OFFMODE="${2:-auto}"; shift 2
export CV_PSLOT=txt
ENGINE=cpp; PYMODEL=""; CPPMODEL="$MODEL"
case "$MODEL" in
  groq)    ENGINE=groq; PYMODEL=whisper-large-v3-turbo; CPPMODEL=base.en;;
  fw-fast) ENGINE=fw;   PYMODEL=distil-small.en;        CPPMODEL=base.en;;
  fw-acc)  ENGINE=fw;   PYMODEL=small.en;               CPPMODEL=small.en;;
esac
command -v python3 >/dev/null || ENGINE=cpp
GPAUSE="$HOME/Library/Application Support/StreamerCuttingVid/.groq_pause"
if [ "$ENGINE" = groq ] && [ -n "$(find "$GPAUSE" -mmin -60 2>/dev/null)" ]; then
  echo "Groq vừa hết lượt miễn phí (<1 giờ trước): quét trên máy."; ENGINE=fw; PYMODEL=distil-small.en
fi
if [ "$ENGINE" = fw ] && ! python3 -c 'import faster_whisper' 2>/dev/null; then
  echo "Đang cài faster-whisper (chỉ lần đầu, 1-3 phút)..."
  python3 -m pip install --user --quiet faster-whisper 2>/dev/null || python3 -m pip install --user --quiet --break-system-packages faster-whisper 2>/dev/null
  python3 -c 'import faster_whisper' 2>/dev/null || { echo "Không cài được faster-whisper, dùng whisper.cpp."; ENGINE=cpp; }
fi
export CV_FFMPEG="$(command -v ffmpeg)" CV_FFPROBE="$(command -v ffprobe)"
G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; C=$'\033[36m'; N=$'\033[0m'
MD="$HOME/Library/Application Support/StreamerCuttingVid/models"
mkdir -p "$MD"

# --- whisper.cpp (tu build tren may, khong can Homebrew) ---
BIN="$HOME/Library/Application Support/StreamerCuttingVid/bin"; mkdir -p "$BIN"
build_whisper() {
  echo "${C}Lần đầu dùng: đang cài whisper.cpp (build trên máy, khoảng 5-10 phút, chỉ 1 lần)...${N}"
  if ! xcode-select -p >/dev/null 2>&1; then
    echo "${Y}Máy cần Command Line Tools của Apple. Một cửa sổ cài đặt sẽ hiện ra: bấm Install, cài xong thì chạy lại.${N}"
    xcode-select --install 2>/dev/null; return 1
  fi
  local CM; CM=$(command -v cmake)
  if [ -z "$CM" ]; then
    echo "${C}  Cài cmake...${N}"
    python3 -m pip install --user --quiet cmake 2>/dev/null || python3 -m pip install --user --quiet --break-system-packages cmake
    CM="$(python3 -m site --user-base)/bin/cmake"
  fi
  [ -x "$CM" ] || { echo "${R}Không cài được cmake.${N}"; return 1; }
  local W; W=$(mktemp -d)
  echo "${C}  Tải mã nguồn whisper.cpp...${N}"
  curl -L --fail --progress-bar "https://github.com/ggml-org/whisper.cpp/archive/refs/heads/master.tar.gz" | tar xz -C "$W" || { echo "${R}Tải mã nguồn lỗi.${N}"; return 1; }
  local SRC; SRC=$(ls -d "$W"/whisper.cpp-* | head -n1)
  echo "${C}  Đang build (vài phút)...${N}"
  "$CM" -S "$SRC" -B "$SRC/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=ON >/dev/null \
    && "$CM" --build "$SRC/build" --config Release -j "$(sysctl -n hw.ncpu)" --target whisper-cli >/dev/null \
    && cp "$SRC/build/bin/whisper-cli" "$BIN/whisper-cli" && chmod +x "$BIN/whisper-cli"
  rm -rf "$W"
  [ -x "$BIN/whisper-cli" ] || { echo "${R}Build whisper.cpp bị lỗi. Chụp màn hình gửi lại để kiểm tra.${N}"; return 1; }
  echo "${G}  Đã cài whisper.cpp.${N}"
}
CPPREADY=0
ensure_cpp() {
[ $CPPREADY = 1 ] && return 0
WB=$(command -v whisper-cli || command -v whisper-cpp)
if [ -z "$WB" ]; then build_whisper; WB=$(command -v whisper-cli); fi
[ -z "$WB" ] && return 1

# --- model ---
MF="$MD/ggml-$CPPMODEL.bin"
if [ ! -s "$MF" ]; then
  echo "${C}Lần đầu dùng: đang tải model $CPPMODEL (chỉ tải 1 lần)...${N}"
  if curl -L --fail --progress-bar -o "$MF.part" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$CPPMODEL.bin"; then
    mv "$MF.part" "$MF"
  else
    rm -f "$MF.part"; echo "${R}Tải model bị lỗi. Kiểm tra mạng rồi thử lại.${N}"; return 1
  fi
fi
# Model loc khoang lang (VAD) giup bot "bia chu" o doan chi co nhac / im lang
VADF="$MD/ggml-silero-v5.1.2.bin"
if [ ! -s "$VADF" ]; then
  curl -L --fail -s -o "$VADF.part" "https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin" && mv "$VADF.part" "$VADF"
  rm -f "$VADF.part"
fi
USEVAD=0
if [ -s "$VADF" ] && "$WB" --help 2>&1 | grep -q -- '--vad'; then USEVAD=1; fi
TH=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
CPPREADY=1
}

total=$#; i=0; okc=0
for IN in "$@"; do
  i=$((i + 1))
  [ -f "$IN" ] || { echo "${R}Không thấy file: $IN${N}"; continue; }
  dir=$(dirname "$IN"); bn=$(basename "$IN"); stem="${bn%.*}"; out="$dir/$stem"
  if [ "$OFFMODE" = auto ]; then OFF=$(auto_offset "$IN"); else OFF="$OFFMODE"; fi
  echo
  echo "${C}[$i/$total] Đang quét: $bn${N}"
  export CV_PBASE=$(( (i - 1) * 100 / total )) CV_PSPAN=$(( 100 / total )) CV_PLABEL="Phụ đề · phần $i/$total"
  P "$CV_PBASE" "$CV_PLABEL" "$bn"
  echo "${C}    Mốc trong txt sẽ tính từ $(fmt "$OFF") của buổi live${N}"
  if [ "$ENGINE" != cpp ]; then
    t0=$(date +%s)
    [ "$ENGINE" = groq ] && echo "${C}    Cách quét: Groq qua mạng (whisper-large-v3-turbo)${N}" || echo "${C}    Cách quét: faster-whisper trên máy ($PYMODEL)${N}"
    python3 "$HERE/asr.py" "$ENGINE" "$PYMODEL" "$IN" "$OFF" "$out"; rc=$?
    if [ $rc = 0 ] && [ -s "$out.txt" ]; then
      okc=$((okc + 1)); echo "${G}    Xong sau $(( $(date +%s) - t0 )) giây: $stem.txt${N}"; continue
    fi
    if [ "$ENGINE" = groq ]; then
      # Groq loi/het luot: cac file con lai (va 1 gio toi) quet tren may luon, khong thu Groq nua
      touch "$GPAUSE"; ENGINE=fw; PYMODEL=distil-small.en; JUSTGROQ=1
      python3 -c 'import faster_whisper' 2>/dev/null || python3 -m pip install --user --quiet faster-whisper >/dev/null 2>&1 || python3 -m pip install --user --quiet --break-system-packages faster-whisper >/dev/null 2>&1
      python3 -c 'import faster_whisper' 2>/dev/null || ENGINE=cpp
    fi
    if [ "$ENGINE" = fw ] && [ -n "$JUSTGROQ" ]; then
      JUSTGROQ=
      echo "${Y}    Groq không dùng được, chuyển sang faster-whisper trên máy...${N}"
      python3 "$HERE/asr.py" fw distil-small.en "$IN" "$OFF" "$out" && [ -s "$out.txt" ] && { okc=$((okc + 1)); echo "${G}    Xong: $stem.txt${N}"; continue; }
    fi
    echo "${Y}    Chuyển sang whisper.cpp...${N}"
  fi
  ensure_cpp || { echo "${R}    Không cài được whisper.cpp.${N}"; continue; }
  tmpd=$(mktemp -d); wav="$tmpd/a.wav"
  ffmpeg -hide_banner -loglevel error -y -i "$IN" -vn -ac 1 -ar 16000 -c:a pcm_s16le "$wav"
  if [ ! -s "$wav" ]; then echo "${R}    Không đọc được âm thanh của file này.${N}"; rm -rf "$tmpd"; continue; fi
  args=(-m "$MF" -f "$wav" -l en -t "$TH" -osrt -of "$out" -pp -np)
  [ $USEVAD = 1 ] && args+=(--vad -vm "$VADF")
  "$WB" "${args[@]}"
  if [ ! -s "$out.srt" ] && [ $USEVAD = 1 ]; then
    echo "${Y}    Thử lại không dùng lọc khoảng lặng...${N}"
    "$WB" -m "$MF" -f "$wav" -l en -t "$TH" -osrt -of "$out" -pp -np
  fi
  rm -rf "$tmpd"
  if [ ! -s "$out.srt" ]; then echo "${R}    Quét bị lỗi.${N}"; continue; fi
  {
    echo "# Phu de: $bn"
    echo "# Moc [HH:MM:SS] tinh tu dau buoi live (file nay bat dau o $(fmt "$OFF"))"
    awk -v off="$OFF" '
      /^[0-9]+:[0-9]+:[0-9]+,[0-9]+ --> / {
        split($1, a, /[:,]/); t = a[1] * 3600 + a[2] * 60 + a[3] + off
        ts = sprintf("[%02d:%02d:%02d]", int(t / 3600), int((t % 3600) / 60), t % 60)
        line = ""
        while ((getline nx) > 0 && nx != "") { gsub(/\r/, "", nx); line = (line == "" ? nx : line " " nx) }
        gsub(/^[ \t]+/, "", line)
        if (line != "") print ts " " line
      }' "$out.srt"
  } > "$out.txt"
  okc=$((okc + 1))
  echo "${G}    Xong: $stem.txt ($(grep -c '^\[' "$out.txt") câu)${N}"
done
echo
if [ $okc -gt 0 ]; then
  P 100 "Phụ đề xong" "$okc / $total file"; [ -n "$1" ] && PRESULT "$(dirname "$1")"
  echo "${G}XONG! Đã tạo phụ đề cho $okc / $total file (txt + srt nằm cạnh file gốc).${N}"
  echo "${Y}Gửi file .txt cho Claude để phân tích lời thoại.${N}"
  [ -n "$1" ] && [ -z "$CV_NOOPEN" ] && open -R "$(dirname "$1")/$(basename "${1%.*}").txt" 2>/dev/null
else
  echo "${R}Không tạo được phụ đề nào.${N}"; P -2 "Không tạo được phụ đề" "Bấm Xem chi tiết để xem lỗi"
fi
