# Writing a skin

A skin is one small TOML file. It decides what the wheel looks like: the
colours, the shape of the buttons and how they are shaded. No code, no
restart — the menu reads it on the next press.

## Where skins live

| Place | For whom |
|---|---|
| `~/.config/copilot-key/skins/` | just you — this one wins |
| `/usr/local/share/copilot-key/skins/` | everyone, from a system-wide install |
| `skins/` next to the scripts | a git checkout |

The file name without `.toml` is the skin's id — that is what goes into the
configuration:

```toml
[general]
menu_skin = "aurora"
```

The editor has a **Skin** tab that lists everything it finds, shows a live
preview and opens the folder for you.

## The quickest way to start

Copy one of the shipped skins and edit it:

```bash
mkdir -p ~/.config/copilot-key/skins
cp /usr/local/share/copilot-key/skins/terracotta.toml ~/.config/copilot-key/skins/mine.toml
```

A skin only needs the keys it actually changes. Everything else falls back to
the built-in look, so a three-line file is a perfectly good skin.

## Every key

```toml
name = "My skin"          # shown in the editor
author = "you"            # optional

# How the buttons are shaded:
#   flat   filled, with a hairline outline          (the built-in look)
#   glass  lit 3D spheres with a highlight and a drop shadow
#   mint   flat with a soft gradient and a solid border
style = "flat"

# The outline of a button:
#   circle    a disc
#   rounded   a rounded square
shape = "circle"

# One colour per button, cycled around the wheel. Leave it out and every
# button uses "button" below.
#
# Careful: this line has to stand BEFORE [colors]. A key written after a
# table header belongs to that table - that is TOML, not us. (The loader
# accepts it inside [colors] too, because everybody trips over it once.)
palette = ["#FF6B6B", "#FFD23F", "#3FA7FF"]

[colors]
backdrop = "#0B0A09"      # the dimmed desktop behind the wheel
button = "#1C1A18"        # an unselected button
edge = "#FFFFFF1F"        # its outline
accent = "#D97757"        # selection, badges, the centre button
text = "#F2EFEB"          # labels and icons
text_dim = "#A39C94"      # subtitles and hints
```

## Colours

`#RGB`, `#RRGGBB` and `#RRGGBBAA` all work. The last two digits are the alpha,
which is what makes `edge = "#FFFFFF1F"` a faint white hairline rather than a
white ring.

The shading is derived from the colours you give: `glass` lightens the top of
a button and darkens its bottom, `mint` does the same far more gently. You
only pick the base colour.

## Trying it out

```bash
copilot-key menu          # the real thing
copilot-key configure     # the Skin tab, with a preview
```

A broken file never breaks the menu: it is skipped with a warning on stderr
and the built-in skin is used instead. Run `copilot-key menu` from a terminal
to see that warning.

## Sharing one

Skins are plain text and carry no artwork, so they are easy to pass around —
paste the file, or open a pull request against
[copilot-key-linux](https://github.com/SoulInfernoDE/copilot-key-linux) if it
should ship with the project. Please keep them original: no logos, no copied
assets, nothing that needs a licence.
