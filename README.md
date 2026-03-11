# Perekluk

Minimal macOS keyboard layout switcher. Press **Option** to fix text typed in the wrong layout.

<img src="AppIcon.png" width="128" alt="Perekluk icon">

## Features

- **Fix last word** — type in the wrong layout, press Option, text is corrected
- **Fix selected text** — select text, press Option, selection is converted
- **Toggle back** — press Option again to reverse the conversion
- **Menu bar indicator** — shows current layout (Ру / En)
- **No dock icon** — runs quietly in the menu bar

## Install

### Download

Download **Perekluk.dmg** from [Releases](../../releases/latest), open it, drag `Perekluk.app` to Applications.

### Build from source

```bash
git clone https://github.com/abaskalov/perekluk.git
cd perekluk
make install
```

## Setup

On first launch, Perekluk will ask for **Accessibility** permission:

**System Settings → Privacy & Security → Accessibility → enable Perekluk**

This is required to read keystrokes and simulate text replacement. Restart the app after granting access.

## Usage

| Action | How |
|--------|-----|
| Fix last word | Type a word in wrong layout → press **Option** |
| Fix selection | Select text → press **Option** |
| Switch layout | Press **Option** with nothing typed or selected |
| Toggle back | Press **Option** again |
| Quit | Click menu bar indicator → Quit |

## Requirements

- macOS 13 (Ventura) or later
- Two keyboard layouts enabled (e.g. English + Russian)

## How it works

Perekluk uses a global keyboard event tap to buffer keystrokes. When you press Option alone, it deletes the buffered characters via simulated backspaces and retypes them using the character mapping from the other keyboard layout (via `UCKeyTranslate`). For selected text, it uses the clipboard to read and replace the selection.

## License

[MIT](LICENSE)
