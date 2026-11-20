// CuttingVid by Louis Chu (Mac) - cua so chinh + kiem tra + chay lenh trong Terminal.
// Chay bang: exec osascript -l JavaScript app.js RES CONF TITLE ICON
// (exec de chinh app CuttingVid hien tren Dock voi logo, ghim duoc)
ObjC.import('Cocoa');
try { ObjC.import('WebKit'); } catch (e) {}

var WEBCODE = 0;
function stopWith(c) { WEBCODE = c; try { $.NSApplication.sharedApplication.stopModalWithCode(c); } catch (e) {} }
ObjC.registerSubclass({
  name: 'CVTarget',
  methods: {
    'go:': { types: ['void', ['id']], implementation: function (sender) { stopWith(1000); } },
    'dir:': { types: ['void', ['id']], implementation: function (sender) { stopWith(2002); } },
    'pick:': {
      types: ['void', ['id']],
      implementation: function (sender) {
        var i = 0; try { i = Number(sender.indexOfSelectedItem); } catch (e) {}
        if (i >= 1 && i <= 4) stopWith(2000 + i * 10); // 2010 file, 2020 quet nhieu, 2030 key, 2040 mo thu muc
        else if (i === 5) stopWith(2003);              // Thoat
      }
    },
    'tick:': { types: ['void', ['id']], implementation: function (t) { try { if (typeof webTick === 'function') webTick(); } catch (e) {} } },
    'windowShouldClose:': { types: ['bool', ['id']], implementation: function (w) { stopWith(2003); return false; } }
  }
});

var RES, CONF, TITLE, ICONIMG = null, TGT = null;
var ENGINES = ['groq', 'fw-fast', 'fw-acc'];

function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
function exists(p) { return p && $.NSFileManager.defaultManager.fileExistsAtPath(p); }
function isDir(p) {
  var d = Ref();
  return p && $.NSFileManager.defaultManager.fileExistsAtPathIsDirectory(p, d) && d[0];
}
function isLocal(u) { return !!u && !/^https?:\/\//i.test(u) && exists(u) && !isDir(u); }
function readText(p) {
  var s = $.NSString.stringWithContentsOfFileEncodingError(p, $.NSUTF8StringEncoding, null);
  return (s && !s.isNil()) ? s.js.trim() : '';
}
function writeText(p, t) { $(t).writeToFileAtomicallyEncodingError(p, true, $.NSUTF8StringEncoding, null); }
function clip() {
  var s = $.NSPasteboard.generalPasteboard.stringForType($.NSPasteboardTypeString);
  var t = (s && !s.isNil()) ? s.js.split('\n')[0].trim() : '';
  return /^https?:\/\//i.test(t) ? t : '';
}
function toSec(s) {
  s = String(s).replace(/\s/g, '').replace(/^-/, '');
  var m = s.match(/^(\d{1,3}):(\d{1,2}):(\d{1,2})$/);
  if (m) return (+m[1]) * 3600 + (+m[2]) * 60 + (+m[3]);
  m = s.match(/^(\d{1,3}):(\d{1,2})$/);
  if (m) return (+m[1]) * 60 + (+m[2]);
  return null;
}

function alertBox(text, buttons, style) {
  var a = $.NSAlert.alloc.init;
  a.setMessageText(TITLE);
  a.setInformativeText(text);
  if (style) a.setAlertStyle(style);
  if (ICONIMG) a.setIcon(ICONIMG);
  for (var i = 0; i < buttons.length; i++) a.addButtonWithTitle(buttons[i]);
  return a.runModal - 1000;
}
// Hoi API key Groq (luu tai CONF/groq_key.txt, chi tren may nay)
function askGroqKey() {
  var a = $.NSAlert.alloc.init;
  a.setMessageText(TITLE);
  a.setInformativeText('Chế độ Siêu nhanh dùng Groq (miễn phí, không cần thẻ).\n\n1. Bấm "Mở trang lấy key" → đăng nhập Google\n2. Bấm "Create API Key" → copy\n3. Dán vào ô dưới rồi bấm Lưu.\n\nKey chỉ lưu trên máy này.');
  if (ICONIMG) a.setIcon(ICONIMG);
  a.addButtonWithTitle('Lưu'); a.addButtonWithTitle('Mở trang lấy key'); a.addButtonWithTitle('Hủy');
  var f = $.NSTextField.alloc.initWithFrame($.NSMakeRect(0, 0, 320, 24));
  f.setPlaceholderString('gsk_...');
  a.setAccessoryView(f);
  while (true) {
    a.window.setInitialFirstResponder(f);
    var r = a.runModal - 1000;
    if (r === 1) { $.NSWorkspace.sharedWorkspace.openURL($.NSURL.URLWithString('https://console.groq.com/keys')); continue; }
    if (r !== 0) return false;
    var k = f.stringValue.js.trim();
    if (/^gsk_\S{20,}$/.test(k)) { writeText(CONF + '/groq_key.txt', k); return true; }
    alertBox('Key không đúng dạng (phải bắt đầu bằng gsk_). Thử lại nhé.', ['OK'], 1);
  }
}
function msg(t) { alertBox(t, ['OK'], 1); }
function confirmExit() { return alertBox('Bạn có chắc muốn thoát app không?', ['Không', 'Thoát']) === 1; }
function openPanel(dir, multi) {
  var p = $.NSOpenPanel.openPanel;
  p.setCanChooseFiles(!dir);
  p.setCanChooseDirectories(dir);
  p.setAllowsMultipleSelection(!!multi);
  p.setMessage(dir ? 'Chọn thư mục lưu file' : multi ? 'Chọn các file cần quét phụ đề (giữ Command hoặc Shift để chọn nhiều)' : 'Chọn file video / âm thanh để cắt');
  if (p.runModal != 1) return multi ? [] : '';
  if (!multi) return p.URL.path.js;
  var out = [], u = p.URLs, n = u.count;
  for (var i = 0; i < n; i++) out.push(u.objectAtIndex(i).path.js);
  return out;
}

function showForm(st) {
  var local = isLocal(st.url);
  var W = 480, H = 420;
  var v = $.NSView.alloc.initWithFrame($.NSMakeRect(0, 0, W, H));
  function label(t, x, y, w) { var l = $.NSTextField.labelWithString(t); l.setFrame($.NSMakeRect(x, y, w, 18)); v.addSubview(l); return l; }
  function small(t, x, y, w) { var l = label(t, x, y, w); l.setFont($.NSFont.systemFontOfSize(11)); l.setTextColor($.NSColor.secondaryLabelColor); return l; }
  function field(t, x, y, w) { var f = $.NSTextField.alloc.initWithFrame($.NSMakeRect(x, y, w, 24)); f.setStringValue(t); v.addSubview(f); return f; }
  function check(t, x, y, w, on) {
    var b = $.NSButton.alloc.initWithFrame($.NSMakeRect(x, y, w, 22));
    b.setButtonType(3); b.setTitle(t); b.setState(on ? 1 : 0); v.addSubview(b); return b;
  }

  // Menu so xuong o goc tren ben phai
  var menu = $.NSPopUpButton.alloc.initWithFramePullsDown($.NSMakeRect(W - 120, 390, 120, 28), true);
  ['Tùy chọn ▾', 'Chọn file trên máy để cắt…', 'Chỉ quét phụ đề nhiều file…', 'Nhập / đổi key Groq…', 'Mở thư mục lưu', 'Thoát'].forEach(function (t) { menu.addItemWithTitle(t); });
  menu.setTarget(TGT);
  menu.setAction('pick:');
  v.addSubview(menu);

  label(local ? 'File trên máy:' : 'Link YouTube (đang live hay đã xong):', 0, 394, W - 130);
  var fUrl = field(st.url, 0, 362, W);

  label('Cắt từ:', 0, 330, 60);
  var fFrom = field(st.from, 60, 326, 110);
  label('đến:', 190, 330, 40);
  var fTo = field(st.to, 230, 326, 110);
  small(local ? 'giờ:phút:giây tính từ đầu file. Để trống ô "đến" = tới hết file.'
              : 'Đang live: gõ số âm như YouTube, vd -4:31:41. Trống ô "đến" = tới hiện tại / hết video.', 0, 304, W);

  label('Lấy:', 0, 272, 40);
  var pop = $.NSPopUpButton.alloc.initWithFramePullsDown($.NSMakeRect(56, 266, W - 56, 28), false);
  var items = local
    ? ['1. Chỉ tiếng (MP3)', '2. Giữ nguyên chất lượng gốc (MP4)', '3. Thu nhỏ xuống 480p (MP4, nhẹ hơn)', '4. Thu nhỏ xuống 1080p (MP4)']
    : ['1. Chỉ tiếng (MP3)', '2. Tiếng + hình 480p (MP4), nhẹ, hợp để dò đoạn', '3. Tiếng + hình 1080p (MP4)', '4. Tiếng + hình 2K 1440p (MP4)'];
  items.forEach(function (t) { pop.addItemWithTitle(t); });
  pop.selectItemAtIndex(st.idx);
  v.addSubview(pop);

  var cTxt = check('Xuất phụ đề txt', 0, 228, 150, st.txt);
  var popW = $.NSPopUpButton.alloc.initWithFramePullsDown($.NSMakeRect(150, 224, W - 150, 28), false);
  ['Siêu nhanh qua mạng (Groq, miễn phí, cần key)', 'Nhanh trên máy (faster-whisper)', 'Chính xác trên máy (chậm hơn)'].forEach(function (t) { popW.addItemWithTitle(t); });
  popW.selectItemAtIndex(Math.max(0, ENGINES.indexOf(st.wmodel)));
  v.addSubview(popW);
  var cExact = check('Cắt chính xác từng giây (chậm hơn, dùng khi cắt bản cuối)', 0, 200, W, st.exact);
  var cSplit = check('Chia nhỏ, mỗi phần', 0, 172, 150, st.split);
  var fMin = field(st.min, 150, 171, 50);
  label('phút / phần (mỗi phần có txt riêng)', 206, 175, W - 206);

  label('Tên file (để trống = tự đặt theo mốc thời gian):', 0, 136, W);
  var fName = field(st.name, 0, 108, W);

  label('Lưu vào:', 0, 76, W);
  var fDir = field(st.dir, 0, 48, W - 110);
  var bDir = $.NSButton.alloc.initWithFrame($.NSMakeRect(W - 102, 45, 102, 30));
  bDir.setTitle('Đổi…'); bDir.setBezelStyle(1);
  bDir.setTarget(TGT); bDir.setAction('dir:');
  v.addSubview(bDir);
  small('Chọn file trên máy, quét phụ đề nhiều file, key Groq: menu "Tùy chọn ▾" ở góc trên.', 0, 18, W);

  var CW = W + 40, CH = H + 170;
  var win = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer($.NSMakeRect(0, 0, CW, CH), 1 | 2 | 4, 2, false);
  win.setTitle(TITLE);
  win.setReleasedWhenClosed(false);
  win.setDelegate(TGT);
  var cv = win.contentView;
  if (ICONIMG) {
    var iv = $.NSImageView.alloc.initWithFrame($.NSMakeRect(20, CH - 84, 64, 64));
    iv.setImage(ICONIMG); cv.addSubview(iv);
  }
  var head = $.NSTextField.labelWithString(TITLE);
  head.setFont($.NSFont.boldSystemFontOfSize(18));
  head.setFrame($.NSMakeRect(96, CH - 62, CW - 116, 26)); cv.addSubview(head);
  v.setFrame($.NSMakeRect(20, 76, W, H)); cv.addSubview(v);
  var go = $.NSButton.alloc.initWithFrame($.NSMakeRect(CW / 2 - 120, 20, 240, 40));
  go.setTitle(local ? 'CẮT' : 'CẮT VÀ TẢI VỀ');
  go.setBezelStyle(1);
  go.setKeyEquivalent('\r');
  go.setTarget(TGT); go.setAction('go:');
  cv.addSubview(go);
  win.setInitialFirstResponder(fUrl);
  win.center;
  win.makeKeyAndOrderFront(null);
  var code = $.NSApplication.sharedApplication.runModalForWindow(win);
  win.orderOut(null);

  st.url = fUrl.stringValue.js.trim().replace(/^"|"$/g, '');
  st.from = fFrom.stringValue.js; st.to = fTo.stringValue.js;
  st.idx = pop.indexOfSelectedItem;
  st.txt = cTxt.state == 1; st.wmodel = ENGINES[popW.indexOfSelectedItem] || 'fw-fast'; st.exact = cExact.state == 1; st.split = cSplit.state == 1;
  st.min = fMin.stringValue.js; st.name = fName.stringValue.js; st.dir = fDir.stringValue.js.trim();
  if (code == 2010) return 'file';
  if (code == 2020) return 'multi';
  if (code == 2030) return 'key';
  if (code == 2040) return 'open';
  if (code == 2002) return 'dir';
  if (code == 1000) return 'go';
  return 'quit';
}

function terminal(cmd) {
  var T = Application('Terminal');
  T.activate();
  T.doScript(cmd);
}

function runClassic(argv) {
  RES = argv[0]; CONF = argv[1]; TITLE = argv[2];
  var app = $.NSApplication.sharedApplication;
  app.setActivationPolicy(0);
  var img = $.NSImage.alloc.initWithContentsOfFile(argv[3]);
  if (img && !img.isNil()) { ICONIMG = img; app.setApplicationIconImage(img); }
  app.activateIgnoringOtherApps(true);
  TGT = $.CVTarget.alloc.init;
  if (argv[4]) alertBox(argv[4] + ' Những thay đổi mới đã có hiệu lực.', ['OK']);

  var dir = readText(CONF + '/folder');
  if (!isDir(dir)) dir = $.NSHomeDirectory().js + '/Desktop';
  var st = { url: clip(), from: '00:00:00', to: '00:05:00', idx: 1, wmodel: readText(CONF + '/engine') || 'fw-fast', exact: false, split: false, min: '30', txt: false, name: '', dir: dir };

  while (true) {
    var r;
    try { r = showForm(st); } catch (e) { msg('App gặp lỗi: ' + e + '\nChụp màn hình gửi lại để sửa.'); continue; }
    if (r === 'quit') { if (confirmExit()) return ''; continue; }
    if (r === 'file') { var f = openPanel(false); if (f) { st.url = f; if (st.to === '00:05:00') st.to = ''; st.idx = 1; } continue; }
    if (r === 'dir') { var d = openPanel(true); if (d) st.dir = d; continue; }
    if (r === 'key') { askGroqKey(); continue; }
    if (r === 'open') { if (isDir(st.dir)) $.NSWorkspace.sharedWorkspace.openFile(st.dir); continue; }
    if (r === 'multi') {
      var fs = openPanel(false, true);
      if (!fs.length) continue;
      var todo = fs.filter(function (f) { return !exists(f.replace(/\.[^.\/]+$/, '') + '.txt'); });
      if (todo.length < fs.length) {
        var c = alertBox((fs.length - todo.length) + ' / ' + fs.length + ' file đã có txt. Quét lại cả những file đó?', ['Chỉ quét file chưa có txt', 'Quét lại tất cả', 'Hủy']);
        if (c === 2) continue;
        if (c === 1) todo = fs;
      }
      if (!todo.length) continue;
      if (st.wmodel === 'groq' && !readText(CONF + '/groq_key.txt') && !askGroqKey()) st.wmodel = 'fw-fast';
      writeText(CONF + '/engine', st.wmodel);
      terminal('clear; CV_NOOPEN=1 bash ' + [RES + '/transcribe.sh', st.wmodel, 'auto'].concat(todo).map(q).join(' ') + '; open ' + q(todo[0].replace(/\/[^\/]*$/, '')));
      return '';
    }

    // --- kiem tra ---
    var local = isLocal(st.url);
    if (!local && !/^https?:\/\//i.test(st.url)) { msg('Hãy dán link YouTube, hoặc chọn "Chọn file trên máy…" trong menu Tùy chọn.'); continue; }
    st.dir = st.dir.replace(/\/+$/, '');
    if (!isDir(st.dir)) { msg('Thư mục lưu không tồn tại.'); continue; }
    var fromT = st.from.replace(/\s/g, '') || '00:00:00', toT = st.to.replace(/\s/g, '');
    var from = toSec(fromT), fneg = fromT.charAt(0) === '-';
    var tend = toT === '', to = tend ? 0 : toSec(toT), tneg = !tend && toT.charAt(0) === '-';
    if (from === null || (!tend && to === null)) { msg('Mốc thời gian phải ghi dạng giờ:phút:giây, ví dụ 01:15:00 hoặc -4:31:41'); continue; }
    if (local && (fneg || tneg)) { msg('Với file trên máy chỉ dùng số dương, tính từ đầu file.'); continue; }
    if (!tend && !fneg && !tneg && to <= from) { msg('Mốc "đến" phải lớn hơn mốc "từ".'); continue; }
    if (!tend && fneg && tneg && to >= from) { msg('Với số âm: mốc "từ" phải âm nhiều hơn mốc "đến". Ví dụ từ -4:31:41 đến -4:30:00'); continue; }
    if (st.split && !(/^\d+$/.test(st.min) && +st.min >= 1)) { msg('Số phút mỗi phần phải là số, ví dụ 30'); continue; }

    if (st.txt && st.wmodel === 'groq' && !readText(CONF + '/groq_key.txt')) {
      if (!askGroqKey()) { st.wmodel = 'fw-fast'; msg('Chưa có key Groq nên app chuyển sang "Nhanh trên máy".'); continue; }
    }
    writeText(CONF + '/folder', st.dir);
    writeText(CONF + '/engine', st.wmodel);
    var name = st.name.replace(/[\/:]/g, '-').replace(/\.(mp3|mp4)$/i, '').trim();
    var type, h, exact = st.exact ? 1 : 0;
    if (st.idx === 0) { type = 'audio'; h = 1080; exact = 0; }
    else if (local) { type = 'both'; h = [0, 99999, 480, 1080][st.idx]; }
    else { type = 'both'; h = [0, 480, 1080, 1440][st.idx]; }
    var splitMin = st.split ? +st.min : 0;

    // File tren may, lay ca file, giu nguyen, khong chia: chi quet phu de
    if (local && from === 0 && tend && type === 'both' && h === 99999 && !exact && !splitMin) {
      if (st.txt) { terminal('clear; bash ' + [RES + '/transcribe.sh', st.wmodel, 'auto', st.url].map(q).join(' ')); return ''; }
      msg('Bạn đang lấy nguyên file, giữ nguyên chất lượng, không chia nhỏ: không có gì để cắt. Tick "Xuất phụ đề txt" nếu chỉ muốn quét lời nói.');
      continue;
    }

    var args = [RES + '/job.sh', type, st.url, st.dir, from, to, fromT, toT || 'het', h, exact, splitMin, name,
                fneg ? 1 : 0, tneg ? 1 : 0, st.txt ? 1 : 0, tend ? 1 : 0, st.wmodel];
    terminal('bash ' + args.map(q).join(' '));
    return '';
  }
}


// ======================= GIAO DIEN MOI (WebKit, than chi + vang kim) =======================
// Trang ui.html <-> app: trang dat document.title = "cv:<so>:<json lenh>", app doc title moi 0.2s,
// xu ly roi goi CV.ack(). App gui du lieu vao trang bang evaluateJavaScript.
var WV = null, WIN = null, SA = null, LASTT = '', TICKN = 0, RUNPID = '', WSTATE = null, STOPPING = false;
var LOG = '';

// Luu y: KHONG truyen null cho completionHandler (JXA boc null thanh block, WebKit goi lai -> loi "null is not an object")
function jsDone(r, e) {}
function js(code) { try { WV.evaluateJavaScriptCompletionHandler(code, jsDone); } catch (e) {} }
function sh(cmd) { try { return SA.doShellScript(cmd); } catch (e) { return ''; } }
function readTail(p, n) {
  var fh = $.NSFileHandle.fileHandleForReadingAtPath(p);
  if (!fh || fh.isNil()) return '';
  var size = Number(fh.seekToEndOfFile);
  fh.seekToFileOffset(Math.max(0, size - n));
  var d = fh.readDataToEndOfFile; fh.closeFile;
  var str = $.NSString.alloc.initWithDataEncoding(d, $.NSUTF8StringEncoding);
  if (!str || str.isNil()) str = $.NSString.alloc.initWithDataEncoding(d, $.NSISOLatin1StringEncoding);
  return (str && !str.isNil()) ? str.js : '';
}
function cleanLog(t) {
  t = t.replace(/\x1b\][^\x07]*\x07/g, '').replace(/\x1b\[[0-9;]*[A-Za-z]/g, '').replace(/\r/g, '\n');
  var L = t.split('\n').filter(function (x) { return x.trim() !== ''; });
  return L.slice(-12).join('\n');
}
function readProg(slot) {
  var t = readText(CONF + '/progress.' + slot);
  return t ? t.split('\t') : null;
}
function pidAlive(pid) { return !!pid && sh('kill -0 ' + pid + ' 2>/dev/null && echo 1 || echo 0') === '1'; }

// Kiem tra form -> {err} hoac {cmd: [...], txtOnly}
function prepare(st) {
  var local = isLocal(st.url);
  if (!st.url) return { err: 'Hãy dán link YouTube hoặc bấm "Chọn file…".' };
  if (!local && !/^https?:\/\//i.test(st.url)) return { err: 'Link không đúng, hoặc file trên máy không còn ở đó.' };
  st.dir = (st.dir || '').replace(/\/+$/, '');
  if (!isDir(st.dir)) return { err: 'Thư mục lưu không tồn tại. Bấm "Đổi…" để chọn lại.' };
  var fromT = (st.from || '').replace(/\s/g, '') || '00:00:00', toT = (st.to || '').replace(/\s/g, '');
  var from = toSec(fromT), fneg = fromT.charAt(0) === '-';
  var tend = toT === '', to = tend ? 0 : toSec(toT), tneg = !tend && toT.charAt(0) === '-';
  if (from === null || (!tend && to === null)) return { err: 'Mốc thời gian phải ghi dạng giờ:phút:giây, ví dụ 01:15:00 hoặc -4:31:41' };
  if (local && (fneg || tneg)) return { err: 'Với file trên máy chỉ dùng số dương, tính từ đầu file.' };
  if (!tend && !fneg && !tneg && to <= from) return { err: 'Mốc "đến" phải lớn hơn mốc "từ".' };
  if (!tend && fneg && tneg && to >= from) return { err: 'Với số âm: mốc "từ" phải âm nhiều hơn mốc "đến". Ví dụ từ -4:31:41 đến -4:30:00' };
  if (st.split && !(/^\d+$/.test(st.min) && +st.min >= 1)) return { err: 'Số phút mỗi phần phải là số, ví dụ 30' };
  var name = (st.name || '').replace(/[\/:]/g, '-').replace(/\.(mp3|mp4)$/i, '').trim();
  var type, h, exact = st.exact ? 1 : 0, idx = +st.idx;
  if (idx === 0) { type = 'audio'; h = 1080; exact = 0; }
  else if (local) { type = 'both'; h = [0, 99999, 480, 1080][idx]; }
  else { type = 'both'; h = [0, 480, 1080, 1440][idx]; }
  var splitMin = st.split ? +st.min : 0;
  if (local && from === 0 && tend && type === 'both' && h === 99999 && !exact && !splitMin) {
    if (st.txt) return { cmd: ['/bin/bash', RES + '/transcribe.sh', st.wmodel, 'auto', st.url], txtOnly: true };
    return { err: 'Bạn đang lấy nguyên file, giữ nguyên chất lượng, không chia nhỏ: không có gì để cắt. Bật "Xuất phụ đề txt" nếu chỉ muốn quét lời nói.' };
  }
  return { cmd: ['/bin/bash', RES + '/job.sh', type, st.url, st.dir, from, to, fromT, toT || 'het', h, exact, splitMin, name,
                 fneg ? 1 : 0, tneg ? 1 : 0, st.txt ? 1 : 0, tend ? 1 : 0, st.wmodel] };
}

// Chay nen (khong mo Terminal): nhom tien trinh rieng de nut "Dung" tat duoc ca yt-dlp / ffmpeg con
function launchBg(cmd) {
  LOG = CONF + '/job.log';
  sh('cd ' + q($.NSHomeDirectory().js) + '; rm -f ' + q(CONF) + '/progress.*; nohup /usr/bin/perl -e ' + q('setpgrp(0,0); exec @ARGV') +
     ' /bin/bash ' + q(RES + '/run.sh') + ' ' + cmd.map(q).join(' ') + ' > ' + q(LOG) + ' 2>&1 < /dev/null &');
  for (var i = 0; i < 20 && !RUNPID; i++) { delay(0.1); RUNPID = readText(CONF + '/running'); }
  js('CV.running()');
}
function jobRunning() {
  var pid = readText(CONF + '/running');
  return pidAlive(pid) ? pid : '';
}

function handle(m) {
  var d = m.data || {};
  switch (m.cmd) {
    case 'paste': js('CV.set(' + JSON.stringify({ url: clip() || '' }) + ')'); break;
    case 'file': {
      var f = openPanel(false);
      if (f) js('CV.set(' + JSON.stringify({ url: f, local: true }) + ')');
      break;
    }
    case 'dir': {
      var dd = openPanel(true);
      if (dd) { writeText(CONF + '/folder', dd); js('CV.set(' + JSON.stringify({ dir: dd }) + ')'); }
      break;
    }
    case 'opendir': if (isDir(d.dir)) $.NSWorkspace.sharedWorkspace.openFile(d.dir); break;
    case 'openres': {
      var r = readText(CONF + '/progress.result');
      if (r && isDir(r)) $.NSWorkspace.sharedWorkspace.openFile(r);
      else if (r && exists(r)) $.NSWorkspace.sharedWorkspace.selectFileInFileViewerRootedAtPath(r, '');
      break;
    }
    case 'key': if (askGroqKey()) js('CV.set({hasKey:true});CV.toast("Đã lưu key Groq.",1)'); break;
    case 'ytupdate':
      sh('(PATH="' + CONF + '/bin:$PATH" yt-dlp -U > /dev/null 2>&1 &)');
      js('CV.toast("Đang cập nhật yt-dlp ở nền (khoảng 1 phút). Xong thì thử tải lại.",1)');
      break;
    case 'showlog':
      terminal('clear; tail -n 200 -f ' + q(CONF + '/job.log'));
      break;
    case 'cancel':
      if (alertBox('Dừng lượt đang chạy? Phần nào đã xong vẫn giữ lại.', ['Không', 'Dừng']) === 1) {
        var pid = readText(CONF + '/running');
        if (pid) sh('kill -TERM -' + pid + ' 2>/dev/null; sleep 1; kill -KILL -' + pid + ' 2>/dev/null; true');
        writeText(CONF + '/progress.main', '-2\tĐã dừng\tBạn đã dừng lượt này');
        writeText(CONF + '/progress.done', '143');
      }
      break;
    case 'multi': {
      if (jobRunning()) { js('CV.toast("Đang có 1 lượt chạy. Đợi xong rồi làm tiếp nhé.")'); break; }
      var fs = openPanel(false, true);
      if (!fs.length) break;
      var todo = fs.filter(function (f) { return !exists(f.replace(/\.[^.\/]+$/, '') + '.txt'); });
      if (todo.length < fs.length) {
        var c = alertBox((fs.length - todo.length) + ' / ' + fs.length + ' file đã có txt. Quét lại cả những file đó?', ['Chỉ quét file chưa có txt', 'Quét lại tất cả', 'Hủy']);
        if (c === 2) break;
        if (c === 1) todo = fs;
      }
      if (!todo.length) break;
      var wm = readText(CONF + '/engine') || 'fw-fast';
      if (wm === 'groq' && !readText(CONF + '/groq_key.txt') && !askGroqKey()) wm = 'fw-fast';
      launchBg(['/bin/bash', RES + '/transcribe.sh', wm, 'auto'].concat(todo));
      break;
    }
    case 'go': {
      if (jobRunning()) { js('CV.toast("Đang có 1 lượt chạy. Đợi xong (hoặc bấm Dừng) rồi làm tiếp nhé.")'); break; }
      var st = d;
      var p = prepare(st);
      if (p.err) { js('CV.toast(' + JSON.stringify(p.err) + ')'); break; }
      if (st.txt && st.wmodel === 'groq' && !readText(CONF + '/groq_key.txt')) {
        if (!askGroqKey()) { js('CV.toast("Chưa có key Groq nên lượt này quét trên máy.",1)'); p.cmd[p.cmd.length - 1] = 'fw-fast'; if (p.txtOnly) p.cmd[2] = 'fw-fast'; }
        else js('CV.set({hasKey:true})');
      }
      writeText(CONF + '/folder', st.dir);
      writeText(CONF + '/engine', st.wmodel);
      launchBg(p.cmd);
      break;
    }
    case 'quit':
      stopWith(2003);
      break;
  }
}

function webTick() {
  if (!WV) return;
  TICKN++;
  var t = '';
  try { t = WV.title.js; } catch (e) { WSTATE.terr = String(e); }
  if (!WSTATE.sent && TICKN > 40) {
    var ld = ''; try { ld = String(WV.isLoading) + ' url=' + (WV.URL && !WV.URL.isNil() ? WV.URL.absoluteString.js : 'nil'); } catch (e) { ld = 'x ' + e; }
    WSTATE.why = 'trang không báo sẵn sàng (title="' + t + '", loading=' + ld + (WSTATE.terr ? ', ' + WSTATE.terr : '') + ')';
    stopWith(2999); return;
  }
  if (t === 'ready' && !WSTATE.sent) {
    WSTATE.sent = true;
    js('CV.init(' + JSON.stringify(WSTATE.init) + ')');
  }
  if (t !== LASTT && t.indexOf('cv:') === 0) {
    LASTT = t;
    var m = null;
    try { m = JSON.parse(t.slice(t.indexOf(':', 3) + 1)); } catch (e) {}
    if (m) { try { handle(m); } catch (e) { js('CV.toast(' + JSON.stringify('Lỗi: ' + e) + ')'); } }
    js('CV.ack()');
  }
  // Tien do: 2 lan / giay
  if (TICKN % 3 === 0 && (RUNPID || exists(CONF + '/progress.main') || exists(CONF + '/progress.txt'))) {
    var o = { main: readProg('main'), txt: readProg('txt'), log: cleanLog(readTail(CONF + '/job.log', 6000)) };
    var done = readText(CONF + '/progress.done');
    if (!done && RUNPID && TICKN % 15 === 0 && !pidAlive(RUNPID)) done = '1';
    if (done) {
      o.done = true; o.code = +done; o.result = readText(CONF + '/progress.result');
      RUNPID = '';
    }
    if (RUNPID || done || !WSTATE.lastDone) js('CV.progress(' + JSON.stringify(o) + ')');
    WSTATE.lastDone = !!done;
  }
}

function runWeb(argv) {
  if (typeof $.WKWebView === 'undefined' || !exists(RES + '/ui.html')) throw 'no webkit';
  SA = Application.currentApplication(); SA.includeStandardAdditions = true;
  var dir = readText(CONF + '/folder');
  if (!isDir(dir)) dir = $.NSHomeDirectory().js + '/Desktop';
  RUNPID = jobRunning();
  WSTATE = { sent: false, lastDone: false, init: {
    url: clip(), dir: dir, wmodel: readText(CONF + '/engine') || 'fw-fast', hasKey: !!readText(CONF + '/groq_key.txt'),
    version: (TITLE.match(/v([0-9.]+)/) || [0, ''])[1], running: !!RUNPID, msg: argv[4] ? argv[4] + ' Những thay đổi mới đã có hiệu lực.' : '' } };
  var W = 920, H = 820;
  WIN = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer($.NSMakeRect(0, 0, W, H), 1 | 2 | 4 | 8, 2, false);
  WIN.setTitle(TITLE);
  WIN.setTitlebarAppearsTransparent(true);
  WIN.setTitleVisibility(1);
  try { WIN.setAppearance($.NSAppearance.appearanceNamed('NSAppearanceNameDarkAqua')); } catch (e) {}
  WIN.setBackgroundColor($.NSColor.colorWithSRGBRedGreenBlueAlpha(0.102, 0.114, 0.133, 1));
  WIN.setMinSize($.NSMakeSize(820, 560));
  WIN.setReleasedWhenClosed(false);
  WIN.setDelegate(TGT);
  WSTATE.step = 'webview';
  var cfg = $.WKWebViewConfiguration.alloc.init;
  WV = $.WKWebView.alloc.initWithFrameConfiguration($.NSMakeRect(0, 0, W, H), cfg);
  try { WV.setValueForKey($(false), 'drawsBackground'); } catch (e) {}
  WV.setAutoresizingMask(2 | 16);
  WIN.contentView.addSubview(WV);
  var u = $.NSURL.fileURLWithPath(RES + '/ui.html');
  WV.loadFileURLAllowingReadAccessToURL(u, $.NSURL.fileURLWithPath(RES));
  WIN.center;
  WIN.makeKeyAndOrderFront(null);
  // Menu Sua (de Command+C / V / A / Z dung duoc trong o nhap)
  try {
    var mb = $.NSMenu.alloc.init, ai = $.NSMenuItem.alloc.init, am = $.NSMenu.alloc.initWithTitle('CuttingVid');
    am.addItemWithTitleActionKeyEquivalent('Thoát CuttingVid', 'terminate:', 'q'); ai.setSubmenu(am); mb.addItem(ai);
    var em = $.NSMenu.alloc.initWithTitle('Sửa'), ei = $.NSMenuItem.alloc.init;
    [['Hoàn tác', 'undo:', 'z'], ['Cắt', 'cut:', 'x'], ['Chép', 'copy:', 'c'], ['Dán', 'paste:', 'v'], ['Chọn tất cả', 'selectAll:', 'a']]
      .forEach(function (a) { em.addItemWithTitleActionKeyEquivalent(a[0], a[1], a[2]); });
    ei.setSubmenu(em); mb.addItem(ei);
    $.NSApplication.sharedApplication.setMainMenu(mb);
  } catch (e) {}
  // Vong lap su kien tu lam (khong dung runModalForWindow: loi voi WKWebView tren macOS 14.8)
  var app = $.NSApplication.sharedApplication;
  var MASK = 0xFFFFFFFF; // moi loai su kien
  var MODE = $.NSDefaultRunLoopMode;
  WEBCODE = 0;
  var last = 0;
  while (true) {
    var ev = app.nextEventMatchingMaskUntilDateInModeDequeue(MASK, $.NSDate.dateWithTimeIntervalSinceNow(0.05), MODE, true);
    if (ev && !ev.isNil()) app.sendEvent(ev);
    var now = Date.now();
    if (now - last >= 200) { last = now; try { webTick(); } catch (e) { WSTATE.tickErr = String(e); } }
    if (WEBCODE == 2999) { WIN.orderOut(null); throw WSTATE.why || 'blank'; }
    if (WEBCODE == 2003) {
      WEBCODE = 0;
      var msgx = jobRunning() ? 'Thoát app? Lượt đang chạy vẫn tiếp tục chạy nền, mở lại app để xem tiến độ.' : 'Bạn có chắc muốn thoát app không?';
      if (alertBox(msgx, ['Không', 'Thoát']) === 1) { WIN.orderOut(null); return ''; }
    }
  }
}

function run(argv) {
  RES = argv[0]; CONF = argv[1]; TITLE = argv[2];
  var app = $.NSApplication.sharedApplication;
  app.setActivationPolicy(0);
  var img = $.NSImage.alloc.initWithContentsOfFile(argv[3]);
  if (img && !img.isNil()) { ICONIMG = img; app.setApplicationIconImage(img); }
  app.activateIgnoringOtherApps(true);
  TGT = $.CVTarget.alloc.init;
  if (!exists(CONF + '/classic_ui')) {
    try { return runWeb(argv); } catch (e) {
      if (WIN) { try { WIN.orderOut(null); } catch (x) {} } WV = null;
      var why = String(e) + (e && e.line ? ' (dòng ' + e.line + ')' : '');
      writeText(CONF + '/ui_error.txt', why);
      alertBox('Giao diện mới chưa mở được, app dùng tạm giao diện cũ.\n\nChụp màn hình bảng này gửi Claude để sửa:\n' + why, ['OK']);
    }
  }
  return runClassic(argv, true);
}
