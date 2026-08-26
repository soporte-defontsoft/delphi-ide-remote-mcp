# -*- coding: utf-8 -*-
"""Static docs gate - NO server executable needed (hermes' P2.10: the old
docs battery mixed static checks with launching the EXE, so a Linux CI box
failed before checking a single doc).

The tool census comes from docs/CAPABILITIES.json (the generated manifest).
The LIVE battery (test_docs_consistency.py) keeps proving that the manifest
matches the real tools/list of the built exe; this one proves the DOCS match
the manifest, and it runs anywhere Python runs:

  - every "N tools" / "N core tools" / "the other N" figure in README.md;
  - every manifest tool has its section in docs/TOOLS.md, and none extra;
  - CHANGELOG's newest entry matches src/Lsp.Texts.pas SERVER_VERSION;
  - tests/ compiles without SyntaxWarnings (Python 3.12+ escape hygiene).

Usage:  python tests/test_docs_static.py
"""
import json, os, re, sys, glob, warnings, py_compile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))

P = F = 0


def check(name, ok, detail=''):
    global P, F
    if ok:
        P += 1
        print('PASS', name)
    else:
        F += 1
        print('FAIL', name, '--', str(detail)[:300])


cap_path = os.path.join(REPO, 'docs', 'CAPABILITIES.json')
check('docs/CAPABILITIES.json existe', os.path.exists(cap_path))
if not os.path.exists(cap_path):
    print('\n== docs static: %d PASS / %d FAIL ==' % (P, F))
    sys.exit(1)

cap = json.load(open(cap_path, encoding='utf-8'))
TOOLS = sorted(cap.get('toolNames', []))
TOTAL = len(TOOLS)
VAULT_TOOLS = sorted(t for t in TOOLS if t.startswith('vault_'))
CORE = TOTAL - len(VAULT_TOOLS)
LSP_BACKED = sorted(cap.get('lspBacked', []))
NON_LSP_CORE = CORE - len(LSP_BACKED)

check('manifest coherente consigo mismo',
      cap.get('tools') == TOTAL and cap.get('coreTools') == CORE and
      cap.get('optionalTools') == len(VAULT_TOOLS),
      {k: cap.get(k) for k in ('tools', 'coreTools', 'optionalTools')})

# ---- README ------------------------------------------------------------
readme = open(os.path.join(REPO, 'README.md'), encoding='utf-8').read()
for m in re.finditer(r'\b(\d+) tools\b', readme):
    n = int(m.group(1))
    check('README "%d tools" == %d del manifest' % (n, TOTAL), n == TOTAL,
          readme[max(0, m.start() - 60):m.end() + 20])
for m in re.finditer(r'\b(\d+) core tools\b', readme):
    n = int(m.group(1))
    check('README "%d core tools" == %d' % (n, CORE), n == CORE,
          readme[max(0, m.start() - 60):m.end() + 20])
for m in re.finditer(r'the other (\d+)\b', readme):
    n = int(m.group(1))
    ok = n in (TOTAL - len(LSP_BACKED), NON_LSP_CORE)
    check('README "the other %d" cuadra' % n, ok,
          readme[max(0, m.start() - 60):m.end() + 20])
check('README nombra los 5 vault_* como opcionales',
      '5 optional `vault_*`' in readme and len(VAULT_TOOLS) == 5, VAULT_TOOLS)

# ---- TOOLS.md ----------------------------------------------------------
toolsmd = open(os.path.join(REPO, 'docs', 'TOOLS.md'), encoding='utf-8').read()
documented = sorted(set(re.findall(r'^### `([a-z_]+)`', toolsmd, re.M)))
missing = [t for t in TOOLS if t not in documented]
extra = [t for t in documented if t not in TOOLS]
check('TOOLS.md documenta TODAS las tools del manifest', not missing, missing)
check('TOOLS.md no documenta tools inexistentes', not extra, extra)

# ---- CHANGELOG vs SERVER_VERSION ---------------------------------------
texts = open(os.path.join(REPO, 'src', 'Lsp.Texts.pas'), encoding='utf-8').read()
mv = re.search(r"SERVER_VERSION = '([^']+)'", texts)
ch = open(os.path.join(REPO, 'CHANGELOG.md'), encoding='utf-8').read()
mc = re.search(r'^## \[([^\]]+)\] - ', ch, re.M)
check('CHANGELOG mas reciente == SERVER_VERSION (%s)' % (mv and mv.group(1)),
      bool(mv and mc) and mv.group(1) == mc.group(1),
      (mv and mv.group(1), mc and mc.group(1)))

# ---- Python escape hygiene ---------------------------------------------
warnings.simplefilter('error', SyntaxWarning)
bad = []
for f in glob.glob(os.path.join(HERE, '*.py')):
    try:
        py_compile.compile(f, doraise=True)
    except Exception:
        bad.append(os.path.basename(f))
check('tests/ compila sin SyntaxWarnings', not bad, bad)

print('\n== docs static: %d PASS / %d FAIL ==' % (P, F))
sys.exit(1 if F else 0)
