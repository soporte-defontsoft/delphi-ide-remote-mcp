# -*- coding: utf-8 -*-
"""Release gate (hermes' P0.2): ONE command that refuses to bless a release
unless every version source agrees, the full regression is green, and the
artifact is packaged with its SHA-256.

Verifies, in order:
  1. SERVER_VERSION (src/Lsp.Texts.pas) == CHANGELOG newest entry;
  2. the .dproj VerInfo FileVersion/ProductVersion match (X.Y.0.0 for
     vX.Y.0-beta) and VerInfo is enabled for Windows builds;
  3. the built exe EMBEDS that version (read via the Windows version API);
  4. docs/CAPABILITIES.json is coherent (count == list length);
  5. the full regression (tests/run_all.py) ends with 0 failures;
  6. packages DelphiLspMcp-v<version>-win64.zip and prints its SHA-256.

Writes release-check.json next to the zip with everything a publisher (or a
verifying agent) needs: version, commit, checks, artifact, sha256.

Usage:  python tests/release_check.py [--skip-regression]
"""
import ctypes, hashlib, json, os, re, subprocess, sys, zipfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
OUT = os.path.join(REPO, 'release-out')

fails = []


def check(name, ok, detail=''):
    print(('PASS ' if ok else 'FAIL ') + name + ('' if ok else ' -- %s' % detail))
    if not ok:
        fails.append(name)


# 1) SERVER_VERSION vs CHANGELOG
texts = open(os.path.join(REPO, 'src', 'Lsp.Texts.pas'), encoding='utf-8').read()
ver = re.search(r"SERVER_VERSION = '([^']+)'", texts).group(1)
ch = open(os.path.join(REPO, 'CHANGELOG.md'), encoding='utf-8').read()
head = re.search(r'^## \[([^\]]+)\] - ', ch, re.M).group(1)
check('SERVER_VERSION == CHANGELOG head (%s)' % ver, ver == head, head)

m = re.match(r'^(\d+)\.(\d+)\.(\d+)', ver)
winver = '%s.%s.%s.0' % m.groups()

# 2) .dproj VerInfo
dproj = open(os.path.join(REPO, 'src', 'DelphiLspMcp.dproj'), encoding='utf-8').read()
check('.dproj FileVersion == %s' % winver,
      ('FileVersion=%s;' % winver) in dproj and ('ProductVersion=%s' % winver) in dproj,
      re.search(r'FileVersion=([\d.]+)', dproj).group(1))
check('.dproj embeds VERSIONINFO for Windows',
      dproj.count('<VerInfo_IncludeVerInfo>true</VerInfo_IncludeVerInfo>') >= 3)

# 3) built exe embeds it
exe = os.path.join(REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')
check('built exe exists', os.path.exists(exe), exe)


def exe_version(path):
    size = ctypes.windll.version.GetFileVersionInfoSizeW(path, None)
    if not size:
        return ''
    data = ctypes.create_string_buffer(size)
    ctypes.windll.version.GetFileVersionInfoW(path, 0, size, data)
    val = ctypes.c_void_p()
    vlen = ctypes.c_uint()
    if not ctypes.windll.version.VerQueryValueW(data, '\\', ctypes.byref(val), ctypes.byref(vlen)):
        return ''
    class VSFI(ctypes.Structure):
        _fields_ = [('Signature', ctypes.c_uint32), ('StrucVersion', ctypes.c_uint32),
                    ('MS', ctypes.c_uint32), ('LS', ctypes.c_uint32)] + \
                   [('r%d' % i, ctypes.c_uint32) for i in range(9)]
    fi = ctypes.cast(val, ctypes.POINTER(VSFI)).contents
    return '%d.%d.%d.%d' % (fi.MS >> 16, fi.MS & 0xFFFF, fi.LS >> 16, fi.LS & 0xFFFF)


ev = exe_version(exe) if os.path.exists(exe) else ''
check('exe VERSIONINFO == %s' % winver, ev == winver, ev or '(sin VERSIONINFO)')

# 4) CAPABILITIES coherent
cap = json.load(open(os.path.join(REPO, 'docs', 'CAPABILITIES.json'), encoding='utf-8'))
check('CAPABILITIES coherent', cap.get('tools') == len(cap.get('toolNames', [])), cap.get('tools'))

# 5) full regression
if '--skip-regression' in sys.argv:
    print('SKIP regression (--skip-regression)')
    reg_line = 'SKIPPED'
else:
    r = subprocess.run([sys.executable, os.path.join(HERE, 'run_all.py')],
                       capture_output=True, text=True, encoding='utf-8', errors='replace')
    reg_line = (r.stdout or '').strip().splitlines()[-1] if r.stdout else ''
    check('regression green (%s)' % reg_line, r.returncode == 0 and '0 fallos' in reg_line,
          reg_line or r.stderr[-200:] if r.stderr else '')

# 6) package + sha256
commit = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=REPO, capture_output=True,
                        text=True).stdout.strip()
os.makedirs(OUT, exist_ok=True)
zip_name = 'DelphiLspMcp-v%s-win64.zip' % ver
zip_path = os.path.join(OUT, zip_name)
if os.path.exists(zip_path):
    os.remove(zip_path)
rel = os.path.join(REPO, 'src', 'Compiled', 'Win64', 'Release')
CONTENT = [
    (os.path.join(rel, 'DelphiLspMcp.exe'), 'DelphiLspMcp.exe'),
    (os.path.join(rel, 'DelphiLspMcpTray.exe'), 'DelphiLspMcpTray.exe'),
    (os.path.join(rel, 'DelphiStyleConvert.exe'), 'DelphiStyleConvert.exe'),
    (os.path.join(REPO, 'settings.example.ini'), 'settings.example.ini'),
    (os.path.join(REPO, 'runner', 'mcp-runner.py'), 'runner/mcp-runner.py'),
    (os.path.join(REPO, 'README.md'), 'README.md'),
    (os.path.join(REPO, 'CHANGELOG.md'), 'CHANGELOG.md'),
    (os.path.join(REPO, 'LICENSE'), 'LICENSE'),
]
with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as z:
    for src, arc in CONTENT:
        if os.path.exists(src):
            z.write(src, arc)
        else:
            check('artifact member exists: %s' % arc, False, src)
    for root, _dirs, files in os.walk(os.path.join(REPO, 'docs')):
        for f in files:
            full = os.path.join(root, f)
            z.write(full, 'docs/' + os.path.relpath(full, os.path.join(REPO, 'docs')).replace(os.sep, '/'))

sha = hashlib.sha256(open(zip_path, 'rb').read()).hexdigest()

summary = {
    'version': ver,
    'tag': 'v' + ver,
    'commit': commit,
    'date': time.strftime('%Y-%m-%d %H:%M:%S'),
    'regression': reg_line,
    'artifact': zip_name,
    'artifactBytes': os.path.getsize(zip_path),
    'sha256': sha,
    'checksFailed': fails,
    'ok': not fails,
}
json.dump(summary, open(os.path.join(OUT, 'release-check.json'), 'w', encoding='utf-8'), indent=2)

print()
print(json.dumps(summary, indent=2))
print('\n== release check: %s ==' % ('OK - listo para taggear y publicar' if not fails
                                     else 'FAILED (%d)' % len(fails)))
sys.exit(1 if fails else 0)
