"""Fetch a small multilingual read-speech, with --accents accented conversational English, or with --meetings AMI and EdAcc call recordings, test corpus from HF datasets-server."""
import array, json, operator, re, subprocess, time, urllib.error, sys, urllib.request, urllib.parse, wave
from pathlib import Path

OUT = Path(sys.argv[1])
OUT.mkdir(parents=True, exist_ok=True)
PER_LANG = int(sys.argv[2]) if len(sys.argv) > 2 and sys.argv[2].isdigit() else 40
ACCENTS = [("en-IN", "Indian English"), ("en-NG", "Nigerian English"), ("en-US", "Mainstream US English")]
UNSCORABLE = re.compile(r"<(?:OVERLAP|FOREIGN|DTMF|NO-SPEECH)>|IGNORE_TIME_SEGMENT")
MEETING_FILLERS = re.compile(r"<[^>]+>|\b(?:UM|UH|ER|HMM|MM|MM-HMM|UM-HUM|UH-HUH|HM|MHM)\b")
AMI_MEETINGS, EDACC_CALLS, RATE = ["ES2004a", "IS1009a", "TS3003a", "EN2002a"], ["C05", "C09", "C29", "C34", "C36", "C41"], 16000
SOURCES = [
    ("en", "openslr/librispeech_asr", "clean", "test", 2620, "text"),
    ("en-other", "openslr/librispeech_asr", "other", "test", 2939, "text"),
    ("de", "facebook/multilingual_librispeech", "german", "test", 3394, "transcript"),
    ("fr", "facebook/multilingual_librispeech", "french", "test", 2426, "transcript"),
    ("es", "facebook/multilingual_librispeech", "spanish", "test", 2385, "transcript"),
    ("it", "facebook/multilingual_librispeech", "italian", "test", 1262, "transcript"),
    ("pt", "facebook/multilingual_librispeech", "portuguese", "test", 871, "transcript"),
    ("nl", "facebook/multilingual_librispeech", "dutch", "test", 3075, "transcript"),
    ("pl", "facebook/multilingual_librispeech", "polish", "test", 520, "transcript"),
]

def rows(dataset, config, split, offset, length):
    query = urllib.parse.urlencode({"dataset": dataset, "config": config, "split": split, "offset": offset, "length": length})
    for attempt in range(8):
        try:
            with urllib.request.urlopen(f"https://datasets-server.huggingface.co/rows?{query}", timeout=120) as r:
                return json.load(r)["rows"]
        except (urllib.error.HTTPError, TimeoutError) as error:
            if getattr(error, "code", 503) not in (429, 500, 502, 503, 504) or attempt == 7:
                raise
            time.sleep(15 * (attempt + 1))

def edacc():
    """Evenly spaced EdAcc segments per accent with at least four scorable words, fillers and noise tags removed."""
    usable = {accent: [] for _, accent in ACCENTS}
    for split in ("validation", "test"):
        offset = 0
        while batch := rows("edinburghcstr/edacc", "default", split, offset, 100):
            for item in batch:
                row = item["row"]
                words = re.sub(r"<[^>]+>|\b(?:UM|UH|ER|HMM|MM)\b", " ", row["text"]).split()
                if row["accent"] in usable and not UNSCORABLE.search(row["text"]) and len(words) >= 4:
                    usable[row["accent"]].append((f"{split[0]}{item['row_idx']:05d}", row, " ".join(words)))
            offset += 100
            time.sleep(1)
    return {accent: found[::max(1, len(found) // PER_LANG)][:PER_LANG] for accent, found in usable.items()}

def download(audio, wav):
    if not wav.exists():
        src = wav.with_suffix(".src")
        urllib.request.urlretrieve(audio, src)
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", str(src), str(wav)], check=True)
        src.unlink()
    return wav

def matching(dataset, config, split, keep):
    """Scans a whole split in row order, since datasets-server /filter often fails with HTTP 500 on these datasets."""
    found, offset = [], 0
    while batch := rows(dataset, config, split, offset, 100):
        found += [item for item in batch if keep(item["row"])]
        offset += 100
        time.sleep(0.3)
    return found

def segment(name, item):
    (OUT / "segments").mkdir(exist_ok=True)
    with wave.open(str(download(item["row"]["audio"][0]["src"], OUT / "segments" / f"{name}-{item['row_idx']}.wav"))) as w:
        return array.array("h", w.readframes(w.getnframes()))

def turn(speaker, start, samples, text, **extra):
    return {"speaker": speaker, **extra, "start": start, "end": start + len(samples) / RATE, "text": " ".join(MEETING_FILLERS.sub(" ", text).split())}

def meeting(name, pieces):
    """Mixes (turn, samples) pieces into one 16 kHz recording at their start times and writes the speaker-timed reference beside it."""
    mix = array.array("i", bytes(4 * (max(int(t["start"] * RATE) + len(s) for t, s in pieces) + RATE)))
    for t, samples in pieces:
        at = int(t["start"] * RATE)
        mix[at:at + len(samples)] = array.array("i", map(operator.add, mix[at:at + len(samples)], samples))
    scale = min(1.0, 0.99 * 32768 / max(1, max(map(abs, mix))))
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1), w.setsampwidth(2), w.setframerate(RATE)
        w.writeframes(array.array("h", (max(-32768, min(32767, round(value * scale))) for value in mix)).tobytes())
    (OUT / f"{name}.json").write_text(json.dumps({"id": name, "turns": sorted((t for t, _ in pieces), key=lambda t: t["start"])}, indent=1))
    print(name, len(pieces), "turns", file=sys.stderr)

def save(clip_id, language, audio, reference):
    wav = download(audio, OUT / f"{clip_id}.wav")
    manifest.append({"id": clip_id, "language": language, "audio": str(wav), "reference": reference})
    print(clip_id, file=sys.stderr)

manifest = []
if "--meetings" in sys.argv:
    ami = matching("edinburghcstr/ami", "ihm", "test", lambda row: row["meeting_id"] in AMI_MEETINGS and row["begin_time"] < 600)
    for name in AMI_MEETINGS:
        pieces = []
        for item in (item for item in ami if item["row"]["meeting_id"] == name):
            row, samples = item["row"], segment(f"ami-{name}", item)
            pieces.append((turn(row["speaker_id"], row["begin_time"], samples, row["text"]), samples))
        meeting(f"ami-{name}", pieces)
    prefixes = tuple(f"EDACC-{call}-" for call in EDACC_CALLS)
    calls = [(split, item) for split in ("validation", "test") for item in matching("edinburghcstr/edacc", "default", split, lambda row: row["speaker"].startswith(prefixes))]
    for call in EDACC_CALLS:
        pieces, clock = [], 0.0
        for split, item in calls:
            if not item["row"]["speaker"].startswith(f"EDACC-{call}-") or clock >= 300 or UNSCORABLE.search(item["row"]["text"]):
                continue
            row, samples = item["row"], segment(f"edacc-{call}-{split}", item)
            pieces.append((turn(row["speaker"], clock, samples, row["text"], accent=row["accent"]), samples))
            clock += len(samples) / RATE + 0.3
        meeting(f"edacc-EDACC-{call}", pieces)
    raise SystemExit
if "--accents" in sys.argv:
    picked = edacc()
    for language, accent in ACCENTS:
        for key, row, reference in picked[accent]:
            save(f"{language}-{key}", language, row["audio"][0]["src"], reference)
else:
    for lang, dataset, config, split, total, field in SOURCES:
        batches = 8
        step = max(1, total // batches)
        picked = []
        for b in range(batches):
            try:
                picked += [(b * step + i, item["row"]) for i, item in enumerate(rows(dataset, config, split, b * step, PER_LANG // batches))]
            except Exception as error:
                print(f"skip {lang} batch {b}: {error}", file=sys.stderr)
            time.sleep(2)
        for offset, row in picked:
            save(f"{lang}-{offset:05d}", lang.split("-")[0], row["audio"][0]["src"], row[field])

(OUT / "manifest.jsonl").write_text("".join(json.dumps(m, ensure_ascii=False) + "\n" for m in manifest))
print(f"{len(manifest)} clips", file=sys.stderr)
