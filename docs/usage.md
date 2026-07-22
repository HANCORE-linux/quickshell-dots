# Use Quickshell Rise

This guide explains daily interaction, V1 and V2 switching, widget controls, visual styles, keybindings, and inter-process communication (IPC). Interface settings remain separate, so changing V2 does not overwrite the V1 layout.

## Use the bar

Most widgets open a related panel with a left click. Panels close when you click the backdrop or press `Esc`.

Use these shared bar actions:

- Double-click an empty bar area to unlock widget-group drag and drop
- Drag groups to change their order while the bar is unlocked
- Press `Esc` or click the backdrop to lock the layout
- Open the launcher widget to reach the Control Panel
- Select **Default layout** to restore the variant’s shipped layout and colors

The most common widget bindings are:

| Widget | Left click | Right click | Scroll |
|---|---|---|---|
| Audio | Open volume panel | Toggle mute | Change volume |
| Brightness | Open brightness panel | None | Change brightness |
| Clock | Toggle 24-hour or 12-hour time | Open timezone picker | None |
| Power profile | Open profile panel | Cycle profile | None |
| Network or Bluetooth | Open panel | Open system manager | None |
| Weather | Open weather panel | Refresh | None |
| Workspace | Switch workspace | Open workspace panel | None |
| MPRIS | Use inline controls | Open media panel | Mode-dependent |
| Tray widget | Open hidden-app panel | None | None |
| Tray icon | Activate application | Hide icon | None |

The Media Player Remote Interfacing Specification (MPRIS) widget has two bar presentations. **Default** shows transport controls, track text, and equalizer motion. **FULL** shows a vinyl mark, real-time CAVA waveform, and transport state. In FULL mode, click the surface to play or pause, scroll up for the next track, and scroll down for the previous track.

## Switch between V1 and V2

The Control Panel includes V1 and V2 actions. The active interface cannot be selected again while it is running.

You can also switch through the lifecycle controller:

```bash
$HOME/.config/quickshell/bin/qs-barctl switch-wait v1
$HOME/.config/quickshell/bin/qs-barctl switch-wait v2
```

The shared host closes variant panels, destroys the old interface, loads the target, and waits for `ready=true`. It stores the new choice only after the target remains ready.

## Choose workspace and bar styles

Workspace count and visual style are independent settings. Both variants support 10, 5, and active-only workspace modes.

| Interface | Workspace styles |
|---|---|
| V1 | Default, Numbers, Magic |
| V2 | Default, Numbers, Magic, Kanji, Frame, Aurora |

V1 retains the original split-group layout, selectable gap animations, border, frost, shadow, and compact widget modes.

V2 adds four outer-shell layouts:

- **Full**: span the output width
- **Fit**: shrink to the active content width
- **Dock**: attach a content-width surface to the screen edge
- **Notch**: attach the compact surface with continuous side transitions

V2 can place every shell at the top or bottom edge. The Bar Border and Panel & Tooltip Border controls are independent.

## Apply colors and widget styles

Both variants expose `color01` through `color07` and Foreground from the active Omarchy `colors.toml`. The selected bar color has an underline in the Control Panel.

V2 also exposes a palette button for each configurable widget group. Use it to:

- Apply a palette color or return to inherited color
- Enable a widget border without enabling fill
- Select automatic, foreground, or background contrast for a filled widget

Status-driven icons keep their semantic state colors where required. Other icons use the assigned widget color or Foreground according to the selected rule.

## Configure widgets and panels

The Control Panel can show or hide optional groups and select compact modes where the widget supports them. Hardware-dependent controls remain disabled when the required device is absent.

V2 includes detailed panels for:

- CPU model, policy, kernel, usage, and top processes
- Memory usage, type, and reported clock speed
- GPU model, driver, load, clock, temperature, power, and video memory
- Storage device type, mount point, usage, and free space
- Selectable temperature sources for the bar widget
- Wi-Fi, Ethernet, transmit and receive activity, and Cloudflare speed tests

The storage panel reports devices but does not mount or unmount filesystems.

The AI usage widget supports Claude, Codex, and OpenCode. Availability depends on the optional backends selected during installation and the corresponding local account or database.

## Open pickers through IPC

IPC lets Hyprland keybindings call the active variant without guessing its Quickshell instance. Always route picker calls through `qs-barctl`.

Run picker commands from a terminal:

```bash
barctl="$HOME/.config/quickshell/bin/qs-barctl"
"$barctl" ipc picker theme
"$barctl" ipc picker wallpaper
"$barctl" ipc picker screenshots
"$barctl" ipc picker videos
```

The controller forwards arbitrary targets, functions, and string arguments to the single registered Rise instance. It rejects calls when no instance or more than one matching instance exists.

## Route Omarchy keybindings to Rise

Omarchy normally binds its theme and wallpaper menus to `Super` combinations. Add these bindings to `~/.config/hypr/bindings.conf` to open the Rise pickers instead:

```conf
unbind = SUPER SHIFT CTRL, SPACE
unbind = SUPER CTRL, SPACE
bindd = SUPER SHIFT CTRL, SPACE, Theme picker, exec, ~/.config/quickshell/bin/qs-barctl ipc picker theme
bindd = SUPER CTRL, SPACE, Wallpaper picker, exec, ~/.config/quickshell/bin/qs-barctl ipc picker wallpaper
```

Reload Hyprland after editing the bindings:

```bash
hyprctl reload
```

Read [Maintain and recover Quickshell Rise](maintenance-and-recovery.md) for status, restart, update, log, and recovery commands.

[Back to the project README](../README.md)
