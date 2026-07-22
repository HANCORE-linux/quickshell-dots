<h1 align="center"> Quickshell Rise </h1>

<h4 align="center"> My Quickshell bar for Omarchy — my new Rise journey into Quickshell starts here. Enjoy! </h4>
<div align="center">

[![Stars](https://img.shields.io/github/stars/HANCORE-linux/quickshell-dots?style=for-the-badge&labelColor=000000&color=209edb&logo=github&logoColor=209edb&cacheSeconds=21600)](https://github.com/HANCORE-linux/quickshell-dots)
[![Forks](https://img.shields.io/github/forks/HANCORE-linux/quickshell-dots?style=for-the-badge&labelColor=000000&color=209edb&logo=github&logoColor=209edb&cacheSeconds=21600)](https://github.com/HANCORE-linux/quickshell-dots/network)
[![Issues](https://img.shields.io/github/issues/HANCORE-linux/quickshell-dots?style=for-the-badge&labelColor=000000&color=209edb&logo=github&logoColor=209edb&cacheSeconds=21600)](https://github.com/HANCORE-linux/quickshell-dots/issues)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-SUPPORT-000000?style=for-the-badge&labelColor=000000&color=209edb&logo=buymeacoffee&logoColor=209edb)](https://buymeacoffee.com/hancore)

</div>

<table>
  <tr>
    <td align="center"><b>Theme Picker</b></td>
    <td align="center"><b>Bar Functions &amp; Animations</b></td>
    <td align="center"><b>Unlockbar + Widget Drag/Drop</b></td>
  </tr>
  <tr>
    <td><video src="https://github.com/user-attachments/assets/160ca54f-defb-40de-a0e4-6d2e4139294d" controls="controls" style="max-width: 100%;"></video></td>
    <td><video src="https://github.com/user-attachments/assets/5e91501e-e12c-4125-be10-caa26678098d" controls="controls" style="max-width: 100%;"></video></td>
    <td><video src="https://github.com/user-attachments/assets/1971385a-6d8b-43ee-ab1d-763e2e40dbf7" controls="controls" style="max-width: 100%;"></video></td>
  </tr>
</table>

## Install / Remove

Install and start the bar for the current session with V1 initially active:

```bash
curl -fsSL https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/install.sh | bash -s V1
```

Use `V2` instead to start with the V2 interface. Both UI variants are installed
as one shell and can be switched later without launching a second Quickshell
process.

Install and keep the bar after reboot:

```bash
curl -fsSL https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/install.sh | bash -s V1 --autostart
```

Remove the bar and restore your previous config:

```bash
curl -fsSL https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/uninstall.sh | bash
```

The installer backs up an existing config to `~/.config/quickshell/bar.bak.<timestamp>`.

On an interactive install without an existing Rise login hook, Omarchy Quattro
asks whether to enable Rise at login and hide the stock bar after Rise has been
verified healthy. For scripted installs, choose explicitly with `--autostart` or
`--no-autostart`; without a TTY or either flag, Rise starts for the current
session and leaves the persistent stock-bar state unchanged (normally visible).

### Manual Start / Restart

After installation, the integrated bar lives at `~/.config/quickshell/bar`.
Use its controller for lifecycle operations so duplicate bars are normalized and
unrelated Quickshell applications remain untouched.

Start it manually:

```bash
$HOME/.config/quickshell/bin/qs-barctl start-wait
```

Stop or restart it:

```bash
$HOME/.config/quickshell/bin/qs-barctl stop-wait
$HOME/.config/quickshell/bin/qs-barctl start-wait
```

Switch the UI inside the same process:

```bash
$HOME/.config/quickshell/bin/qs-barctl switch-wait v1
$HOME/.config/quickshell/bin/qs-barctl switch-wait v2
```

Read the named config's current log:

```bash
qs log -c bar
```

Run the checked-out repo directly for development:

```bash
qs -p ~/Projects/Quickshell-Dots/versions/V1/shell.qml
```

## What You Get

| Area | Highlights |
|---|---|
| Bar layout | unlock mode, widget-group drag/drop, persistent order, top/bottom position |
| Visual style | theme-aware colors, border, shadow, frost, split groups, gap animations |
| Pickers | theme, wallpaper, screenshots, videos, with Tanzaku, Hearthstone, and Carousel styles |
| Widgets | workspaces, audio, battery, CPU, memory, network, Bluetooth, weather, MPRIS, tray, notifications |
| Updates | in-bar shell update badge, Arch/AUR counter, known-infected AUR safety check |
| AI usage | Claude + Codex usage pill with switchable provider and detail panel |

<details>
<summary>Full feature list</summary>

| Module | Function |
|---|---|
| Unlock &amp; reorder | unlock the bar, drag widget-groups to swap positions, persistent |
| Image pickers | theme, wallpaper, screenshots, videos, 3 selectable styles, cached thumbnails |
| Self-update | in-bar badge when a new version ships, one-click update and restart |
| Package updates | system + AUR counter with pre-install security check |
| AI usage | combined Claude + Codex token-usage pill |
| Workspaces | switch, overview, 10 / 5 / active-only modes, dots / numbers / magic styles |
| Weather | current conditions, metric / imperial toggle |
| Clock | time, calendar, 24h / 12h toggle |
| MPRIS | media controls |
| Notifications | mako history, unread count, clear |
| System monitors | CPU, RAM, battery health, network, Bluetooth |
| Speed test | manual Cloudflare speed test in the network panel |
| Control center | quick toggles, power, Bar Functions fly-out |
| Bar style | border, shadow, frost, pill radius, top/bottom position |
| Split groups | positional pill splits + Stream, Surge, Bolt, Bolt 2 gap animations |
| Keybind IPC | `qs-barctl ipc picker theme\|wallpaper\|screenshots\|videos` |
| Per-widget panels | click widget to open its popup |

</details>

## Requirements

Built for **Omarchy / Hyprland**. It integrates with `omarchy-*` helpers, Omarchy theme files, Hyprland, mako, and Omarchy's hook system.

Required packages are checked by the installer:

```bash
sudo pacman -S quickshell git jq curl coreutils util-linux procps-ng ttf-jetbrains-mono-nerd ttf-material-symbols-variable
```

<details>
<summary>Optional widget dependencies</summary>

Optional packages enable specific widgets:

```bash
sudo pacman -S wireplumber libpulse pamixer brightnessctl upower power-profiles-daemon bluez-utils iwd impala hypridle gpu-screen-recorder cava
```

Notes:

- `bluez-utils` provides `bluetoothctl`, which the Bluetooth widget currently uses.
- `wireplumber` provides `wpctl`; `libpulse` provides `pactl` for the audio panel.
- `cava` provides the real-time waveform used by the MPRIS FULL bar style and media panel.
- `voxtype` is optional for the Voxtype widget.
- The install script checks required tools and warns about missing optional tools.

</details>

## Compatibility

Rise supports three transition paths without changing its QML layout:

- **Omarchy Quattro:** the Quattro shell keeps running for notifications,
  launcher, OSD, and other services. With Rise autostart enabled, only its stock
  bar surface is hidden after Rise passes a bounded registry health check.
- **Omarchy 3.8.x / Waybar:** the existing Waybar path remains active. Waybar is
  stopped only after Rise is healthy and is restored by the uninstaller.
- **Other Hyprland systems:** Rise still installs and starts normally. Omarchy
  hooks and theme integration are optional; configure login autostart through
  your desktop's normal session mechanism.

<details>
<summary>Omarchy Quattro stock-bar controls</summary>

The command direction follows Omarchy's persistent `bar-off` toggle and is easy
to misread:

```bash
omarchy toggle bar on   # hide the Quattro stock bar
omarchy toggle bar off  # show the Quattro stock bar again
```

The installer owns this state only when it hid a previously visible stock bar.
That ownership is recorded under
`~/.local/state/quickshell-rise/owns-omarchy-bar-off`; uninstall and
`--no-autostart` restore the stock bar only when that marker exists. A stock bar
already hidden by the user or another tool remains user-owned and unchanged.

Recovery never requires a keybind: open a terminal or TTY and run
`omarchy toggle bar off`. A normal `omarchy restart shell` leaves a regular
`qs -c bar` Rise process running. The rare Quickshell crash-relaunch form can run
as a bare `quickshell` process and may be stopped by that Omarchy restart; showing
the stock bar is the recovery path for this documented edge case.

</details>

## Usage

Most interactions follow one rule: click a widget to open its panel.

Common actions:

- Double-click an empty bar area to unlock drag/drop mode.
- Press `Esc` or click the dimmed backdrop to lock again.
- Open the launcher/control widget to change bar style, widgets, workspaces, logo, splits, and animations.
- Use the self-update badge when it appears to update the shell from inside the bar.

<details>
<summary>Click bindings</summary>

| Widget | Left | Middle | Right | Scroll |
|---|---|---|---|---|
| Audio | panel | - | mute toggle | volume |
| Brightness | panel | - | - | brightness |
| Clock | toggle 24h / 12h | - | timezone picker | - |
| Power Profile | panel | - | cycle profile | - |
| Network / Bluetooth | panel | - | open system manager | - |
| Weather | panel | - | force refresh | - |
| Voxtype | cycle model | - | config | - |
| Workspace | switch workspace | - | overview | - |
| MPRIS | inline controls | - | toggle panel | - |
| Tray bar widget | toggle tray panel | - | - | - |
| Tray icon | activate | context menu | hide icon | - |

</details>

<details>
<summary>Theme / wallpaper keybinds</summary>

Omarchy binds theme and wallpaper menus to these keys by default:

| Action | Key | Omarchy default |
|---|---|---|
| Theme | `Super` + `Shift` + `Ctrl` + `Space` | `omarchy-menu theme` |
| Wallpaper | `Super` + `Ctrl` + `Space` | `omarchy-menu background` |

To route those keys to this bar's pickers, add this to `~/.config/hypr/bindings.conf`:

```conf
unbind = SUPER SHIFT CTRL, SPACE
unbind = SUPER CTRL, SPACE
bindd  = SUPER SHIFT CTRL, SPACE, Theme picker,     exec, qs -c bar ipc call picker theme
bindd  = SUPER CTRL, SPACE,       Wallpaper picker, exec, qs -c bar ipc call picker wallpaper
```

Then run:

```bash
hyprctl reload
```

Other picker IPC commands:

```bash
qs -c bar ipc call picker screenshots
qs -c bar ipc call picker videos
```

</details>

<details>
<summary>Manual autostart hook</summary>

If you did not install with `--autostart`, add the Omarchy post-boot hook manually.
On Quattro it starts and verifies Rise before hiding the stock bar:

```bash
mkdir -p ~/.config/omarchy/hooks/post-boot.d
curl -fsSL -o ~/.config/omarchy/hooks/post-boot.d/quickshell-rise \
  https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/contrib/post-boot.d/quickshell-rise
chmod +x ~/.config/omarchy/hooks/post-boot.d/quickshell-rise
```

Remove the hook safely. The conditional block returns only a stock-bar state
owned by Rise; it does not override a bar the user had already hidden:

```bash
marker=~/.local/state/quickshell-rise/owns-omarchy-bar-off
if [[ -f $marker || -f $marker.pending ]]; then
  omarchy toggle bar off && rm -f "$marker" "$marker.pending"
fi
rm -f ~/.config/omarchy/hooks/post-boot.d/quickshell-rise
```

</details>

## Updates

The bar checks for shell updates and shows an update badge when this repo has a newer version.

<details>
<summary>Shell updates and Arch/AUR safety checks</summary>

Click the shell update badge to review changes and apply the update.

Package updates run through the ArchUpdater panel. It checks packages against the known-infected AUR list and blocks known-bad packages from the update command.

</details>

## Repo Structure

<details>
<summary>Project layout</summary>

`versions/V1` is one deployable shell generation. The common bootstrap owns
lifecycle, state and IPC; V1 and V2 retain isolated roots so they can evolve
independently while sharing one process and one exclusive zone.

```text
versions/V1/
├── shell.qml        # stable shared entry point
├── VariantRoot.qml  # isolated V1 root
├── core/            # VariantHost, StateService, IPC router
├── variants/V2/     # complete isolated V2 bundle
├── BarSlot.qml      # V1 slot-based bar
├── Theme.qml        # V1 colors, state, flags
├── Palette.js       # reads Omarchy colors.toml
├── IconMap.js       # icon name to codepoint
├── assets/          # bundled logo assets
├── modules/         # bar widgets
└── panels/          # popups and overlays
```

</details>

## Credits

Parts of this project are adapted from [Omarchy Shell](https://github.com/basecamp/omarchy/tree/omarchy-shell) and modified to integrate with Quickshell Rise. This includes the Carousel picker and selected widget functionality.

The Tanzaku and Hearthstone pickers are original implementations created for this project.

## License

[MIT](LICENSE) © 2026 HANCORE-linux
