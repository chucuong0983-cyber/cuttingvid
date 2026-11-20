// CuttingVid by Louis Chu (Mac) - cua so chinh + kiem tra + chay lenh trong Terminal.
// Chay bang: exec osascript -l JavaScript app.js RES CONF TITLE ICON
// (exec de chinh app CuttingVid hien tren Dock voi logo, ghim duoc)
ObjC.import('Cocoa');

function stopWith(c) { try { $.NSApplication.sharedApplication.stopModalWithCode(c); } catch (e) {} }
ObjC.registerSubclass({
  name: 'CVTarget',
  methods: {
    'go:': { types: ['void', ['id']], implementation: function (sender) { stopWith(1000); } },
    'dir:': { types: ['void', ['id']], implementation: function (sender) { stopWith(2002); } },
    'pick:': {
      types: ['void', ['id']],
      implementation: function (sender) {
        var i = 0; try { i = Number(sender.indexOfSelectedItem); } catch (e) {}
        if (i === 1) stopWith(2001);      // Chon file
        else if (i === 2) stopWith(2003); // Thoat
      }
    },
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
function openPanel(dir) {
  var p = $.NSOpenPanel.openPanel;
  p.setCanChooseFiles(!dir);
  p.setCanChooseDirectories(dir);
  p.setAllowsMultipleSelection(false);
  p.setMessage(dir ? 'Chọn thư mục lưu file' : 'Chọn file video / âm thanh để cắt');
  if (p.runModal == 1) return p.URL.path.js;
  return '';
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
  var menu = $.NSPopUpButton.alloc.initWithFramePullsDown($.NSMakeRect(W - 150, 390, 150, 28), true);
  ['Tùy chọn ▾', 'Chọn file trên máy…', 'Thoát'].forEach(function (t) { menu.addItemWithTitle(t); });
  menu.setTarget(TGT);
  menu.setAction('pick:');
  v.addSubview(menu);

  label(local ? 'File trên máy:' : 'Link YouTube (đang live hay đã xong):', 0, 394, W - 160);
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
  label('phút (gửi Claude: dưới 400MB/phần)', 206, 175, W - 206);

  label('Tên file (để trống = tự đặt theo mốc thời gian):', 0, 136, W);
  var fName = field(st.name, 0, 108, W);

  label('Lưu vào:', 0, 76, W);
  var fDir = field(st.dir, 0, 48, W - 110);
  var bDir = $.NSButton.alloc.initWithFrame($.NSMakeRect(W - 102, 45, 102, 30));
  bDir.setTitle('Đổi…'); bDir.setBezelStyle(1);
  bDir.setTarget(TGT); bDir.setAction('dir:');
  v.addSubview(bDir);
  small('Chọn file trên máy: menu "Tùy chọn ▾" ở góc trên. Nút đỏ / Thoát sẽ được hỏi lại.', 0, 18, W);

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
  if (code == 2001) return 'file';
  if (code == 2002) return 'dir';
  if (code == 1000) return 'go';
  return 'quit';
}

function terminal(cmd) {
  var T = Application('Terminal');
  T.activate();
  T.doScript(cmd);
}

function run(argv) {
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
