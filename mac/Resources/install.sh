#!/bin/bash
# Cai cong cu cho CuttingVid - KHONG can Homebrew (Homebrew da bo Mac chip Intel).
# Tai thang ban chay san vao ~/Library/Application Support/StreamerCuttingVid/bin
BIN="$HOME/Library/Application Support/StreamerCuttingVid/bin"
mkdir -p "$BIN"
export PATH="$BIN:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; C=$'\033[36m'; N=$'\033[0m'
clear
echo "${C}=== Cài công cụ cho CuttingVid by Louis Chu ===${N}"
ARCH=$(uname -m)
TMP=$(mktemp -d)
fail=0

dl() { curl -L --fail --progress-bar -o "$2" "$1"; }

echo; echo "${C}1/3  yt-dlp (tải video YouTube)...${N}"
if dl "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos" "$BIN/yt-dlp.new"; then
  mv "$BIN/yt-dlp.new" "$BIN/yt-dlp"; chmod +x "$BIN/yt-dlp"; xattr -c "$BIN/yt-dlp" 2>/dev/null
else echo "${R}   Lỗi tải yt-dlp${N}"; fail=1; fi

echo; echo "${C}2/3  ffmpeg + ffprobe (cắt video)...${N}"
if [ "$ARCH" = arm64 ] && command -v brew >/dev/null; then
  brew install ffmpeg || fail=1
else
  # evermeet.cx da dong (loi 410). Dung ban dung san tren GitHub, ban du phong: ffbinaries
  for t in ffmpeg ffprobe; do
    ok=0
    if dl "https://github.com/eugeneware/ffmpeg-static/releases/latest/download/$t-darwin-x64.gz" "$TMP/$t.gz" && gunzip -c "$TMP/$t.gz" > "$BIN/$t"; then ok=1
    elif dl "https://github.com/ffbinaries/ffbinaries-prebuilt/releases/download/v6.1/$t-6.1-macos-64.zip" "$TMP/$t.zip" && unzip -o -q "$TMP/$t.zip" -d "$BIN"; then ok=1; fi
    if [ $ok = 1 ]; then chmod +x "$BIN/$t"; xattr -c "$BIN/$t" 2>/dev/null; else echo "${R}   Lỗi tải $t${N}"; fail=1; fi
  done
fi

echo; echo "${C}3/3  deno (yt-dlp cần để đọc YouTube)...${N}"
if [ "$ARCH" = arm64 ]; then DZ=deno-aarch64-apple-darwin.zip; else DZ=deno-x86_64-apple-darwin.zip; fi
if dl "https://github.com/denoland/deno/releases/latest/download/$DZ" "$TMP/deno.zip" && unzip -o -q "$TMP/deno.zip" -d "$BIN"; then
  chmod +x "$BIN/deno"; xattr -c "$BIN/deno" 2>/dev/null
else echo "${Y}   Lỗi tải deno (vẫn dùng được, nhưng một số video YouTube có thể không đọc được)${N}"; fi
rm -rf "$TMP"

echo
if command -v yt-dlp >/dev/null && command -v ffmpeg >/dev/null && "$BIN/yt-dlp" --version >/dev/null 2>&1 && ffmpeg -version >/dev/null 2>&1; then
  echo "${G}XONG! yt-dlp $(yt-dlp --version), $(ffmpeg -version | head -n1 | cut -d' ' -f1-3)${N}"
  echo "${G}Đóng cửa sổ này rồi mở lại app.${N}"
  echo "${Y}(Phần phụ đề Whisper sẽ tự cài ở lần đầu bạn tick \"Xuất phụ đề txt\".)${N}"
  date +%s > "$HOME/Library/Application Support/StreamerCuttingVid/last_update"
else
  echo "${R}Có lỗi khi cài. Chụp màn hình cửa sổ này gửi lại để kiểm tra.${N}"
fi
