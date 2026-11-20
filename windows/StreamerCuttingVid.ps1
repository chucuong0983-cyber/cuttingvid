# CuttingVid by Louis Chu (Windows) - cua so chinh. Phan tai / cat nam o job.ps1.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'
trap {
    [System.Windows.Forms.MessageBox]::Show("App gặp lỗi:`n`n" + $_.ToString() + "`n`nDòng: " + $_.InvocationInfo.ScriptLineNumber, 'CuttingVid - lỗi', 'OK', 'Error') | Out-Null
    exit 1
}

$AppVersion = '2.0.1'
$AppName = 'CuttingVid by Louis Chu'
$Here = $PSScriptRoot
$ConfDir = Join-Path $env:APPDATA 'StreamerCuttingVid'
$ConfFile = Join-Path $ConfDir 'folder.txt'
$LockFile = Join-Path $ConfDir 'running.txt'
New-Item -ItemType Directory -Force -Path $ConfDir | Out-Null

function Show-Msg([string]$text, [string]$icon = 'Information') {
    $top = New-Object System.Windows.Forms.Form -Property @{ TopMost = $true }
    [System.Windows.Forms.MessageBox]::Show($top, $text, $AppName, 'OK', $icon) | Out-Null
    $top.Dispose()
}

# ---------- Tu cap nhat tu GitHub: chi can tat app mo lai ----------
$Repo = 'https://raw.githubusercontent.com/chucuong0983-cyber/cuttingvid/main/windows'
$updMark = Join-Path $ConfDir 'updated.txt'
try {
    $remote = (Invoke-WebRequest -UseBasicParsing -TimeoutSec 4 "$Repo/version.txt").Content.Trim()
    if ($remote -match '^\d+(\.\d+)+$' -and ([version]$remote -gt [version]$AppVersion)) {
        $list = @((Invoke-WebRequest -UseBasicParsing -TimeoutSec 8 "$Repo/files.txt").Content -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '\.\.|[\\/:]' })
        $tmp = Join-Path $env:TEMP ('scv_upd_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        foreach ($f in $list) { Invoke-WebRequest -UseBasicParsing -TimeoutSec 120 "$Repo/$f" -OutFile (Join-Path $tmp $f) }
        foreach ($f in $list) { Move-Item -LiteralPath (Join-Path $tmp $f) -Destination (Join-Path $Here $f) -Force }
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        Set-Content -LiteralPath $updMark -Value $remote
        Start-Process wscript.exe -ArgumentList ('"' + (Join-Path $Here 'launch.vbs') + '"')
        exit
    }
} catch {}
if (Test-Path -LiteralPath $updMark) {
    $v = (Get-Content -LiteralPath $updMark -Raw).Trim()
    Remove-Item -LiteralPath $updMark -Force -ErrorAction SilentlyContinue
    Show-Msg "Đã tự cập nhật lên v$v. Những thay đổi mới đã có hiệu lực."
}

# Tu cap nhat yt-dlp moi tuan (chay ngam)
$lastUpd = Join-Path $ConfDir 'last_ytdlp_update.txt'
$lu = 0; if (Test-Path -LiteralPath $lastUpd) { [int64]::TryParse((Get-Content -LiteralPath $lastUpd -Raw).Trim(), [ref]$lu) | Out-Null }
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
if ($now - $lu -gt 604800) {
    Set-Content -LiteralPath $lastUpd -Value $now
    Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', 'yt-dlp -U' -ErrorAction SilentlyContinue
}

# "1:15:00" / "15:00" -> giay; sai -> $null
function Convert-ToSeconds([string]$s) {
    $parts = $s.Trim().TrimStart('-').Split(':')
    if ($parts.Count -lt 2 -or $parts.Count -gt 3) { return $null }
    foreach ($p in $parts) { if ($p -notmatch '^\d{1,3}$') { return $null } }
    $n = @($parts | ForEach-Object { [int]$_ })
    if ($n.Count -eq 2) { return $n[0] * 60 + $n[1] }
    return $n[0] * 3600 + $n[1] * 60 + $n[2]
}
function New-Ctl($type, $text, $x, $y, $w, $h) {
    $c = New-Object "System.Windows.Forms.$type"
    if ($text) { $c.Text = $text }
    $c.Location = New-Object System.Drawing.Point($x, $y)
    if ($w) { $c.Size = New-Object System.Drawing.Size($w, $h) } else { $c.AutoSize = $true }
    $form.Controls.Add($c)
    return $c
}

foreach ($tool in 'yt-dlp', 'ffmpeg', 'ffprobe') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Show-Msg "Chưa tìm thấy $tool.`n`nMở PowerShell và chạy:`nwinget install yt-dlp.yt-dlp`n`nSau đó mở lại app." 'Error'
        exit
    }
}

# ---------- Giao dien (than chi + vang kim) ----------
function RGB([string]$h) { return [System.Drawing.ColorTranslator]::FromHtml($h) }
$C_BG = RGB '#1A1D22'; $C_SIDE = RGB '#23272E'; $C_CARD = RGB '#2B3038'; $C_FIELD = RGB '#20242A'; $C_LINE = RGB '#3A404A'
$C_GOLD = RGB '#C9A24A'; $C_GOLD2 = RGB '#E0BE6E'; $C_IVORY = RGB '#F7F6F2'; $C_MUTED = RGB '#9AA1AB'; $C_BAD = RGB '#E8746B'; $C_BTN = RGB '#323843'
$F_N = New-Object System.Drawing.Font('Segoe UI', 10)
$F_S = New-Object System.Drawing.Font('Segoe UI', 8.5)
$F_B = New-Object System.Drawing.Font('Segoe UI Semibold', 10)
$F_H = New-Object System.Drawing.Font('Segoe UI Semibold', 16)

$EngFile = Join-Path $ConfDir 'engine.txt'; $GroqKeyFile = Join-Path $ConfDir 'groq_key.txt'
$PDIR = $ConfDir; $LogFile = Join-Path $PDIR 'job.log'

$form = New-Object System.Windows.Forms.Form
$form.Text = "$AppName  ·  v$AppVersion"
$form.ClientSize = New-Object System.Drawing.Size(940, 760)
$form.StartPosition = 'CenterScreen'
$form.Font = $F_N; $form.BackColor = $C_BG; $form.ForeColor = $C_IVORY
$form.FormBorderStyle = 'FixedSingle'; $form.MaximizeBox = $false
$icoPath = Join-Path $Here 'icon.ico'
if (Test-Path -LiteralPath $icoPath) { try { $form.Icon = New-Object System.Drawing.Icon($icoPath) } catch {} }

function Round($ctl, [int]$r) {
    $w = $ctl.Width; $h = $ctl.Height
    $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
    $gp.AddArc(0, 0, $r, $r, 180, 90); $gp.AddArc($w - $r, 0, $r, $r, 270, 90)
    $gp.AddArc($w - $r, $h - $r, $r, $r, 0, 90); $gp.AddArc(0, $h - $r, $r, $r, 90, 90); $gp.CloseFigure()
    $ctl.Region = New-Object System.Drawing.Region($gp)
}
function Add-Ctl($parent, $type, $text, $x, $y, $w, $h) {
    $c = New-Object "System.Windows.Forms.$type"
    if ($null -ne $text) { $c.Text = $text }
    $c.Location = New-Object System.Drawing.Point($x, $y)
    if ($w) { $c.Size = New-Object System.Drawing.Size($w, $h) } else { $c.AutoSize = $true }
    $parent.Controls.Add($c); return $c
}
function New-Lbl($parent, $text, $x, $y, $font, $color, $w = 0, $h = 0) {
    $l = Add-Ctl $parent Label $text $x $y $w $h
    $l.Font = $font; $l.ForeColor = $color; $l.BackColor = [System.Drawing.Color]::Transparent; return $l
}
function New-Txt($parent, $text, $x, $y, $w) {
    $t = Add-Ctl $parent TextBox $text $x $y $w 28
    $t.BackColor = $C_FIELD; $t.ForeColor = $C_IVORY; $t.BorderStyle = 'FixedSingle'; $t.Font = New-Object System.Drawing.Font('Segoe UI', 11)
    return $t
}
function New-Btn($parent, $text, $x, $y, $w, $h, [bool]$gold = $false) {
    $b = Add-Ctl $parent Button $text $x $y $w $h
    $b.FlatStyle = 'Flat'; $b.Cursor = 'Hand'; $b.Font = $F_B
    if ($gold) { $b.BackColor = $C_GOLD; $b.ForeColor = (RGB '#1E1A10'); $b.FlatAppearance.BorderColor = $C_GOLD; $b.FlatAppearance.MouseOverBackColor = $C_GOLD2 }
    else { $b.BackColor = $C_BTN; $b.ForeColor = $C_IVORY; $b.FlatAppearance.BorderColor = $C_LINE; $b.FlatAppearance.MouseOverBackColor = (RGB '#3B4250') }
    return $b
}
function New-Card($parent, $x, $y, $w, $h) {
    $p = Add-Ctl $parent Panel $null $x $y $w $h
    $p.BackColor = $C_CARD; Round $p 18; return $p
}
# Cong tac bat/tat ve tay
function New-Switch($parent, $x, $y, [bool]$on) {
    $s = Add-Ctl $parent Panel $null $x $y 42 24
    $s.Tag = $on; $s.Cursor = 'Hand'; $s.BackColor = $parent.BackColor
    $s.Add_Paint({
        param($sd, $e)
        $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'
        $col = if ($sd.Tag) { $C_GOLD } else { (RGB '#4A515C') }
        $br = New-Object System.Drawing.SolidBrush($col)
        $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
        $gp.AddArc(0, 0, 23, 23, 90, 180); $gp.AddArc(18, 0, 23, 23, 270, 180); $gp.CloseFigure()
        $g.FillPath($br, $gp)
        $kx = if ($sd.Tag) { 20 } else { 3 }
        $g.FillEllipse((New-Object System.Drawing.SolidBrush($C_IVORY)), $kx, 3, 18, 18)
    })
    $s.Add_Click({ param($sd, $e) $sd.Tag = -not $sd.Tag; $sd.Invalidate(); & $updAll })
    return $s
}

# ---- Thanh ben trai ----
$side = Add-Ctl $form Panel $null 0 0 230 760
$side.BackColor = $C_SIDE
$pic = Add-Ctl $side PictureBox $null 20 22 44 44
$pic.SizeMode = 'Zoom'
if (Test-Path -LiteralPath $icoPath) { try { $pic.Image = (New-Object System.Drawing.Icon($icoPath, 256, 256)).ToBitmap() } catch {} }
[void](New-Lbl $side 'CuttingVid' 74 24 (New-Object System.Drawing.Font('Segoe UI Semibold', 13)) $C_IVORY)
[void](New-Lbl $side 'by Louis Chu' 76 48 $F_S $C_GOLD)
[void](New-Lbl $side 'CÔNG CỤ' 22 96 $F_S $C_MUTED)
$navs = @()
function New-Nav($text, $y) {
    $n = New-Lbl $side ('    ' + $text) 12 $y $F_N (RGB '#D6D8DC') 206 36
    $n.TextAlign = 'MiddleLeft'; $n.Cursor = 'Hand'; $n.BackColor = $C_SIDE
    $n.Add_MouseEnter({ param($sd) if ($sd.Tag -ne 'on') { $sd.BackColor = (RGB '#2E333B') } })
    $n.Add_MouseLeave({ param($sd) if ($sd.Tag -ne 'on') { $sd.BackColor = $C_SIDE } })
    Round $n 10
    $script:navs += $n; return $n
}
$nCut = New-Nav 'Cắt video' 118
$nMulti = New-Nav 'Quét phụ đề nhiều file' 156
$nOpen = New-Nav 'Mở thư mục lưu' 194
$nKey = New-Nav 'Key Groq' 232
$nYt = New-Nav 'Sửa lỗi tải (cập nhật yt-dlp)' 270
$nQuit = New-Nav 'Thoát' 308
$nCut.Tag = 'on'; $nCut.BackColor = (RGB '#3A3424'); $nCut.ForeColor = $C_GOLD2
$lblVer = New-Lbl $side "v$AppVersion`nTắt app mở lại để cập nhật" 22 700 $F_S (RGB '#6F7681')

# ---- Vung chinh: FORM ----
$pnlForm = Add-Ctl $form Panel $null 230 0 710 760
$pnlForm.BackColor = $C_BG
[void](New-Lbl $pnlForm 'Cắt video' 28 16 $F_H $C_IVORY)
[void](New-Lbl $pnlForm 'Dán link YouTube (đang live hay đã xong) hoặc chọn file trên máy.' 30 50 $F_N $C_MUTED)

$c1 = New-Card $pnlForm 28 82 654 108
$lblUrl = New-Lbl $c1 'LINK YOUTUBE / FILE TRÊN MÁY' 18 14 $F_S $C_MUTED
$txtUrl = New-Txt $c1 '' 18 36 410
$btnPaste = New-Btn $c1 'Dán' 438 34 80 32
$btnFile = New-Btn $c1 'Chọn file…' 526 34 110 32
$lblSrc = New-Lbl $c1 'Link YouTube' 20 76 $F_S $C_GOLD2

$c2 = New-Card $pnlForm 28 202 654 176
[void](New-Lbl $c2 'CẮT TỪ' 18 14 $F_S $C_MUTED)
$txtFrom = New-Txt $c2 '00:00:00' 18 36 300
[void](New-Lbl $c2 'ĐẾN' 336 14 $F_S $C_MUTED)
$txtTo = New-Txt $c2 '00:05:00' 336 36 300
$lblHint = New-Lbl $c2 '' 18 70 $F_S (RGB '#7F8691') 620 18
[void](New-Lbl $c2 'LẤY' 18 98 $F_S $C_MUTED)
$opts = @()
for ($k = 0; $k -lt 4; $k++) {
    $rb = Add-Ctl $c2 RadioButton '' (18 + $k * 156) 120 148 44
    $rb.Appearance = 'Button'; $rb.FlatStyle = 'Flat'; $rb.TextAlign = 'MiddleCenter'; $rb.Cursor = 'Hand'
    $rb.BackColor = $C_FIELD; $rb.ForeColor = $C_IVORY; $rb.FlatAppearance.BorderColor = $C_LINE
    $rb.FlatAppearance.CheckedBackColor = (RGB '#3A3424'); $rb.FlatAppearance.MouseOverBackColor = (RGB '#2A2E35')
    $rb.Font = $F_B; $rb.Tag = $k
    $rb.Add_CheckedChanged({ param($sd) if ($sd.Checked) { $sd.ForeColor = $C_GOLD2; $sd.FlatAppearance.BorderColor = $C_GOLD } else { $sd.ForeColor = $C_IVORY; $sd.FlatAppearance.BorderColor = $C_LINE }; & $updAll })
    $opts += $rb
}

$c3 = New-Card $pnlForm 28 390 654 158
[void](New-Lbl $c3 'Xuất phụ đề txt' 18 14 $F_B $C_IVORY)
[void](New-Lbl $c3 'Mốc [giờ:phút:giây] tính theo buổi live' 18 34 $F_S $C_MUTED)
$cmbW = Add-Ctl $c3 ComboBox $null 330 16 240 28
$cmbW.DropDownStyle = 'DropDownList'; $cmbW.FlatStyle = 'Flat'; $cmbW.BackColor = $C_FIELD; $cmbW.ForeColor = $C_IVORY
[void]$cmbW.Items.Add('Siêu nhanh qua mạng (Groq)'); [void]$cmbW.Items.Add('Nhanh trên máy (base.en)'); [void]$cmbW.Items.Add('Chính xác trên máy (small.en)')
$cmbW.SelectedIndex = 1
try { $ei = [int](Get-Content -LiteralPath $EngFile -ErrorAction Stop | Select-Object -First 1); if ($ei -ge 0 -and $ei -le 2) { $cmbW.SelectedIndex = $ei } } catch {}
$swTxt = New-Switch $c3 594 18 $false
[void](New-Lbl $c3 'Chia nhỏ' 18 64 $F_B $C_IVORY)
[void](New-Lbl $c3 'Mỗi phần có file txt riêng' 18 84 $F_S $C_MUTED)
$numSplit = Add-Ctl $c3 NumericUpDown $null 400 66 60 28
$numSplit.Minimum = 1; $numSplit.Maximum = 240; $numSplit.Value = 30; $numSplit.BackColor = $C_FIELD; $numSplit.ForeColor = $C_IVORY; $numSplit.BorderStyle = 'FixedSingle'
$lblSplit = New-Lbl $c3 'phút / phần' 468 70 $F_S $C_MUTED
$swSplit = New-Switch $c3 594 68 $false
[void](New-Lbl $c3 'Cắt chính xác từng giây' 18 112 $F_B $C_IVORY)
[void](New-Lbl $c3 'Chậm hơn, dùng khi cắt bản cuối' 18 132 $F_S $C_MUTED)
$swExact = New-Switch $c3 594 116 $false

$c4 = New-Card $pnlForm 28 560 654 120
[void](New-Lbl $c4 'TÊN FILE (TRỐNG = TỰ ĐẶT THEO MỐC)' 18 12 $F_S $C_MUTED)
$txtName = New-Txt $c4 '' 18 32 618
[void](New-Lbl $c4 'LƯU VÀO' 18 66 $F_S $C_MUTED)
$txtFolder = New-Txt $c4 '' 18 84 518
$btnBrowse = New-Btn $c4 'Đổi…' 546 82 90 32
$saved = ''
if (Test-Path -LiteralPath $ConfFile) { $saved = (Get-Content -LiteralPath $ConfFile -Raw -ErrorAction SilentlyContinue).Trim() }
if ($saved -and (Test-Path -LiteralPath $saved -PathType Container)) { $txtFolder.Text = $saved } else { $txtFolder.Text = [Environment]::GetFolderPath('Desktop') }

$btnGo = New-Btn $pnlForm 'CẮT VÀ TẢI VỀ' 28 694 654 50 $true
$btnGo.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
Round $btnGo 16
$form.AcceptButton = $btnGo

# ---- Vung chinh: TIEN DO ----
$pnlProg = Add-Ctl $form Panel $null 230 0 710 760
$pnlProg.BackColor = $C_BG; $pnlProg.Visible = $false
$lblPT = New-Lbl $pnlProg 'Đang chạy…' 28 16 $F_H $C_IVORY
[void](New-Lbl $pnlProg 'Có thể đóng app, lượt này vẫn chạy nền. Mở lại app để xem tiếp.' 30 50 $F_N $C_MUTED)
function New-ProgCard($y) {
    $c = New-Card $pnlProg 28 $y 654 100
    $o = @{ card = $c }
    $o.t = New-Lbl $c 'Đang chuẩn bị' 18 14 (New-Object System.Drawing.Font('Segoe UI Semibold', 11)) $C_IVORY 520 24
    $o.p = New-Lbl $c '' 540 14 (New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)) $C_GOLD2 96 24
    $o.p.TextAlign = 'TopRight'
    $o.track = Add-Ctl $c Panel $null 18 46 618 12
    $o.track.BackColor = (RGB '#1C1F24'); Round $o.track 12
    $o.fill = Add-Ctl $o.track Panel $null 0 0 0 12
    $o.fill.BackColor = $C_GOLD
    $o.d = New-Lbl $c '' 18 66 $F_S $C_MUTED 618 20
    $o.ind = $false; $o.pos = 0
    return $o
}
$P1 = New-ProgCard 82
$P2 = New-ProgCard 194; $P2.card.Visible = $false
$txtLog = Add-Ctl $pnlProg TextBox '' 28 306 654 200
$txtLog.Multiline = $true; $txtLog.ReadOnly = $true; $txtLog.ScrollBars = 'Vertical'; $txtLog.BorderStyle = 'None'
$txtLog.BackColor = (RGB '#16191D'); $txtLog.ForeColor = (RGB '#AEB4BD'); $txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$bLog = New-Btn $pnlProg 'Xem chi tiết' 28 522 210 40
$bCancel = New-Btn $pnlProg 'Dừng lượt này' 250 522 210 40
$bOpen = New-Btn $pnlProg 'Mở thư mục kết quả' 472 522 210 40 $true
$bNew = New-Btn $pnlProg 'Làm lượt mới' 250 522 210 40
$bOpen.Visible = $false; $bNew.Visible = $false

function Set-Bar($o, $v) {
    $o.ind = $false; $o.fill.BackColor = $C_GOLD
    if ($v -eq -1) { $o.ind = $true; $o.p.Text = ''; $o.fill.Width = 180; return }
    if ($v -eq -2) { $o.fill.BackColor = $C_BAD; $o.fill.Left = 0; $o.fill.Width = 618; $o.p.Text = 'lỗi'; return }
    $v = [math]::Max(0, [math]::Min(100, [int]$v)); $o.fill.Left = 0; $o.fill.Width = [int](618 * $v / 100); $o.p.Text = "$v%"
}
function Read-Prog([string]$slot) {
    $f = Join-Path $PDIR "progress.$slot"
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try { return ([IO.File]::ReadAllText($f, [Text.Encoding]::UTF8)).TrimEnd() -split "`t" } catch { return $null }
}
function Job-Pid {
    if (-not (Test-Path -LiteralPath $LockFile)) { return 0 }
    $old = (Get-Content -LiteralPath $LockFile -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($old -and $old.Trim() -match '^\d+$' -and (Get-Process -Id ([int]$old.Trim()) -ErrorAction SilentlyContinue)) { return [int]$old.Trim() }
    return 0
}
$script:watching = $false
function Show-Prog {
    $pnlForm.Visible = $false; $pnlProg.Visible = $true; $lblPT.Text = 'Đang chạy…'
    $bCancel.Visible = $true; $bLog.Visible = $true; $bOpen.Visible = $false; $bNew.Visible = $false
    $P2.card.Visible = $false; $P1.t.Text = 'Đang chuẩn bị'; $P1.d.Text = ''; Set-Bar $P1 -1; $txtLog.Text = ''
    $script:watching = $true
}
function Show-Form { $pnlProg.Visible = $false; $pnlForm.Visible = $true }

$tmr = New-Object System.Windows.Forms.Timer
$tmr.Interval = 120
$script:tk = 0
$tmr.Add_Tick({
    foreach ($o in @($P1, $P2)) { if ($o.ind) { $o.pos = ($o.pos + 14) % 800; $o.fill.Left = $o.pos - 180 } }
    $script:tk++
    if (-not $script:watching -or ($script:tk % 5) -ne 0) { return }
    $m = Read-Prog 'main'; $t = Read-Prog 'txt'
    if ($m) { $P1.t.Text = $m[1]; if ($m.Count -gt 2) { $P1.d.Text = $m[2] } else { $P1.d.Text = '' }; Set-Bar $P1 ([int]$m[0]) }
    if ($t) { $P2.card.Visible = $true; $P2.t.Text = $t[1]; if ($t.Count -gt 2) { $P2.d.Text = $t[2] } else { $P2.d.Text = '' }; Set-Bar $P2 ([int]$t[0]) }
    if (($script:tk % 15) -eq 0 -and (Test-Path -LiteralPath $LogFile)) {
        try {
            $fs = [IO.File]::Open($LogFile, 'Open', 'Read', 'ReadWrite')
            $n = [math]::Min($fs.Length, 6000); [void]$fs.Seek(-$n, 'End'); $buf = New-Object byte[] $n; [void]$fs.Read($buf, 0, $n); $fs.Close()
            $lines = @(([Text.Encoding]::UTF8.GetString($buf) -split "`r?`n") | Where-Object { $_.Trim() -and $_ -notmatch '^\*{5,}|^(Windows PowerShell|Start time|End time|Username|RunAs|Configuration|Machine|Host Application|Process ID|PSVersion|PSEdition|PSCompatible|BuildVersion|CLRVersion|WSManStack|PSRemoting|SerializationVersion|Transcript started)' })
            $txtLog.Text = (($lines | Select-Object -Last 12) -join "`r`n"); $txtLog.SelectionStart = $txtLog.Text.Length; $txtLog.ScrollToCaret()
        } catch {}
    }
    $done = Test-Path -LiteralPath (Join-Path $PDIR 'progress.done')
    if (-not $done -and ($script:tk % 25) -eq 0 -and (Job-Pid) -eq 0) { $done = $true }
    if ($done) {
        $script:watching = $false
        $bad = ($m -and [int]$m[0] -eq -2) -or -not $m
        $lblPT.Text = $(if ($bad) { 'Có lỗi, chưa xong' } else { 'Xong rồi!' })
        if (-not $bad -and $P1.ind) { Set-Bar $P1 100 }
        if (-not $bad -and $P2.ind) { Set-Bar $P2 100 }
        $bCancel.Visible = $false; $bNew.Visible = $true
        if (Test-Path -LiteralPath (Join-Path $PDIR 'progress.result')) { $bOpen.Visible = $true }
    }
})
$tmr.Start()

# ---------- Che do: link YouTube / file tren may ----------
$script:modeLocal = $null
$M = @{
    web   = @{ items = @("Chỉ tiếng`nMP3", "480p`nnhẹ, để dò", "1080p`nnét", "2K 1440p`nbản đẹp"); h = @('1080', '480', '1080', '1440'); mb = @(1, 7.5, 40, 80) }
    local = @{ items = @("Chỉ tiếng`nMP3", "Giữ nguyên`nchất lượng gốc", "Thu nhỏ 480p`nnhẹ hơn", "Thu nhỏ 1080p`nnét"); h = @('99999', '99999', '480', '1080'); mb = @(1, 40, 7.5, 40) }
}
function Cur { if ($script:modeLocal) { return $M.local } else { return $M.web } }
function Sel { foreach ($o in $opts) { if ($o.Checked) { return [int]$o.Tag } }; return 1 }
$updAll = {
    $i = Sel
    $mb = [int]([double]$numSplit.Value * (Cur).mb[$i])
    $lblSplit.Text = "phút / phần (≈ $mb MB)"
    $numSplit.Enabled = $swSplit.Tag; $cmbW.Enabled = $swTxt.Tag; $swExact.Enabled = ($i -gt 0)
}
function Set-Mode([bool]$local) {
    if ($script:modeLocal -eq $local) { return }
    $script:modeLocal = $local
    for ($k = 0; $k -lt 4; $k++) { $opts[$k].Text = (Cur).items[$k] }
    $opts[1].Checked = $true
    if ($local) {
        $btnGo.Text = 'CẮT'; $lblSrc.Text = 'File trên máy'
        $lblHint.Text = 'giờ:phút:giây tính từ đầu file. Để trống ô "đến" = tới hết file.'
    } else {
        $btnGo.Text = 'CẮT VÀ TẢI VỀ'; $lblSrc.Text = 'Link YouTube'
        $lblHint.Text = 'Đang live: gõ số âm như YouTube, vd -4:31:41. Trống ô "đến" = tới hiện tại / hết video.'
    }
    & $updAll
}
$numSplit.Add_ValueChanged($updAll)
$txtUrl.Add_TextChanged({
    $t = $txtUrl.Text.Trim().Trim('"')
    Set-Mode ([bool]($t -and ($t -notmatch '^https?://') -and (Test-Path -LiteralPath $t -PathType Leaf -ErrorAction SilentlyContinue)))
})
Set-Mode $false

function Ask-GroqKey {
    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Key Groq (miễn phí)'; $f.ClientSize = New-Object System.Drawing.Size(500, 220); $f.StartPosition = 'CenterParent'
    $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.MinimizeBox = $false
    $f.Font = $F_N; $f.BackColor = $C_CARD; $f.ForeColor = $C_IVORY
    [void](New-Lbl $f "Chế độ Siêu nhanh dùng Groq (miễn phí, không cần thẻ).`n1. Bấm 'Mở trang lấy key' → đăng nhập Google`n2. Bấm 'Create API Key' → copy`n3. Dán vào ô dưới rồi bấm Lưu. Key chỉ lưu trên máy này." 16 12 $F_N $C_IVORY 470 90)
    $t = New-Txt $f '' 16 108 466
    $bo = New-Btn $f 'Mở trang lấy key' 16 160 160 36
    $bo.Add_Click({ Start-Process 'https://console.groq.com/keys' })
    $bs = New-Btn $f 'Lưu' 290 160 90 36 $true; $bs.DialogResult = 'OK'
    $bc = New-Btn $f 'Hủy' 392 160 90 36; $bc.DialogResult = 'Cancel'
    $f.AcceptButton = $bs; $f.CancelButton = $bc
    while ($f.ShowDialog($form) -eq 'OK') {
        $k = $t.Text.Trim()
        if ($k -match '^gsk_\S{20,}$') { [IO.File]::WriteAllText($GroqKeyFile, $k); $nKey.Text = '   Đổi key Groq'; return $true }
        Show-Msg 'Key không đúng dạng (phải bắt đầu bằng gsk_). Thử lại nhé.' 'Warning'
    }
    return $false
}
if (Test-Path -LiteralPath $GroqKeyFile) { $nKey.Text = '   Đổi key Groq' } else { $nKey.Text = '   Nhập key Groq' }

# Chay job.ps1 an (khong cua so den), tien do hien trong app
function Start-Job2($params) {
    $params.bg = $true
    $stamp = [guid]::NewGuid().ToString('N')
    $pf = Join-Path $env:TEMP "scv_params_$stamp.json"
    $jf = Join-Path $env:TEMP "scv_job_$stamp.ps1"
    [IO.File]::WriteAllText($pf, ($params | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
    Copy-Item -LiteralPath (Join-Path $Here 'job.ps1') -Destination $jf -Force   # ban sao rieng: cap nhat app khong anh huong luot dang chay
    Get-ChildItem -LiteralPath $PDIR -Filter 'progress.*' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    $jp = Start-Process powershell.exe -WindowStyle Hidden -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $jf + '"'), '-ParamFile', ('"' + $pf + '"') -PassThru
    try { Set-Content -LiteralPath $LockFile -Value $jp.Id -ErrorAction Stop } catch {}
    Show-Prog
}

# ---------- Su kien ----------
$btnPaste.Add_Click({ $c = [System.Windows.Forms.Clipboard]::GetText(); if ($c) { $txtUrl.Text = $c.Trim() } })
$btnFile.Add_Click({
    $od = New-Object System.Windows.Forms.OpenFileDialog
    $od.Title = 'Chọn file video / âm thanh để cắt'
    $od.Filter = 'Video / âm thanh|*.mp4;*.mkv;*.webm;*.mov;*.m4a;*.mp3;*.ts;*.flv|Tất cả file|*.*'
    if ($od.ShowDialog() -eq 'OK') { $txtUrl.Text = $od.FileName; if ($txtTo.Text -eq '00:05:00') { $txtTo.Text = '' } }
})
$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.SelectedPath = $txtFolder.Text
    if ($dlg.ShowDialog() -eq 'OK') { $txtFolder.Text = $dlg.SelectedPath; try { Set-Content -LiteralPath $ConfFile -Value $dlg.SelectedPath -Encoding UTF8 } catch {} }
})
$nCut.Add_Click({ if ($script:watching) { Show-Msg 'Đang có 1 lượt chạy. Bấm "Dừng lượt này" nếu muốn làm lượt khác.' } else { Show-Form } })
$nOpen.Add_Click({ if (Test-Path -LiteralPath $txtFolder.Text -PathType Container) { Start-Process explorer.exe -ArgumentList ('"' + $txtFolder.Text + '"') } })
$nKey.Add_Click({ if (Ask-GroqKey) { Show-Msg 'Đã lưu key Groq.' } })
$nYt.Add_Click({
    Start-Process powershell.exe -ArgumentList '-NoExit', '-Command', 'yt-dlp -U; winget upgrade yt-dlp.yt-dlp; Write-Host ''Xong. Dong cua so nay roi thu tai lai.'' -ForegroundColor Green'
})
$nQuit.Add_Click({ $form.Close() })
$bNew.Add_Click({ Show-Form })
$bLog.Add_Click({
    if (Test-Path -LiteralPath $LogFile) { Start-Process powershell.exe -ArgumentList '-NoExit', '-Command', ('Get-Content -LiteralPath "' + $LogFile + '" -Tail 200 -Wait -Encoding UTF8') }
})
$bOpen.Add_Click({
    $r = ''; try { $r = ([IO.File]::ReadAllText((Join-Path $PDIR 'progress.result'), [Text.Encoding]::UTF8)).Trim() } catch {}
    if ($r -and (Test-Path -LiteralPath $r -PathType Container)) { Start-Process explorer.exe -ArgumentList ('"' + $r + '"') }
    elseif ($r -and (Test-Path -LiteralPath $r)) { Start-Process explorer.exe -ArgumentList ('/select,"' + $r + '"') }
})
$bCancel.Add_Click({
    $r = [System.Windows.Forms.MessageBox]::Show($form, 'Dừng lượt đang chạy? Phần nào đã xong vẫn giữ lại.', $AppName, 'YesNo', 'Question', 'Button2')
    if ($r -ne 'Yes') { return }
    $id = Job-Pid
    if ($id) { & taskkill.exe /T /F /PID $id | Out-Null }
    [IO.File]::WriteAllText((Join-Path $PDIR 'progress.main'), "-2`tĐã dừng`tBạn đã dừng lượt này", (New-Object System.Text.UTF8Encoding($false)))
    [IO.File]::WriteAllText((Join-Path $PDIR 'progress.done'), '1')
})
$form.Add_FormClosing({
    param($sender, $e)
    $msg = 'Bạn có chắc muốn thoát app không?'
    if ($script:watching) { $msg = 'Thoát app? Lượt đang chạy vẫn tiếp tục chạy nền, mở lại app để xem tiến độ.' }
    $r = [System.Windows.Forms.MessageBox]::Show($form, $msg, $AppName, 'YesNo', 'Question', 'Button2')
    if ($r -ne 'Yes') { $e.Cancel = $true }
})

$nMulti.Add_Click({
    if (Job-Pid) { Show-Msg 'Đang có 1 lượt chạy. Đợi xong rồi làm tiếp nhé.' 'Warning'; return }
    $od = New-Object System.Windows.Forms.OpenFileDialog
    $od.Title = 'Chọn các file cần quét phụ đề (giữ Ctrl hoặc Shift để chọn nhiều)'
    $od.Filter = 'Video / âm thanh|*.mp4;*.mkv;*.webm;*.mov;*.m4a;*.mp3;*.ts;*.flv|Tất cả file|*.*'
    $od.Multiselect = $true
    if ($od.ShowDialog() -ne 'OK') { return }
    $fs = @($od.FileNames | Sort-Object)
    $todo = @($fs | Where-Object { -not (Test-Path -LiteralPath ([IO.Path]::ChangeExtension($_, '.txt'))) })
    if ($todo.Count -lt $fs.Count) {
        $r = [System.Windows.Forms.MessageBox]::Show($form, "$($fs.Count - $todo.Count) / $($fs.Count) file đã có txt.`n`nCó: quét lại tất cả`nKhông: chỉ quét file chưa có txt", $AppName, 'YesNoCancel', 'Question')
        if ($r -eq 'Cancel') { return }
        if ($r -eq 'Yes') { $todo = $fs }
    }
    if ($todo.Count -eq 0) { return }
    $wm = @('groq', 'base.en', 'small.en')[$cmbW.SelectedIndex]
    if ($wm -eq 'groq' -and -not (Test-Path -LiteralPath $GroqKeyFile)) { if (-not (Ask-GroqKey)) { $wm = 'base.en' } }
    try { Set-Content -LiteralPath $EngFile -Value $cmbW.SelectedIndex } catch {}
    Start-Job2 ([ordered]@{ type = 'both'; url = $todo[0]; dir = (Split-Path -Parent $todo[0]); from = 0; to = 0; fromTxt = '00:00:00'; toTxt = 'het'
        h = 99999; exact = $false; split = 0; name = ''; fneg = $false; tneg = $false; txt = $true; tend = $true; wmodel = $wm; only_txt = $true; files = $todo })
})

$btnGo.Add_Click({
    if (Job-Pid) { Show-Msg 'Đang có một lượt chạy. Đợi lượt đó xong (hoặc bấm Dừng) rồi hãy làm tiếp, để YouTube không chặn.' 'Warning'; return }
    $url = $txtUrl.Text.Trim().Trim('"')
    $isLocal = ($url -notmatch '^https?://') -and $url -and (Test-Path -LiteralPath $url -PathType Leaf)
    if (-not $isLocal -and $url -notmatch '^https?://') { Show-Msg 'Hãy dán link YouTube, hoặc bấm "Chọn file…" để chọn video trên máy.' 'Warning'; return }
    $folder = $txtFolder.Text.Trim().TrimEnd('\')
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { Show-Msg 'Thư mục lưu không tồn tại.' 'Warning'; return }
    $fT = $txtFrom.Text.Trim(); if (-not $fT) { $fT = '00:00:00' }
    $tT = $txtTo.Text.Trim()
    $fNeg = $fT.StartsWith('-'); $tEnd = ($tT -eq ''); $tNeg = (-not $tEnd) -and $tT.StartsWith('-')
    $from = Convert-ToSeconds $fT
    $to = 0; if (-not $tEnd) { $to = Convert-ToSeconds $tT }
    if ($null -eq $from -or (-not $tEnd -and $null -eq $to)) { Show-Msg 'Mốc thời gian phải ghi dạng giờ:phút:giây, ví dụ 01:15:00 hoặc -4:31:41' 'Warning'; return }
    if ($isLocal -and ($fNeg -or $tNeg)) { Show-Msg 'Với file trên máy chỉ dùng số dương, tính từ đầu file.' 'Warning'; return }
    if (-not $tEnd -and -not $fNeg -and -not $tNeg -and $to -le $from) { Show-Msg 'Mốc "đến" phải lớn hơn mốc "từ".' 'Warning'; return }
    if (-not $tEnd -and $fNeg -and $tNeg -and $to -ge $from) { Show-Msg 'Với số âm: mốc "từ" phải âm nhiều hơn mốc "đến". Ví dụ từ -4:31:41 đến -4:30:00' 'Warning'; return }
    try { Set-Content -LiteralPath $ConfFile -Value $folder -Encoding UTF8 } catch {}

    $name = $txtName.Text.Trim() -replace '[\\/:*?"<>|]', '-'
    $name = ($name -replace '\.(mp3|mp4)$', '').Trim().TrimEnd('.')
    $i = Sel
    $type = 'both'; if ($i -eq 0) { $type = 'audio' }
    $h = [int]((Cur).h[$i])
    $exact = [bool]$swExact.Tag -and $i -gt 0
    $split = 0; if ($swSplit.Tag) { $split = [int]$numSplit.Value }
    $txtOn = [bool]$swTxt.Tag
    $wmodel = @('groq', 'base.en', 'small.en')[$cmbW.SelectedIndex]
    if ($txtOn -and $wmodel -eq 'groq' -and -not (Test-Path -LiteralPath $GroqKeyFile)) {
        if (-not (Ask-GroqKey)) { $cmbW.SelectedIndex = 1; $wmodel = 'base.en'; Show-Msg 'Chưa có key Groq nên lượt này quét trên máy.' 'Information' }
    }
    try { Set-Content -LiteralPath $EngFile -Value $cmbW.SelectedIndex } catch {}
    if ($isLocal -and $from -eq 0 -and $tEnd -and $type -eq 'both' -and $h -eq 99999 -and -not $exact -and $split -eq 0 -and -not $txtOn) {
        Show-Msg 'Bạn đang lấy nguyên file, giữ nguyên chất lượng, không chia nhỏ: không có gì để cắt. Bật "Xuất phụ đề txt" nếu chỉ muốn quét lời nói.' 'Warning'; return
    }
    Start-Job2 ([ordered]@{
        type = $type; url = $url; dir = $folder; from = $from; to = $to; fromTxt = $fT; toTxt = $(if ($tEnd) { 'het' } else { $tT })
        h = $h; exact = $exact; split = $split; name = $name; fneg = $fNeg; tneg = $tNeg; txt = $txtOn; tend = $tEnd; wmodel = $wmodel
        only_txt = ($isLocal -and $from -eq 0 -and $tEnd -and $h -eq 99999 -and $type -eq 'both' -and -not $exact -and $split -eq 0)
    })
})

# Mo app khi dang co luot chay -> hien tien do luon
if (Job-Pid) { Show-Prog }
$form.TopMost = $true
$form.Add_Shown({ $form.Activate(); $form.TopMost = $false })
[void]$form.ShowDialog()
