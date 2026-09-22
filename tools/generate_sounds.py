#!/usr/bin/env python3
"""Synthesise the Copilot-key sound set from scratch.

All sounds are generated procedurally - no samples, no external audio material,
so the result can be published under CC0 without any third-party rights.

Sound design brief:
  * warm glass-bell timbre (sine fundamental + gently damped harmonics)
  * short (<500 ms), quiet (peak -18 dBFS), soft attack to avoid clicks
  * one shared pentatonic scale so every cue belongs to the same family

The two drag cues are the shortest of the family on purpose: they fire while
the pointer is moving, so they have to be felt rather than listened to.

Usage:  python3 tools/generate_sounds.py [output_dir]
"""

from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import wave
import pathlib
from pathlib import Path

import numpy as np

SR = 48_000            # sample rate
PEAK_DBFS = -18.0      # target peak level: audible but never intrusive

# Pentatonic scale on D - warm and consonant in every combination.
NOTE = {
    "D4": 293.66, "E4": 329.63, "Fs4": 369.99, "A4": 440.00, "B4": 493.88,
    "D5": 587.33, "E5": 659.25, "Fs5": 739.99, "A5": 880.00, "D6": 1174.66,
}


def bell(freq: float, dur: float, *, decay: float = 6.0, attack: float = 0.008,
         bend: float = 0.0, harmonics=((1.0, 1.0), (2.0, 0.18), (3.01, 0.07))) -> np.ndarray:
    """One glass-bell partial stack with an exponential decay envelope.

    bend: relative pitch glide over the note (e.g. 0.03 = +3 % upwards).
    """
    n = int(SR * dur)
    t = np.linspace(0.0, dur, n, endpoint=False)
    # Smooth pitch glide; integrate frequency to get phase.
    glide = 1.0 + bend * (t / dur)
    sig = np.zeros(n)
    for ratio, amp in harmonics:
        phase = 2.0 * np.pi * np.cumsum(freq * ratio * glide) / SR
        # Higher partials decay faster, like a real struck bell.
        sig += amp * np.sin(phase) * np.exp(-decay * ratio**0.6 * t)
    env_attack = np.clip(t / max(attack, 1e-6), 0.0, 1.0) ** 2
    return sig * env_attack


def place(canvas: np.ndarray, sig: np.ndarray, at: float, gain: float = 1.0) -> None:
    """Mix sig into canvas starting at second `at`."""
    start = int(SR * at)
    end = min(start + len(sig), len(canvas))
    canvas[start:end] += gain * sig[: end - start]


def air(sig: np.ndarray, amount: float = 0.22, delay: float = 0.045) -> np.ndarray:
    """Very small feedback delay - gives the cue a bit of room without reverb libs."""
    out = sig.copy()
    d = int(SR * delay)
    for tap, g in ((d, amount), (2 * d, amount * 0.45), (3 * d, amount * 0.2)):
        if tap < len(out):
            out[tap:] += g * sig[: len(sig) - tap]
    return out


def finish(mono: np.ndarray, *, spread: float = 0.0006) -> np.ndarray:
    """Normalise, de-click and widen to a subtle stereo image."""
    mono = air(mono)
    # 6 ms fade-out guards against a DC step at the end of the buffer.
    fade = int(SR * 0.006)
    if len(mono) > fade:
        mono[-fade:] *= np.linspace(1.0, 0.0, fade)
    peak = np.max(np.abs(mono))
    if peak > 0:
        mono *= (10 ** (PEAK_DBFS / 20)) / peak
    # Haas-style widening: a sub-millisecond offset between the channels.
    off = int(SR * spread)
    left = mono
    right = np.concatenate([np.zeros(off), mono])[: len(mono)] if off else mono
    return np.stack([left, right], axis=1)


def write_wav(path: Path, stereo: np.ndarray) -> None:
    data = np.clip(stereo, -1.0, 1.0)
    pcm = (data * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


# --- the cues ---------------------------------------------------------------

def cue_menu_open() -> np.ndarray:
    """Two rising notes: something is unfolding, waiting for your choice."""
    buf = np.zeros(int(SR * 0.55))
    place(buf, bell(NOTE["A4"], 0.45, decay=7.0), 0.000, 0.85)
    place(buf, bell(NOTE["D5"], 0.45, decay=6.0), 0.075, 0.95)
    place(buf, bell(NOTE["A5"], 0.35, decay=9.0), 0.085, 0.25)
    return buf


def cue_menu_dismiss() -> np.ndarray:
    """Mirror of the open cue, falling and darker: nothing happened."""
    buf = np.zeros(int(SR * 0.45))
    place(buf, bell(NOTE["D5"], 0.32, decay=9.0), 0.000, 0.7)
    place(buf, bell(NOTE["A4"], 0.40, decay=8.0), 0.070, 0.8)
    return buf


def cue_launch() -> np.ndarray:
    """Rising arpeggio with a sustained top note: the action is on its way."""
    buf = np.zeros(int(SR * 0.85))
    place(buf, bell(NOTE["D4"], 0.55, decay=6.5), 0.000, 0.7)
    place(buf, bell(NOTE["A4"], 0.55, decay=5.5), 0.070, 0.8)
    place(buf, bell(NOTE["D5"], 0.65, decay=4.0), 0.140, 0.95)
    place(buf, bell(NOTE["Fs5"], 0.55, decay=5.0), 0.150, 0.35)
    return buf


def cue_toggle_show() -> np.ndarray:
    """Short bright blip with an upward glide: the window comes forward."""
    buf = np.zeros(int(SR * 0.30))
    place(buf, bell(NOTE["Fs5"], 0.22, decay=13.0, attack=0.004, bend=0.035), 0.0, 1.0)
    place(buf, bell(NOTE["D6"], 0.14, decay=18.0, attack=0.003), 0.006, 0.18)
    return buf


def cue_toggle_hide() -> np.ndarray:
    """The counterpart of toggle-show: from F#5 down to D5, a major third.

    Two clean steps instead of a glide. The first version bent a single bell
    downwards, and a decaying note that slowly goes flat - it sagged by two
    thirds of a semitone - sounds out of tune rather than calm. The slightly
    inharmonic third partial is left out for the same reason: it beat against
    the fundamental.
    """
    soft = ((1.0, 1.0), (2.0, 0.10))
    buf = np.zeros(int(SR * 0.38))
    place(buf, bell(NOTE["Fs5"], 0.12, decay=20.0, attack=0.005, harmonics=soft), 0.000, 0.55)
    place(buf, bell(NOTE["D5"], 0.30, decay=11.0, attack=0.007, harmonics=soft), 0.045, 0.90)
    return buf


def cue_error() -> np.ndarray:
    """Soft low two-tone - informative, deliberately not harsh."""
    buf = np.zeros(int(SR * 0.50))
    place(buf, bell(NOTE["E4"], 0.30, decay=10.0, harmonics=((1.0, 1.0), (2.0, 0.10))), 0.000, 0.8)
    place(buf, bell(NOTE["D4"], 0.38, decay=9.0, harmonics=((1.0, 1.0), (2.0, 0.10))), 0.110, 0.8)
    return buf


def cue_drag_lift() -> np.ndarray:
    """Short upward pluck: the button came loose and now follows the pointer."""
    buf = np.zeros(int(SR * 0.26))
    place(buf, bell(NOTE["E5"], 0.17, decay=17.0, attack=0.003, bend=0.060), 0.000, 0.75)
    place(buf, bell(NOTE["B4"], 0.15, decay=15.0, attack=0.004), 0.000, 0.30)
    return buf


def cue_drag_drop() -> np.ndarray:
    """A plop: a low note bent sharply down, damped almost at once."""
    buf = np.zeros(int(SR * 0.28))
    place(buf, bell(NOTE["D4"], 0.20, decay=21.0, attack=0.002, bend=-0.22,
                    harmonics=((1.0, 1.0), (2.0, 0.06))), 0.000, 1.00)
    place(buf, bell(NOTE["D5"], 0.09, decay=30.0, attack=0.002), 0.004, 0.20)
    return buf


CUES = {
    "menu-open": cue_menu_open,
    "menu-dismiss": cue_menu_dismiss,
    "launch": cue_launch,
    "toggle-show": cue_toggle_show,
    "toggle-hide": cue_toggle_hide,
    "error": cue_error,
    "drag-lift": cue_drag_lift,
    "drag-drop": cue_drag_drop,
}


def main() -> int:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "sounds")
    out.mkdir(parents=True, exist_ok=True)
    ffmpeg = shutil.which("ffmpeg")
    with tempfile.TemporaryDirectory() as tmp:
        for name, fn in CUES.items():
            stereo = finish(fn())
            if ffmpeg:
                # Encode via a scratch WAV so the output dir only ever sees OGG.
                wav = pathlib.Path(tmp) / f"{name}.wav"
                write_wav(wav, stereo)
                ogg = out / f"{name}.ogg"
                subprocess.run(
                    [ffmpeg, "-y", "-loglevel", "error", "-i", str(wav),
                     "-c:a", "libvorbis", "-q:a", "4", str(ogg)],
                    check=True,
                )
                print(f"  {ogg.name}  {ogg.stat().st_size / 1024:.1f} KiB")
            else:
                wav = out / f"{name}.wav"
                write_wav(wav, stereo)
                print(f"  {wav.name}  (ffmpeg missing - keeping WAV)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
