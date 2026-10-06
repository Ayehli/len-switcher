# len-switcher

Windows helper for when you type a whole field in the wrong keyboard layout. Press a shortcut: it selects the current text field, remaps the letters as if the other layout had been on, pastes the result, and switches Windows to that language.

Plain copy → switch layout → paste does not fix this. Paste keeps the same letters. This script remaps by physical key between the two layouts you choose in Settings.

## Install (recommended)

Double-click **`LenSwitcher.exe`**. The first run downloads portable [AutoHotkey v2](https://www.autohotkey.com/) into `%LocalAppData%\LenSwitcher` (you need internet once). After that it just starts the helper; a green **H** icon appears in the tray.

You do not need to install AutoHotkey yourself. Later launches reuse the cached download.

To rebuild the exe after you edit `len-switcher.ahk`:

```powershell
powershell -ExecutionPolicy Bypass -File .\build-exe.ps1
```

## Run the script directly

If you already have AutoHotkey v2 installed, you can double-click `len-switcher.ahk` instead of the exe.

## Use

1. Click in a text field (Notepad, a browser input, Word, WhatsApp Desktop, and similar).
2. Press the convert hotkey (default **Ctrl+Shift+L**).
3. The field contents convert in place between your two configured layouts, then Windows switches to the target layout.

It will not be reliable in terminals, games, or when focus is not in a text field (Ctrl+A may select a whole web page). Complex IME layouts (e.g. CJK) are not supported.

## Settings

Right-click the tray icon → **Settings** (ASCII-style window):

1. **Hotkey** — click **Set Hotkey**, then press the combo you want (Esc cancels).
2. **Language pair** — pick any two installed keyboard layouts. Mistyped text is remapped between those layouts.

Settings are saved to:

`%LocalAppData%\LenSwitcher\settings.ini`

Changing the script or rebuilding the exe does not wipe this file.

## Run at login

1. Press **Win+R**, type `shell:startup`, press Enter.
2. Put a shortcut to `LenSwitcher.exe` (or `len-switcher.ahk`) in that folder.

Windows will start it when you sign in.
