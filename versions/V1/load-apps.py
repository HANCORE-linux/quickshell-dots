#!/usr/bin/env python3
import os, glob, configparser, re, sys, locale

home = os.path.expanduser('~')

# Locale para nombres traducidos: es_ES.UTF-8 → lang_country='es_ES', lang='es'
_raw_locale = (os.environ.get('LANG') or os.environ.get('LC_ALL') or 'en').split('.')[0]
_lang_country = _raw_locale          # e.g. 'es_ES'
_lang         = _raw_locale.split('_')[0]  # e.g. 'es'

def localized_name(entry) -> str:
    """Returns Name[lang_country] > Name[lang] > Name, empty string if missing."""
    return (entry.get(f'Name[{_lang_country}]') or
            entry.get(f'Name[{_lang}]') or
            entry.get('Name', ''))
CACHE = home + '/.cache/quickshell-launcher-apps'

# ── Cache validity check ──
def cache_valid():
    if not os.path.exists(CACHE):
        return False
    ct = os.path.getmtime(CACHE)
    dirs = ['/usr/share/applications', home + '/.local/share/applications']
    for d in dirs:
        if not os.path.isdir(d):
            continue
        if os.path.getmtime(d) > ct:
            return False
        for f in glob.glob(d + '/*.desktop'):
            if os.path.getmtime(f) > ct:
                return False
    # also invalidate if icon theme changed
    try:
        theme_file = home + '/.config/omarchy/current/theme/icons.theme'
        if os.path.getmtime(theme_file) > ct:
            return False
    except:
        pass
    return True

if '--force' not in sys.argv and cache_valid():
    with open(CACHE) as f:
        print(f.read(), end='')
    sys.exit(0)

# ── Build icon index ──
try:
    with open(home + '/.config/omarchy/current/theme/icons.theme') as f:
        icon_theme = f.read().strip()
except:
    icon_theme = 'hicolor'

icon_index = {}
local_icons   = home + '/.local/share/icons'
flatpak_icons = home + '/.local/share/flatpak/exports/share/icons'
priority = [f'/usr/share/icons/{icon_theme}', '/usr/share/icons/hicolor',
            local_icons + f'/{icon_theme}', local_icons + '/hicolor',
            flatpak_icons + '/hicolor']
others = []
for icons_root in ['/usr/share/icons', local_icons, flatpak_icons]:
    if not os.path.isdir(icons_root):
        continue
    for d in os.listdir(icons_root):
        p = os.path.join(icons_root, d)
        if os.path.isdir(p) and p not in priority:
            others.append(p)
for base in priority + others:
    for rd, _, files in os.walk(base):
        for fname in files:
            stem, ext = os.path.splitext(fname)
            if ext.lower() in ('.svg', '.png') and stem not in icon_index:
                icon_index[stem] = os.path.join(rd, fname)

for fname in glob.glob('/usr/share/pixmaps/*'):
    stem = os.path.splitext(os.path.basename(fname))[0]
    if stem not in icon_index:
        icon_index[stem] = fname

def resolve_icon(name):
    if not name:
        return ''
    if os.path.isabs(name) and os.path.exists(name):
        return 'file://' + name
    return 'file://' + icon_index[name] if name in icon_index else ''

# ── Parse desktop entries ──
paths = (glob.glob('/usr/share/applications/*.desktop') +
         glob.glob(home + '/.local/share/applications/*.desktop'))

seen, apps = set(), []
for p in sorted(set(paths)):
    c = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        c.read(p, encoding='utf-8')
        if 'Desktop Entry' not in c:
            continue
        e = c['Desktop Entry']
        if e.get('Type') != 'Application':
            continue
        if e.get('NoDisplay', '').lower() == 'true':
            continue
        if e.get('Hidden', '').lower() == 'true':
            continue
        name  = localized_name(e)
        icon_n = e.get('Icon', '')
        exec_  = e.get('Exec', '').strip()
        if not name or not exec_ or name in seen:
            continue
        seen.add(name)
        exec_c = re.sub(r'%[fFuUdDnNickvm]', '', exec_).strip()
        apps.append(name + '||' + resolve_icon(icon_n) + '||' + exec_c)
    except:
        pass

output = '\n'.join(sorted(apps, key=lambda x: x.lower()))

# ── Save cache ──
try:
    with open(CACHE, 'w') as f:
        f.write(output)
except:
    pass

print(output)
