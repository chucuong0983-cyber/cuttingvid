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

$AppVersion = '1.26'
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

# ---------- Giao dien ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = "$AppName  ·  v$AppVersion"
$form.ClientSize = New-Object System.Drawing.Size(560, 600)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$icoPath = Join-Path $Here 'icon.ico'
if (Test-Path -LiteralPath $icoPath) { try { $form.Icon = New-Object System.Drawing.Icon($icoPath) } catch {} }

# Dau trang: logo + ten
$pic = New-Object System.Windows.Forms.PictureBox
$pic.Location = New-Object System.Drawing.Point(18, 14); $pic.Size = New-Object System.Drawing.Size(56, 56); $pic.SizeMode = 'Zoom'
if (Test-Path -LiteralPath $icoPath) { try { $pic.Image = (New-Object System.Drawing.Icon($icoPath, 256, 256)).ToBitmap() } catch {} }
$form.Controls.Add($pic)
$lblHead = New-Ctl Label "$AppName  ·  v$AppVersion" 86 28 $null $null
$lblHead.Font = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)

$lblUrl = New-Ctl Label 'Link YouTube (đang live hay đã xong), hoặc chọn file trên máy:' 18 86 $null $null
$txtUrl = New-Ctl TextBox $null 18 110 352 27
$btnFile = New-Ctl Button 'Chọn file' 378 108 82 30
$btnPaste = New-Ctl Button 'Dán' 466 108 76 30

[void](New-Ctl Label 'Cắt từ:' 18 153 $null $null)
$txtFrom = New-Ctl TextBox '00:00:00' 78 150 100 27
[void](New-Ctl Label 'đến:' 196 153 $null $null)
$txtTo = New-Ctl TextBox '00:05:00' 240 150 100 27
$lblHint = New-Ctl Label 'Đang live: gõ số âm như YouTube, vd -4:31:41. Trống ô "đến" = tới hiện tại / hết video.' 18 182 530 20
$lblHint.ForeColor = [System.Drawing.Color]::DimGray

[void](New-Ctl Label 'Lấy:' 18 215 $null $null)
$cmbType = New-Ctl ComboBox $null 78 212 464 27
$cmbType.DropDownStyle = 'DropDownList'
$lblSize = New-Ctl Label '' 78 240 464 20
$lblSize.ForeColor = [System.Drawing.Color]::DimGray

$chkTxt = New-Object System.Windows.Forms.CheckBox
$chkTxt.Text = 'Xuất phụ đề txt'; $chkTxt.Location = New-Object System.Drawing.Point(18, 270); $chkTxt.Size = New-Object System.Drawing.Size(140, 24)
$form.Controls.Add($chkTxt)
$cmbW = New-Ctl ComboBox $null 160 268 382 27
$cmbW.DropDownStyle = 'DropDownList'
[void]$cmbW.Items.Add('Nhanh (base.en, nhanh gấp 2-3 lần)')
[void]$cmbW.Items.Add('Chính xác (small.en, chậm)')
$cmbW.SelectedIndex = 0

$chkExact = New-Object System.Windows.Forms.CheckBox
$chkExact.Text = 'Cắt chính xác từng giây (chậm hơn, dùng khi cắt bản cuối)'
$chkExact.Location = New-Object System.Drawing.Point(18, 302); $chkExact.Size = New-Object System.Drawing.Size(524, 24)
$form.Controls.Add($chkExact)

$chkSplit = New-Object System.Windows.Forms.CheckBox
$chkSplit.Text = 'Chia nhỏ, mỗi phần'; $chkSplit.Location = New-Object System.Drawing.Point(18, 334); $chkSplit.Size = New-Object System.Drawing.Size(150, 24)
$form.Controls.Add($chkSplit)
$numSplit = New-Object System.Windows.Forms.NumericUpDown
$numSplit.Location = New-Object System.Drawing.Point(170, 333); $numSplit.Size = New-Object System.Drawing.Size(60, 27)
$numSplit.Minimum = 1; $numSplit.Maximum = 240; $numSplit.Value = 30
$form.Controls.Add($numSplit)
$lblSplit = New-Ctl Label 'phút (gửi Claude: dưới 400MB/phần)' 236 336 310 20

[void](New-Ctl Label 'Tên file (để trống = tự đặt theo mốc thời gian):' 18 372 $null $null)
$txtName = New-Ctl TextBox $null 18 396 524 27

[void](New-Ctl Label 'Lưu vào:' 18 434 $null $null)
$txtFolder = New-Ctl TextBox $null 18 458 436 27
$btnBrowse = New-Ctl Button 'Đổi…' 462 456 80 30
$saved = ''
if (Test-Path -LiteralPath $ConfFile) { $saved = (Get-Content -LiteralPath $ConfFile -Raw -ErrorAction SilentlyContinue).Trim() }
if ($saved -and (Test-Path -LiteralPath $saved -PathType Container)) { $txtFolder.Text = $saved } else { $txtFolder.Text = [Environment]::GetFolderPath('Desktop') }

$btnGo = New-Ctl Button 'CẮT VÀ TẢI VỀ' 18 502 524 48
$btnGo.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$btnGo.BackColor = [System.Drawing.Color]::FromArgb(17, 17, 17)
$btnGo.ForeColor = [System.Drawing.Color]::White
$btnGo.FlatStyle = 'Flat'
$form.AcceptButton = $btnGo

$lnkUpdate = New-Object System.Windows.Forms.LinkLabel
$lnkUpdate.Text = 'Bị lỗi không tải được? Bấm để cập nhật yt-dlp'
$lnkUpdate.Location = New-Object System.Drawing.Point(18, 566); $lnkUpdate.AutoSize = $true
$form.Controls.Add($lnkUpdate)
$btnExit = New-Ctl Button 'Thoát' 462 560 80 30

# ---------- Che do: link YouTube / file tren may ----------
$script:modeLocal = $null
$M = @{
    web   = @{ items = @('1. Chỉ tiếng (MP3)', '2. Tiếng + hình 480p (MP4), nhẹ, hợp để dò đoạn', '3. Tiếng + hình 1080p (MP4)', '4. Tiếng + hình 2K 1440p (MP4)');
              h = @('1080', '480', '1080', '1440'); mb = @(1, 7.5, 40, 80);
              size = @('Khoảng 1MB / phút', 'Khoảng 6-9MB / phút', 'Khoảng 30-50MB / phút', 'Khoảng 60-100MB / phút (live thường chỉ có tới 1080p)') }
    local = @{ items = @('1. Chỉ tiếng (MP3)', '2. Giữ nguyên chất lượng gốc (MP4)', '3. Thu nhỏ xuống 480p (MP4, nhẹ hơn)', '4. Thu nhỏ xuống 1080p (MP4)');
              h = @('99999', '99999', '480', '1080'); mb = @(1, 40, 7.5, 40);
              size = @('Khoảng 1MB / phút', 'Giữ nguyên hình như file gốc, không bị mờ, cắt rất nhanh', 'Nhẹ hơn nhưng sẽ mờ hơn file gốc', 'Chỉ mờ hơn nếu file gốc nét hơn 1080p') }
}
function Cur { if ($script:modeLocal) { return $M.local } else { return $M.web } }
$updAll = {
    $i = $cmbType.SelectedIndex
    if ($i -ge 0) {
        $lblSize.Text = (Cur).size[$i]
        $mb = [int]([double]$numSplit.Value * (Cur).mb[$i])
        $lblSplit.Text = "phút  (≈ $mb MB/phần; gửi Claude: dưới 400MB)"
    }
    $numSplit.Enabled = $chkSplit.Checked
    $cmbW.Enabled = $chkTxt.Checked
    $chkExact.Enabled = ($i -gt 0)
}
function Set-Mode([bool]$local) {
    if ($script:modeLocal -eq $local) { return }
    $script:modeLocal = $local
    $cmbType.Items.Clear()
    foreach ($it in (Cur).items) { [void]$cmbType.Items.Add($it) }
    $cmbType.SelectedIndex = 1
    $chkExact.Checked = $false
    if ($local) {
        $btnGo.Text = 'CẮT'
        $lblUrl.Text = 'File trên máy (bấm "Chọn file" để đổi):'
        $lblHint.Text = 'giờ:phút:giây tính từ đầu file. Để trống ô "đến" = tới hết file.'
    } else {
        $btnGo.Text = 'CẮT VÀ TẢI VỀ'
        $lblUrl.Text = 'Link YouTube (đang live hay đã xong), hoặc chọn file trên máy:'
        $lblHint.Text = 'Đang live: gõ số âm như YouTube, vd -4:31:41. Trống ô "đến" = tới hiện tại / hết video.'
    }
    & $updAll
}
$cmbType.Add_SelectedIndexChanged($updAll); $numSplit.Add_ValueChanged($updAll)
$chkSplit.Add_CheckedChanged($updAll); $chkTxt.Add_CheckedChanged($updAll)
$txtUrl.Add_TextChanged({
    $t = $txtUrl.Text.Trim().Trim('"')
    Set-Mode ([bool]($t -and ($t -notmatch '^https?://') -and (Test-Path -LiteralPath $t -PathType Leaf -ErrorAction SilentlyContinue)))
})
Set-Mode $false

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
    if ($dlg.ShowDialog() -eq 'OK') { $txtFolder.Text = $dlg.SelectedPath }
})
$lnkUpdate.Add_LinkClicked({
    Start-Process powershell.exe -ArgumentList '-NoExit', '-Command', 'yt-dlp -U; winget upgrade yt-dlp.yt-dlp; Write-Host ''Xong. Dong cua so nay roi thu tai lai.'' -ForegroundColor Green'
})
$btnExit.Add_Click({ $form.Close() })
$form.Add_FormClosing({
    param($sender, $e)
    $r = [System.Windows.Forms.MessageBox]::Show($form, 'Bạn có chắc muốn thoát app không?', $AppName, 'YesNo', 'Question', 'Button2')
    if ($r -ne 'Yes') { $e.Cancel = $true }
})

$btnGo.Add_Click({
    if (Test-Path -LiteralPath $LockFile) {
        $old = (Get-Content -LiteralPath $LockFile -Raw -ErrorAction SilentlyContinue)
        if ($old -and $old.Trim() -match '^\d+$' -and (Get-Process -Id ([int]$old.Trim()) -ErrorAction SilentlyContinue)) {
            Show-Msg 'Đang có một lượt tải / cắt chạy. Đợi lượt đó xong (hoặc đóng cửa sổ đen của nó) rồi hãy làm tiếp, để YouTube không chặn.' 'Warning'; return
        }
    }
    $url = $txtUrl.Text.Trim().Trim('"')
    $isLocal = ($url -notmatch '^https?://') -and $url -and (Test-Path -LiteralPath $url -PathType Leaf)
    if (-not $isLocal -and $url -notmatch '^https?://') { Show-Msg 'Hãy dán link YouTube, hoặc bấm "Chọn file" để chọn video trên máy.' 'Warning'; return }
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
    $i = $cmbType.SelectedIndex
    $type = 'both'; if ($i -eq 0) { $type = 'audio' }
    $h = [int]((Cur).h[$i])
    $exact = $chkExact.Checked -and $i -gt 0
    $split = 0; if ($chkSplit.Checked) { $split = [int]$numSplit.Value }
    $wmodel = 'base.en'; if ($cmbW.SelectedIndex -eq 1) { $wmodel = 'small.en' }

    # File tren may, lay ca file, giu nguyen, khong chia, chi can phu de -> van chay job (job tu quet)
    if ($isLocal -and $from -eq 0 -and $tEnd -and $type -eq 'both' -and $h -eq 99999 -and -not $exact -and $split -eq 0 -and -not $chkTxt.Checked) {
        Show-Msg 'Bạn đang lấy nguyên file, giữ nguyên chất lượng, không chia nhỏ: không có gì để cắt. Tick "Xuất phụ đề txt" nếu chỉ muốn quét lời nói.' 'Warning'; return
    }

    $params = [ordered]@{
        type = $type; url = $url; dir = $folder; from = $from; to = $to; fromTxt = $fT; toTxt = $(if ($tEnd) { 'het' } else { $tT })
        h = $h; exact = $exact; split = $split; name = $name; fneg = $fNeg; tneg = $tNeg; txt = $chkTxt.Checked; tend = $tEnd; wmodel = $wmodel
        only_txt = ($isLocal -and $from -eq 0 -and $tEnd -and $h -eq 99999 -and $type -eq 'both' -and -not $exact -and $split -eq 0)
    }
    $stamp = [guid]::NewGuid().ToString('N')
    $pf = Join-Path $env:TEMP "scv_params_$stamp.json"
    $jf = Join-Path $env:TEMP "scv_job_$stamp.ps1"
    [IO.File]::WriteAllText($pf, ($params | ConvertTo-Json), (New-Object System.Text.UTF8Encoding($false)))
    Copy-Item -LiteralPath (Join-Path $Here 'job.ps1') -Destination $jf -Force   # ban sao rieng: cap nhat app khong anh huong luot dang chay

    $btnGo.Enabled = $false
    $jp = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $jf + '"'), '-ParamFile', ('"' + $pf + '"') -PassThru
    try { Set-Content -LiteralPath $LockFile -Value $jp.Id -ErrorAction Stop } catch {}
    $tm = New-Object System.Windows.Forms.Timer
    $tm.Interval = 4000
    $tm.Add_Tick({ $btnGo.Enabled = $true; $this.Stop(); $this.Dispose() })
    $tm.Start()
})

$form.TopMost = $true
$form.Add_Shown({ $form.Activate(); $form.TopMost = $false })
[void]$form.ShowDialog()
