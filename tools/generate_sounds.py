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

Besides the hand-tuned default set, the generator builds the shipped sound
themes (see THEMES) into sub-directories of the output directory.

Usage:  python3 tools/generate_sounds.py [output_dir] [theme ...]
        theme: "default" and/or the names in THEMES; all of them when omitted
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

# The pure major third above D5. Equal temperament puts it 14 cents sharp,
# which is inaudible in a melody but not when two bells overlap: they ring
# in whole-number ratios, and 5:4 is the one this interval wants.
FS5_PURE = NOTE["D5"] * 5 / 4

# The pure fifths around D5, for menu-open: tempered they sit 2 cents flat,
# enough for a partial that should coincide to beat instead.
A4_PURE = NOTE["D5"] * 3 / 4
A5_PURE = NOTE["D5"] * 3 / 2


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
    """Two rising notes: something is unfolding, waiting for your choice.

    Pure fifths and no inharmonic partial. With the default bell, D5's third
    partial (3.01 x) landed 7.9 Hz from A5's second and the two beat - a slow
    wobble that made the chord sound slightly out of tune.
    """
    soft = ((1.0, 1.0), (2.0, 0.18))
    buf = np.zeros(int(SR * 0.55))
    place(buf, bell(A4_PURE, 0.45, decay=7.0, harmonics=soft), 0.000, 0.85)
    place(buf, bell(NOTE["D5"], 0.45, decay=6.0, harmonics=soft), 0.075, 0.95)
    place(buf, bell(A5_PURE, 0.35, decay=9.0, harmonics=soft), 0.085, 0.25)
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
    """The window comes forward: D5 stepping up a pure major third.

    The mirror of toggle-hide, brighter by a touch more octave. The first
    version bent F#5 upwards under a D6: the note drifted by half a semitone
    and the interval between the two slid past the point where it rings true,
    so the whole cue sounded slightly out of tune. Steps, not glides; a pure
    third rather than the tempered one; no inharmonic partial to beat.
    """
    bright = ((1.0, 1.0), (2.0, 0.16))
    buf = np.zeros(int(SR * 0.36))
    place(buf, bell(NOTE["D5"], 0.11, decay=20.0, attack=0.004, harmonics=bright), 0.000, 0.55)
    place(buf, bell(FS5_PURE, 0.28, decay=11.0, attack=0.005, harmonics=bright), 0.042, 1.00)
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


# --- further themes -----------------------------------------------------------
# The default set above is tuned by hand, cue by cue. The other themes are
# derived instead: every cue keeps one gesture - rising for "open" and "show",
# falling for "dismiss" and "hide" - written once as pure ratios over a root,
# and a theme only picks the root, the timbre and how fast the notes die away.
# Pure ratios and purely harmonic partials leave nothing to beat and nothing
# to drift, which is what the default set had to learn the hard way.

# (ratio to the root, start in s, length in s, gain, decay factor)
GESTURES = {
    "menu-open":    [(3 / 4, 0.000, 0.45, 0.85, 1.0), (1, 0.075, 0.45, 0.95, 0.9),
                     (3 / 2, 0.085, 0.35, 0.25, 1.4)],
    "menu-dismiss": [(1, 0.000, 0.32, 0.70, 1.4), (3 / 4, 0.070, 0.40, 0.80, 1.2)],
    "launch":       [(1 / 2, 0.000, 0.55, 0.70, 1.0), (3 / 4, 0.070, 0.55, 0.80, 0.9),
                     (1, 0.140, 0.65, 0.95, 0.65), (5 / 4, 0.150, 0.55, 0.35, 0.8)],
    "toggle-show":  [(1, 0.000, 0.11, 0.55, 3.0), (5 / 4, 0.042, 0.28, 1.00, 1.7)],
    "toggle-hide":  [(5 / 4, 0.000, 0.12, 0.55, 3.0), (1, 0.045, 0.30, 0.90, 1.7)],
    "error":        [(9 / 16, 0.000, 0.30, 0.80, 1.5), (1 / 2, 0.110, 0.38, 0.80, 1.4)],
    "drag-lift":    [(1, 0.000, 0.09, 0.50, 3.4), (9 / 8, 0.028, 0.15, 0.85, 2.7)],
    "drag-drop":    [(1 / 2, 0.000, 0.14, 1.00, 3.8), (1, 0.004, 0.06, 0.18, 5.0)],
}

THEMES = {
    "crystal": {
        "name": "Crystal",
        "name_de": "Kristall",
        "description": "Bright, clear chimes an octave above the glass bells",
        "description_de": "Helle, klare Glöckchen eine Oktave über den Glasglocken",
        "root": NOTE["D6"],
        "harmonics": ((1.0, 1.0), (2.0, 0.22), (3.0, 0.08), (4.0, 0.04)),
        "attack": 0.003,
        "decay": 7.5,
    },
    "felt": {
        "name": "Felt",
        "name_de": "Filz",
        "description": "Soft wooden mallets, low and muted",
        "description_de": "Weiche Holzschlägel, tief und gedämpft",
        "root": NOTE["D5"] * 3 / 4,
        # A marimba bar sounds its fundamental and, tuned on purpose, the
        # double octave - nothing in between, which is what makes it wooden.
        "harmonics": ((1.0, 1.0), (4.0, 0.10)),
        "attack": 0.012,
        "decay": 11.0,
    },
}

DEFAULT_THEME = {
    "name": "Glass",
    "name_de": "Glas",
    "description": "Soft glass bells on a pentatonic scale over D",
    "description_de": "Weiche Glasglocken auf einer pentatonischen Skala über D",
}


def render_gesture(theme: dict, cue: str) -> np.ndarray:
    notes = GESTURES[cue]
    length = max(start + dur for _r, start, dur, _g, _d in notes) + 0.05
    buf = np.zeros(int(SR * length))
    for ratio, start, dur, gain, decay in notes:
        place(buf, bell(theme["root"] * ratio, dur, decay=theme["decay"] * decay,
                        attack=theme["attack"], harmonics=theme["harmonics"]),
              start, gain)
    return buf


def theme_toml(meta: dict) -> str:
    lines = ["# Generated by tools/generate_sounds.py - CC0, like the sounds.",
             "# Every key is optional; see docs/sound-themes.md."]
    for key in ("name", "name_de", "description", "description_de"):
        lines.append(f'{key} = "{meta[key]}"')
    if meta is not DEFAULT_THEME:
        lines.append('inherits = "default"')
    lines.append('author = "copilot-key"')
    return "\n".join(lines) + "\n"


def encode(stereo: np.ndarray, target: Path, tmp: str, ffmpeg: str | None) -> Path:
    if not ffmpeg:
        wav = target.with_suffix(".wav")
        write_wav(wav, stereo)
        return wav
    # Encode via a scratch WAV so the output dir only ever sees OGG.
    wav = pathlib.Path(tmp) / f"{target.stem}.wav"
    write_wav(wav, stereo)
    subprocess.run([ffmpeg, "-y", "-loglevel", "error", "-i", str(wav),
                    "-c:a", "libvorbis", "-q:a", "4", str(target)], check=True)
    return target


def main() -> int:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "sounds")
    wanted = sys.argv[2:] or ["default", *THEMES]
    unknown = [name for name in wanted if name != "default" and name not in THEMES]
    if unknown:
        print(f"unknown theme(s): {', '.join(unknown)}", file=sys.stderr)
        return 2
    ffmpeg = shutil.which("ffmpeg")
    with tempfile.TemporaryDirectory() as tmp:
        for name in wanted:
            target = out if name == "default" else out / name
            target.mkdir(parents=True, exist_ok=True)
            meta = DEFAULT_THEME if name == "default" else THEMES[name]
            (target / "theme.toml").write_text(theme_toml(meta), encoding="utf-8")
            print(f"{name}:")
            for cue, fn in CUES.items():
                buf = fn() if name == "default" else render_gesture(THEMES[name], cue)
                done = encode(finish(buf), target / f"{cue}.ogg", tmp, ffmpeg)
                print(f"  {done.name}  {done.stat().st_size / 1024:.1f} KiB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
