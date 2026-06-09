<h1 align="center"> Quickshell Rise </h1>

<h4 align="center"> My Quickshell bar for Omarchy — my new Rise journey into Quickshell starts here. Enjoy! </h4>
<div align="center">

[![Stars](https://img.shields.io/github/stars/HANCORE-linux/quickshell-dots?style=for-the-badge&labelColor=000000&color=209edb&logo=github&logoColor=209edb)](https://github.com/HANCORE-linux/quickshell-dots)
[![Forks](https://img.shields.io/github/forks/HANCORE-linux/quickshell-dots?style=for-the-badge&labelColor=000000&color=209edb&logo=github&logoColor=209edb&cacheSeconds=3600)](https://github.com/HANCORE-linux/quickshell-dots/network)
[![Issues](https://img.shields.io/github/issues/HANCORE-linux/quickshell-dots?style=for-the-badge&labelColor=000000&color=209edb&logo=github&logoColor=209edb)](https://github.com/HANCORE-linux/quickshell-dots/issues)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-SUPPORT-000000?style=for-the-badge&labelColor=000000&color=209edb&logo=buymeacoffee&logoColor=209edb)](https://buymeacoffee.com/hancore)

</div>

## Usability
<details>

- **Omarchy-based.** Integrates the `omarchy-*` helpers (wifi/bluetooth/audio launchers, update, screen recorder, voxtype) and reads the active Omarchy theme.
- Built for Omarchy / Hyprland — not for plain setups without Omarchy.

</details>

## Dependencies
<details>

Comes with Omarchy: Hyprland, the `omarchy-*` helpers, fonts (JetBrainsMono Nerd Font + Material Symbols Rounded), mako.

Extra:
```bash
sudo pacman -S quickshell git jq curl ttf-jetbrains-mono-nerd ttf-material-symbols-variable
```
Optional per widget: `pamixer`, `brightnessctl`, `power-profiles-daemon`, `bluez`, `iwd` + `impala`, `hypridle`, `gpu-screen-recorder`, `voxtype`.

</details>

## Structure
<details>

Each folder under `versions/` is a complete, self-contained bar.

```
versions/V1/
├── shell.qml        # entry point
├── Bar.qml          # layout + dynamic split pills
├── Theme.qml        # colors, state, flags
├── Palette.js       # reads Omarchy colors.toml
├── IconMap.js       # icon name → codepoint
├── assets/          # logo
├── modules/         # bar widgets  (*Widget.qml)
└── panels/          # popups       (*Panel.qml, TooltipOverlay)
```

</details>

## Uninstall
<details>

One command (works for any installed version) — stops the bar, removes theme hook and post-boot hook, and brings back your previous config from the backup:
```bash
curl -fsSL https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/uninstall.sh | bash
```
Every install also backs up the old config to `~/.config/quickshell/bar.bak.<timestamp>` (older backups are kept).

</details>

## Autostart
<details>
<summary>Post-boot hook (opt-in)</summary>

```bash
curl -fsSL -o ~/.config/omarchy/hooks/post-boot.d/quickshell-rise \
  https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/contrib/post-boot.d/quickshell-rise
chmod +x ~/.config/omarchy/hooks/post-boot.d/quickshell-rise
```
Remove: `rm -f ~/.config/omarchy/hooks/post-boot.d/quickshell-rise`
</details>

## V1


https://github.com/user-attachments/assets/e99e49f0-4760-4433-bdb6-e014cac55fe4



##### V1 Features
<details>

| Module | Function |
|---|---|
| Workspaces | switch · overview |
| Weather | current · forecast |
| Clock | time · calendar |
| Mpris | media controls |
| System monitors | CPU · RAM · battery · net · bt |
| Control center | quick toggles · power |
| Split groups | splittable module pills |
| Per-widget panels | click widget → popup |

</details>

##### V1 Install-command (copy & paste in your terminal):
```bash
curl -fsSL https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/install.sh | bash -s V1
```
The bar launches immediately so you can try it.
##### V1 Click bindings
<details>

Default: left-click opens the widget panel. Exceptions:

| Widget | Left | Right | Scroll |
|---|---|---|---|
| Audio | panel | mute toggle | ±volume |
| Brightness | panel | — | ±brightness |
| Clock | toggle 24h / 12h | timezone picker | — |
| Power Profile | panel | cycle profile | — |
| Network / Bluetooth | panel | open system manager | — |
| Weather | panel (Refresh ⁄ °C↔°F) | force refresh | — |
| Voxtype | cycle model | config | — |
| Workspace | click dot: switch | overview | — |
| Mpris | ‹ play › buttons inline | toggle panel | — |
| Tray (bar) | toggle tray panel | — | — |
| Tray icon | activate | hide icon | context menu |

</details>

##### V1 Keybindings — theme / wallpaper picker on the Omarchy hotkeys (optional)
<details>

Omarchy binds its theme/wallpaper menus (shown via walker) to:

| Action | Key | Omarchy default |
|---|---|---|
| Theme | `Super`+`Shift`+`Ctrl`+`Space` | `omarchy-menu theme` |
| Wallpaper | `Super`+`Ctrl`+`Space` | `omarchy-menu background` |

To make those keys open the bar's own pickers instead (and unbind walker for them), add this to **your own** `~/.config/hypr/bindings.conf` — Omarchy sources it *after* its defaults, so it survives `omarchy update`:

```conf
# quickshell-dots: route the theme/wallpaper hotkeys to the bar's pickers
unbind = SUPER SHIFT CTRL, SPACE
unbind = SUPER CTRL, SPACE
bindd  = SUPER SHIFT CTRL, SPACE, Theme picker,     exec, qs -c bar ipc call picker theme
bindd  = SUPER CTRL, SPACE,       Wallpaper picker, exec, qs -c bar ipc call picker wallpaper
```

Then `hyprctl reload`. The `unbind` lines stop walker's menu from *also* firing on those keys; delete the block to restore the Omarchy default. Walker stays your launcher everywhere else — only these two keys change.

> Different Omarchy version? Check `~/.local/share/omarchy/default/hypr/bindings/utilities.conf` for the `omarchy-menu theme` / `omarchy-menu background` lines and match whatever keys are bound there.

(Also available: `qs -c bar ipc call picker screenshots` and `… videos`.)

</details>
<!-- drag a screenshot here on GitHub to embed it -->








