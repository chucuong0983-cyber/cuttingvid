#!/usr/bin/env python3
# CuttingVid - quet loi noi thanh chu.
#   python3 asr.py ENGINE MODEL INPUT OFFSET_SEC OUT_BASE
#   ENGINE: groq  -> Groq API (whisper-large-v3-turbo), rat nhanh, can API key
#           fw    -> faster-whisper tren may (int8, quet theo lo, loc khoang lang)
# Ra: OUT_BASE.srt (moc tinh tu dau file) va OUT_BASE.txt ([HH:MM:SS] cau, moc tinh tu dau buoi live)
# Thoat 0 = thanh cong; 3 = khong dung duoc engine nay (de script goi quay ve whisper.cpp)
import shutil
import re
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
    # Gui bang curl cua he thong (on dinh hon urllib; Groq hay chan/ngat urllib -> "Broken pipe")
    tmp = tempfile.mkdtemp(prefix='cv_gp_')
    hdr = os.path.join(tmp, 'h.txt'); out = os.path.join(tmp, 'o.json')
    with open(hdr, 'w') as f:
        f.write('Authorization: Bearer %s\n' % key)
    cmd = ['curl', '-sS', '--max-time', '600', '-A', 'CuttingVid/1.0', '-o', out, '-w', '%{http_code}', '-H', '@' + hdr,
           '-F', 'file=@' + path + ';type=audio/mpeg', '--form-string', 'model=' + model,
           '--form-string', 'response_format=verbose_json', '--form-string', 'language=en', '--form-string', 'temperature=0',
           'https://api.groq.com/openai/v1/audio/transcriptions']
    try:
        for attempt in range(4):
            r = subprocess.run(cmd, capture_output=True, text=True)
            code = (r.stdout or '').strip()[-3:]
            body = ''
            if os.path.exists(out):
                with open(out, encoding='utf-8', errors='replace') as f:
                    body = f.read()
            if code == '200':
                return json.loads(body)
            if code in ('401', '403'):
                say('   Groq tu choi key (%s): %s' % (code, body[:200]))
                return None
            if code == '429' or code.startswith('5') or code in ('000', ''):
                wait = 15 * (attempt + 1)
                m = re.search(r'try again in ([0-9hms.]+)', body)
                if code == '429' and m:
                    t = m.group(1); sec = 0.0
                    for v, u in re.findall(r'([0-9.]+)([hms])', t):
                        sec += float(v) * {'h': 3600, 'm': 60, 's': 1}[u]
                    wait = int(sec) + 2
                if wait > 90 or attempt == 3:
                    say('   Groq het luot mien phi / loi mang (%s). Chuyen sang quet tren may.' % (code or r.stderr.strip()[:120]))
                    return None
                say('   Groq chua tra loi (%s), doi %ds roi thu lai...' % (code if code not in ('000', '') else r.stderr.strip()[:120], wait))
                time.sleep(wait)
                continue
            say('   Groq bao loi %s: %s' % (code, body[:200]))
            return None
        return None
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def run_groq(src, model):
    key = groq_key()
    if not key:
        say('Chua co API key Groq.')
        return None
    total = duration(src)
    if total <= 0:
        say('Khong doc duoc do dai file.')
        return None
    # Cat 10 phut / doan (~3.5MB): Groq xu ly nhanh hon, it bi loi 524 (qua thoi gian);
    # gui 3 doan cung luc de nhanh gap ~3 lan.
    chunk = 600
    t0 = time.time()
    tmp = tempfile.mkdtemp(prefix='cv_groq_')
    starts = []
    st = 0.0
    while st < total:
        starts.append(st); st += chunk

    def one(k):
        st = starts[k]
        mp3 = os.path.join(tmp, 'c%03d.mp3' % k)
        subprocess.run([FFMPEG, '-hide_banner', '-loglevel', 'error', '-y', '-ss', str(st), '-i', src, '-t', str(chunk),
                        '-vn', '-ac', '1', '-ar', '16000', '-c:a', 'libmp3lame', '-b:a', '48k', mp3])
        if not os.path.exists(mp3) or os.path.getsize(mp3) < 1000:
            return []
        data = groq_post(mp3, key, model)
        try: os.remove(mp3)
        except OSError: pass
        if data is None:
            raise RuntimeError('groq')
        return [(st + float(x.get('start', 0)), st + float(x.get('end', 0)), x.get('text', '')) for x in (data.get('segments') or [])]

    from concurrent.futures import ThreadPoolExecutor
    res = [None] * len(starts); done = 0
    try:
        with ThreadPoolExecutor(max_workers=3) as ex:
            futs = {ex.submit(one, k): k for k in range(len(starts))}
            for f in futs:
                res[futs[f]] = f.result()
                done += 1
                say('   Groq: da xong %d/%d doan 10 phut (%.0fs)' % (done, len(starts), time.time() - t0))
    except RuntimeError:
        shutil.rmtree(tmp, ignore_errors=True)
        return None
    shutil.rmtree(tmp, ignore_errors=True)
    segs = [x for r in res for x in (r or [])]
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
