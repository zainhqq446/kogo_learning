#!/usr/bin/env python3
"""Generate Kogo's recorded voice clips with ElevenLabs.

Usage:
    dart run tool/voice_catalog.dart > build/voice_catalog.json
    ELEVENLABS_API_KEY=... python3 tool/generate_voice.py --voice <voice_id>
    python3 tool/generate_voice.py --voice <voice_id> --dry-run   # count characters only

Clips are written to assets/voice/<hash>.mp3 together with manifest.json.
Clips that already exist are reused, so re-running only pays for new or
changed sentences. The API key is read from the environment and never stored.
"""

import argparse
import concurrent.futures
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

API = "https://api.elevenlabs.io/v1/text-to-speech/{voice}?output_format=mp3_22050_32"

# Child-friendly delivery: expressive sentences, slower and clearer target words.
SETTINGS = {
    "line": {"stability": 0.45, "similarity_boost": 0.8, "style": 0.3, "use_speaker_boost": True, "speed": 0.95},
    "word": {"stability": 0.6, "similarity_boost": 0.8, "style": 0.1, "use_speaker_boost": True, "speed": 0.85},
    "letter": {"stability": 0.6, "similarity_boost": 0.8, "style": 0.1, "use_speaker_boost": True, "speed": 0.85},
    "spell": {"stability": 0.6, "similarity_boost": 0.8, "style": 0.1, "use_speaker_boost": True, "speed": 0.8},
}


class QuotaError(Exception):
    pass


def clip_name(voice, model, entry):
    settings = json.dumps(SETTINGS[entry["kind"]], sort_keys=True)
    digest = hashlib.sha1(f"{voice}|{model}|{settings}|{entry['kind']}|{entry['text']}".encode()).hexdigest()
    return digest[:16] + ".mp3"


def synthesize(api_key, voice, model, entry, seed=None):
    payload = {"text": entry["text"], "model_id": model, "language_code": "id", "voice_settings": SETTINGS[entry["kind"]]}
    if seed is not None:
        payload["seed"] = seed
    body = json.dumps(payload).encode()
    request = urllib.request.Request(
        API.format(voice=voice),
        data=body,
        method="POST",
        headers={"xi-api-key": api_key, "content-type": "application/json", "accept": "audio/mpeg"},
    )
    delay = 2.0
    for attempt in range(6):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                audio = response.read()
                cost = int(response.headers.get("character-cost") or 0)
            if len(audio) < 1000:
                raise RuntimeError(f"audio too small ({len(audio)} bytes)")
            return audio, cost
        except urllib.error.HTTPError as error:
            detail = error.read().decode(errors="replace")[:300]
            if error.code in (401, 402, 403) or "quota" in detail.lower():
                raise QuotaError(f"HTTP {error.code}: {detail}")
            if error.code not in (429, 500, 502, 503, 504) or attempt == 5:
                raise RuntimeError(f"HTTP {error.code}: {detail}")
        except (urllib.error.URLError, TimeoutError, ConnectionError) as error:
            if attempt == 5:
                raise RuntimeError(str(error))
        time.sleep(delay)
        delay *= 2
    raise RuntimeError("unreachable")


# Very short inputs sometimes come back with long silences; clips are trimmed and
# re-generated when a pause inside the sentence is longer than this (seconds).
MAX_PAUSE = {"line": 0.6, "word": 0.5, "letter": 0.5, "spell": 1.3}


def trim(path):
    """Remove leading/trailing silence (keeps 60 ms) and re-encode at the same quality."""
    edge = "silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.06"
    tmp = path + ".trim.mp3"
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", path, "-af", f"{edge},areverse,{edge},areverse", "-ac", "1", "-ar", "22050", "-b:a", "32k", tmp],
        capture_output=True,
    )
    if result.returncode == 0 and os.path.getsize(tmp) > 500:
        os.replace(tmp, path)
    elif os.path.exists(tmp):
        os.remove(tmp)


def duration(path):
    result = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path], capture_output=True, text=True)
    return float(result.stdout.strip() or 0)


def badness(path, entry):
    """0 for a clean clip; grows with over-long pauses and unusually long audio."""
    per_char = 0.2 if entry["kind"] == "spell" else 0.16
    expected = 0.9 + per_char * len(entry["text"])
    return max(0.0, longest_pause(path) - MAX_PAUSE[entry["kind"]]) + max(0.0, duration(path) - expected)


def longest_pause(path):
    result = subprocess.run(
        ["ffmpeg", "-hide_banner", "-i", path, "-af", "silencedetect=noise=-40dB:d=0.3", "-f", "null", "-"], capture_output=True, text=True
    )
    pauses = [float(x) for x in re.findall(r"silence_duration: ([\d.]+)", result.stderr)]
    return max(pauses, default=0.0)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--catalog", default="build/voice_catalog.json")
    parser.add_argument("--out", default="assets/voice")
    parser.add_argument("--voice", required=True, help="ElevenLabs voice_id")
    parser.add_argument("--model", default="eleven_turbo_v2_5")
    parser.add_argument("--workers", type=int, default=3)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--retries", type=int, default=3, help="re-generations for clips with long pauses")
    args = parser.parse_args()

    with open(args.catalog, encoding="utf-8") as f:
        catalog = json.load(f)
    os.makedirs(args.out, exist_ok=True)

    clips = {e["key"]: clip_name(args.voice, args.model, e) for e in catalog}
    todo = [e for e in catalog if not os.path.exists(os.path.join(args.out, clips[e["key"]]))]
    chars = sum(len(e["text"]) for e in todo)
    print(f"catalog: {len(catalog)} clips, to generate: {len(todo)} ({chars} characters)")
    if args.dry_run:
        return 0

    api_key = os.environ.get("ELEVENLABS_API_KEY")
    if not api_key:
        print("ELEVENLABS_API_KEY is not set", file=sys.stderr)
        return 2

    lock = threading.Lock()
    stop = threading.Event()
    done = {"count": 0, "cost": 0}
    failures = []

    def work(entry):
        if stop.is_set():
            return
        try:
            audio, cost = synthesize(api_key, args.voice, args.model, entry)
        except QuotaError as error:
            stop.set()
            failures.append(f"{entry['key']}: {error}")
            return
        except Exception as error:  # noqa: BLE001 - report and continue with the rest
            failures.append(f"{entry['key']}: {error}")
            return
        path = os.path.join(args.out, clips[entry["key"]])
        with open(path + ".tmp", "wb") as f:
            f.write(audio)
        os.replace(path + ".tmp", path)
        with lock:
            done["count"] += 1
            done["cost"] += cost
            if done["count"] % 50 == 0:
                print(f"  {done['count']}/{len(todo)} clips, {done['cost']} credits")

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        list(pool.map(work, todo))

    # Quality pass (needs ffmpeg): trim every clip, re-generate clips that still
    # contain a long pause, and keep the best take.
    if shutil.which("ffmpeg"):
        by_key = {e["key"]: e for e in catalog}
        paths = {k: os.path.join(args.out, v) for k, v in clips.items()}
        with concurrent.futures.ThreadPoolExecutor(max_workers=os.cpu_count() or 2) as pool:
            list(pool.map(trim, [p for p in paths.values() if os.path.exists(p)]))
        bad = [k for k, p in paths.items() if os.path.exists(p) and badness(p, by_key[k]) > 0]
        print(f"quality: {len(bad)} clips with long pauses or unusual length")
        for attempt in range(1, args.retries + 1):
            if not bad or stop.is_set():
                break
            still = []
            for key in bad:
                entry, path = by_key[key], paths[key]
                try:
                    audio, cost = synthesize(api_key, args.voice, args.model, entry, seed=attempt * 7919)
                except QuotaError as error:
                    stop.set()
                    failures.append(f"{key}: {error}")
                    break
                except Exception as error:  # noqa: BLE001
                    failures.append(f"{key}: {error}")
                    continue
                done["cost"] += cost
                take = path + ".take.mp3"
                with open(take, "wb") as f:
                    f.write(audio)
                trim(take)
                if badness(take, entry) < badness(path, entry):
                    os.replace(take, path)
                else:
                    os.remove(take)
                if badness(path, entry) > 0:
                    still.append(key)
            print(f"quality retry {attempt}: {len(bad) - len(still)} fixed, {len(still)} left")
            bad = still
        for key in bad:
            print(f"WARNING best take kept despite pause/length: {by_key[key]['text']!r}", file=sys.stderr)
    else:
        print("ffmpeg not found: skipped trimming and quality checks", file=sys.stderr)

    # The manifest only lists clips that exist, so the app falls back to the
    # device voice for anything that is still missing.
    available = {k: v for k, v in clips.items() if os.path.exists(os.path.join(args.out, v))}
    manifest = {"voice_id": args.voice, "model_id": args.model, "clips": dict(sorted(available.items()))}
    with open(os.path.join(args.out, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=1)
    referenced = set(available.values())
    removed = 0
    for name in os.listdir(args.out):
        if name.endswith(".mp3") and name not in referenced:
            os.remove(os.path.join(args.out, name))
            removed += 1

    print(f"generated {done['count']} clips ({done['cost']} credits); manifest has {len(available)}/{len(catalog)}; removed {removed} unused")
    for failure in failures[:10]:
        print("FAILED", failure, file=sys.stderr)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
