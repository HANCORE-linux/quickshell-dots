//@ pragma UseQApplication
import Quickshell
import QtQuick
import "panels"

ShellRoot {
    id: root

    Theme { id: theme }

    Bar { root: theme }
    TooltipOverlay { root: theme }
    CalendarPopup { root: theme }
    ArchUpdaterPanel { root: theme }
    PowerProfilePanel { root: theme }
    MemoryPanel { root: theme }
    CpuPanel { root: theme }
    VolumePanel { root: theme }
    TrayPanel { root: theme }
    NotificationPanel { root: theme }
    NetworkPanel { root: theme }
    BluetoothPanel { root: theme }
    BatteryPanel { root: theme }
    BrightnessPanel { root: theme }
    MprisPanel { root: theme }
    WeatherPanel { root: theme }
    WorkspacePanel { root: theme }
    ControlPanel { root: theme }
    TrayMenu { root: theme }
    OmarchyMenuPanel     { root: theme }
    ThemePickerPanel     { root: theme }
    WallpaperPickerPanel { root: theme }
}
