# Flipper Lab (中文功能指南)

Chinese help pages on the Flipper screen for the built-in apps: Bluetooth
connection, Infrared, Sub-GHz, NFC, 125 kHz RFID, iButton, GPIO serial, files
and the planned phone companion. Each topic explains what the function does,
the steps in the existing (English) app, what the phone and the Flipper each do,
and concrete limits.

The app only draws text. It does not translate or replace the existing apps and
never drives radio, infrared, NFC, RFID, iButton or GPIO hardware. On a detail
page, OK asks the loader to start the matching existing app after Flipper Lab
exits (`loader_enqueue_launch`); nothing is sent or read automatically.

## Controls

| Screen | Up / Down | Left / Right | OK | Back |
| --- | --- | --- | --- | --- |
| Topic list | select (wraps) | jump three topics | open topic | exit |
| Topic page | previous / next page | previous / next page | open the existing app, if the topic has one | back to the list |

Holding Back exits from either screen.

## Files

| File | Role |
| --- | --- |
| `application.fam` | MENUEXTERNAL app `lab`, entry `lab_app`, category Tools |
| `lab_app.c` | ViewPort app; input goes through a message queue, state is guarded by a mutex |
| `lab_content.json` | every visible string, topic, launch target and the screen layout |
| `lab_content.h` | generated text tables and layout constants |
| `lab_font.h` | generated font subset `lab_font[]` |

## Editing the text

1. Edit `lab_content.json`. A page has at most three lines; a line has at most
   10 non-ASCII characters. Keep `/` out of list rows and page lines: its glyph is
   one pixel taller than a 12-pixel row allows (it is fine in titles, footers and
   page numbers).
2. Run `python scripts/generate_lab_font.py` to rewrite both headers.
3. Run `python scripts/generate_lab_font.py --check` (exit code 1 = stale headers,
   2 = invalid input) and `python scripts/tests/test_lab_font.py`.

The generator measures every string with the same glyph metrics u8g2 uses on the
device (`canvas_string_width`) and checks its horizontal limit and vertical band,
so text that would not fit fails the build step instead of being cut off on the
screen. `lab_app.c` still measures each line and cuts at a whole UTF-8
character if a header is out of date.

`launch` must be the `name` of a MENUEXTERNAL or SETTINGS app in
`applications/main` or `applications/settings`, which is how the main menu starts
them. The generator verifies this against the `application.fam` files. Current
targets: `Bluetooth`, `Infrared`, `Sub-GHz`, `NFC`, `125 kHz RFID`, `iButton`,
`GPIO`. The Archive is not started through the loader by name, so the files
topic explains the desktop shortcut instead. If a target app is not installed,
the loader shows its usual error dialog.

## Font origin and licence

`lab_font.h` is a subset of `u8g2_font_wqy12_t_gb2312` from
`lib/u8g2/u8g2_fonts.c`, where the full 208,526-byte font sits behind
`#ifdef U8G2_USE_LARGE_FONTS` and is not linked by this app. The subset contains
printable ASCII plus the characters used in `lab_content.json`; each glyph's
bytes are copied unchanged and only the u8g2 lookup data is rebuilt.

The comment above that font in `u8g2_fonts.c`, which `lab_font.h` repeats
verbatim, identifies the source as
`-wenquanyi-wenquanyi bitmap song-medium-r-normal--12-120-75-75-P-119-ISO10646-1`
(WenQuanYi Bitmap Song, 12 px) and gives `Copyright: (null)`: no copyright
string was recorded when u8g2 converted the font.

The upstream font documentation and original BDF header were checked on
2026-09-24: copyright belongs to WenQuanYi Project Board of Trustees and
Qianqian Fang (2004–2010), under GPL v2 with the font embedding exception.
See [FONT_LICENSE.md](FONT_LICENSE.md) for the source links and attribution.
The converted C comment's `(null)` does not remove that attribution.

## Limits

- The whole `.fap`, including the font subset, is loaded into RAM while the app
  runs. The exact size is printed in the `lab_font.h` header comment.
- The Unicode glyph lookup is a single linear block, which is fast enough for
  a few hundred glyphs and a text-only screen.
- The phone companion described in the phone topic is still in development; the
  device pages say so rather than describing its features as available.
