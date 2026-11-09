# omarchy-dtp-no-dock

Turns the Omarchy dock off. Super+Space and Super+Alt+Space are how you reach the system and your apps.

Super+Space opens the Omarchy menu. Super+Alt+Space opens apps. When the list launcher is enabled, that key opens it. Otherwise it opens the menu's Apps list.

## Install

`omarchy-dtp-install` runs this after `omarchy-dtp-app-list`. From a checkout:

```bash
./install.sh
```

The script disables every enabled dock: a personal clone first, then `omarchy.dock`. Disabling a clone turns the stock dock back on, so both steps are required. Running it again leaves a dock that is already off, and a key or menu row that already avoids the dock, untouched. It does not copy monitors, touchpad settings, pinned apps, or `shell.json`.

Pinned apps stay in `shell.json`. They show again if the dock is turned back on.

## Turn the dock back on

```bash
omarchy plugin enable dtpietrzak.dock
```

Use `omarchy plugin enable omarchy.dock` when this machine has no dock clone.

## Minimize

Super+M and the title-bar minus still park a window on a hidden workspace. The dock was what brought that window back. With the dock off, leave minimize alone.
