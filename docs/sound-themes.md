# Sound themes

A sound theme is a folder of audio files, one per cue, with an optional
`theme.toml` next to them. No code, no restart — the next key press uses it.

## Which file plays

For every cue the launcher walks down this list and takes the first file it
finds:

1. **A file of your own for just this cue** — `[sounds]` in your
   configuration, which the editor's *Sounds* tab fills in.
2. **The active sound theme.**
3. **The theme it inherits from** — and that one's parent, and so on.
4. **The glass bells** that ship with copilot-key.

So a theme never has to be complete. Three files and a `theme.toml` make a
perfectly good theme; everything it leaves out comes from further down.

## Which theme is active

```toml
[general]
sound_theme = "auto"      # or "default", "crystal", "felt", or your own
```

`auto` — the default — takes the theme the current skin names. The shipped
skins bring their own: Terracotta the glass bells, Aurora 3D *Crystal*, Mint
*Felt*. Pick a theme explicitly and it stays, whatever skin you switch to.

## The cues

| File name | When it plays |
|---|---|
| `menu-open` | the menu opens |
| `menu-dismiss` | the menu closes without a choice |
| `launch` | an action starts |
| `toggle-show` | a window comes forward |
| `toggle-hide` | a window is minimised |
| `error` | something is not available |
| `drag-lift` | a button is picked up in the wheel's edit mode |
| `drag-drop` | it is put down again |

Each one as `<cue>.ogg`, `.oga`, `.wav`, `.flac` or `.mp3`. Ogg and WAV play
everywhere; FLAC needs `paplay` or `pw-play`; MP3 needs `ffplay` or `mpv`
(`./doctor.sh` lists the players you have).

## Where themes live

| Place | For whom |
|---|---|
| `~/.config/copilot-key/sounds/<name>/` | just you — this one wins |
| `/usr/local/share/copilot-key/sounds/<name>/` | everyone, from a system-wide install |
| `sounds/<name>/` next to the scripts | a git checkout |

The folder name is the theme's id, the value `sound_theme` takes. The glass
bells are the `sounds/` folder itself; to change single bells for yourself
only, put files into `~/.config/copilot-key/sounds/default/`.

## theme.toml

Every key is optional.

```toml
name = "My theme"
name_de = "Mein Theme"              # shown instead of name in German
description = "What it sounds like"
description_de = "Wie es klingt"
author = "you"
inherits = "crystal"                # missing cues come from here; default: "default"
gain = 0.6                          # 0.0-1.0, tames files that are too loud
```

`gain` matters more than it looks: the shipped cues peak at −18 dBFS, and a
file normalised to 0 dBFS is eighteen decibels louder — startling right next
to the others. Lower it until your theme sits at the same level.

## Linking a skin to a theme

One line in the skin's TOML (see [skins.md](skins.md)):

```toml
sound_theme = "my-theme"
```

Whoever keeps `sound_theme = "auto"` then hears your theme with your skin.

## Single files without a theme

The *Sounds* tab in the editor has a *File…* button next to every cue. The
file is copied into `~/.config/copilot-key/sounds/`, so tidying up Downloads
breaks nothing, and the configuration names it:

```toml
[sounds]
launch = "my-start.ogg"          # a name in ~/.config/copilot-key/sounds/
error = "none"                   # mute just this one
drag-drop = "~/Music/plop.wav"   # ~/... and absolute paths work too
```

## Making sounds that fit

The shipped themes follow three rules, all learned from cues that sounded
slightly out of tune:

- **Steps, not glides.** A decaying note whose pitch drifts sounds detuned.
- **Pure intervals where notes overlap** — a major third as 5:4, a fifth as
  3:2 — rather than the tempered ones, which two ringing bells give away.
- **Short and quiet.** Under a second, with a soft attack: these play dozens
  of times a day.

`tools/generate_sounds.py` builds the shipped themes from scratch. A new
synthesised theme is one entry in its `THEMES` table — a root note, a timbre
and a decay — because every cue's melody is shared between themes. Run it
with the theme's name to build just that one:

```bash
python3 tools/generate_sounds.py sounds my-theme
```

## Sharing one

Keep them yours: sounds you recorded or synthesised, or ones whose licence
allows redistribution. The shipped themes are CC0; a theme proposed for the
project should be as well.
