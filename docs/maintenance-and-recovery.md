# Maintain and recover Quickshell Rise

This guide covers lifecycle commands, updates, logs, compatibility, duplicate-instance recovery, and stock-bar recovery. The controller targets the exact installed Rise path and leaves unrelated Quickshell applications running.

## Check the installed bar

Use the lifecycle controller installed with Rise:

```bash
$HOME/.config/quickshell/bin/qs-barctl status
```

The status result describes the registered shell:

| Result | Meaning |
|---|---|
| `v1` or `v2` | One ready Rise instance is running with that interface |
| `stopped` | No installed Rise instance is registered |
| `duplicate:<count>` | More than one installed Rise instance is registered |
| `degraded:<variant>` | One instance exists but does not report a stable active state |
| `switching:<state>` | The shared host is changing interfaces |

Non-healthy states return a nonzero exit code so scripts can stop instead of assuming success.

## Start, stop, or restart Rise

Start Rise and wait until one instance reports `ready=true`:

```bash
$HOME/.config/quickshell/bin/qs-barctl start-wait
```

Stop every registered instance for the installed Rise path:

```bash
$HOME/.config/quickshell/bin/qs-barctl stop-wait
```

Restart Rise with two bounded operations:

```bash
$HOME/.config/quickshell/bin/qs-barctl stop-wait
$HOME/.config/quickshell/bin/qs-barctl start-wait
```

The non-waiting `start` and `stop` forms dispatch the same work in the background. Use the `-wait` commands when another command depends on the result.

## Apply shell and package updates

Rise checks the repository and displays a shell update badge when `main` contains a newer generation. Open the update panel to review the change before applying it.

A shell update stages and validates these files before it stops the current bar:

- Integrated V1 and V2 payload
- Lifecycle controller and compatibility wrapper
- Update helpers
- Omarchy hooks
- Related systemd user files

The updater swaps the installed generation on the same filesystem and restarts the selected interface. If the new generation fails to start, it restores the previous payload and companion files. The active V1 or V2 choice lives outside the deployed directory and remains unchanged.

Existing V1-only installations can migrate through the published updater. When no previous variant state exists, the integrated generation starts with V1.

Package updates run through the ArchUpdater panel, with two explicit execution models:

- On plain Arch, the security gate checks every displayed repository package against the known-infected Arch User Repository (AUR) list. The apply helper then re-scans and re-runs the gate after authentication before it can execute the complete `pacman -Syu` transaction.
- On Omarchy, the package results are advisory. The update button opens Omarchy's official updater, which owns its broader system, migration, AUR, and tooling transaction. The Quickshell gate neither filters nor claims to authorize that upstream transaction.

## Read Quickshell logs

Select the installed configuration by its exact path:

```bash
qs log -p "$HOME/.config/quickshell/bar/shell.qml" --tail 100 --no-color
```

List every Quickshell instance when you need its process ID, instance ID, configuration path, or display connection:

```bash
qs list --all
```

Do not identify Rise by process name alone. Other desktop components can run in separate `qs` or `quickshell` processes.

## Recover a stopped or degraded bar

Run `start-wait` first. The controller keeps one ready instance, removes duplicate Rise instances, and replaces a registered instance that never reaches readiness.

```bash
$HOME/.config/quickshell/bin/qs-barctl start-wait
$HOME/.config/quickshell/bin/qs-barctl status
```

If the controller reports that the integrated configuration is missing, reinstall Rise from [Install Quickshell Rise](getting-started.md). The installer validates the new payload before it replaces an installed generation.

## Recover the Omarchy Quattro stock bar

Omarchy’s persistent `bar-off` toggle uses a counterintuitive direction. Run this command from a terminal or text console to show the Quattro stock bar:

```bash
omarchy toggle bar off
```

Run this command to hide the Quattro stock bar again:

```bash
omarchy toggle bar on
```

Rise records an ownership marker at `~/.local/state/quickshell-rise/owns-omarchy-bar-off` only when it hides a previously visible stock bar. The uninstaller and `--no-autostart` restore the stock bar only when that marker exists.

## Check compositor compatibility

Rise handles three supported environments differently:

- **Omarchy Quattro**: Quattro continues to provide notifications, launcher, on-screen display, and other services. Rise hides only the stock bar after its own lifecycle check succeeds
- **Omarchy 3.8.x with Waybar**: the installer stops Waybar only after Rise becomes ready. The uninstaller restores the previous path
- **Other Hyprland systems**: Rise can start without Omarchy hooks, but you must configure login startup through the desktop session

If a theme hook is unavailable, the bar still runs. Automatic Omarchy theme and launcher integration will not run until the matching hook system exists.

Read [Develop Quickshell Rise](development.md) before starting the repository copy beside an installed bar.

[Back to the project README](../README.md)
