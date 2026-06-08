import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

PanelWindow {
    id: menuPanel
    required property var root

    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "omarchy-menu-panel"
    WlrLayershell.keyboardFocus: root.omarchyMenuVisible
                                 ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    readonly property int barBottom: 35
    readonly property int gap: 8

    property real reveal: root.omarchyMenuVisible ? 1 : 0
    Behavior on reveal {
        NumberAnimation {
            duration: root.omarchyMenuVisible ? 180 : 130
            easing.type: root.omarchyMenuVisible ? Easing.OutCubic : Easing.InCubic
        }
    }
    visible: reveal > 0.001

    // ── mode flags ──
    readonly property bool appMode: currentMenu === "apps"

    // ── navigation stack ──
    property var    navStack: []
    property string query:    ""
    readonly property string currentMenu: navStack.length > 0 ? navStack[navStack.length - 1] : ""

    property int selectedMenuIndex: 0   // menu mode keyboard selection
    property int selectedIndex:     0   // app mode keyboard selection

    function _resetScroll() { selectedMenuIndex = 0; selectedIndex = 0; listArea.scrollOffset = 0 }

    function navigate(key) {
        navStack = navStack.concat([key])
        query = ""; searchInput.text = ""; settingsMode = false; _resetScroll()
    }
    function goBack() {
        if (navStack.length > 1) navStack = navStack.slice(0, navStack.length - 1)
        else                     navStack = []
        query = ""; searchInput.text = ""; settingsMode = false; _resetScroll()
    }
    function hasSubmenu(key) { return key === "apps" || submenus.hasOwnProperty(key) }

    function closePanel() {
        root.omarchyMenuVisible = false
        query = ""; navStack = []; searchInput.text = ""; settingsMode = false; _resetScroll()
    }
    function launchLeaf(key) {
        root.omarchyMenuVisible = false; root.controlVisible = false
        query = ""; navStack = []; searchInput.text = ""; settingsMode = false; _resetScroll()
        Qt.callLater(function() { Quickshell.execDetached(["omarchy-menu", key]) })
    }
    function launchApp(app) {
        if (!app) return
        root.omarchyMenuVisible = false; root.controlVisible = false
        query = ""; navStack = []; searchInput.text = ""; settingsMode = false; _resetScroll()
        launchProc.command = ["bash", "-c", "nohup " + app.exec + " &>/dev/null &"]
        launchProc.running = true
    }
    Process { id: launchProc; command: [] }

    // ── app data + favorites ──
    property var  allApps:      []
    property var  filteredApps: []
    property var  favorites:    []
    property var  hiddenApps:   []
    property bool settingsMode: false

    readonly property string favFile: Quickshell.env("HOME") + "/.cache/quickshell-launcher-favorites"
    readonly property string hidFile: Quickshell.env("HOME") + "/.cache/quickshell-launcher-hidden"

    Process {
        id: appLoader
        command: ["python3", Quickshell.env("HOME") + "/.config/quickshell/bar/load-apps.py"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = this.text.trim().split("\n"); var apps = []
                for (var i = 0; i < lines.length; i++) {
                    var parts = lines[i].split("||")
                    if (parts.length >= 3 && parts[0].trim())
                        apps.push({ name: parts[0], icon: parts[1], exec: parts[2] })
                }
                menuPanel.allApps = apps; menuPanel.filterApps()
            }
        }
    }
    Process {
        id: favLoader
        command: ["sh", "-c", "cat '" + menuPanel.favFile + "' 2>/dev/null || true"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                menuPanel.favorites = this.text.trim().split("\n").filter(function(x){ return x.trim() !== "" })
                menuPanel.filterApps()
            }
        }
    }
    Process {
        id: hidLoader
        command: ["sh", "-c", "cat '" + menuPanel.hidFile + "' 2>/dev/null || true"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                menuPanel.hiddenApps = this.text.trim().split("\n").filter(function(x){ return x.trim() !== "" })
                menuPanel.filterApps()
            }
        }
    }
    Process { id: saveFavProc; command: [] }
    Process { id: saveHidProc; command: [] }

    Component.onCompleted: { favLoader.running = true; hidLoader.running = true; appLoader.running = true }

    function filterApps() {
        var q = query.toLowerCase().trim()
        var all = q ? allApps.filter(function(a){ return a.name.toLowerCase().indexOf(q) >= 0 })
                    : allApps.slice()
        if (settingsMode) {
            filteredApps = all
        } else {
            var vis = all.filter(function(a){ return hiddenApps.indexOf(a.name) < 0 })
            var favs = vis.filter(function(a){ return favorites.indexOf(a.name) >= 0 })
            var rest = vis.filter(function(a){ return favorites.indexOf(a.name) < 0 })
            filteredApps = favs.concat(rest)
        }
        selectedIndex = 0
    }

    function toggleFavorite(appName) {
        var idx = favorites.indexOf(appName); var nf = favorites.slice()
        if (idx >= 0) nf.splice(idx, 1); else nf.push(appName)
        favorites = nf; saveFavorites(); filterApps()
    }
    function toggleHidden(appName) {
        var idx = hiddenApps.indexOf(appName); var nh = hiddenApps.slice()
        if (idx >= 0) nh.splice(idx, 1); else nh.push(appName)
        hiddenApps = nh; saveHidden(); filterApps()
    }
    function saveFavorites() {
        var args = ["python3", "-c",
            "import sys; f=open(sys.argv[1],'w'); f.write('\\n'.join(sys.argv[2:])); f.close()",
            favFile]
        for (var i = 0; i < favorites.length; i++) args.push(favorites[i])
        saveFavProc.command = args; saveFavProc.running = true
    }
    function saveHidden() {
        var args = ["python3", "-c",
            "import sys; f=open(sys.argv[1],'w'); f.write('\\n'.join(sys.argv[2:])); f.close()",
            hidFile]
        for (var i = 0; i < hiddenApps.length; i++) args.push(hiddenApps[i])
        saveHidProc.command = args; saveHidProc.running = true
    }

    // ── display items (menu mode) ──
    readonly property var displayItems: {
        var stack = navStack
        var menu  = stack.length > 0 ? stack[stack.length - 1] : ""
        if (appMode) return []   // apps handled separately
        if (query !== "") return filteredMenuItems
        if (menu !== "" && submenus[menu]) return submenus[menu]
        return allItems
    }

    readonly property var filteredMenuItems: {
        var q = query.toLowerCase().trim()
        if (q === "") return allItems
        return allItems.filter(function(it) {
            return it.label.toLowerCase().split(/\s+/).some(function(w) { return w.indexOf(q) === 0 })
        })
    }

    // ── title ──
    readonly property string menuTitle: {
        if (navStack.length === 0) return "Menu"
        if (appMode) return "Apps"
        var k = navStack[navStack.length - 1]
        for (var i = 0; i < allItems.length; i++) {
            if (allItems[i].key === k) return allItems[i].label
        }
        if (navStack.length >= 2) {
            var par = navStack[navStack.length - 2]
            if (submenus[par]) {
                var arr = submenus[par]
                for (var j = 0; j < arr.length; j++) {
                    if (arr[j].key === k) return arr[j].label
                }
            }
        }
        return k
    }

    // auto-focus on open
    onRevealChanged: if (reveal > 0.5) focusTimer.restart()
    onAppModeChanged: if (appMode) { filterApps(); focusTimer.restart() }
    Timer { id: focusTimer; interval: 30; onTriggered: searchInput.forceActiveFocus() }

    function cp(n) { return String.fromCodePoint(n) }

    // ── root items ──
    readonly property var allItems: [
        { icon: cp(0xF003B), label: "Apps",     key: "apps"    },
        { icon: cp(0xF09D1), label: "Learn",    key: "learn"   },
        { icon: cp(0xF14DE), label: "Trigger",  key: "trigger" },
        { icon: cp(0xEBCF),  label: "Style",    key: "style"   },
        { icon: cp(0xE615),  label: "Setup",    key: "setup"   },
        { icon: cp(0xF0249), label: "Install",  key: "install" },
        { icon: cp(0xF0B4C), label: "Remove",   key: "remove"  },
        { icon: cp(0xF021),  label: "Update",   key: "update"  },
        { icon: cp(0xEA74),  label: "About",    key: "about"   },
        { icon: cp(0xF011),  label: "System",   key: "system"  },
    ]

    // ── submenus ──
    readonly property var submenus: ({
        "style": [
            { icon: cp(0xF0E0C), label: "Theme",       key: "style-theme"       },
            { icon: cp(0xF07F5), label: "Unlock",      key: "style-unlock"      },
            { icon: cp(0xE659),  label: "Font",        key: "style-font"        },
            { icon: cp(0xF03E),  label: "Wallpaper",   key: "background"        },
            { icon: cp(0xF035C), label: "Waybar",      key: "style-waybar"      },
            { icon: cp(0xF0607), label: "Corners",     key: "style-corners"     },
            { icon: cp(0xF359),  label: "Hyprland",    key: "style-hyprland"    },
            { icon: cp(0xF1104), label: "Screensaver", key: "style-screensaver" },
            { icon: cp(0xEA74),  label: "About",       key: "style-about"       },
        ],
        "learn": [
            { icon: cp(0xF11C),  label: "Keybindings", key: "learn-keybindings" },
            { icon: cp(0xF489),  label: "Tmux keys",   key: "learn-tmux"        },
            { icon: cp(0xF405),  label: "Omarchy",     key: "learn-omarchy"     },
            { icon: cp(0xF359),  label: "Hyprland",    key: "learn-hyprland"    },
            { icon: cp(0xF08C7), label: "Arch",        key: "learn-arch"        },
            { icon: cp(0xE6AE),  label: "Neovim",      key: "learn-neovim"      },
            { icon: cp(0xF1183), label: "Bash",        key: "learn-bash"        },
        ],
        "trigger": [
            { icon: cp(0xF051B), label: "Reminder",   key: "reminder"           },
            { icon: cp(0xF030),  label: "Capture",    key: "capture"            },
            { icon: cp(0xF09F8), label: "Transcode",  key: "trigger-transcode"  },
            { icon: cp(0xF50E),  label: "Share",      key: "share"              },
            { icon: cp(0xF050E), label: "Toggle",     key: "toggle"             },
            { icon: cp(0xEF70),  label: "Hardware",   key: "hardware"           },
        ],
        "reminder": [
            { icon: cp(0xF051B), label: "Create",    key: "reminder-create" },
            { icon: cp(0xF051B), label: "Show all",  key: "reminder-show"   },
            { icon: cp(0xF051B), label: "Clear all", key: "reminder-clear"  },
        ],
        "capture": [
            { icon: cp(0xF030),  label: "Screenshot",         key: "capture-screenshot"   },
            { icon: cp(0xF03D),  label: "Screen recording",   key: "capture-screenrecord" },
            { icon: cp(0xF0D11), label: "Extract text (OCR)", key: "capture-ocr"          },
            { icon: cp(0xF00C9), label: "Color picker",       key: "capture-color"        },
        ],
        "capture-screenrecord": [
            { icon: cp(0xF03D),  label: "Stop recording",             key: "screenrecord-stop"     },
            { icon: cp(0xF03D),  label: "No audio",                   key: "screenrecord-noaudio"  },
            { icon: cp(0xE638),  label: "System audio",               key: "screenrecord-audio"    },
            { icon: cp(0xF036E), label: "System audio + microphone",  key: "screenrecord-micaudio" },
        ],
        "share": [
            { icon: cp(0xF0786), label: "Clipboard", key: "share-clipboard" },
            { icon: cp(0xF0214), label: "File",      key: "share-file"      },
            { icon: cp(0xF024B), label: "Folder",    key: "share-folder"    },
            { icon: cp(0xF0966), label: "Receive",   key: "share-receive"   },
        ],
        "toggle": [
            { icon: cp(0xF1104), label: "Screensaver",       key: "toggle-screensaver"   },
            { icon: cp(0xF050E), label: "Night light",       key: "toggle-nightlight"    },
            { icon: cp(0xF16D6), label: "Idle lock",         key: "toggle-idle"          },
            { icon: cp(0xF009B), label: "Notifications",     key: "toggle-notifications" },
            { icon: cp(0xF035C), label: "Top bar",           key: "toggle-bar"           },
            { icon: cp(0xF102C), label: "Workspace layout",  key: "toggle-layout"        },
            { icon: cp(0xF0B3E), label: "Window gaps",       key: "toggle-gaps"          },
            { icon: cp(0xF09AA), label: "Window ratio",      key: "toggle-ratio"         },
            { icon: cp(0xF0379), label: "Monitor scaling",   key: "toggle-scaling"       },
            { icon: cp(0xF072E), label: "Direct boot",       key: "toggle-directboot"    },
            { icon: cp(0xF07F5), label: "Passwordless sudo", key: "toggle-sudo"          },
        ],
        "hardware": [
            { icon: cp(0xF0663), label: "Laptop screen",  key: "hardware-screen"      },
            { icon: cp(0xF0379), label: "Mirror screen",  key: "hardware-mirror"      },
            { icon: cp(0xF01C5), label: "Hybrid GPU",     key: "hardware-gpu"         },
            { icon: cp(0xF07F8), label: "Touchpad",       key: "hardware-touchpad"    },
            { icon: cp(0xF01BD), label: "Touchscreen",    key: "hardware-touchscreen" },
        ],
        "setup": [
            { icon: cp(0xE638),  label: "Audio",          key: "setup-audio"       },
            { icon: cp(0xF1EB),  label: "WiFi",           key: "setup-wifi"        },
            { icon: cp(0xF00AF), label: "Bluetooth",      key: "setup-bt"          },
            { icon: cp(0xF14DB), label: "Power profile",  key: "power"             },
            { icon: cp(0xEBA2),  label: "Suspend config", key: "setup-suspend"     },
            { icon: cp(0xF0379), label: "Monitors",       key: "setup-monitors"    },
            { icon: cp(0xF11C),  label: "Keybindings",    key: "setup-keybindings" },
            { icon: cp(0xF488),  label: "Input",          key: "setup-input"       },
            { icon: cp(0xF488),  label: "Defaults",       key: "setup-defaults"    },
            { icon: cp(0xF059B), label: "DNS",            key: "setup-dns"         },
            { icon: cp(0xEB11),  label: "Security",       key: "setup-security"    },
            { icon: cp(0xE615),  label: "Config files",   key: "setup-configfiles" },
        ],
        "setup-security": [
            { icon: cp(0xF0237), label: "Fingerprint", key: "setup-sec-fingerprint" },
            { icon: cp(0xEB11),  label: "Fido2",       key: "setup-sec-fido2"       },
        ],
        "setup-configfiles": [
            { icon: cp(0xF359),  label: "Hyprland",   key: "setup-arch-hyprland"   },
            { icon: cp(0xEBA2),  label: "Hypridle",   key: "setup-arch-hypridle"   },
            { icon: cp(0xF023),  label: "Hyprlock",   key: "setup-arch-hyprlock"   },
            { icon: cp(0xF5A7),  label: "Hyprsunset", key: "setup-arch-hyprsunset" },
            { icon: cp(0xF028),  label: "Swayosd",    key: "setup-arch-swayosd"    },
            { icon: cp(0xF002),  label: "Walker",     key: "setup-arch-walker"     },
            { icon: cp(0xF035C), label: "Waybar",     key: "setup-arch-waybar"     },
            { icon: cp(0xF0785), label: "XCompose",   key: "setup-arch-xcompose"   },
        ],
        "install": [
            { icon: cp(0xF08C7), label: "Package",     key: "install-package"  },
            { icon: cp(0xF08C7), label: "AUR",         key: "install-aur"      },
            { icon: cp(0xF268),  label: "Web App",     key: "install-webapp"   },
            { icon: cp(0xF489),  label: "TUI",         key: "install-tui"      },
            { icon: cp(0xF487),  label: "Service",     key: "install-service"  },
            { icon: cp(0xEBCF),  label: "Style",       key: "install-style"    },
            { icon: cp(0xF0D6E), label: "Development", key: "install-dev"      },
            { icon: cp(0xF15C),  label: "Editor",      key: "install-editor"   },
            { icon: cp(0xF489),  label: "Terminal",    key: "install-terminal" },
            { icon: cp(0xF268),  label: "Browser",     key: "install-browser"  },
            { icon: cp(0xF16A4), label: "AI",          key: "install-ai"       },
            { icon: cp(0xF11B),  label: "Gaming",      key: "install-gaming"   },
            { icon: cp(0xF0372), label: "Windows VM",  key: "install-windows"  },
        ],
        "install-service": [
            { icon: cp(0xE707),  label: "Dropbox",          key: "install-serv-dropbox"  },
            { icon: cp(0xF487),  label: "Tailscale",        key: "install-serv-tailscale"},
            { icon: cp(0xF11F1), label: "NordVPN [AUR]",   key: "install-serv-nordvpn"  },
            { icon: cp(0xF03D6), label: "ONCE",             key: "install-serv-once"     },
            { icon: cp(0x2600),  label: "Sunshine",         key: "install-serv-sunshine" },
            { icon: cp(0xF07F5), label: "Bitwarden",        key: "install-serv-bitwarden"},
            { icon: cp(0xE7F0),  label: "Chromium Account", key: "install-serv-chromium" },
        ],
        "install-style": [
            { icon: cp(0xF0E0C), label: "Theme",     key: "install-style-theme"    },
            { icon: cp(0xF03E),  label: "Wallpaper", key: "install-style-wallpaper"},
            { icon: cp(0xE659),  label: "Font",      key: "install-style-font"     },
        ],
        "install-dev": [
            { icon: cp(0xF0ACF), label: "Ruby on Rails", key: "install-dev-rails"  },
            { icon: cp(0xF21F),  label: "Docker DB",     key: "install-dev-docker" },
            { icon: cp(0xE781),  label: "JavaScript",    key: "install-dev-js"     },
            { icon: cp(0xE627),  label: "Go",            key: "install-dev-go"     },
            { icon: cp(0xE73D),  label: "PHP",           key: "install-dev-php"    },
            { icon: cp(0xE73C),  label: "Python",        key: "install-dev-python" },
            { icon: cp(0xE62D),  label: "Elixir",        key: "install-dev-elixir" },
            { icon: cp(0xE8EF),  label: "Zig",           key: "install-dev-zig"    },
            { icon: cp(0xE7A8),  label: "Rust",          key: "install-dev-rust"   },
            { icon: cp(0xE738),  label: "Java",          key: "install-dev-java"   },
            { icon: cp(0xE77F),  label: ".NET",          key: "install-dev-dotnet" },
            { icon: cp(0xE84E),  label: "OCaml",         key: "install-dev-ocaml"  },
            { icon: cp(0xE768),  label: "Clojure",       key: "install-dev-clojure"},
            { icon: cp(0xE737),  label: "Scala",         key: "install-dev-scala"  },
        ],
        "install-editor": [
            { icon: cp(0xE8DA), label: "VSCode",       key: "install-editor-vscode"  },
            { icon: cp(0xF15C), label: "Cursor",       key: "install-editor-cursor"  },
            { icon: cp(0xF15C), label: "Zed",          key: "install-editor-zed"     },
            { icon: cp(0xF15C), label: "Sublime Text", key: "install-editor-sublime" },
            { icon: cp(0xF15C), label: "Helix",        key: "install-editor-helix"   },
            { icon: cp(0xE62B), label: "Vim",          key: "install-editor-vim"     },
            { icon: cp(0xF15C), label: "Emacs",        key: "install-editor-emacs"   },
        ],
        "install-terminal": [
            { icon: cp(0xF489), label: "Alacritty", key: "install-term-alacritty"},
            { icon: cp(0xF489), label: "Foot",      key: "install-term-foot"     },
            { icon: cp(0xF489), label: "Ghostty",   key: "install-term-ghostty"  },
            { icon: cp(0xF489), label: "Kitty",     key: "install-term-kitty"    },
        ],
        "install-browser": [
            { icon: cp(0xF268),  label: "Chrome",       key: "install-browser-chrome"       },
            { icon: cp(0xF268),  label: "Edge",         key: "install-browser-edge"         },
            { icon: cp(0xF268),  label: "Brave",        key: "install-browser-brave"        },
            { icon: cp(0xF268),  label: "Brave Origin", key: "install-browser-brave-origin" },
            { icon: cp(0xF269),  label: "Firefox",      key: "install-browser-firefox"      },
            { icon: cp(0xF059F), label: "Zen",          key: "install-browser-zen"          },
        ],
        "install-ai": [
            { icon: cp(0xEC12),  label: "Voice Typing", key: "install-ai-voicetyping"},
            { icon: cp(0xF16A4), label: "LM Studio",    key: "install-ai-lmstudio"   },
            { icon: cp(0xF16A4), label: "Ollama",       key: "install-ai-ollama"     },
            { icon: cp(0xF16A4), label: "Crush",        key: "install-ai-crush"      },
        ],
        "install-gaming": [
            { icon: cp(0xF1B6),  label: "Steam",           key: "install-gaming-steam"    },
            { icon: cp(0xF0BC9), label: "RetroArch",       key: "install-gaming-retroarch"},
            { icon: cp(0xF0373), label: "Minecraft",       key: "install-gaming-minecraft"},
            { icon: cp(0xF08B9), label: "NVIDIA GeForce",  key: "install-gaming-geforce"  },
            { icon: cp(0xED3E),  label: "Xbox Cloud",      key: "install-gaming-xboxcloud"},
            { icon: cp(0xF00AF), label: "Xbox Controller", key: "install-gaming-xboxpad"  },
            { icon: cp(0xF0379), label: "Moonlight",       key: "install-gaming-moonlight"},
            { icon: cp(0xF268),  label: "Lutris",          key: "install-gaming-lutris"   },
            { icon: cp(0xF14DF), label: "Heroic",          key: "install-gaming-heroic"   },
        ],
        "remove": [
            { icon: cp(0xF08C7), label: "Package",      key: "remove-package"    },
            { icon: cp(0xF268),  label: "Web App",      key: "remove-webapp"     },
            { icon: cp(0xF489),  label: "TUI",          key: "remove-tui"        },
            { icon: cp(0xF0D6E), label: "Development",  key: "remove-dev"        },
            { icon: cp(0xF0E0C), label: "Theme",        key: "remove-theme"      },
            { icon: cp(0xF268),  label: "Browser",      key: "remove-browser"    },
            { icon: cp(0xEC12),  label: "Voice Typing", key: "remove-voicetyping"},
            { icon: cp(0xF11B),  label: "Gaming",       key: "remove-gaming"     },
            { icon: cp(0xF0372), label: "Windows VM",   key: "remove-windows"    },
            { icon: cp(0xF03D3), label: "Pre-installs", key: "remove-preinstalls"},
            { icon: cp(0xEB11),  label: "Security",     key: "remove-security"   },
        ],
        "remove-dev": [
            { icon: cp(0xF0ACF), label: "Ruby on Rails", key: "remove-dev-rails"  },
            { icon: cp(0xE781),  label: "JavaScript",    key: "remove-dev-js"     },
            { icon: cp(0xE627),  label: "Go",            key: "remove-dev-go"     },
            { icon: cp(0xE73D),  label: "PHP",           key: "remove-dev-php"    },
            { icon: cp(0xE73C),  label: "Python",        key: "remove-dev-python" },
            { icon: cp(0xE62D),  label: "Elixir",        key: "remove-dev-elixir" },
            { icon: cp(0xE8EF),  label: "Zig",           key: "remove-dev-zig"    },
            { icon: cp(0xE7A8),  label: "Rust",          key: "remove-dev-rust"   },
            { icon: cp(0xE738),  label: "Java",          key: "remove-dev-java"   },
            { icon: cp(0xE77F),  label: ".NET",          key: "remove-dev-dotnet" },
            { icon: cp(0xE84E),  label: "OCaml",         key: "remove-dev-ocaml"  },
            { icon: cp(0xE768),  label: "Clojure",       key: "remove-dev-clojure"},
            { icon: cp(0xE737),  label: "Scala",         key: "remove-dev-scala"  },
        ],
        "remove-browser": [
            { icon: cp(0xF268),  label: "Chrome",       key: "remove-browser-chrome"       },
            { icon: cp(0xF268),  label: "Edge",         key: "remove-browser-edge"         },
            { icon: cp(0xF268),  label: "Brave",        key: "remove-browser-brave"        },
            { icon: cp(0xF268),  label: "Brave Origin", key: "remove-browser-brave-origin" },
            { icon: cp(0xF269),  label: "Firefox",      key: "remove-browser-firefox"      },
            { icon: cp(0xF059F), label: "Zen",          key: "remove-browser-zen"          },
        ],
        "remove-gaming": [
            { icon: cp(0xF1B6),  label: "Steam",           key: "remove-gaming-steam"    },
            { icon: cp(0xF0BC9), label: "RetroArch",       key: "remove-gaming-retroarch"},
            { icon: cp(0xF0373), label: "Minecraft",       key: "remove-gaming-minecraft"},
            { icon: cp(0xF08B9), label: "NVIDIA GeForce",  key: "remove-gaming-geforce"  },
            { icon: cp(0xED3E),  label: "Xbox Cloud",      key: "remove-gaming-xboxcloud"},
            { icon: cp(0xF00AF), label: "Xbox Controller", key: "remove-gaming-xboxpad"  },
            { icon: cp(0xF0379), label: "Moonlight",       key: "remove-gaming-moonlight"},
            { icon: cp(0xF268),  label: "Lutris",          key: "remove-gaming-lutris"   },
            { icon: cp(0xF14DF), label: "Heroic",          key: "remove-gaming-heroic"   },
        ],
        "remove-security": [
            { icon: cp(0xF0237), label: "Fingerprint", key: "remove-sec-fingerprint"},
            { icon: cp(0xEB11),  label: "Fido2",       key: "remove-sec-fido2"      },
        ],
        "update": [
            { icon: cp(0xE900),  label: "Omarchy",      key: "update-omarchy",  iconFont: "omarchy", iconSize: 14 },
            { icon: cp(0xF052B), label: "Channel",      key: "update-channel"   },
            { icon: cp(0xE615),  label: "Config",       key: "update-config"    },
            { icon: cp(0xF0E0C), label: "Extra Themes", key: "update-themes"    },
            { icon: cp(0xEBA2),  label: "Processes",    key: "update-processes" },
            { icon: cp(0xEF70),  label: "Hardware",     key: "update-hardware"  },
            { icon: cp(0xF01C5), label: "Firmware",     key: "update-firmware"  },
            { icon: cp(0xF023),  label: "Password",     key: "update-password"  },
            { icon: cp(0xF017),  label: "Timezone",     key: "update-timezone"  },
            { icon: cp(0xF017),  label: "Time",         key: "update-time"      },
        ],
        "update-channel": [
            { icon: cp(0x1F7E2), label: "Stable", key: "update-channel-stable"},
            { icon: cp(0x1F7E1), label: "RC",     key: "update-channel-rc"    },
            { icon: cp(0x1F7E0), label: "Edge",   key: "update-channel-edge"  },
            { icon: cp(0x1F534), label: "Dev",    key: "update-channel-dev"   },
        ],
        "update-processes": [
            { icon: cp(0xEBA2),  label: "Hypridle",   key: "update-proc-hypridle"  },
            { icon: cp(0xF5A7),  label: "Hyprsunset", key: "update-proc-hyprsunset"},
            { icon: cp(0xF039F), label: "Mako",       key: "update-proc-mako"      },
            { icon: cp(0xF028),  label: "Swayosd",    key: "update-proc-swayosd"   },
            { icon: cp(0xF002),  label: "Walker",     key: "update-proc-walker"    },
            { icon: cp(0xF035C), label: "Waybar",     key: "update-proc-waybar"    },
        ],
        "update-hardware": [
            { icon: cp(0xE638),  label: "Audio",     key: "update-hw-audio"   },
            { icon: cp(0xF1EB),  label: "Wi-Fi",     key: "update-hw-wifi"    },
            { icon: cp(0xF00AF), label: "Bluetooth", key: "update-hw-bt"      },
            { icon: cp(0xF07F8), label: "Trackpad",  key: "update-hw-trackpad"},
        ],
        "update-config": [
            { icon: cp(0xF359),  label: "Hyprland",   key: "update-cfg-hyprland"   },
            { icon: cp(0xEBA2),  label: "Hypridle",   key: "update-cfg-hypridle"   },
            { icon: cp(0xF023),  label: "Hyprlock",   key: "update-cfg-hyprlock"   },
            { icon: cp(0xF5A7),  label: "Hyprsunset", key: "update-cfg-hyprsunset" },
            { icon: cp(0xF18F4), label: "Plymouth",   key: "update-cfg-plymouth"   },
            { icon: cp(0xF028),  label: "Swayosd",    key: "update-cfg-swayosd"    },
            { icon: cp(0xF489),  label: "Tmux",       key: "update-cfg-tmux"       },
            { icon: cp(0xF002),  label: "Walker",     key: "update-cfg-walker"     },
            { icon: cp(0xF035C), label: "Waybar",     key: "update-cfg-waybar"     },
        ],
        "update-password": [
            { icon: cp(0xF023), label: "Disk encryption", key: "update-pass-disk"},
            { icon: cp(0xF004), label: "User",            key: "update-pass-user"},
        ],
        "system": [
            { icon: cp(0xF1104), label: "Screensaver", key: "system-screensaver"},
            { icon: cp(0xF023),  label: "Lock",        key: "system-lock"       },
            { icon: cp(0xF04B2), label: "Suspend",     key: "system-suspend"    },
            { icon: cp(0xF0901), label: "Hibernate",   key: "system-hibernate"  },
            { icon: cp(0xF0343), label: "Log out",     key: "system-logout"     },
            { icon: cp(0xF0709), label: "Reboot",      key: "system-reboot"     },
            { icon: cp(0xF0425), label: "Shutdown",    key: "system-shutdown"   },
        ],
    })

    // ── backdrop ──
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.BackButton
        onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton || mouse.button === Qt.BackButton) {
                if (menuPanel.currentMenu !== "") menuPanel.goBack()
                else menuPanel.closePanel()
            } else {
                menuPanel.closePanel()
            }
        }
    }

    // ── card ──
    Rectangle {
        id: card
        width: 260
        x: 248
        y: menuPanel.barBottom + menuPanel.gap
        height: cardCol.implicitHeight + 20
        opacity: menuPanel.reveal
        radius: 6
        color: root.bg
        border.color: root.sep
        border.width: 1

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.RightButton | Qt.BackButton
            onClicked: function(mouse) {
                if (menuPanel.currentMenu !== "") menuPanel.goBack()
                else menuPanel.closePanel()
            }
        }

        Column {
            id: cardCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            spacing: 6

            // ── header ──
            Item {
                width: parent.width
                height: 26

                Item {
                    id: backBtn
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    width: visible ? 22 : 0; height: 22
                    visible: menuPanel.navStack.length > 0
                    Rectangle {
                        anchors.fill: parent; radius: 4
                        color: backMa.containsMouse
                            ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.18) : "transparent"
                        Behavior on color { ColorAnimation { duration: 80 } }
                    }
                    Text {
                        anchors.centerIn: parent; text: "‹"
                        color: backMa.containsMouse ? root.seal : root.sumi; font.pixelSize: 16
                        Behavior on color { ColorAnimation { duration: 80 } }
                    }
                    MouseArea {
                        id: backMa; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor; onClicked: menuPanel.goBack()
                    }
                }

                Text {
                    anchors.left: backBtn.right
                    anchors.leftMargin: backBtn.visible ? 4 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: menuPanel.menuTitle
                    color: root.ink; font.family: root.mono
                    font.pixelSize: 12; font.letterSpacing: 1; font.weight: Font.Medium
                }

                Text {
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    text: "✕"; color: hdrCloseMa.containsMouse ? root.seal : root.sumi
                    font.pixelSize: 11
                    Behavior on color { ColorAnimation { duration: 100 } }
                    MouseArea {
                        id: hdrCloseMa; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor; onClicked: menuPanel.closePanel()
                    }
                }
            }

            // ── search bar ──
            Item {
                width: parent.width; height: 34

                Rectangle {
                    anchors.fill: parent; radius: 5
                    color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.06)
                    border.color: searchInput.activeFocus
                        ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.65) : root.sep
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 100 } }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left; anchors.leftMargin: 10
                    text: menuPanel.appMode ? "Search applications…" : "Search…"
                    color: root.sumi; font.family: root.mono; font.pixelSize: 12
                    visible: searchInput.text.length === 0
                }
                // gear button (apps mode only)
                Item {
                    id: gearBtn
                    anchors.right: parent.right; anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    width: menuPanel.appMode ? 28 : 0; height: 28
                    visible: menuPanel.appMode
                    Rectangle {
                        anchors.fill: parent; radius: 4
                        color: menuPanel.settingsMode
                            ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.2)
                            : (gearMa.containsMouse ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.1) : "transparent")
                        Behavior on color { ColorAnimation { duration: 80 } }
                    }
                    Text {
                        anchors.centerIn: parent; text: "⚙"
                        color: menuPanel.settingsMode ? root.seal : root.sumi; font.pixelSize: 14
                        Behavior on color { ColorAnimation { duration: 80 } }
                    }
                    MouseArea {
                        id: gearMa; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            menuPanel.settingsMode = !menuPanel.settingsMode
                            menuPanel.filterApps()
                            searchInput.forceActiveFocus()
                        }
                    }
                }

                TextInput {
                    id: searchInput
                    anchors {
                        left: parent.left
                        right: menuPanel.appMode ? gearBtn.left : parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 10; rightMargin: menuPanel.appMode ? 4 : 10
                    }
                    color: root.ink; font.family: root.mono; font.pixelSize: 12
                    selectByMouse: true
                    onTextChanged: {
                        menuPanel.query = text
                        if (menuPanel.appMode) menuPanel.filterApps()
                        menuPanel.selectedIndex = 0
                        listArea.scrollOffset = 0
                    }

                    Keys.onUpPressed: {
                        if (menuPanel.appMode) {
                            if (menuPanel.selectedIndex > 0) {
                                menuPanel.selectedIndex--
                                var top = menuPanel.selectedIndex * 42
                                if (top < listArea.scrollOffset) listArea.scrollOffset = top
                            }
                        } else {
                            if (menuPanel.selectedMenuIndex > 0) {
                                menuPanel.selectedMenuIndex--
                                var top2 = menuPanel.selectedMenuIndex * 38
                                if (top2 < listArea.scrollOffset) listArea.scrollOffset = top2
                            }
                        }
                    }
                    Keys.onDownPressed: {
                        if (menuPanel.appMode) {
                            var count = menuPanel.filteredApps.length
                            if (menuPanel.selectedIndex < count - 1) {
                                menuPanel.selectedIndex++
                                var bottom = (menuPanel.selectedIndex + 1) * 42
                                if (bottom > listArea.scrollOffset + listArea.height)
                                    listArea.scrollOffset = bottom - listArea.height
                            }
                        } else {
                            var mcount = menuPanel.displayItems.length
                            if (menuPanel.selectedMenuIndex < mcount - 1) {
                                menuPanel.selectedMenuIndex++
                                var mbottom = (menuPanel.selectedMenuIndex + 1) * 38
                                if (mbottom > listArea.scrollOffset + listArea.height)
                                    listArea.scrollOffset = mbottom - listArea.height
                            }
                        }
                    }
                    Keys.onReturnPressed: {
                        if (menuPanel.appMode) {
                            if (!menuPanel.settingsMode && menuPanel.filteredApps.length > 0)
                                menuPanel.launchApp(menuPanel.filteredApps[menuPanel.selectedIndex])
                        } else {
                            var items = menuPanel.displayItems
                            if (items.length > 0) {
                                var item = items[menuPanel.selectedMenuIndex]
                                if (menuPanel.hasSubmenu(item.key)) menuPanel.navigate(item.key)
                                else menuPanel.launchLeaf(item.key)
                            }
                        }
                    }
                    Keys.onEscapePressed: {
                        if (text.length > 0) {
                            text = ""; menuPanel.query = ""
                            if (menuPanel.appMode) menuPanel.filterApps()
                            menuPanel.selectedIndex = 0; menuPanel.selectedMenuIndex = 0
                            listArea.scrollOffset = 0
                        } else if (menuPanel.settingsMode) {
                            menuPanel.settingsMode = false; menuPanel.filterApps()
                        } else if (menuPanel.currentMenu !== "") {
                            menuPanel.goBack()
                        } else {
                            menuPanel.closePanel()
                        }
                    }
                }
            }

            // ── item list ──
            Item {
                id: listArea
                width: parent.width
                height: Math.min(
                    menuPanel.appMode ? menuPanel.filteredApps.length * 42
                                      : menuPanel.displayItems.length * 38,
                    420)
                clip: true

                property real scrollOffset: 0

                // app-mode keyboard highlight
                Rectangle {
                    id: keyHighlight
                    width: listArea.width - 2; x: 1; height: 40
                    y: menuPanel.appMode && menuPanel.filteredApps.length > 0
                        ? menuPanel.selectedIndex * 42 + 1 - listArea.scrollOffset : -50
                    radius: 4
                    color: Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.15)
                    border.color: Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.4)
                    border.width: 1; visible: menuPanel.appMode; z: 1
                }
                // menu-mode keyboard highlight
                Rectangle {
                    id: menuKeyHighlight
                    width: listArea.width - 2; x: 1; height: 36
                    y: !menuPanel.appMode && menuPanel.displayItems.length > 0
                        ? menuPanel.selectedMenuIndex * 38 + 1 - listArea.scrollOffset : -50
                    radius: 4
                    color: Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.15)
                    border.color: Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.4)
                    border.width: 1; visible: !menuPanel.appMode; z: 1
                }

                MouseArea {
                    anchors.fill: parent; z: 5
                    acceptedButtons: Qt.NoButton
                    onWheel: function(wheel) {
                        var count = menuPanel.appMode
                            ? menuPanel.filteredApps.length
                            : menuPanel.displayItems.length
                        var itemH = menuPanel.appMode ? 42 : 38
                        var maxOff = Math.max(0, count * itemH - listArea.height)
                        if (maxOff <= 0) return
                        listArea.scrollOffset = Math.max(0,
                            Math.min(listArea.scrollOffset - wheel.angleDelta.y / 2, maxOff))
                    }
                }

                // ── apps list (app mode) ──
                Column {
                    id: appListCol
                    width: listArea.width
                    y: -listArea.scrollOffset
                    spacing: 0
                    visible: menuPanel.appMode
                    z: 2

                    Repeater {
                        model: menuPanel.filteredApps
                        delegate: Item {
                            required property var modelData
                            required property int index
                            width: appListCol.width; height: 42

                            property bool isFav: menuPanel.favorites.indexOf(modelData.name) >= 0
                            property bool isHid: menuPanel.hiddenApps.indexOf(modelData.name) >= 0

                            Rectangle {
                                anchors { fill: parent; topMargin: 1; bottomMargin: 1 }
                                radius: 4
                                color: appRowMa.containsMouse
                                    ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.06) : "transparent"
                                Behavior on color { ColorAnimation { duration: 80 } }

                                MouseArea {
                                    id: appRowMa; anchors.fill: parent
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    enabled: !menuPanel.settingsMode
                                    onClicked: menuPanel.launchApp(modelData)
                                }

                                Row {
                                    anchors.left: parent.left; anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 12

                                    Image {
                                        width: 22; height: 22
                                        anchors.verticalCenter: parent.verticalCenter
                                        source: modelData.icon
                                        sourceSize: Qt.size(22, 22)
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true; mipmap: true; asynchronous: true
                                        opacity: (menuPanel.settingsMode && isHid) ? 0.3 : 1.0
                                        Behavior on opacity { NumberAnimation { duration: 120 } }
                                        layer.enabled: root.launcherIconEffect === "gradient-tint"
                                        layer.effect: ShaderEffect {
                                            property color tintColor: root.launcherIconTint
                                            fragmentShader: Qt.resolvedUrl("../shaders/icon-gradient.frag.qsb")
                                        }
                                    }
                                    Text {
                                        text: modelData.name
                                        color: (menuPanel.settingsMode && isHid) ? root.sumi : root.ink
                                        font.family: root.mono; font.pixelSize: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }
                                }

                                // normal mode: ★ for favorites
                                Text {
                                    anchors.right: parent.right; anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "★"; font.pixelSize: 10
                                    color: Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.55)
                                    visible: !menuPanel.settingsMode && isFav
                                }

                                // settings mode: ★/☆ and ●/✕ buttons
                                Row {
                                    anchors.right: parent.right; anchors.rightMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4; visible: menuPanel.settingsMode

                                    Item {
                                        width: 28; height: 28
                                        Rectangle {
                                            anchors.fill: parent; radius: 4
                                            color: favMa.containsMouse
                                                ? Qt.rgba(root.seal.r, root.seal.g, root.seal.b, 0.18) : "transparent"
                                            Behavior on color { ColorAnimation { duration: 80 } }
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            text: isFav ? "★" : "☆"
                                            color: isFav ? root.seal : root.sumi; font.pixelSize: 15
                                            Behavior on color { ColorAnimation { duration: 80 } }
                                        }
                                        MouseArea {
                                            id: favMa; anchors.fill: parent; hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: menuPanel.toggleFavorite(modelData.name)
                                        }
                                    }
                                    Item {
                                        width: 28; height: 28
                                        Rectangle {
                                            anchors.fill: parent; radius: 4
                                            color: hidMa.containsMouse
                                                ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.1) : "transparent"
                                            Behavior on color { ColorAnimation { duration: 80 } }
                                        }
                                        Text {
                                            anchors.centerIn: parent
                                            text: isHid ? "✕" : "●"
                                            color: isHid ? Qt.rgba(1.0, 0.38, 0.38, 0.9) : root.sumi
                                            font.pixelSize: isHid ? 12 : 8
                                            Behavior on color { ColorAnimation { duration: 80 } }
                                        }
                                        MouseArea {
                                            id: hidMa; anchors.fill: parent; hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: menuPanel.toggleHidden(modelData.name)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── menu list (menu mode) ──
                Column {
                    id: menuListCol
                    width: listArea.width
                    y: -listArea.scrollOffset
                    spacing: 0
                    visible: !menuPanel.appMode
                    z: 1

                    Repeater {
                        model: menuPanel.displayItems
                        delegate: Item {
                            required property var modelData
                            required property int index
                            width: menuListCol.width; height: 38
                            readonly property bool sub: menuPanel.hasSubmenu(modelData.key)

                            Rectangle {
                                anchors { fill: parent; topMargin: 1; bottomMargin: 1 }
                                radius: 4
                                color: rowMa.containsMouse
                                    ? Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.08) : "transparent"
                                Behavior on color { ColorAnimation { duration: 80 } }

                                MouseArea {
                                    id: rowMa; anchors.fill: parent
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (sub) menuPanel.navigate(modelData.key)
                                        else     menuPanel.launchLeaf(modelData.key)
                                    }
                                }

                                Row {
                                    anchors.left: parent.left; anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 12

                                    Text {
                                        text: modelData.icon
                                        color: rowMa.containsMouse ? root.seal : root.sumi
                                        font.family: modelData.iconFont || root.mono
                                        font.pixelSize: modelData.iconSize || 15
                                        anchors.verticalCenter: parent.verticalCenter
                                        Behavior on color { ColorAnimation { duration: 80 } }
                                    }
                                    Text {
                                        text: modelData.label
                                        color: root.ink; font.family: root.mono; font.pixelSize: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }

                                Text {
                                    anchors.right: parent.right; anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "›"
                                    color: rowMa.containsMouse ? root.seal : root.sumi
                                    font.pixelSize: 14; visible: sub
                                    Behavior on color { ColorAnimation { duration: 80 } }
                                }
                            }
                        }
                    }
                }
            }

            // settings mode footer
            Item {
                width: parent.width
                height: menuPanel.settingsMode ? 24 : 0
                clip: true; visible: height > 0
                Text {
                    anchors.centerIn: parent
                    text: "★ favorite   ● visible / ✕ hidden"
                    color: root.sumi; font.family: root.mono; font.pixelSize: 10; opacity: 0.6
                }
            }
        }
    }

    onNavStackChanged:   { listArea.scrollOffset = 0; selectedMenuIndex = 0 }
    onQueryChanged:      { if (!appMode) { listArea.scrollOffset = 0; selectedMenuIndex = 0 } }

    IpcHandler {
        target: "omarchy-menu"
        function toggle(): void   { root.omarchyMenuVisible = !root.omarchyMenuVisible }
        function show(): void     { root.omarchyMenuVisible = true }
        function hide(): void     { root.omarchyMenuVisible = false }
        function showApps(): void {
            navStack = ["apps"]
            root.omarchyMenuVisible = true
        }
    }
}
