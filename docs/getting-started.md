# Install Quickshell Rise

This guide covers requirements, installation, removal, autostart, and the initial V1 or V2 choice. The installer verifies the selected interface before it changes the active stock-bar state.

## Check the requirements

Quickshell Rise targets Omarchy and Hyprland on Arch Linux. The installer checks each required command and stops before changing your configuration when one is missing.

Install the required packages:

```bash
sudo pacman -S \
  quickshell git jq curl pacman-contrib coreutils util-linux procps-ng \
  ttf-jetbrains-mono-nerd ttf-material-symbols-variable
```

Optional packages enable hardware controls and individual widgets:

```bash
sudo pacman -S \
  wireplumber libpulse pamixer brightnessctl upower \
  power-profiles-daemon bluez-utils iwd impala hypridle \
  gpu-screen-recorder cava
```

The optional commands affect these surfaces:

- **Audio**: `wpctl`, `pactl`, and `pamixer`
- **Brightness**: `brightnessctl`
- **Battery and power profiles**: `upower` and `powerprofilesctl`
- **Bluetooth**: `bluetoothctl`
- **Wi-Fi**: `iwctl` and `impala`
- **Idle control**: `hypridle`
- **Screen recording**: `gpu-screen-recorder`
- **Media waveform**: `cava`

Python 3 is required only when you install the optional artificial intelligence (AI) usage backends for Claude, Codex, and OpenCode.

## Install an interface

The V1 and V2 arguments select the interface that opens after installation. Both interfaces are installed inside the same shell generation.

Install V1:

```bash
curl -fsSL https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/install.sh | bash -s V1
```

Install V2:

```bash
curl -fsSL https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/install.sh | bash -s V2
```

The installer writes the shell to `~/.config/quickshell/bar`. A foreign configuration at that path is moved to `~/.config/quickshell/bar.bak.<timestamp>` before installation.

Reinstalling Rise keeps the previously active interface unless you pass `V1` or `V2`. It also preserves a custom `quotes.txt` from the installed Rise directory.

## Choose installation flags

Flags let non-interactive installs choose autostart and the AI usage backend.

| Flag | Result |
|---|---|
| `--autostart` | Install the Omarchy post-boot hook and let Rise manage the stock-bar state |
| `--no-autostart` | Remove the Rise post-boot hook and leave persistent startup disabled |
| `--ai-backend` | Install available Claude, Codex, and OpenCode usage backends |
| `--no-ai-backend` | Skip the optional AI usage backends |

For example, install V2 with autostart and the AI usage backends:

```bash
curl -fsSL https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/install.sh | bash -s V2 --autostart --ai-backend
```

Without an autostart flag, an existing Rise hook is refreshed. On a new
interactive Omarchy Quattro install, the installer asks whether to enable Rise at
login and hide the stock bar. Pressing Enter accepts the default **Yes**. Other new
Omarchy installs print the manual hook commands. A non-interactive install without
either flag starts Rise for the current session and leaves persistent startup
unchanged.

## Understand autostart behavior

On Omarchy Quattro, `--autostart` hides the stock bar only after Rise reports the requested variant and `ready=true`. Rise records ownership of that hidden state so the uninstaller can restore it without overriding a choice made by another tool.

On Omarchy installations without Quattro, Rise starts after login through the same post-boot hook. Other Hyprland environments need their own session startup entry because they do not expose the Omarchy hook system.

## Install the post-boot hook manually

Install the published Omarchy hook when Rise is already installed without `--autostart`:

```bash
mkdir -p "$HOME/.config/omarchy/hooks/post-boot.d"
curl -fsSL \
  -o "$HOME/.config/omarchy/hooks/post-boot.d/quickshell-rise" \
  https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/contrib/post-boot.d/quickshell-rise
chmod +x "$HOME/.config/omarchy/hooks/post-boot.d/quickshell-rise"
```

The hook starts Rise, waits for lifecycle readiness, and then hides an owned Quattro stock bar. It leaves the stock bar visible when Rise does not become healthy.

## Remove Quickshell Rise

The uninstaller stops the registered Rise instance, removes installed helpers and hooks, and restores the previous configuration when a backup exists.

Run the published uninstaller:

```bash
curl -fsSL https://raw.githubusercontent.com/HANCORE-linux/quickshell-dots/main/uninstall.sh | bash
```

The uninstaller restores the Quattro stock bar only when Rise owns that state. A stock bar hidden before Rise was installed remains unchanged.

## Continue with Rise

Read [Use Quickshell Rise](usage.md) for interface controls, widgets, styles, keybindings, and inter-process communication (IPC). Use [Maintain and recover Quickshell Rise](maintenance-and-recovery.md) for lifecycle commands, updates, logs, and recovery.

[Back to the project README](../README.md)
