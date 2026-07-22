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

For requirements, autostart options, and installation details, read [Getting started](docs/getting-started.md).

## Compare V1 and V2

Both interfaces include theme integration, pickers, updates, notifications, AI usage, media controls, system panels, and draggable widget groups.

| Area | V1 | V2 |
|---|---|---|
| Layout | Original Rise layout with splits and gap animations | Compact redesign with Full, Fit, Dock, and Notch shells |
| Workspaces | Default, Numbers, and Magic | Default, Numbers, Magic, Kanji, Frame, and Aurora |
| Widget styling | Global palette, compact modes, border, frost, and shadow | Global palette plus per-widget fill, border, and contrast controls |
| Now playing | Default controls or FULL waveform view | Default controls or FULL waveform view |
| State | Separate V1 layout and style cache | Separate V2 layout and style cache |

### V2 preview


https://github.com/user-attachments/assets/0e43f091-95d0-4a37-8b65-77a65fd17b74




Click the preview to play the V2 demo.

## Documentation

Each guide covers one task and links back to this page.

| Guide | Contents |
|---|---|
| [Getting started](docs/getting-started.md) | Requirements, installation, removal, and autostart |
| [Usage](docs/usage.md) | Widgets, styles, variants, keybindings, and IPC |
| [Maintenance and recovery](docs/maintenance-and-recovery.md) | Lifecycle, updates, logs, compatibility, and recovery |
| [Development](docs/development.md) | Repository startup, tests, linting, and releases |
| [Architecture](docs/architecture.md) | Variants, controller, state, IPC, and project layout |

## Credits

Parts of this project are adapted from [Omarchy Shell](https://github.com/basecamp/omarchy/tree/omarchy-shell) and modified to integrate with Quickshell Rise. This includes the Carousel picker and selected widget functionality.

The Tanzaku and Hearthstone pickers are original implementations created for this project.

## License

[MIT](LICENSE) © 2026 HANCORE-linux
