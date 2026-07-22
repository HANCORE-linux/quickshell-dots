.pragma library

// WANTED is the single source of truth for which raw colors.toml keys map
// onto this shell's semantic slots. Legacy Omarchy colorN keys intentionally
// come first so mixed files keep the old values stable.
const WANTED = [
    { target: "paper",      keys: ["background", "bg"] },
    { target: "ink",        keys: ["foreground", "fg"] },
    { target: "color01",    keys: ["color1", "red"] },
    { target: "color02",    keys: ["color2", "green"] },
    { target: "color03",    keys: ["color3", "yellow"] },
    { target: "color04",    keys: ["color4", "blue"] },
    { target: "color05",    keys: ["color5", "magenta"] },
    { target: "color06",    keys: ["color6", "cyan"] },
    { target: "color07",    keys: ["color7", "bright_fg", "light_fg"] },
    { target: "sumi",       keys: ["color8", "muted", "dark_fg"] },
    { target: "accentHint", keys: ["accent"] },
];

const LINE = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]+)"/;

function parseAll(text) {
    const out = {};
    if (!text) return out;
    const lines = text.split("\n");
    for (let i = 0; i < lines.length; i++) {
        const m = lines[i].match(LINE);
        if (m) out[m[1].toLowerCase()] = m[2];
    }
    return out;
}

function mapKeys(raw) {
    const out = {};
    if (!raw) return out;
    for (let i = 0; i < WANTED.length; i++) {
        const group = WANTED[i];
        for (let j = 0; j < group.keys.length; j++) {
            const value = raw[group.keys[j]];
            if (validColor(value)) {
                out[group.target] = value;
                break;
            }
        }
    }
    return out;
}

function parse(text) {
    return mapKeys(parseAll(text));
}

function validColor(value) {
    return typeof value === "string" && /^#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/.test(value);
}

function setColor(theme, key, value) {
    if (validColor(value)) theme[key] = value;
}

// Write a parsed palette onto a Theme.qml instance. Missing slots are left
// at their current value so a partial or malformed palette never blanks the
// live theme. Omarchy colors.toml values used by this shell are #RRGGBB; accept
// #RRGGBBAA too for forward-compatible alpha colours.
function apply(theme, palette) {
    if (!palette) return;
    setColor(theme, "paper",      palette.paper);
    setColor(theme, "ink",        palette.ink);
    setColor(theme, "sumi",       palette.sumi);
    setColor(theme, "color01",    palette.color01);
    setColor(theme, "color02",    palette.color02);
    setColor(theme, "color03",    palette.color03);
    setColor(theme, "color04",    palette.color04);
    setColor(theme, "color05",    palette.color05);
    setColor(theme, "color06",    palette.color06);
    setColor(theme, "color07",    palette.color07);
    setColor(theme, "accentHint", palette.accentHint);
}
