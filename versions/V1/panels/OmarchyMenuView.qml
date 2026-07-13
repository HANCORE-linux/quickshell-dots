import QtQuick
import Quickshell
import Quickshell.Io

// Vista reutilizable del menú Omarchy (búsqueda + lista + drill-down).
// Extraída de OmarchyMenuPanel.qml para empotrarla en el ControlPanel
// (pestaña System) usando EXACTAMENTE los mismos endpoints. Datos, navegación
// y activación idénticos al panel standalone (que sigue intacto).
Item {
    id: view
    implicitHeight: viewCol.implicitHeight
    required property var theme
    property int maxListHeight: 420
    property alias searchInput: searchInput
    signal closeRequested()   // Escape en la raíz → el host cierra su ventana

    // ── menu data (idéntico a OmarchyMenuPanel; NO editar aquí sin sincronizar) ──
    function cp(n) { return String.fromCodePoint(n) }

    // hibernación requiere swap de disco + resume en initramfs (zram no vale);
    // sin esto systemctl hibernate falla en silencio
    property bool canHibernate: false
    Process {
        id: hibernateCheck
        command: ["omarchy-hibernation-available"]
        running: true
        onExited: (exitCode) => view.canHibernate = exitCode === 0
    }

    readonly property var submenus: ({
        "style": [
            { icon: cp(0xF0E0C), label: "Tema",          key: "style-theme" },
            { icon: cp(0xF07F5), label: "Unlock",         key: "style-unlock" },
            { icon: cp(0xE659),  label: "Fuente",         key: "style-font" },
            { icon: cp(0xF03E),  label: "Fondo",          key: "style-wallpaper" },
            { icon: cp(0xF0607), label: "Esquinas",       key: "style-corners" },
            { icon: cp(0xF359),  label: "Hyprland",       key: "style-hyprland" },
            { icon: cp(0xF1104), label: "Salvapantallas", key: "style-screensaver" },
            { icon: cp(0xEA74),  label: "Acerca de",      key: "style-about" },
        ],
        "style-corners": [
            { icon: cp(0xF08FC), label: "Rectas",       key: "style-corners-sharp" },
            { icon: cp(0xF0607), label: "Redondeadas",  key: "style-corners-round" },
        ],
        "style-screensaver": [
            { icon: cp(0xF044),  label: "Editar texto", key: "style-screensaver-text" },
            { icon: cp(0xF03E),  label: "Desde imagen", key: "style-screensaver-image" },
            { icon: cp(0xF0E2),  label: "Restaurar",    key: "style-screensaver-reset" },
        ],
        "style-about": [
            { icon: cp(0xF044),  label: "Editar texto", key: "style-about-text" },
            { icon: cp(0xF03E),  label: "Desde imagen", key: "style-about-image" },
            { icon: cp(0xF0E2),  label: "Restaurar",    key: "style-about-reset" },
        ],
        "learn": [
            { icon: cp(0xF11C),  label: "Atajos de teclado", key: "learn-keybindings" },
            { icon: cp(0xF489),  label: "Tmux",             key: "learn-tmux" },
            { icon: cp(0xF405),  label: "Omarchy",          key: "learn-omarchy" },
            { icon: cp(0xF359),  label: "Hyprland",         key: "learn-hyprland" },
            { icon: cp(0xF08C7), label: "Arch",             key: "learn-arch" },
            { icon: cp(0xE6AE),  label: "Neovim",           key: "learn-neovim" },
            { icon: cp(0xF1183), label: "Bash",             key: "learn-bash" },
        ],
        "trigger": [
            { icon: cp(0xF051B), label: "Recordatorio",   key: "reminder" },
            { icon: cp(0xF030),  label: "Captura",         key: "capture" },
            { icon: cp(0xF09F8), label: "Transcodificar",  key: "trigger-transcode" },
            { icon: cp(0xF50E),  label: "Compartir",       key: "share" },
            { icon: cp(0xF050E), label: "Alternar",        key: "toggle" },
            { icon: cp(0xEF70),  label: "Hardware",        key: "hardware" },
        ],
        "reminder": [
            { icon: cp(0xF051B), label: "Crear",           key: "reminder-create" },
            { icon: cp(0xF051B), label: "Mostrar todos",   key: "reminder-show" },
            { icon: cp(0xF051B), label: "Borrar todos",    key: "reminder-clear" },
        ],
        "capture": [
            { icon: cp(0xF030),  label: "Captura de pantalla",  key: "capture-screenshot" },
            { icon: cp(0xF03D),  label: "Grabación de pantalla",key: "capture-screenrecord" },
            { icon: cp(0xF0D11), label: "Extraer texto (OCR)",  key: "capture-ocr" },
            { icon: cp(0xF00C9), label: "Selector de color",    key: "capture-color" },
        ],
        "capture-screenrecord": [
            { icon: cp(0xF03D),  label: "Parar grabación",      key: "screenrecord-stop" },
            { icon: cp(0xF03D),  label: "Sin audio",            key: "screenrecord-noaudio" },
            { icon: cp(0xE638),  label: "Audio del sistema",    key: "screenrecord-audio" },
            { icon: cp(0xF036E), label: "Sistema + micrófono",  key: "screenrecord-micaudio" },
        ],
        "share": [
            { icon: cp(0xF0786), label: "Portapapeles",    key: "share-clipboard" },
            { icon: cp(0xF0214), label: "Archivo",         key: "share-file" },
            { icon: cp(0xF024B), label: "Carpeta",         key: "share-folder" },
            { icon: cp(0xF0966), label: "Recibir",         key: "share-receive" },
        ],
        "toggle": [
            { icon: cp(0xF1104), label: "Salvapantallas",  key: "toggle-screensaver" },
            { icon: cp(0xF050E), label: "Luz nocturna",    key: "toggle-nightlight" },
            { icon: cp(0xF16D6), label: "Bloqueo inactivo",key: "toggle-idle" },
            { icon: cp(0xF009B), label: "Notificaciones",  key: "toggle-notifications" },
            { icon: cp(0xF102C), label: "Layout workspace",key: "toggle-layout" },
            { icon: cp(0xF0B3E), label: "Huecos ventanas", key: "toggle-gaps" },
            { icon: cp(0xF09AA), label: "Ratio ventana",   key: "toggle-ratio" },
            { icon: cp(0xF0379), label: "Escala monitor",  key: "toggle-scaling" },
            { icon: cp(0xF072E), label: "Arranque directo",key: "toggle-directboot" },
            { icon: cp(0xF07F5), label: "Sudo sin pass",   key: "toggle-sudo" },
        ],
        "hardware": [
            { icon: cp(0xF0663), label: "Pantalla portátil", key: "hardware-screen" },
            { icon: cp(0xF0379), label: "Espejo pantalla",   key: "hardware-mirror" },
            { icon: cp(0xF01C5), label: "GPU híbrida",       key: "hardware-gpu" },
            { icon: cp(0xF07F8), label: "Touchpad",          key: "hardware-touchpad" },
            { icon: cp(0xF01BD), label: "Pantalla táctil",   key: "hardware-touchscreen" },
        ],
        "install": [
            { icon: cp(0xF08C7), label: "Paquete",        key: "install-package" },
            { icon: cp(0xF08C7), label: "AUR",            key: "install-aur" },
            { icon: cp(0xF268),  label: "App Web",        key: "install-webapp" },
            { icon: cp(0xF489),  label: "TUI",            key: "install-tui" },
            { icon: cp(0xF487),  label: "Servicio",       key: "install-service" },
            { icon: cp(0xEBCF),  label: "Estilo",         key: "install-style" },
            { icon: cp(0xF0D6E), label: "Desarrollo",     key: "install-dev" },
            { icon: cp(0xF15C),  label: "Editor",         key: "install-editor" },
            { icon: cp(0xF489),  label: "Terminal",       key: "install-terminal" },
            { icon: cp(0xF268),  label: "Navegador",      key: "install-browser" },
            { icon: cp(0xF16A4), label: "IA",             key: "install-ai" },
            { icon: cp(0xF11B),  label: "Gaming",         key: "install-gaming" },
            { icon: cp(0xF0372), label: "VM Windows",     key: "install-windows" },
        ],
        "install-service": [
            { icon: cp(0xE707),  label: "Dropbox",         key: "install-serv-dropbox" },
            { icon: cp(0xF487),  label: "Tailscale",       key: "install-serv-tailscale" },
            { icon: cp(0xF11F1), label: "NordVPN [AUR]",   key: "install-serv-nordvpn" },
            { icon: cp(0xF03D6), label: "ONCE",            key: "install-serv-once" },
            { icon: cp(0x2600),  label: "Sunshine",        key: "install-serv-sunshine" },
            { icon: cp(0xF07F5), label: "Bitwarden",       key: "install-serv-bitwarden" },
            { icon: cp(0xE7F0),  label: "Cuenta Chromium", key: "install-serv-chromium" },
        ],
        "install-style": [
            { icon: cp(0xF0E0C), label: "Instalar tema",  key: "install-style-theme" },
            { icon: cp(0xF03E),  label: "Fondo",          key: "install-style-wallpaper" },
            { icon: cp(0xE659),  label: "Fuente",         key: "install-style-font" },
        ],
        "install-dev": [
            { icon: cp(0xF0ACF), label: "Ruby on Rails",  key: "install-dev-rails" },
            { icon: cp(0xF21F),  label: "Docker DB",      key: "install-dev-docker" },
            { icon: cp(0xE781),  label: "JavaScript",     key: "install-dev-js" },
            { icon: cp(0xE627),  label: "Go",             key: "install-dev-go" },
            { icon: cp(0xE73D),  label: "PHP",            key: "install-dev-php" },
            { icon: cp(0xE73C),  label: "Python",         key: "install-dev-python" },
            { icon: cp(0xE62D),  label: "Elixir",         key: "install-dev-elixir" },
            { icon: cp(0xE8EF),  label: "Zig",            key: "install-dev-zig" },
            { icon: cp(0xE7A8),  label: "Rust",           key: "install-dev-rust" },
            { icon: cp(0xE738),  label: "Java",           key: "install-dev-java" },
            { icon: cp(0xE77F),  label: ".NET",           key: "install-dev-dotnet" },
            { icon: cp(0xE84E),  label: "OCaml",          key: "install-dev-ocaml" },
            { icon: cp(0xE768),  label: "Clojure",        key: "install-dev-clojure" },
            { icon: cp(0xE737),  label: "Scala",          key: "install-dev-scala" },
        ],
        "install-dev-js": [
            { icon: cp(0xE781),  label: "Node.js",   key: "install-dev-js-node" },
            { icon: cp(0xF15C),  label: "Bun",       key: "install-dev-js-bun" },
            { icon: cp(0xF15C),  label: "Deno",      key: "install-dev-js-deno" },
        ],
        "install-dev-php": [
            { icon: cp(0xE73D),  label: "PHP",       key: "install-dev-php-php" },
            { icon: cp(0xF15C),  label: "Laravel",   key: "install-dev-php-laravel" },
            { icon: cp(0xF15C),  label: "Symfony",   key: "install-dev-php-symfony" },
        ],
        "install-dev-elixir": [
            { icon: cp(0xE62D),  label: "Elixir",    key: "install-dev-elixir-elixir" },
            { icon: cp(0xF14DF), label: "Phoenix",   key: "install-dev-elixir-phoenix" },
        ],
        "install-editor": [
            { icon: cp(0xE8DA),  label: "VSCode",         key: "install-editor-vscode" },
            { icon: cp(0xF15C),  label: "Cursor",         key: "install-editor-cursor" },
            { icon: cp(0xF15C),  label: "Zed",            key: "install-editor-zed" },
            { icon: cp(0xF15C),  label: "Sublime Text",   key: "install-editor-sublime" },
            { icon: cp(0xF15C),  label: "Helix",          key: "install-editor-helix" },
            { icon: cp(0xE62B),  label: "Vim",            key: "install-editor-vim" },
            { icon: cp(0xF15C),  label: "Emacs",          key: "install-editor-emacs" },
        ],
        "install-terminal": [
            { icon: cp(0xF489),  label: "Alacritty",      key: "install-term-alacritty" },
            { icon: cp(0xF489),  label: "Foot",           key: "install-term-foot" },
            { icon: cp(0xF489),  label: "Ghostty",        key: "install-term-ghostty" },
            { icon: cp(0xF489),  label: "Kitty",          key: "install-term-kitty" },
        ],
        "install-browser": [
            { icon: cp(0xF268),  label: "Chrome",         key: "install-browser-chrome" },
            { icon: cp(0xF268),  label: "Edge",           key: "install-browser-edge" },
            { icon: cp(0xF268),  label: "Brave",          key: "install-browser-brave" },
            { icon: cp(0xF268),  label: "Brave Origin",   key: "install-browser-brave-origin" },
            { icon: cp(0xF269),  label: "Firefox",        key: "install-browser-firefox" },
            { icon: cp(0xF059F), label: "Zen",            key: "install-browser-zen" },
        ],
        "install-ai": [
            { icon: cp(0xEC12),  label: "Voice Typing",   key: "install-ai-voicetyping" },
            { icon: cp(0xF16A4), label: "LM Studio",      key: "install-ai-lmstudio" },
            { icon: cp(0xF16A4), label: "Ollama",         key: "install-ai-ollama" },
            { icon: cp(0xF16A4), label: "Crush",          key: "install-ai-crush" },
        ],
        "install-gaming": [
            { icon: cp(0xF1B6),  label: "Steam",          key: "install-gaming-steam" },
            { icon: cp(0xF0BC9), label: "RetroArch",      key: "install-gaming-retroarch" },
            { icon: cp(0xF0BC9), label: "RetroArch Launcher", key: "install-gaming-retroarch-launcher" },
            { icon: cp(0xF0373), label: "Minecraft",      key: "install-gaming-minecraft" },
            { icon: cp(0xF08B9), label: "NVIDIA GeForce NOW", key: "install-gaming-geforce" },
            { icon: cp(0xED3E),  label: "Xbox Cloud Gaming",  key: "install-gaming-xboxcloud" },
            { icon: cp(0xF00AF), label: "Xbox Controller",key: "install-gaming-xboxpad" },
            { icon: cp(0xF0379), label: "Moonlight",      key: "install-gaming-moonlight" },
            { icon: cp(0xF268),  label: "Lutris",         key: "install-gaming-lutris" },
            { icon: cp(0xF14DF), label: "Heroic",         key: "install-gaming-heroic" },
        ],
        "remove": [
            { icon: cp(0xF08C7), label: "Paquete",        key: "remove-package" },
            { icon: cp(0xF268),  label: "App Web",        key: "remove-webapp" },
            { icon: cp(0xF489),  label: "TUI",            key: "remove-tui" },
            { icon: cp(0xF0D6E), label: "Desarrollo",     key: "remove-dev" },
            { icon: cp(0xF0E0C), label: "Remover tema",   key: "remove-theme" },
            { icon: cp(0xF268),  label: "Navegador",      key: "remove-browser" },
            { icon: cp(0xEC12),  label: "Voice Typing",   key: "remove-voicetyping" },
            { icon: cp(0xF11B),  label: "Gaming",         key: "remove-gaming" },
            { icon: cp(0xF0372), label: "VM Windows",     key: "remove-windows" },
            { icon: cp(0xF03D3), label: "Pre-instalados", key: "remove-preinstalls" },
            { icon: cp(0xEB11),  label: "Seguridad",      key: "remove-security" },
        ],
        "remove-browser": [
            { icon: cp(0xF268),  label: "Chrome",         key: "remove-browser-chrome" },
            { icon: cp(0xF268),  label: "Edge",           key: "remove-browser-edge" },
            { icon: cp(0xF268),  label: "Brave",          key: "remove-browser-brave" },
            { icon: cp(0xF268),  label: "Brave Origin",   key: "remove-browser-brave-origin" },
            { icon: cp(0xF269),  label: "Firefox",        key: "remove-browser-firefox" },
            { icon: cp(0xF059F), label: "Zen",            key: "remove-browser-zen" },
        ],
        "remove-gaming": [
            { icon: cp(0xF1B6),  label: "Steam",          key: "remove-gaming-steam" },
            { icon: cp(0xF0BC9), label: "RetroArch",      key: "remove-gaming-retroarch" },
            { icon: cp(0xF0373), label: "Minecraft",      key: "remove-gaming-minecraft" },
            { icon: cp(0xF08B9), label: "NVIDIA GeForce NOW", key: "remove-gaming-geforce" },
            { icon: cp(0xED3E),  label: "Xbox Cloud Gaming",  key: "remove-gaming-xboxcloud" },
            { icon: cp(0xF00AF), label: "Xbox Controller",key: "remove-gaming-xboxpad" },
            { icon: cp(0xF0379), label: "Moonlight",      key: "remove-gaming-moonlight" },
            { icon: cp(0xF268),  label: "Lutris",         key: "remove-gaming-lutris" },
            { icon: cp(0xF14DF), label: "Heroic",         key: "remove-gaming-heroic" },
        ],
        "remove-dev": [
            { icon: cp(0xF0ACF), label: "Ruby on Rails",  key: "remove-dev-rails" },
            { icon: cp(0xE781),  label: "JavaScript",     key: "remove-dev-js" },
            { icon: cp(0xE627),  label: "Go",             key: "remove-dev-go" },
            { icon: cp(0xE73D),  label: "PHP",            key: "remove-dev-php" },
            { icon: cp(0xE73C),  label: "Python",         key: "remove-dev-python" },
            { icon: cp(0xE62D),  label: "Elixir",         key: "remove-dev-elixir" },
            { icon: cp(0xE8EF),  label: "Zig",            key: "remove-dev-zig" },
            { icon: cp(0xE7A8),  label: "Rust",           key: "remove-dev-rust" },
            { icon: cp(0xE738),  label: "Java",           key: "remove-dev-java" },
            { icon: cp(0xE77F),  label: ".NET",           key: "remove-dev-dotnet" },
            { icon: cp(0xE84E),  label: "OCaml",          key: "remove-dev-ocaml" },
            { icon: cp(0xE768),  label: "Clojure",        key: "remove-dev-clojure" },
            { icon: cp(0xE737),  label: "Scala",          key: "remove-dev-scala" },
        ],
        "remove-dev-js": [
            { icon: cp(0xE781),  label: "Node.js",   key: "remove-dev-js-node" },
            { icon: cp(0xF15C),  label: "Bun",       key: "remove-dev-js-bun" },
            { icon: cp(0xF15C),  label: "Deno",      key: "remove-dev-js-deno" },
        ],
        "remove-dev-php": [
            { icon: cp(0xE73D),  label: "PHP",       key: "remove-dev-php-php" },
            { icon: cp(0xF15C),  label: "Laravel",   key: "remove-dev-php-laravel" },
            { icon: cp(0xF15C),  label: "Symfony",   key: "remove-dev-php-symfony" },
        ],
        "remove-dev-elixir": [
            { icon: cp(0xE62D),  label: "Elixir",    key: "remove-dev-elixir-elixir" },
            { icon: cp(0xF14DF), label: "Phoenix",   key: "remove-dev-elixir-phoenix" },
        ],
        "remove-security": [
            { icon: cp(0xF0237), label: "Huella dactilar",key: "remove-sec-fingerprint" },
            { icon: cp(0xEB11),  label: "Fido2",          key: "remove-sec-fido2" },
        ],
        "update": [
            { icon: cp(0xE900),  label: "Omarchy",        key: "update-omarchy", iconFont: "omarchy", iconSize: 14 },
            { icon: cp(0xF052B), label: "Canal",          key: "update-channel" },
            { icon: cp(0xE615),  label: "Config",         key: "update-config" },
            { icon: cp(0xF0E0C), label: "Actualizar temas", key: "update-themes" },
            { icon: cp(0xEBA2),  label: "Procesos",       key: "update-processes" },
            { icon: cp(0xEF70),  label: "Hardware",       key: "update-hardware" },
            { icon: cp(0xF01C5), label: "Firmware",       key: "update-firmware" },
            { icon: cp(0xF023),  label: "Contraseña",     key: "update-password" },
            { icon: cp(0xF017),  label: "Zona horaria",   key: "update-timezone" },
            { icon: cp(0xF017),  label: "Hora",           key: "update-time" },
        ],
        "update-channel": [
            { icon: cp(0x1F7E2), label: "Stable",         key: "update-channel-stable" },
            { icon: cp(0x1F7E1), label: "RC",             key: "update-channel-rc" },
            { icon: cp(0x1F7E0), label: "Edge",           key: "update-channel-edge" },
            { icon: cp(0x1F534), label: "Dev",            key: "update-channel-dev" },
        ],
        "update-processes": [
            { icon: cp(0xEBA2),  label: "Hypridle",       key: "update-proc-hypridle" },
            { icon: cp(0xF5A7),  label: "Hyprsunset",     key: "update-proc-hyprsunset" },
            { icon: cp(0xF002),  label: "Walker",         key: "update-proc-walker" },
        ],
        "update-hardware": [
            { icon: cp(0xE638),  label: "Audio",          key: "update-hw-audio" },
            { icon: cp(0xF1EB),  label: "Wi-Fi",          key: "update-hw-wifi" },
            { icon: cp(0xF00AF), label: "Bluetooth",      key: "update-hw-bt" },
            { icon: cp(0xF07F8), label: "Trackpad",       key: "update-hw-trackpad" },
        ],
        "update-config": [
            { icon: cp(0xF359),  label: "Hyprland",       key: "update-cfg-hyprland" },
            { icon: cp(0xEBA2),  label: "Hypridle",       key: "update-cfg-hypridle" },
            { icon: cp(0xF023),  label: "Hyprlock",       key: "update-cfg-hyprlock" },
            { icon: cp(0xF5A7),  label: "Hyprsunset",     key: "update-cfg-hyprsunset" },
            { icon: cp(0xF18F4), label: "Plymouth",       key: "update-cfg-plymouth" },
            { icon: cp(0xF489),  label: "Tmux",           key: "update-cfg-tmux" },
            { icon: cp(0xF002),  label: "Walker",         key: "update-cfg-walker" },
        ],
        "update-password": [
            { icon: cp(0xF023),  label: "Cifrado disco",  key: "update-pass-disk" },
            { icon: cp(0xF004),  label: "Usuario",        key: "update-pass-user" },
        ],
        "setup": [
            { icon: cp(0xE638),  label: "Audio",             key: "setup-audio" },
            { icon: cp(0xF1EB),  label: "WiFi",              key: "setup-wifi" },
            { icon: cp(0xF00AF), label: "Bluetooth",         key: "setup-bt" },
            { icon: cp(0xF14DB), label: "Perfil energía",    key: "power" },
            { icon: cp(0xEBA2),  label: "Config suspensión", key: "setup-suspend" },
            { icon: cp(0xF0379), label: "Monitores",         key: "setup-monitors" },
            { icon: cp(0xF11C),  label: "Atajos",            key: "setup-keybindings" },
            { icon: cp(0xF488),  label: "Entrada",           key: "setup-input" },
            { icon: cp(0xF488),  label: "Predeterminados",   key: "setup-defaults" },
            { icon: cp(0xF059B), label: "DNS",               key: "setup-dns" },
            { icon: cp(0xEB11),  label: "Seguridad",         key: "setup-security" },
            { icon: cp(0xE615),  label: "Archivos config",   key: "setup-configfiles" },
        ],
        "setup-security": [
            { icon: cp(0xF0237), label: "Huella dactilar",key: "setup-sec-fingerprint" },
            { icon: cp(0xEB11),  label: "Fido2",          key: "setup-sec-fido2" },
        ],
        "setup-configfiles": [
            { icon: cp(0xF359),  label: "Hyprland",       key: "setup-arch-hyprland" },
            { icon: cp(0xEBA2),  label: "Hypridle",       key: "setup-arch-hypridle" },
            { icon: cp(0xF023),  label: "Hyprlock",       key: "setup-arch-hyprlock" },
            { icon: cp(0xF5A7),  label: "Hyprsunset",     key: "setup-arch-hyprsunset" },
            { icon: cp(0xF002),  label: "Walker",         key: "setup-arch-walker" },
            { icon: cp(0xF0785), label: "XCompose",       key: "setup-arch-xcompose" },
        ],
        "system": [
            { icon: cp(0xF1104), label: "Salvapantallas", key: "system-screensaver" },
            { icon: cp(0xF023),  label: "Bloquear",       key: "system-lock" },
            { icon: cp(0xF04B2), label: "Suspender",      key: "system-suspend" },
            { icon: cp(0xF0901), label: "Hibernar",       key: "system-hibernate", show: view.canHibernate },
            { icon: cp(0xF0343), label: "Cerrar sesión",  key: "system-logout",   sep: true, danger: true },
            { icon: cp(0xF0709), label: "Reiniciar",      key: "system-reboot",   danger: true },
            { icon: cp(0xF0425), label: "Apagar",         key: "system-shutdown", danger: true },
        ].filter(it => it.show === undefined || it.show),
    })

    readonly property var allItems: [
        { icon: cp(0xF003B), label: "Apps",       key: "apps",    category: "" },
        { icon: cp(0xF09D1), label: "Aprender",   key: "learn",   category: "" },
        { icon: cp(0xF14DE), label: "Acciones",   key: "trigger", category: "" },
        { icon: cp(0xEBCF),  label: "Estilo",     key: "style",   category: "" },
        { icon: cp(0xE615),  label: "Config",     key: "setup",   category: "" },
        { icon: cp(0xF0249), label: "Instalar",   key: "install", category: "" },
        { icon: cp(0xF0B4C), label: "Eliminar",   key: "remove",  category: "" },
        { icon: cp(0xF021),  label: "Actualizar", key: "update",  category: "" },
        { icon: cp(0xEA74),  label: "Acerca de",  key: "about",   category: "" },
        { icon: cp(0xF011),  label: "Sistema",    key: "system",  category: "" },
    ]

    // ── navigation state ──
    property var navStack: []
    property string currentMenu: navStack.length > 0 ? navStack[navStack.length - 1] : ""
    property string query: ""
    property var displayItems: []
    property int displayTick: 0
    // El cursor de teclado y el hover son estados distintos. Así al abrir no
    // parece que se haya elegido el primer ítem, pero las flechas conservan
    // una referencia clara una vez se usan.
    property int selIdx: -1
    property int hoverIdx: -1

    function rebuildDisplay() {
        var q = query.toLowerCase().trim()
        var menu = navStack.length > 0 ? navStack[navStack.length - 1] : ""
        var result
        if (q !== "") {
            var pool = allItems.slice()
            var skeys = Object.keys(submenus)
            for (var si = 0; si < skeys.length; si++) {
                var sub = submenus[skeys[si]]
                for (var sj = 0; sj < sub.length; sj++) pool.push(sub[sj])
            }
            var seen = {}
            result = pool.filter(function(it) {
                if (seen[it.key]) return false
                seen[it.key] = true
                return it.label.toLowerCase().split(/\s+/).some(function(w) { return w.indexOf(q) === 0 })
            })
        } else if (menu !== "" && submenus[menu]) {
            result = submenus[menu]
        } else {
            result = allItems.filter(function(it) { return it.category === "" })
        }
        displayItems = result
        displayTick++
        selIdx = -1
        hoverIdx = -1
    }
    onQueryChanged:    rebuildDisplay()
    onNavStackChanged: rebuildDisplay()

    function navigate(key) { navStack = navStack.concat([key]) }
    function goBack() {
        if (navStack.length > 1) navStack = navStack.slice(0, navStack.length - 1)
        else navStack = []
    }
    function hasSubmenu(key) { return submenus.hasOwnProperty(key) }
    function menuLabel(key) {
        for (var i = 0; i < allItems.length; i++)
            if (allItems[i].key === key) return allItems[i].label
        return key
    }
    function activateIndex(i) {
        var it = displayItems[i]
        if (!it) return
        if (hasSubmenu(it.key)) { navigate(it.key); searchInput.text = "" }
        else handleAction(it.key)
    }
    // resetea a la raíz (lo llama el host al abrir / cambiar de pestaña)
    function resetToRoot() { navStack = []; query = ""; searchInput.text = ""; rebuildDisplay() }

    // endpoints IDÉNTICOS al OmarchyMenuPanel.handleAction (misma acción por key)
    function handleAction(k) {
        view.closeRequested()
        Qt.callLater(function() {
            Quickshell.execDetached(["omarchy-menu", k])
        })
    }

    Component.onCompleted: rebuildDisplay()

    // clic derecho / botón "atrás" del ratón → sube un nivel (los ítems solo
    // aceptan el botón izquierdo, así que el derecho cae aquí detrás)
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton | Qt.BackButton
        onClicked: if (view.currentMenu !== "") view.goBack()
    }

    // ── visual: search / lista ──
    Column {
        id: viewCol
        width: parent.width
        spacing: 0

        // el buscador aparece solo al escribir (o al entrar en un submenú, para
        // mostrar breadcrumb/back). El TextInput mantiene el foco aunque la caja
        // esté colapsada (height/opacity a 0, NO visible:false que mataría el foco).
        Rectangle {
            id: searchBox
            // aparece SOLO al escribir (en cualquier nivel; en submenús pequeños como
            // "Sistema" un buscador no aporta nada). Back sin barra: ESC/←/⌫ o clic derecho.
            readonly property bool shown: searchInput.text !== ""
            width: parent.width
            height: shown ? 30 : 0
            clip: true
            opacity: shown ? 1 : 0
            radius: view.theme.tileRadius
            color: Qt.rgba(view.theme.ink.r, view.theme.ink.g, view.theme.ink.b, 0.07)
            border.color: searchInput.activeFocus ? view.theme.seal : view.theme.sep
            border.width: shown ? 1 : 0
            Behavior on height  { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
            Behavior on opacity { NumberAnimation { duration: 110 } }
            Behavior on border.color { ColorAnimation { duration: 120 } }

            TextInput {
                id: searchInput
                anchors.fill: parent
                anchors.leftMargin: 8; anchors.rightMargin: 8
                anchors.topMargin: 6; anchors.bottomMargin: 6
                color: view.theme.ink
                font.family: view.theme.mono; font.pixelSize: 13
                onTextChanged: view.query = text
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Escape) {
                        if (view.currentMenu !== "") { view.goBack(); text = "" }
                        else if (text !== "") { text = "" }
                        else { view.closeRequested() }
                        event.accepted = true
                    } else if (event.key === Qt.Key_Down) {
                        view.hoverIdx = -1
                        if (view.displayItems.length > 0)
                            view.selIdx = (view.selIdx + 1) % view.displayItems.length
                        event.accepted = true
                    } else if (event.key === Qt.Key_Up) {
                        view.hoverIdx = -1
                        if (view.displayItems.length > 0)
                            view.selIdx = view.selIdx <= 0 ? view.displayItems.length - 1 : view.selIdx - 1
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        view.activateIndex(view.selIdx)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Right && text === "") {
                        var cur = view.displayItems[view.selIdx]
                        if (cur && view.hasSubmenu(cur.key)) view.navigate(cur.key)
                        event.accepted = true
                    } else if ((event.key === Qt.Key_Left || event.key === Qt.Key_Backspace)
                               && text === "" && view.currentMenu !== "") {
                        view.goBack()
                        event.accepted = true
                    }
                }
            }

            Text {
                anchors.left: parent.left; anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                visible: searchInput.text === ""
                text: view.currentMenu !== "" ? ("› " + view.menuLabel(view.currentMenu)) : "Buscar…"
                color: view.theme.sumi
                font.family: view.theme.mono; font.pixelSize: 13
            }
        }

        // gap + separador SOLO cuando el buscador está visible (colapsan a 0 en la raíz,
        // así no queda una línea suelta bajo el label ni choca con el hover del 1er ítem)
        Item { width: 1; height: searchBox.shown ? 7 : 0; Behavior on height { NumberAnimation { duration: 130 } } }
        Rectangle { width: parent.width; height: searchBox.shown ? 1 : 0; color: view.theme.sep }
        Item { width: 1; height: searchBox.shown ? 6 : 0; Behavior on height { NumberAnimation { duration: 130 } } }

        Flickable {
            id: listFlick
            width: parent.width
            height: Math.min(itemCol.implicitHeight, view.maxListHeight)
            contentHeight: itemCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            Column {
                id: itemCol
                width: parent.width
                spacing: 2

                Repeater {
                    model: { var _t = view.displayTick; return view.displayItems }
                    delegate: Item {
                        id: genItem
                        required property var modelData
                        required property int index
                        readonly property bool hot: index === (view.hoverIdx >= 0 ? view.hoverIdx : view.selIdx)
                        readonly property bool showSep: modelData.sep === true && searchInput.text === ""
                        width: itemCol.width
                        height: (showSep ? 9 : 0) + 36

                        Rectangle {
                            visible: genItem.showSep
                            width: parent.width; height: 1; y: 4
                            color: view.theme.sep
                        }

                        Rectangle {
                            width: parent.width; height: 36; radius: view.theme.tileRadius
                            anchors.bottom: parent.bottom
                            color: genItem.hot ? view.theme.fillHover : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }

                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left; anchors.leftMargin: 8
                                spacing: 10
                                Text {
                                    width: 22; text: genItem.modelData.icon
                                    color: genItem.hot || genItem.modelData.danger === true ? view.theme.seal : view.theme.ink
                                    font.family: genItem.modelData.iconFont !== undefined
                                                 ? genItem.modelData.iconFont : view.theme.mono
                                    font.pixelSize: genItem.modelData.iconSize !== undefined
                                                    ? genItem.modelData.iconSize : 17
                                    horizontalAlignment: Text.AlignHCenter
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: genItem.modelData.label
                                    color: genItem.hot ? view.theme.seal : view.theme.ink
                                    font.family: view.theme.mono; font.pixelSize: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Text {
                                anchors.right: parent.right; anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: "›"; color: view.theme.sumi; font.pixelSize: 14
                                visible: view.hasSubmenu(genItem.modelData.key)
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onEntered: view.hoverIdx = genItem.index
                                onExited: if (view.hoverIdx === genItem.index) view.hoverIdx = -1
                                onClicked: view.activateIndex(genItem.index)
                            }
                        }
                    }
                }
            }

            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: function(e) {
                    var maxY = Math.max(0, listFlick.contentHeight - listFlick.height)
                    listFlick.contentY = Math.max(0, Math.min(maxY, listFlick.contentY - e.angleDelta.y))
                }
            }
        }
    }
}
