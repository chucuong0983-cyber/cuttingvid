# CuttingVid by Louis Chu (Windows) - phan chay tai / cat / phu de. Chay trong cua so rieng.
# powershell -ExecutionPolicy Bypass -File job.ps1 -ParamFile <json>
param([string]$ParamFile)
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$P = Get-Content -LiteralPath $ParamFile -Raw -Encoding UTF8 | ConvertFrom-Json
Remove-Item -LiteralPath $ParamFile -Force -ErrorAction SilentlyContinue

$CONF = Join-Path $env:LOCALAPPDATA 'StreamerCuttingVid'
$BIN = Join-Path $CONF 'bin'
$MD = Join-Path $CONF 'models'
New-Item -ItemType Directory -Force -Path $BIN, $MD | Out-Null
$env:Path = "$BIN;$(Join-Path $BIN 'whisper');$env:Path"
$lock = Join-Path $env:APPDATA 'StreamerCuttingVid\running.txt'

$type = $P.type; $url = $P.url; $dir = $P.dir
$from = [int]$P.from; $to = [int]$P.to; $fromTxt = $P.fromTxt; $toTxt = $P.toTxt
$h = [int]$P.h; $exact = [bool]$P.exact; $split = [int]$P.split; $name = $P.name
$fneg = [bool]$P.fneg; $tneg = [bool]$P.tneg; $txt = [bool]$P.txt; $tend = [bool]$P.tend; $wmodel = $P.wmodel
if (-not $wmodel) { $wmodel = 'base.en' }
$ENG = 'cpp'; if ($wmodel -eq 'groq') { $ENG = 'groq'; $wmodel = 'base.en' }
$GKEY = Join-Path $env:APPDATA 'StreamerCuttingVid\groq_key.txt'
if ($ENG -eq 'groq' -and -not (Test-Path -LiteralPath $GKEY)) { $ENG = 'cpp' }
# Script Groq chay nen: cat 20 phut / doan -> gui Groq -> ghi .srt (moc tinh tu dau file)
$GROQPS = Join-Path $env:TEMP 'scv_groq.ps1'
$groqCode = @'
param([string]$In, [string]$Ob, [string]$KeyFile)
$ErrorActionPreference = 'Continue'
$key = (Get-Content -LiteralPath $KeyFile -Raw).Trim()
$hdr = Join-Path $env:TEMP ('scv_h_' + [guid]::NewGuid().ToString('N') + '.txt')
[IO.File]::WriteAllText($hdr, "Authorization: Bearer $key", (New-Object System.Text.UTF8Encoding($false)))
$dur = 0.0; [void][double]::TryParse(((& ffprobe -v error -show_entries format=duration -of csv=p=0 $In) | Select-Object -First 1), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$dur)
if ($dur -le 0) { $dur = 360000 }
function T([double]$x) { $ms = [int64][math]::Round($x * 1000); return ('{0:00}:{1:00}:{2:00},{3:000}' -f [math]::Floor($ms / 3600000), [math]::Floor(($ms % 3600000) / 60000), [math]::Floor(($ms % 60000) / 1000), ($ms % 1000)) }
$sb = New-Object System.Text.StringBuilder; $n = 0; $ok = $true
for ($st = 0; $st -lt $dur; $st += 600) {
    $mp3 = Join-Path $env:TEMP ('scv_g_' + [guid]::NewGuid().ToString('N') + '.mp3')
    $js = "$mp3.json"
    & ffmpeg -hide_banner -loglevel error -y -ss $st -t 600 -i $In -vn -ac 1 -ar 16000 -b:a 48k $mp3
    if (-not (Test-Path -LiteralPath $mp3) -or (Get-Item -LiteralPath $mp3).Length -lt 2000) { Remove-Item -LiteralPath $mp3 -ErrorAction SilentlyContinue; break }
    $got = $false
    for ($a = 1; $a -le 3 -and -not $got; $a++) {
        $code = & curl.exe -s -o $js -w '%{http_code}' -H "@$hdr" -F "file=@$mp3" --form-string 'model=whisper-large-v3-turbo' --form-string 'response_format=verbose_json' --form-string 'language=en' 'https://api.groq.com/openai/v1/audio/transcriptions'
        if ($code -eq '200') { $got = $true }
        elseif ($code -eq '401') { Write-Output 'Key Groq sai hoac het han.'; break }
        elseif ($a -lt 3) { Start-Sleep -Seconds (15 * $a) }
    }
    if (-not $got) { $ok = $false; Remove-Item -LiteralPath $mp3, $js -ErrorAction SilentlyContinue; break }
    $j = Get-Content -LiteralPath $js -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($g in $j.segments) {
        $t = ([string]$g.text).Trim(); if (-not $t) { continue }
        $n++; [void]$sb.Append("$n`n$(T ($st + [double]$g.start)) --> $(T ($st + [double]$g.end))`n$t`n`n")
    }
    Remove-Item -LiteralPath $mp3, $js -ErrorAction SilentlyContinue
}
Remove-Item -LiteralPath $hdr -ErrorAction SilentlyContinue
if ($ok) { [IO.File]::WriteAllText("$Ob.srt", $sb.ToString(), (New-Object System.Text.UTF8Encoding($false))); exit 0 }
exit 1
'@
[IO.File]::WriteAllText($GROQPS, $groqCode, (New-Object System.Text.UTF8Encoding($true)))
# yt-dlp can deno de doc link YouTube on dinh hon: tai 1 lan vao bin
if (($url -match '^https?://') -and -not (Test-Path -LiteralPath (Join-Path $BIN 'deno.exe'))) {
    Write-Host 'Lan dau: dang tai deno (giup yt-dlp doc YouTube on dinh)...' -ForegroundColor Cyan
    $dz = Join-Path $env:TEMP 'scv_deno.zip'
    & curl.exe -L --fail -s -o $dz 'https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip'
    if ($LASTEXITCODE -eq 0) { try { Expand-Archive -LiteralPath $dz -DestinationPath $BIN -Force } catch {} }
    Remove-Item -LiteralPath $dz -ErrorAction SilentlyContinue
}

$Host.UI.RawUI.WindowTitle = "CuttingVid - cat $fromTxt den $toTxt"
Set-Location -LiteralPath $dir
$ext = 'mp4'; if ($type -eq 'audio') { $ext = 'mp3' }
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$SAFE = '--sleep-requests 1 --retry-sleep exp=1:30 --retry-sleep fragment:exp=1:30 --fragment-retries 10'
$FF = @('-hide_banner', '-loglevel', 'error', '-stats', '-y')
if ($exact) { $VENC = @('-c:v', 'libx264', '-preset', 'veryfast', '-crf', '18', '-pix_fmt', 'yuv420p'); $AENC = @('-c:a', 'aac', '-b:a', '192k') }
else { $VENC = @('-c:v', 'copy'); $AENC = @('-c:a', 'copy') }

function Say([string]$t, [string]$c = 'Cyan') { Write-Host $t -ForegroundColor $c }
function Fmt($s) { $s = [math]::Max(0, [int]$s); return ('{0:00}:{1:00}:{2:00}' -f [math]::Floor($s / 3600), [math]::Floor(($s % 3600) / 60), ($s % 60)) }
function FSize([string]$p) {
    try { $fs = [System.IO.File]::Open($p, 'Open', 'Read', 'ReadWrite'); $n = $fs.Length; $fs.Close(); return $n } catch { return 0 }
}
function Hints {
    Say '- Neu thay loi 429 / "not a bot": YouTube dang chan tam mang cua ban. Doi vai tieng hoac doi mang (4G) roi thu lai.' Yellow
    Say '- Co the streamer tat tua lai (DVR). Khi do chi lay duoc sau khi live xong.' Yellow
    Say '- Thu bam dong "cap nhat yt-dlp" trong app roi tai lai.' Yellow
}
function PktCount([string]$f, [string]$sel) {
    $n = (& ffprobe -v error -select_streams $sel -count_packets -show_entries stream=nb_read_packets -of csv=p=0 $f 2>$null | Select-Object -First 1)
    if ($n -match '(\d+)') { return [double]$Matches[1] } return 0
}
function VDur([string]$f) {
    $n = PktCount $f 'v:0'
    $r = (& ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 $f 2>$null | Select-Object -First 1)
    $fps = 30.0
    if ($r -match '^(\d+)/(\d+)') { if ([double]$Matches[2] -gt 0) { $fps = [double]$Matches[1] / [double]$Matches[2] } }
    elseif ($r -match '^(\d+)') { $fps = [double]$Matches[1] }
    if ($fps -le 0) { $fps = 30 }
    return [int]($n / $fps)
}
function ADur([string]$f) {
    $n = PktCount $f 'a:0'
    $r = (& ffprobe -v error -select_streams a:0 -show_entries stream=sample_rate -of csv=p=0 $f 2>$null | Select-Object -First 1)
    $sr = 44100.0; if ($r -match '(\d+)') { $sr = [double]$Matches[1] }
    return [int]($n * 1024 / $sr)
}

# Moc bat dau (giay, tinh tu dau buoi live) cua 1 file do app tao ra
function Auto-Offset([string]$f) {
    $d = Split-Path -Parent $f; $bn = Split-Path -Leaf $f
    $info = Join-Path $d '.scv_info'
    if (Test-Path -LiteralPath $info) {
        $st = 0; $sp = 0
        foreach ($l in (Get-Content -LiteralPath $info)) { if ($l -match '^start=(\d+)') { $st = [int]$Matches[1] }; if ($l -match '^split=(\d+)') { $sp = [int]$Matches[1] } }
        $csv = Join-Path $d '.scv_parts.csv'
        if (Test-Path -LiteralPath $csv) {
            foreach ($l in (Get-Content -LiteralPath $csv -Encoding UTF8)) {
                $c = $l.Split(',')
                if ($c.Count -ge 2 -and $c[0] -eq $bn) { return $st + [int][math]::Round([double]::Parse($c[1], [Globalization.CultureInfo]::InvariantCulture)) }
            }
        }
        if ($bn -match ' (\d+)\.[A-Za-z0-9]+$') { return $st + ([int]$Matches[1] - 1) * $sp * 60 }
    }
    if ($bn -match '(tu|cut) (\d+)-(\d{2})-(\d{2}) den') { return [int]$Matches[2] * 3600 + [int]$Matches[3] * 60 + [int]$Matches[4] }
    return 0
}

# ---------- Phu de (whisper.cpp ban dung san cho Windows) ----------
$WHDIR = Join-Path $BIN 'whisper'
$WCLI = Join-Path $WHDIR 'whisper-cli.exe'
function Ensure-Whisper {
    if (-not (Test-Path -LiteralPath $WCLI)) {
        Say 'Lan dau dung phu de: dang tai whisper.cpp (vai MB)...'
        $z = Join-Path $env:TEMP 'scv_whisper.zip'; $x = Join-Path $env:TEMP 'scv_whisper_x'
        & curl.exe -L --fail --progress-bar -o $z 'https://github.com/ggml-org/whisper.cpp/releases/download/v1.8.2/whisper-bin-x64.zip'
        if (Test-Path -LiteralPath $x) { Remove-Item -LiteralPath $x -Recurse -Force }
        Expand-Archive -LiteralPath $z -DestinationPath $x -Force
        New-Item -ItemType Directory -Force -Path $WHDIR | Out-Null
        Get-ChildItem -LiteralPath $x -Recurse -File | Where-Object { $_.Extension -in '.exe', '.dll' } | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $WHDIR -Force }
        Remove-Item -LiteralPath $z, $x -Recurse -Force -ErrorAction SilentlyContinue
    }
    $script:MF = Join-Path $MD "ggml-$wmodel.bin"
    if (-not (Test-Path -LiteralPath $script:MF) -or (Get-Item -LiteralPath $script:MF).Length -lt 1000000) {
        Say "Lan dau dung model $wmodel`: dang tai (chi tai 1 lan)..."
        & curl.exe -L --fail --progress-bar -o "$($script:MF).part" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$wmodel.bin"
        if ($LASTEXITCODE -eq 0) { Move-Item -LiteralPath "$($script:MF).part" -Destination $script:MF -Force } else { Say 'Tai model loi.' Red; return $false }
    }
    $script:VADF = Join-Path $MD 'ggml-silero-v5.1.2.bin'
    if (-not (Test-Path -LiteralPath $script:VADF)) {
        & curl.exe -L --fail -s -o "$($script:VADF).part" 'https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin'
        if ($LASTEXITCODE -eq 0) { Move-Item -LiteralPath "$($script:VADF).part" -Destination $script:VADF -Force } else { Remove-Item -LiteralPath "$($script:VADF).part" -ErrorAction SilentlyContinue }
    }
    return (Test-Path -LiteralPath $WCLI)
}
# Bat dau quet 1 file o nen. Tra ve doi tuong de theo doi.
function Start-Whisper([string]$file, [int]$offset, [bool]$cpp = $false) {
    $ob = [IO.Path]::Combine((Split-Path -Parent $file), [IO.Path]::GetFileNameWithoutExtension($file))
    if ($ENG -eq 'groq' -and -not $cpp) {
        Remove-Item -LiteralPath "$ob.srt" -ErrorAction SilentlyContinue
        $ga = "-NoProfile -ExecutionPolicy Bypass -File `"$GROQPS`" -In `"$file`" -Ob `"$ob`" -KeyFile `"$GKEY`""
        $p = Start-Process powershell.exe -ArgumentList $ga -WindowStyle Hidden -PassThru
        return [pscustomobject]@{ proc = $p; file = $file; wav = $null; ob = $ob; off = $offset; groq = $true }
    }
    if (-not (Ensure-Whisper)) { return $null }
    $wav = Join-Path $env:TEMP ("scv_" + [guid]::NewGuid().ToString('N') + '.wav')
    & ffmpeg -hide_banner -loglevel error -y -i $file -vn -ac 1 -ar 16000 -c:a pcm_s16le $wav
    if (-not (Test-Path -LiteralPath $wav)) { Say "Khong doc duoc am thanh: $file" Red; return $null }
    $th = [Environment]::ProcessorCount
    $a = "-m `"$($script:MF)`" -f `"$wav`" -l en -t $th -osrt -of `"$ob`" -np"
    if (Test-Path -LiteralPath $script:VADF) { $a += " --vad -vm `"$($script:VADF)`"" }
    $log = Join-Path $env:TEMP 'scv_whisper_log.txt'
    $p = Start-Process -FilePath $WCLI -ArgumentList $a -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -RedirectStandardError "$log.err"
    return [pscustomobject]@{ proc = $p; file = $file; wav = $wav; ob = $ob; off = $offset; groq = $false }
}
# Doi ket thuc thi doi srt -> txt (moc tinh tu dau buoi live)
function Finish-Whisper($w) {
    if ($w.wav) { Remove-Item -LiteralPath $w.wav -Force -ErrorAction SilentlyContinue }
    $srt = "$($w.ob).srt"
    if ($w.groq -and -not (Test-Path -LiteralPath $srt)) {
        Say "   Groq het luot mien phi / loi mang: tu day quet tren may (khong thu Groq nua)." Yellow
        $script:ENG = 'cpp'
        $w2 = Start-Whisper $w.file $w.off $true
        if ($w2) { $w2.proc.WaitForExit(); Finish-Whisper $w2 }
        return
    }
    if (-not (Test-Path -LiteralPath $srt)) { Say "   Quet phu de loi: $(Split-Path -Leaf $w.file)" Red; return }
    $out = New-Object System.Collections.Generic.List[string]
    $out.Add("# Phu de: $(Split-Path -Leaf $w.file)")
    $out.Add("# Moc [HH:MM:SS] tinh tu dau buoi live (file nay bat dau o $(Fmt $w.off))")
    $lines = Get-Content -LiteralPath $srt -Encoding UTF8
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^(\d+):(\d+):(\d+),\d+ -->') {
            $t = [int]$Matches[1] * 3600 + [int]$Matches[2] * 60 + [int]$Matches[3] + $w.off
            $txtl = @(); $j = $i + 1
            while ($j -lt $lines.Count -and $lines[$j].Trim() -ne '') { $txtl += $lines[$j].Trim(); $j++ }
            $i = $j
            $s = ($txtl -join ' ').Trim()
            if ($s) { $out.Add("[$(Fmt $t)] $s") }
        }
    }
    [IO.File]::WriteAllLines("$($w.ob).txt", $out, (New-Object System.Text.UTF8Encoding($false)))
    Say ">> Xong phu de: $(Split-Path -Leaf $w.ob).txt ($($out.Count - 2) cau)" Green
}
# Quet lan luot (cho xong) - dung khi khong chia dan dan
function Transcribe-Files($files, $offsets) {
    if ($ENG -eq 'groq') { Say 'Cach quet: Groq qua mang (whisper-large-v3-turbo, rat nhanh)' } elseif (-not (Ensure-Whisper)) { return }
    for ($k = 0; $k -lt $files.Count; $k++) {
        Say "[$($k + 1)/$($files.Count)] Dang quet phu de: $(Split-Path -Leaf $files[$k]) (moc tu $(Fmt $offsets[$k]))"
        $w = Start-Whisper $files[$k] $offsets[$k]
        if ($w) { $w.proc.WaitForExit(); Finish-Whisper $w }
    }
}

function Done([string]$full) {
    Write-Host ''
    Say ("XONG! File: " + $full) Green
    if ($split -gt 0) {
        $pbase = $outName; if ($name) { $pbase = $name }
        $pd = Join-Path (Split-Path -Parent $full) ($pbase + ' (chia nho)')
        New-Item -ItemType Directory -Force -Path $pd | Out-Null
        Set-Content -LiteralPath (Join-Path $pd '.scv_info') -Value @("start=$absFrom", "split=$split") -Encoding ASCII
        Say "Dang chia nho moi phan $split phut..."
        $pat = Join-Path $pd (($pbase -replace '%', '%%') + ' %02d.' + $ext)
        & ffmpeg -hide_banner -loglevel error -y -i $full -map 0 -c copy -f segment -segment_time ($split * 60) -segment_start_number 1 -reset_timestamps 1 -segment_list (Join-Path $pd '.scv_parts.csv') -segment_list_type csv $pat
        $parts = @(Get-ChildItem -LiteralPath $pd -File -Filter "*.$ext" | Sort-Object Name)
        if ($parts.Count -gt 0) {
            Say "Da chia thanh $($parts.Count) phan trong thu muc: $pd" Green
            if ($txt) { Transcribe-Files @($parts.FullName) @($parts.FullName | ForEach-Object { Auto-Offset $_ }) }
            Start-Process explorer.exe -ArgumentList ('"' + $pd + '"')
            return
        }
        Say 'Chia nho bi loi, file day du van con nguyen.' Red
    }
    if ($txt) { Transcribe-Files @($full) @($absFrom) }
    Start-Process explorer.exe -ArgumentList ('/select,"' + $full + '"')
}

# ---------- Nhan dien nguon ----------
$status = ''; $rts = ''; $vdurV = ''
$isLocal = ($url -notmatch '^https?://') -and (Test-Path -LiteralPath $url -PathType Leaf)
if ($isLocal) { $status = 'local' } else {
    Say 'Dang kiem tra link...'
    for ($try = 1; $try -le 2; $try++) {
        $all = @(& yt-dlp --no-warnings --print live_status --print release_timestamp --print duration $url 2>&1)
        $outL = @($all | Where-Object { $_ -is [string] } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        $errL = @($all | Where-Object { $_ -isnot [string] } | ForEach-Object { $_.ToString() })
        if ($outL.Count -ge 1) { $status = $outL[0] }; if ($outL.Count -ge 2) { $rts = $outL[1] }; if ($outL.Count -ge 3) { $vdurV = $outL[2] }
        if ($status) { break }
        if ($try -eq 1 -and -not (($errL -join ' ') -match 'not a bot|429|Private video|unavailable|does not exist')) {
            Say 'Khong doc duoc link, dang tu cap nhat yt-dlp roi thu lai...' Yellow
            & yt-dlp -U 2>&1 | Out-Null
        } else { break }
    }
    if (-not $status) { $errL | Select-Object -Last 4 | ForEach-Object { Write-Host $_ -ForegroundColor DarkYellow } }
}

$ok = $true
if ($status -and $tend) {
    if ($status -eq 'local') { $d = (& ffprobe -v error -show_entries format=duration -of csv=p=0 $url 2>$null | Select-Object -First 1); if ($d -match '^(\d+)') { $to = [int]$Matches[1] } else { $ok = $false } }
    elseif ($status -eq 'is_live' -or $status -eq 'post_live') { $tneg = $true; $to = 0 }
    elseif ($vdurV -match '^(\d+)') { $to = [int]$Matches[1] }
    else { $ok = $false }
    if (-not $ok) { Say 'Khong biet do dai video. Hay nhap o "den".' Red }
}
if ($ok -and $status -and ($fneg -or $tneg)) {
    if (($status -ne 'is_live' -and $status -ne 'post_live') -or $rts -notmatch '^\d+$') {
        Say 'Moc so am (-) chi dung duoc khi video DANG LIVE. Video nay da xong: hay nhap so duong tinh tu dau video.' Red; $ok = $false
    } else {
        $edge = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [int64]$rts - 8   # YouTube phat cham hon thuc te vai giay
        if ($fneg) { $from = $edge - $from }
        if ($tneg) { $to = $edge - $to }
        if ($from -lt 0) { $from = 0 }
        Say "Live da chay khoang $(Fmt $edge). Doi ra moc tinh tu dau live: $(Fmt $from) den $(Fmt $to)"
        if ($to -le $from) { Say 'Moc "den" phai sau moc "tu".' Red; $ok = $false }
    }
}
$dur = $to - $from
$srcOff = 0; if ($status -eq 'local') { $srcOff = Auto-Offset $url }
$absFrom = $from + $srcOff; $absTo = $to + $srcOff
$tag = (Fmt $absFrom).Replace(':', '-') + ' den ' + (Fmt $absTo).Replace(':', '-')
if ($name) { $outName = "$name (tu $tag)" } else { $outName = "cut $tag $stamp" }
if (Test-Path -LiteralPath "$outName.$ext") { $outName = "$outName $stamp" }

if (-not $status) {
    Say 'Khong doc duoc link. Kiem tra lai link YouTube.' Red; Hints
} elseif (-not $ok) {
    Hints
} elseif ($status -eq 'local' -and [bool]$P.only_txt) {
    # ---- CHI QUET PHU DE CHO FILE CO SAN ----
    Transcribe-Files @($url) @(Auto-Offset $url)
    Start-Process explorer.exe -ArgumentList ('/select,"' + [IO.Path]::ChangeExtension($url, '.txt') + '"')
} elseif ($status -eq 'local') {
    # ---- FILE CO SAN TREN MAY ----
    Say "File tren may: $url"
    Say "Dang cat doan $(Fmt $from) den $(Fmt $to) ..."
    $out = "$outName.$ext"
    if ($type -eq 'audio') {
        & ffmpeg @FF -ss $from -i $url -t $dur -vn -c:a libmp3lame -q:a 0 $out
    } else {
        $srcH = 0
        $hp = (& ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 $url 2>$null | Select-Object -First 1)
        if ($hp -match '^(\d+)') { $srcH = [int]$Matches[1] }
        if (-not $exact -and ($srcH -eq 0 -or $srcH -le $h)) {
            & ffmpeg @FF -ss $from -i $url -t $dur -map '0:v:0?' -map '0:a:0?' -c copy $out
        } else {
            $vf = @(); if ($srcH -gt $h) { $vf = @('-vf', "scale=-2:$h"); Say "Thu nho tu ${srcH}p xuong ${h}p..." Yellow }
            & ffmpeg @FF -ss $from -i $url -t $dur -map '0:v:0?' -map '0:a:0?' @vf -c:v libx264 -preset veryfast -crf 18 -pix_fmt yuv420p -c:a aac -b:a 192k $out
        }
    }
    $full = Join-Path (Get-Location).Path $out
    if ((FSize $full) -gt 1000) { Done $full } else { Say 'Cat file bi loi. Chup man hinh cua so nay de kiem tra.' Red }

} elseif ($status -eq 'is_live' -or $status -eq 'post_live') {
    # ---- DANG LIVE: tai tu dau live toi moc "den", tai du phan nao cat phan do ----
    $base = '_tam_scv_' + $stamp
    $limit = [int64](16500 * ($to + 40))
    $sel = '140/bestaudio'
    if ($type -ne 'audio') { $sel = "bv*[height<=$h][vcodec^=avc1]+140/bv*[height<=$h]+140/bv*+ba" }
    Say 'Video DANG LIVE.'
    Say "Buoc 1/2: tai tu dau buoi live den moc $(Fmt $to) ..."
    Say '(doan cang xa dau live cang lau; neu moc "den" chua toi, app se cho live phat toi do)' Yellow
    $ytArgs = "--live-from-start $SAFE -f `"$sel`" --no-part --no-mtime -o `"$base.%(ext)s`" `"$url`""
    $p = Start-Process yt-dlp -ArgumentList $ytArgs -NoNewWindow -PassThru
    function Find-Aud { Get-ChildItem -LiteralPath . -File | Where-Object { ($_.Name -like "$base.f140.*" -or $_.Name -eq "$base.m4a") -and $_.Name -notmatch 'ytdl$|Frag' } | Select-Object -First 1 }
    function Find-Vid { Get-ChildItem -LiteralPath . -File | Where-Object { $_.Name -like "$base.f*.*" -and $_.Name -notlike "$base.f140.*" -and $_.Name -notmatch 'ytdl$|Frag' } | Select-Object -First 1 }

    $prog = $split -gt 0; $pnext = 1; $queue = New-Object System.Collections.Generic.Queue[object]; $cur = $null
    if ($prog) {
        $pbase = $outName; if ($name) { $pbase = $name }
        $pd = Join-Path (Get-Location).Path ($pbase + ' (chia nho)')
        New-Item -ItemType Directory -Force -Path $pd | Out-Null
        Set-Content -LiteralPath (Join-Path $pd '.scv_info') -Value @("start=$from", "split=$split") -Encoding ASCII
        New-Item -ItemType File -Force -Path (Join-Path $pd '.scv_parts.csv') | Out-Null
        Say "Chia nho moi $split phut: tai du phan nao app cat phan do ngay (thu muc: $pd)" Yellow
        if ($txt) { if (-not (Ensure-Whisper)) { $txt = $false } }
    }
    function Cut-Parts([int]$have, [bool]$fin) {
        while ($true) {
            $ps = $from + ($script:pnext - 1) * $split * 60; if ($ps -ge $to) { return }
            $pe = $ps + $split * 60; if ($pe -gt $to) { $pe = $to }
            if (-not $fin -and ($pe + 15) -gt $have) { return }
            $pn = '{0:00}' -f $script:pnext; $pf = Join-Path $pd "$pbase $pn.$ext"
            $a = Find-Aud; $v = Find-Vid
            if ($type -eq 'audio') { & ffmpeg -hide_banner -loglevel error -y -ss $ps -i $a.FullName -t ($pe - $ps) -vn -c:a libmp3lame -q:a 0 $pf }
            else { & ffmpeg -hide_banner -loglevel error -y -ss $ps -i $v.FullName -ss $ps -i $a.FullName -t ($pe - $ps) -map 0:v:0 -map 1:a:0 @VENC @AENC $pf }
            if ((FSize $pf) -gt 1000) {
                Add-Content -LiteralPath (Join-Path $pd '.scv_parts.csv') -Value "$pbase $pn.$ext,$($ps - $from)" -Encoding UTF8
                Write-Host ''; Say ">> Xong phan $pn ($(Fmt $ps) - $(Fmt $pe)): $pf" Green
                if ($txt) { $script:queue.Enqueue([pscustomobject]@{ f = $pf; off = $ps }) }
            } else { Say "   Cat phan $pn bi loi" Red }
            $script:pnext++
        }
    }
    function Txt-Worker {
        if (-not $txt -or -not $prog) { return }
        if ($script:cur) { if (-not $script:cur.proc.HasExited) { return }; Finish-Whisper $script:cur; $script:cur = $null }
        if ($script:queue.Count -gt 0) {
            $n = $script:queue.Dequeue()
            Say ">> Dang tao phu de: $(Split-Path -Leaf $n.f) (chay nen)"
            $script:cur = Start-Whisper $n.f $n.off
        }
    }

    $need = $to + 20; $aok = $false; $vok = ($type -eq 'audio'); $tick = 0
    while (-not $p.HasExited) {
        Start-Sleep -Seconds 2; $tick++
        if (-not $aok) {
            $a = Find-Aud
            if ($a -and (FSize $a.FullName) -ge $limit) { $aok = $true; if (-not $vok) { Write-Host ''; Say "Tieng da du, dang doi phan hinh tai toi $(Fmt $to)..." } }
        }
        if (-not $vok -and ($tick % 15) -eq 0) {
            $v = Find-Vid
            if ($v) { $d = VDur $v.FullName; if ($d -ge $need) { $vok = $true }; if ($aok -and -not $vok) { Say "   Hinh da tai toi $(Fmt $d) / $(Fmt $to)" Yellow } }
        }
        if ($prog -and ($tick % 30) -eq 0) {
            $a = Find-Aud
            if ($a) {
                $have = ADur $a.FullName
                if ($type -ne 'audio') { $v = Find-Vid; $hv = 0; if ($v) { $hv = VDur $v.FullName }; if ($hv -lt $have) { $have = $hv } }
                Cut-Parts $have $false
            }
        }
        if ($prog) { Txt-Worker }
        if ($aok -and $vok) {
            Write-Host ''; Say 'Da tai du ca hinh va tieng, dang dung tai...'
            taskkill /T /F /PID $p.Id | Out-Null
            break
        }
    }
    Start-Sleep -Seconds 3
    $aud = Find-Aud; $vid = Find-Vid
    $src = $vid; if ($type -eq 'audio') { $src = $aud }
    Write-Host ''
    if (-not $src -or (FSize $src.FullName) -lt 10000) {
        Say 'Khong tai duoc.' Red; Hints
    } elseif ($prog) {
        Say 'Cat cac phan con lai...'
        Cut-Parts 999999 $true
        if ($txt) {
            Say 'Doi tao xong phu de cac phan con lai (co the lau, dung dong cua so)...'
            while ($cur -or $queue.Count -gt 0) { Txt-Worker; Start-Sleep -Seconds 5 }
        }
        Get-ChildItem -LiteralPath . -File | Where-Object { $_.Name.StartsWith($base) } | Remove-Item -Force -ErrorAction SilentlyContinue
        $n = @(Get-ChildItem -LiteralPath $pd -File -Filter "*.$ext").Count
        Write-Host ''; Say "XONG! $n phan trong thu muc: $pd" Green
        if ($txt) { Say 'Moi phan co file .txt cung ten (moc tinh theo buoi live).' Yellow }
        Start-Process explorer.exe -ArgumentList ('"' + $pd + '"')
    } else {
        Say "Buoc 2/2: cat doan $(Fmt $from) den $(Fmt $to) ..."
        $out = "$outName.$ext"
        if ($type -eq 'audio') { & ffmpeg @FF -ss $from -i $aud.FullName -t $dur -vn -c:a libmp3lame -q:a 0 $out }
        elseif ($aud) { & ffmpeg @FF -ss $from -i $vid.FullName -ss $from -i $aud.FullName -t $dur -map 0:v:0 -map 1:a:0 @VENC @AENC $out }
        else { & ffmpeg @FF -ss $from -i $vid.FullName -t $dur @VENC @AENC $out }
        $full = Join-Path (Get-Location).Path $out
        if ((FSize $full) -gt 1000) {
            Get-ChildItem -LiteralPath . -File | Where-Object { $_.Name.StartsWith($base) } | Remove-Item -Force -ErrorAction SilentlyContinue
            Done $full
        } else { Say 'Cat file bi loi. Chup man hinh cua so nay de kiem tra.' Red }
    }

} else {
    # ---- VIDEO THUONG / LIVE DA XONG: chi tai dung doan ----
    Say "Video thuong / live da xong. Dang tai doan $(Fmt $from) den $(Fmt $to) ..."
    $o = $outName.Replace('%', '%%') + '.%(ext)s'
    $sec = "*$from-$to"
    if ($type -eq 'audio') {
        & yt-dlp -N 3 --sleep-requests 1 --retry-sleep exp=1:30 --retry-sleep fragment:exp=1:30 --fragment-retries 10 -x --audio-format mp3 --audio-quality 0 --no-mtime --download-sections $sec -o $o $url
    } else {
        $fk = @(); if ($exact) { $fk = @('--force-keyframes-at-cuts') }
        & yt-dlp -N 3 --sleep-requests 1 --retry-sleep exp=1:30 --retry-sleep fragment:exp=1:30 --fragment-retries 10 @fk -f "bv*[height<=$h][vcodec^=avc1]+ba[ext=m4a]/bv*[height<=$h]+ba/b" --merge-output-format mp4 --no-mtime --download-sections $sec -o $o $url
    }
    $f = Join-Path (Get-Location).Path "$outName.$ext"
    if ((FSize $f) -gt 1000) { Done $f } else { Say 'Khong tai duoc.' Red; Hints }
}
Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue
Write-Host ''
Read-Host 'Bam Enter de dong cua so nay'
