#!/usr/bin/env python3
# CuttingVid - quet loi noi thanh chu.
#   python3 asr.py ENGINE MODEL INPUT OFFSET_SEC OUT_BASE
#   ENGINE: groq  -> Groq API (whisper-large-v3-turbo), rat nhanh, can API key
#           fw    -> faster-whisper tren may (int8, quet theo lo, loc khoang lang)
# Ra: OUT_BASE.srt (moc tinh tu dau file) va OUT_BASE.txt ([HH:MM:SS] cau, moc tinh tu dau buoi live)
# Thoat 0 = thanh cong; 3 = khong dung duoc engine nay (de script goi quay ve whisper.cpp)
import json, os, subprocess, sys, tempfile, time, uuid, urllib.request, urllib.error

CONF = os.path.expanduser('~/Library/Application Support/StreamerCuttingVid')
FFMPEG = os.environ.get('CV_FFMPEG', 'ffmpeg')


def say(t):
    print(t, flush=True)


def hms(s):
    s = max(0, int(s))
    return '%02d:%02d:%02d' % (s // 3600, s % 3600 // 60, s % 60)


def srt_time(s):
    s = max(0.0, float(s))
    ms = int(round(s * 1000))
    return '%02d:%02d:%02d,%03d' % (ms // 3600000, ms % 3600000 // 60000, ms % 60000 // 1000, ms % 1000)


def write_out(segs, out_base, offset, src_name):
    segs = [(a, b, t.strip()) for a, b, t in segs if t and t.strip()]
    with open(out_base + '.srt', 'w', encoding='utf-8') as f:
        for i, (a, b, t) in enumerate(segs, 1):
            f.write('%d\n%s --> %s\n%s\n\n' % (i, srt_time(a), srt_time(b), t))
    with open(out_base + '.txt', 'w', encoding='utf-8') as f:
        f.write('# Phu de: %s\n' % src_name)
        f.write('# Moc [HH:MM:SS] tinh tu dau buoi live (file nay bat dau o %s)\n' % hms(offset))
        for a, b, t in segs:
            f.write('[%s] %s\n' % (hms(a + offset), t))
    return len(segs)


def duration(path):
    try:
        out = subprocess.run([os.environ.get('CV_FFPROBE', 'ffprobe'), '-v', 'error', '-show_entries', 'format=duration',
                              '-of', 'csv=p=0', path], capture_output=True, text=True).stdout.strip()
        return float(out)
    except Exception:
        return 0.0


# ---------------- Groq ----------------
def groq_key():
    p = os.path.join(CONF, 'groq_key.txt')
    try:
        return open(p, encoding='utf-8').read().strip()
    except Exception:
        return ''


def groq_post(path, key, model):
    bnd = uuid.uuid4().hex
    fields = {'model': model, 'response_format': 'verbose_json', 'language': 'en', 'temperature': '0'}
    body = b''
    for k, v in fields.items():
        body += ('--%s\r\nContent-Disposition: form-data; name="%s"\r\n\r\n%s\r\n' % (bnd, k, v)).encode()
    body += ('--%s\r\nContent-Disposition: form-data; name="file"; filename="a.mp3"\r\nContent-Type: audio/mpeg\r\n\r\n' % bnd).encode()
    body += open(path, 'rb').read() + ('\r\n--%s--\r\n' % bnd).encode()
    req = urllib.request.Request('https://api.groq.com/openai/v1/audio/transcriptions', data=body, method='POST',
                                 headers={'Authorization': 'Bearer ' + key, 'Content-Type': 'multipart/form-data; boundary=' + bnd})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                return json.loads(r.read().decode('utf-8'))
        except urllib.error.HTTPError as e:
            msg = e.read().decode('utf-8', 'replace')[:300]
            if e.code == 429 or e.code >= 500:
                try: wait = int(float(e.headers.get('retry-after') or 0))
                except ValueError: wait = 0
                wait = wait or 15 * (attempt + 1)
                if wait > 90 or attempt == 3:
                    say('   Groq da het luot mien phi (cho khoang %d phut). Chuyen sang quet tren may.' % max(1, wait // 60))
                    return None
                say('   Groq dang ban, doi %ds roi thu lai...' % wait)
                time.sleep(wait)
                continue
            if e.code in (401, 403):
                say('   API key Groq khong dung. Kiem tra lai key.')
            else:
                say('   Groq bao loi %d: %s' % (e.code, msg))
            return None
        except Exception as e:
            say('   Loi mang: %s. Thu lai...' % e)
            time.sleep(10)
    return None


def run_groq(src, model):
    key = groq_key()
    if not key:
        say('Chua co API key Groq.')
        return None
    total = duration(src)
    if total <= 0:
        say('Khong doc duoc do dai file.')
        return None
    chunk = 1200  # 20 phut / lan gui (~7MB, duoi gioi han 25MB cua goi mien phi)
    segs, t0 = [], time.time()
    tmp = tempfile.mkdtemp(prefix='cv_groq_')
    start = 0.0
    while start < total:
        mp3 = os.path.join(tmp, 'c.mp3')
        subprocess.run([FFMPEG, '-hide_banner', '-loglevel', 'error', '-y', '-ss', str(start), '-i', src, '-t', str(chunk),
                        '-vn', '-ac', '1', '-ar', '16000', '-c:a', 'libmp3lame', '-b:a', '48k', mp3])
        if os.path.getsize(mp3) < 1000:
            break
        data = groq_post(mp3, key, model)
        if data is None:
            return None
        for s in data.get('segments') or []:
            segs.append((start + float(s.get('start', 0)), start + float(s.get('end', 0)), s.get('text', '')))
        start += chunk
        say('   Groq: da xong %s / %s (%.0fs)' % (hms(min(start, total)), hms(total), time.time() - t0))
    return segs


# ---------------- faster-whisper ----------------
def run_fw(src, model):
    try:
        from faster_whisper import WhisperModel
    except Exception:
        return 'NO'
    say('   faster-whisper: dang nap model %s (lan dau se tai ve)...' % model)
    m = WhisperModel(model, device='cpu', compute_type='int8', cpu_threads=os.cpu_count() or 4)
    kw = dict(language='en', vad_filter=True, beam_size=1, condition_on_previous_text=False)
    try:
        from faster_whisper import BatchedInferencePipeline
        it, info = BatchedInferencePipeline(model=m).transcribe(src, batch_size=8, **kw)
    except Exception:
        it, info = m.transcribe(src, **kw)
    total = getattr(info, 'duration', 0) or duration(src)
    segs, t0, last = [], time.time(), 0
    for s in it:
        segs.append((s.start, s.end, s.text))
        if time.time() - last > 15:
            last = time.time()
            pct = 100.0 * s.end / total if total else 0
            say('   da quet %s / %s (%.0f%%)' % (hms(s.end), hms(total), pct))
    say('   xong sau %.0f giay' % (time.time() - t0))
    return segs


def main():
    engine, model, src, offset, out_base = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4]), sys.argv[5]
    if engine == 'groq':
        segs = run_groq(src, model)
    else:
        segs = run_fw(src, model)
        if segs == 'NO':
            sys.exit(3)
    if segs is None:
        sys.exit(3 if engine == 'groq' else 1)
    n = write_out(segs, out_base, offset, os.path.basename(src))
    say('   Xong: %s.txt (%d cau)' % (os.path.basename(out_base), n))


if __name__ == '__main__':
    main()
