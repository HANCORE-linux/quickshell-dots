.pragma library

// WANTED is the single source of truth for which raw colors.toml keys map
// onto this shell's semantic slots. Both the startup FileView read and the
// IPC push path translate through it.
const WANTED = {
    background: "paper",
    foreground: "ink",
    color7:     "inkDeep",
    color8:     "sumi",
    accent:     "indigo",
    color1:     "sealRaw",
};

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
    for (const key in WANTED) {
        if (raw[key]) out[WANTED[key]] = raw[key];
    }
    return out;
}

function parse(text) {
    return mapKeys(parseAll(text));
}

// Write a parsed palette onto a Theme.qml instance. Missing slots are left
// at their current value so a partial palette never blanks the live theme.
function apply(theme, palette) {
    if (palette.paper)   theme.paper   = palette.paper;
    if (palette.ink)     theme.ink     = palette.ink;
    if (palette.inkDeep) theme.inkDeep = palette.inkDeep;
    if (palette.sumi)    theme.sumi    = palette.sumi;
    if (palette.indigo)  theme.indigo  = palette.indigo;
    if (palette.sealRaw) theme.sealRaw = palette.sealRaw;
}
