# Perekluk

Minimal macOS keyboard layout switcher. Press **Option** to fix text typed in the wrong layout.

Free and open-source alternative to Caramba Switcher and Punto Switcher.

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

This is required to read keystrokes and simulate text replacement. The app starts automatically after you grant access.

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

---

## Описание на русском

**Perekluk** — минималистичный переключатель раскладки клавиатуры для macOS. Бесплатная альтернатива Caramba Switcher и Punto Switcher с открытым исходным кодом.

### Возможности

- **Исправление последнего слова** — набрали текст не в той раскладке, нажали Option — текст исправлен
- **Исправление выделенного текста** — выделите текст, нажмите Option — выделение конвертируется
- **Обратная конвертация** — нажмите Option ещё раз, чтобы вернуть как было
- **Индикатор в строке меню** — показывает текущую раскладку (Ру / En)
- **Без иконки в Dock** — работает тихо в строке меню

### Установка

Скачайте **Perekluk.dmg** из [Releases](../../releases/latest), откройте и перетащите `Perekluk.app` в Программы.

### Настройка

При первом запуске Perekluk запросит разрешение **Универсальный доступ**:

**Системные настройки → Конфиденциальность и безопасность → Универсальный доступ → включить Perekluk**

После выдачи разрешения приложение запустится автоматически.

### Использование

| Действие | Как |
|----------|-----|
| Исправить последнее слово | Набрали в неправильной раскладке → нажмите **Option** |
| Исправить выделенный текст | Выделите текст → нажмите **Option** |
| Переключить раскладку | Нажмите **Option** когда ничего не набрано и не выделено |
| Вернуть обратно | Нажмите **Option** ещё раз |
| Выйти | Нажмите на индикатор в строке меню → Quit |

### Системные требования

- macOS 13 (Ventura) или новее
- Две раскладки клавиатуры (например, English + Russian)
