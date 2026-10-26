"""Generate Kogo's non-verbal sound effects and instrumental background music.

Every sound is synthesised from scratch (sine/bell/pluck oscillators and
filtered noise), so the output is original and free to redistribute.

Usage (from the repository root):
    python3 tool/generate_sfx.py

Requires numpy and ffmpeg (with libmp3lame) on PATH. Output:
    assets/audio/sfx/*.mp3   short UI / feedback effects (< 1.5 s)
    assets/audio/bgm/playful_loop.mp3   seamless 19.2 s instrumental loop
"""

from __future__ import annotations

import pathlib
import subprocess
import tempfile
import wave

import numpy as np

SR = 44100
ROOT = pathlib.Path(__file__).resolve().parent.parent
SFX_DIR = ROOT / "assets" / "audio" / "sfx"
BGM_DIR = ROOT / "assets" / "audio" / "bgm"
RNG = np.random.default_rng(20261025)


def note(name: str) -> float:
    """Frequency for names like 'C5', 'F#4'."""
    names = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}
    pitch, octave = name[:-1], int(name[-1])
    midi = 12 * (octave + 1) + names[pitch]
    return 440.0 * 2 ** ((midi - 69) / 12)


def t_axis(duration: float) -> np.ndarray:
    return np.arange(int(SR * duration)) / SR


def env(duration: float, attack: float = 0.005, decay: float = 0.3) -> np.ndarray:
    t = t_axis(duration)
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    return a * np.exp(-t / max(decay, 1e-4))


def marimba(freq: float, duration: float = 0.6, decay: float = 0.18) -> np.ndarray:
    t = t_axis(duration)
    tone = np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(2 * np.pi * freq * 4 * t) * np.exp(-t / 0.03)
    return tone * env(duration, 0.002, decay)


def bell(freq: float, duration: float = 1.0, decay: float = 0.45) -> np.ndarray:
    t = t_axis(duration)
    partials = [(1.0, 1.0), (2.0, 0.5), (2.76, 0.32), (5.4, 0.18), (8.9, 0.08)]
    tone = sum(amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t * ratio / (decay * 3)) for ratio, amp in partials)
    return tone * env(duration, 0.003, decay)


def pluck(freq: float, duration: float = 0.5, damping: float = 0.996) -> np.ndarray:
    """Karplus-Strong plucked string (ukulele-like)."""
    n = int(SR * duration)
    period = max(2, int(SR / freq))
    buf = RNG.uniform(-1, 1, period)
    out = np.zeros(n)
    for i in range(n):
        out[i] = buf[i % period]
        buf[i % period] = damping * 0.5 * (buf[i % period] + buf[(i + 1) % period])
    return out * env(duration, 0.001, duration)


def glide(f0: float, f1: float, duration: float, decay: float = 0.25) -> np.ndarray:
    t = t_axis(duration)
    freq = f0 * (f1 / f0) ** (t / duration)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return (np.sin(phase) + 0.2 * np.sin(2 * phase)) * env(duration, 0.004, decay)


def noise(duration: float, decay: float, smooth: int = 1) -> np.ndarray:
    n = RNG.uniform(-1, 1, int(SR * duration))
    if smooth > 1:
        n = np.convolve(n, np.ones(smooth) / smooth, mode="same")
    return n * env(duration, 0.001, decay)


def place(track: np.ndarray, clip: np.ndarray, at: float, gain: float = 1.0) -> None:
    start = int(at * SR)
    end = min(len(track), start + len(clip))
    if start < len(track):
        track[start:end] += clip[: end - start] * gain


def finish(signal: np.ndarray, peak_db: float = -3.0, fade: float = 0.01) -> np.ndarray:
    fade_n = int(fade * SR)
    if fade_n and len(signal) > 2 * fade_n:
        signal[:fade_n] *= np.linspace(0, 1, fade_n)
        signal[-fade_n:] *= np.linspace(1, 0, fade_n)
    peak = np.max(np.abs(signal)) or 1.0
    return signal / peak * (10 ** (peak_db / 20))


def write_mp3(path: pathlib.Path, signal: np.ndarray, bitrate: str = "64k") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = (np.clip(signal, -1, 1) * 32767).astype("<i2")
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        with wave.open(tmp.name, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", tmp.name, "-codec:a", "libmp3lame", "-b:a", bitrate, "-ar", "44100", str(path)],
            check=True,
        )
    print(f"wrote {path.relative_to(ROOT)} ({path.stat().st_size} bytes)")


def sfx() -> dict[str, np.ndarray]:
    out: dict[str, np.ndarray] = {}

    tap = marimba(note("G5"), 0.18, 0.05) * 0.8 + noise(0.18, 0.01, 4) * 0.15
    out["tap"] = finish(tap, -6)

    pop = glide(380, 900, 0.12, 0.05)
    out["pop"] = finish(pop, -5)

    correct = np.zeros(int(SR * 0.9))
    place(correct, bell(note("E6"), 0.6, 0.25), 0.0)
    place(correct, bell(note("B6"), 0.8, 0.35), 0.11)
    out["correct"] = finish(correct, -3)

    wrong = np.zeros(int(SR * 0.7))
    place(wrong, glide(note("E4"), note("C4"), 0.28, 0.15), 0.0)
    place(wrong, glide(note("C4"), note("A3"), 0.35, 0.18), 0.22)
    out["wrong"] = finish(wrong, -9)

    star = np.zeros(int(SR * 1.2))
    for i, n in enumerate(["C6", "E6", "G6", "C7", "E7"]):
        place(star, bell(note(n), 0.7, 0.3), i * 0.07, 0.8)
    place(star, noise(1.0, 0.35, 2) * 0.05, 0.0)
    out["star"] = finish(star, -3)

    complete = np.zeros(int(SR * 1.6))
    for i, n in enumerate(["C5", "E5", "G5"]):
        place(complete, marimba(note(n), 0.4, 0.15), i * 0.12)
    for n in ["C5", "E5", "G5", "C6"]:
        place(complete, bell(note(n), 1.2, 0.5), 0.38, 0.55)
    out["complete"] = finish(complete, -2)

    whoosh = noise(0.45, 0.2, 24) * np.sin(np.linspace(0, np.pi, int(SR * 0.45)))
    out["whoosh"] = finish(whoosh, -10)

    unlock = np.zeros(int(SR * 1.0))
    place(unlock, bell(note("G5"), 0.6, 0.3), 0.0)
    place(unlock, bell(note("D6"), 0.6, 0.3), 0.09)
    place(unlock, bell(note("G6"), 0.9, 0.4), 0.18)
    out["unlock"] = finish(unlock, -4)

    out["mic_on"] = finish(glide(note("C5"), note("G5"), 0.16, 0.08), -6)
    out["mic_off"] = finish(glide(note("G5"), note("C5"), 0.16, 0.08), -8)
    return out


def bgm() -> np.ndarray:
    """Cheerful 100 BPM loop: C-Am-F-G progression, plucked chords, marimba melody, soft shaker."""
    bpm = 100
    beat = 60 / bpm
    bars = 8
    length = bars * 4 * beat
    tail = 2.0
    track = np.zeros(int(SR * (length + tail)))

    chords = [["C4", "E4", "G4"], ["A3", "C4", "E4"], ["F3", "A3", "C4"], ["G3", "B3", "D4"]] * 2
    bass = ["C3", "A2", "F2", "G2"] * 2
    melody = [
        ("E5", 0), ("G5", 1), ("A5", 1.5), ("G5", 2), ("E5", 3),
        ("C5", 4), ("E5", 5), ("D5", 6), ("C5", 6.5), ("A4", 7),
        ("A4", 8), ("C5", 9), ("D5", 9.5), ("C5", 10), ("A4", 11),
        ("G4", 12), ("B4", 13), ("D5", 14), ("G5", 15),
        ("E5", 16), ("G5", 17), ("A5", 17.5), ("C6", 18), ("A5", 19),
        ("G5", 20), ("E5", 21), ("D5", 22), ("E5", 22.5), ("C5", 23),
        ("A4", 24), ("C5", 25), ("F5", 26), ("E5", 27),
        ("D5", 28), ("B4", 29), ("G4", 30), ("C5", 31),
    ]

    for bar in range(bars):
        start = bar * 4 * beat
        place(track, marimba(note(bass[bar]), 1.2, 0.5) * 0.9, start)
        place(track, marimba(note(bass[bar]), 1.0, 0.4) * 0.6, start + 2 * beat)
        for off in (0.5, 1.5, 2.5, 3.5):
            for k, n in enumerate(chords[bar]):
                place(track, pluck(note(n), 0.45) * 0.22, start + off * beat + k * 0.008)
        for eighth in range(8):
            accent = 0.06 if eighth % 2 else 0.035
            place(track, noise(0.08, 0.025, 2) * accent, start + eighth * beat / 2)

    for n, at in melody:
        place(track, marimba(note(n), 0.7, 0.28) * 0.55, at * beat)

    loop_n = int(SR * length)
    looped = track[:loop_n].copy()
    looped[: len(track) - loop_n] += track[loop_n:]
    return finish(looped, -5, fade=0.0)


def main() -> None:
    for name, signal in sfx().items():
        write_mp3(SFX_DIR / f"{name}.mp3", signal)
    write_mp3(BGM_DIR / "playful_loop.mp3", bgm(), bitrate="96k")


if __name__ == "__main__":
    main()
