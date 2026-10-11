#!/usr/bin/env python3
"""Score `BetterWisprCLI --meeting` output against speaker-timed references; see docs/accuracy.md."""

import argparse
import json
import sys
from itertools import permutations
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from evaluate_transcripts import edit_distance, normalize


def overlaps(segment, turns):
    """Seconds each reference speaker talks inside the segment."""
    start, end = segment["start"], segment["start"] + segment["duration"]
    heard = {}
    for turn in turns:
        seconds = min(end, turn["end"]) - max(start, turn["start"])
        if seconds > 0:
            heard[turn["speaker"]] = heard.get(turn["speaker"], 0) + seconds
    return heard


def best_match(table):
    """Largest total over one-to-one voice to speaker pairings."""
    if not table:
        return 0.0
    voices, speakers = len(table), len(table[0])
    if voices >= speakers:
        return max(sum(table[v][s] for s, v in enumerate(pick)) for pick in permutations(range(voices), speakers))
    return max(sum(table[v][s] for v, s in enumerate(pick)) for pick in permutations(range(speakers), voices))


def score(reference, segments):
    turns = sorted(reference["turns"], key=lambda t: t["start"])
    segments = sorted(segments, key=lambda s: s["start"])
    words = normalize(" ".join(t["text"] for t in turns)).split()
    row = {"id": reference["id"], "reference_words": len(words), "speakers": len({t["speaker"] for t in turns}),
           "segments": len(segments), "voices_found": len({s["participant"] for s in segments if s.get("participant")})}
    for field in ("text", "rawText"):
        hypothesis = normalize(" ".join(s[field] for s in segments)).split()
        row["wer" if field == "text" else "raw_wer"] = edit_distance(words, hypothesis) / max(1, len(words))
    speakers = sorted({t["speaker"] for t in turns})
    voices = sorted({s["participant"] for s in segments if s.get("participant")})
    weights = [[0.0] * len(speakers) for _ in voices]
    shares = [[0.0] * len(speakers) for _ in voices]
    total = pure = mixed = 0.0
    for segment in segments:
        count = len(normalize(segment["text"]).split())
        heard = overlaps(segment, turns)
        total += count
        if not heard:
            continue
        majority = max(heard, key=heard.get)
        pure += count * heard[majority] / sum(heard.values())
        mixed += sum(heard.values()) - heard[majority] >= 1
        if segment.get("participant"):
            voice = voices.index(segment["participant"])
            weights[voice][speakers.index(majority)] += count
            for speaker, seconds in heard.items():
                shares[voice][speakers.index(speaker)] += count * seconds / sum(heard.values())
    for key, table in (("speaker_accuracy", weights), ("speaker_attribution", shares)):
        row[key] = best_match(table) / max(1, total)
    row["speaker_purity"] = pure / max(1, total)
    row["mixed_segments"] = int(mixed)
    return row


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pairs", nargs="+", help="REFERENCE.json HYPOTHESIS.jsonl, repeated")
    args = parser.parse_args()
    if len(args.pairs) % 2:
        parser.error("pass reference and hypothesis files in pairs")
    rows = []
    for reference, hypothesis in zip(args.pairs[::2], args.pairs[1::2]):
        segments = [json.loads(line) for line in Path(hypothesis).read_text().splitlines() if line.strip()]
        rows.append(score(json.loads(Path(reference).read_text()), segments))
        print(json.dumps(rows[-1]))
    words = sum(r["reference_words"] for r in rows)
    print(json.dumps({"id": "total", "reference_words": words,
                      **{key: sum(r[key] * r["reference_words"] for r in rows) / words
                         for key in ("wer", "raw_wer", "speaker_accuracy", "speaker_purity", "speaker_attribution")}}))


if __name__ == "__main__":
    main()
