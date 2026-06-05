<h1 align="center"> Quickshell Rise </h1>

<h4 align="center"> My Quickshell bar for Omarchy — my new Rise journey into Quickshell starts here. Enjoy! </h4>
<div align="center">

[![Stars](https://img.shields.io/github/stars/HANCORE-linux/quickshell-dots?style=for-the-badge&labelColor=000000&color=df6124&logo=github&logoColor=df6124)](https://github.com/HANCORE-linux/quickshell-dots)
[![Forks](https://img.shields.io/github/forks/HANCORE-linux/quickshell-dots?style=for-the-badge&labelColor=000000&color=df6124&logo=github&logoColor=df6124&cacheSeconds=3600)](https://github.com/HANCORE-linux/quickshell-dots/network)
[![Issues](https://img.shields.io/github/issues/HANCORE-linux/quickshell-dots?style=for-the-badge&labelColor=000000&color=df6124&logo=github&logoColor=df6124)](https://github.com/HANCORE-linux/quickshell-dots/issues)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-SUPPORT-000000?style=for-the-badge&labelColor=000000&color=df6124&logo=buymeacoffee&logoColor=df6124)](https://buymeacoffee.com/hancore)

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
sudo pacman -S quickshell git jq curl ttf-jetbrains-mono-nerd
yay -S ttf-material-symbols-variable-git    # AUR (install.sh does this automatically)
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
<img width="2560" height="1440" alt="screenshot-2026-06-04_21-15-54" src="https://github.com/user-attachments/assets/40d89cf8-5930-4499-a4d9-bf69aa883553" />

- workspaces · weather · clock · mpris · system monitors · control center · split-able module groups · per-widget panels
##### V1 Install-command (copy & paste in your terminal):
```bash
curl -fsSL https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/install.sh | bash -s V1
```
The bar launches immediately so you can try it.
<!-- drag a screenshot here on GitHub to embed it -->
