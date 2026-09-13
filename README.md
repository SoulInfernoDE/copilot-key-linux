# copilot-key

Die Copilot-Taste des **Minisforum AI X1 Pro** sinnvoll belegen – unter Linux,
mit Auswahlmenü, Fenster-Toggle und eigenem Sound-Set.

* **Kurz drücken** → Fenster der primären Aktion nach vorne holen bzw.
  minimieren. Läuft nichts, öffnet sich das Auswahlmenü.
* **Doppelt drücken** → Auswahlmenü erzwingen.
* **Nochmal drücken, während das Menü offen ist** → Menü schließen.
* Jeder Zustandswechsel hat seinen eigenen Klang.

Das Menü legt sich als Vollbild-Overlay über den abgedunkelten Bildschirm und
rollt kreisförmig aus der Mitte auf. Bedienen lässt es sich mit `1`–`9`, den
Pfeiltasten, dem Mausrad oder per Klick; `Esc` oder ein Klick ins Leere
schließt es wieder. Die Symbole sind reine Cairo-Vektorzeichnungen – kein
Icon-Theme, keine fremden Grafiken.

![Auswahlmenü](docs/menu.png)

Entwickelt für Linux Mint 22.3 (Cinnamon, X11, Ubuntu-24.04-Basis); das Menü
ist unter GTK 3 gegengeprüft, die Tastenkette muss auf der Zielmaschine einmal
mit `detect-key.sh` bestätigt werden.

---

## Installation

```bash
cd aix1pro_copilot_key
./install.sh
```

Das Skript wird als normaler Benutzer gestartet und fragt selbst nach `sudo`.
Es erledigt:

1. Abhängigkeiten prüfen (`wmctrl`, `xdotool`, `python3-gi`, `python3-gi-cairo`,
   `pulseaudio-utils`)
2. `keyd` installieren – aus den Paketquellen, sonst aus dem Quellcode nach
   `~/Downloads/keyd` mit Prefix `/usr/local`
3. Launcher nach `~/.local/bin`, Sounds nach `~/.local/share/copilot-key`,
   Konfiguration nach `~/.config/copilot-key/config.toml`
4. `config/keyd-copilot.conf` nach `/etc/keyd/copilot.conf` und `keyd` neu starten
5. Cinnamon-Tastenkürzel `Ctrl+Alt+Shift+F12` → `copilot-key` eintragen

Entfernen: `./uninstall.sh`

Nach einem Update des Projektordners genügt ein erneutes `./install.sh` – die
bestehende Konfiguration bleibt dabei unangetastet.

---

## Wie die Taste überhaupt ankommt

Die Copilot-Taste sendet keinen eigenen Tastencode, sondern den Akkord
**LeftMeta + LeftShift + F23**. Desktop-Umgebungen können diesen Akkord meist
nicht sauber als Kürzel aufnehmen – deshalb die zweistufige Kette:

```
Copilot-Taste  →  keyd (evdev, vor X11/Wayland)  →  Ctrl+Alt+Shift+F12  →  Cinnamon-Kürzel  →  copilot-key
```

`keyd` arbeitet unterhalb des Fenstersystems und funktioniert daher unter X11
und Wayland gleichermaßen.

Sendet die Taste bei dir etwas anderes, zeigt

```bash
./detect-key.sh
```

den tatsächlichen Code an (nutzt `keyd monitor`, sonst `evtest`, sonst `xev`).
In `config/keyd-copilot.conf` stehen die gängigen Alternativen bereits
auskommentiert bereit – Zeile tauschen, dann `sudo keyd reload`.

---

## Konfiguration

`~/.config/copilot-key/config.toml`. Änderungen greifen sofort beim nächsten
Tastendruck.

```toml
[general]
sounds = true
volume = 0.7
double_press_ms = 450
single_press = "toggle_or_menu"   # oder "toggle" / "menu"
menu_title = "Was darf es sein?"
close_on_focus_loss = true
menu_style = "radial"             # oder "list" für eine schlichte Liste
dim_opacity = 0.62                # wie stark der Hintergrund abgedunkelt wird

[[actions]]
id = "claude-desktop"
label = "Claude Desktop"
subtitle = "Fenster in den Vordergrund holen oder starten"
command = "@claude-desktop"
icon = "window"
window_class = "claude"
primary = true
```

Die Reihenfolge der `[[actions]]` ist die Reihenfolge im Menü und entspricht
den Zifferntasten `1`–`9`. `close_on_focus_loss = false` hilft, falls das Menü
auf einem ungewöhnlichen Desktop zu früh verschwindet.

| Platzhalter in `command` | Wirkung |
|---|---|
| `@claude-desktop` | sucht eine installierte Claude-Desktop-App, sonst `claude.ai` im Browser |
| `@terminal <cmd>` | öffnet `<cmd>` in einem neuen Terminalfenster (Terminal bleibt offen) |
| `@browser <url>` | öffnet `<url>` in der Standardanwendung |
| `@edit-config` | öffnet diese Datei im Standardeditor |

Alles andere wird als gewöhnliche Kommandozeile ausgeführt. `window_class` ist
ein Teilstring der `WM_CLASS`; die passende Klasse findest du mit `wmctrl -lx`.

Verfügbare Symbole für `icon`: `window`, `terminal`, `globe`, `gear`, `chat`,
`folder`, `power`, `sparkle`. Ohne Angabe wird anhand von `id` und `label`
geraten, im Zweifel erscheint `sparkle`.

**Hinweis zu „Claude Desktop“:** Eine offizielle Desktop-App für Linux gibt es
nicht. Erkannt werden die gängigen inoffiziellen Pakete (`claude-desktop`,
`claude-desktop-app`, `claude-desktop-bin`); ist keines installiert, öffnet die
Aktion `claude.ai` im Browser. Mit `claude` in der `@terminal`-Aktion startet
dagegen die offizielle **Claude Code CLI**.

---

## Fehlersuche

```bash
./doctor.sh
```

prüft Installation, Sound-Dateien, Audio-Server, verfügbare Player, die
Grafik-Bibliotheken, keyd und das Tastenkürzel – und spielt zum Schluss einen
Testton ab. Kein Ton? Die häufigsten Ursachen:

* `pulseaudio-utils` fehlt → `sudo apt install pulseaudio-utils`
* Sounds nicht installiert → `./install.sh` erneut ausführen
* Ein einzelner Player streikt (`pw-play` etwa lehnt Ogg in manchen Builds ab):
  `COPILOT_KEY_DEBUG=1 ~/.local/bin/copilot-sound menu-open 0.9` zeigt, welcher
  Player greift und welcher abgelehnt hat

Erscheint statt des runden Menüs eine schlichte Liste, fehlt
`python3-gi-cairo` (`sudo apt install python3-gi-cairo`).

---

## Sounds

Sechs Cues, alle aus derselben Klangfamilie – weiche Glasglocken auf einer
pentatonischen Skala über D, kurz, leise (Spitze −18 dBFS) und mit weichem
Attack, damit nichts klickt oder aufdringlich wirkt:

| Cue | Wann | Charakter |
|---|---|---|
| `menu-open` | Menü öffnet sich | zwei aufsteigende Töne, fragend |
| `menu-dismiss` | Menü mit Esc geschlossen | dasselbe abwärts, gedämpft |
| `launch` | Aktion wird gestartet | aufsteigendes Arpeggio, bestätigend |
| `toggle-show` | Fenster kommt nach vorne | heller Blip mit Aufwärts-Glide |
| `toggle-hide` | Fenster wird minimiert | derselbe Blip abwärts |
| `error` | Aktion nicht ausführbar | tiefer Doppelton, bewusst nicht schrill |

Anhören:

```bash
~/.local/bin/copilot-key test-sounds
```

Die Dateien sind **vollständig synthetisch erzeugt** – reine additive Synthese
mit numpy, keine Samples, keine Aufnahmen, kein fremdes Audiomaterial. Der
Generator liegt bei und erzeugt sie identisch neu:

```bash
python3 tools/generate_sounds.py sounds
```

Eigene Sounds: gleichnamige `.ogg`- oder `.wav`-Dateien in
`~/.local/share/copilot-key/sounds` ablegen.

---

## Andere Desktops

Der Installer trägt das Kürzel automatisch nur unter Cinnamon ein. Sonst
`Ctrl+Alt+Shift+F12` von Hand auf `~/.local/bin/copilot-key` legen:

* **GNOME** – Einstellungen → Tastatur → Tastenkombinationen → Eigene Kürzel
* **KDE Plasma** – Systemeinstellungen → Kurzbefehle → Eigene Kurzbefehle
* **XFCE** – Einstellungen → Tastatur → Anwendungskürzel

Unter Wayland funktionieren Menü und Sounds; das Fenster-Toggeln braucht
`wmctrl`/`xdotool` und damit X11 oder XWayland. Die Abdunklung des Hintergrunds
setzt einen laufenden Compositor voraus (unter Cinnamon Standard); ohne
Compositor deckt das Overlay den Bildschirm vollflächig ab.

---

## Projektstruktur

```
bin/copilot-key          Launcher: Toggle-Logik, Menü, Sound-Auslösung
bin/copilot-sound        Sound-Wiedergabe (pw-play / paplay / ffplay / aplay)
config/config.toml       Vorlage der Benutzerkonfiguration
config/keyd-copilot.conf keyd-Regel für den Copilot-Akkord
sounds/                  sechs CC0-Cues
tools/generate_sounds.py Sound-Generator
detect-key.sh            zeigt, was die Taste tatsächlich sendet
doctor.sh                prüft Installation, Audio-Kette und Tastenkürzel
docs/menu.png            Screenshot des Auswahlmenüs
install.sh / uninstall.sh
```

---

## Lizenz

Code: **MIT** (siehe `LICENSE`).
Sounds: **CC0 1.0** (siehe `sounds/LICENSE`).

Dieses Projekt steht in keiner Verbindung zu Anthropic, Microsoft oder
Minisforum. „Claude“, „Copilot“ und „Minisforum“ sind Marken der jeweiligen
Inhaber und werden hier ausschließlich beschreibend verwendet.
