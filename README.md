# Quickshell Rise

A modular [Quickshell](https://quickshell.outfoxxed.me/) bar for **[Omarchy](https://omarchy.org)** (Hyprland).

> **Requires Omarchy.** The bar integrates tightly with the `omarchy-*` helper
> commands (wifi/bluetooth/audio launchers, updates, screen recording, voxtype,
> theme colors). It is not intended for plain Hyprland setups without Omarchy.

## Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/install.sh)
```

Pick a version from the menu, or install one directly:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/install.sh) rise
```

The installer backs up any existing `~/.config/quickshell/bar`, copies the chosen
version there, and adds a Hyprland autostart entry.

## Versions

Each folder under `versions/` is a complete, self-contained bar config.

| Version | Description |
|---------|-------------|
| `rise`  | The full modular bar (workspaces, splits, control center, panels) |

Add a new version by copying an existing one:

```bash
cp -r versions/rise versions/minimal
# edit versions/minimal/... then commit
```

## Dependencies

**Base:** a working **Omarchy** install (provides Hyprland, the `omarchy-*`
helpers, fonts *JetBrainsMono Nerd Font* + *Material Symbols Rounded*, mako, etc.)
plus `quickshell`, `git`, `jq`, `curl`.

**Optional** (per widget, degrade gracefully if absent):
`pamixer`, `brightnessctl`, `power-profiles-daemon`, `bluez`, `iwd` + `impala`,
`hypridle`, `gpu-screen-recorder`, `voxtype`.

## Structure (per version)

```
versions/rise/
├── shell.qml        # entry point
├── Bar.qml          # bar layout + dynamic split pills
├── Theme.qml        # colors, state, split/module flags
├── Palette.js       # reads omarchy theme colors.toml
├── IconMap.js       # Material Symbols name → codepoint
├── assets/          # logo etc.
├── modules/         # bar widgets (*Widget.qml)
└── panels/          # popups / panels (*Panel.qml, *Popup.qml, TooltipOverlay)
```
