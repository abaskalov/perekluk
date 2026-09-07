# Perekluk

<img src="AppIcon.png" width="96" alt="Perekluk icon" align="right">

Lightweight macOS keyboard layout switcher. Type in the wrong layout — press a key — fixed.

Free, open-source alternative to Punto Switcher and Caramba Switcher.

## Features

- **Fix last word** — converts the most recent word to the correct layout
- **Fix selection** — select any text and convert it in place
- **Configurable trigger** — choose Left Option, Right Option, Both, or Caps Lock
- **3+ layouts** — works with any number of keyboard layouts, not just two
- **Dead key support** — handles accented characters (é, ü, ñ) correctly
- **Menu bar indicator** — shows current layout (Ру / En)
- **Launch at login** — enabled automatically on first launch, toggle in the menu
- **Minimal footprint** — no Dock icon, no windows, just a menu bar item

## Install

Download **Perekluk.dmg** from [Releases](../../releases/latest), drag to Applications.

Or build from source:

```
git clone https://github.com/abaskalov/perekluk.git
cd perekluk
make install
```

## Setup

Grant **Accessibility** permission on first launch:

**System Settings → Privacy & Security → Accessibility → Perekluk**

## Usage

| Action | How |
|--------|-----|
| Fix last word | Type in wrong layout → press trigger key |
| Fix selection | Select text → press trigger key |
| Switch layout | Press trigger key with nothing typed/selected |
| Reverse | Press trigger key again |
| Change trigger | Menu bar → Trigger Key → pick one |
| Toggle autostart | Menu bar → Launch at Login |
| Quit | Menu bar → Quit |

### Trigger key options

| Option | Description |
|--------|-------------|
| Both Options ⌥ | Either Option key (default) |
| Left Option ⌥ | Only left Option |
| Right Option ⌥ | Only right Option |
| fn 🌐 | The fn / Globe key |
| Caps Lock ⇪ | Caps Lock acts as switcher, toggle suppressed |

Setting persists across restarts.

> **fn note:** macOS binds a single fn/Globe press to a system action (emoji picker or input-source switch). For a clean trigger, set **System Settings → Keyboard → Press 🌐 key to → Do Nothing**. Perekluk warns about this when you pick fn and offers to open that setting.

## Requirements

- macOS 13+
- Two or more keyboard layouts enabled

## How it works

Perekluk installs a global event tap to buffer keystrokes. On trigger, it deletes the buffered word and retypes it in the target layout using `UCKeyTranslate` with stateful dead key handling. For selections, it reads text via Accessibility API (falling back to the app's Copy menu action and the clipboard; no synthetic Cmd+C, which Ghostty would type as a stray "c"), converts it, and writes it back.

## License

[MIT](LICENSE)
