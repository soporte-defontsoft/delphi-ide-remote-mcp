"""Docs-vs-reality battery (v0.50.0-beta): the numbers the docs claim must
match what tools/list actually returns. Field 2026-08-24: an external review
found the README still saying 29/28 tools while the server registered 36 -
not a server bug, but it paints the project wrong. This battery makes that
drift a test failure.

Checks:
  - every "N tools" / "N core tools" / "the other N" figure in README.md;
  - every tool has its "### `name`" section in docs/TOOLS.md, and none extra;
  - docs/CAPABILITIES.json (the generated manifest) matches tools/list.

Usage:  python tests/test_docs_consistency.py [path-to-DelphiLspMcp.exe]
"""
import json, os, re
import mcp_cliente as mc
from mcp_cliente import check

REPO = mc.REPO
BASE = mc.carpeta('docscheck')
EXE = mc.copia_exe(BASE)
VAULT = os.path.join(BASE, 'vault'); os.makedirs(VAULT)
open(os.path.join(VAULT, 'MEMORY.md'), 'w').write('# MEMORY\n')

env = mc.entorno({'DELPHI_MCP_ROOTS': BASE, 'DELPHI_MCP_VAULT_PATH': VAULT,
                  'DELPHI_MCP_VAULT_READONLY': '0'})  # full surface: the 3 write tools too   # vault tools registered: FULL surface
srv = mc.Stdio(EXE, env, nombre='docs', t=60)
resp = srv.request('tools/list', {})
TOOLS = sorted(t['name'] for t in resp['result']['tools'])
# la tabla de tareas de delphi_help, la primera llamada que el manual pide
TAREAS = srv.call('delphi_help', {'command': 'tasks'})
srv.mata()

TOTAL = len(TOOLS)
VAULT_TOOLS = sorted(t for t in TOOLS if t.startswith('vault_'))
CORE = TOTAL - len(VAULT_TOOLS)
LSP_BACKED = ['delphi_symbols', 'delphi_definition', 'delphi_hover',
              'delphi_completion', 'delphi_signature', 'delphi_diagnostics',
              'delphi_references', 'delphi_rename_symbol']
NON_LSP_CORE = CORE - len(LSP_BACKED)

check('tools/list responde', TOTAL > 0, TOTAL)
check('las LSP-backed existen todas', all(t in TOOLS for t in LSP_BACKED),
      [t for t in LSP_BACKED if t not in TOOLS])

# ---- delphi_help tasks (1.10.0) -----------------------------------------
# Cada tool del servidor sale en la tabla de tareas: una tool que no esta ahi
# no la encuentra el agente que empieza por donde el manual le dice. Se
# comprobaba solo para delphi_docs, a mano; asi vale para la siguiente
fuera = [t for t in TOOLS if not re.search(r'\b%s\b' % re.escape(t), TAREAS)]
check('delphi_help tasks nombra TODAS las tools de tools/list',
      mc.abre(TAREAS, 'SN_HELP_TASKS') and not fuera, fuera or TAREAS[:200])

# ---- README ------------------------------------------------------------
readme = open(os.path.join(REPO, 'README.md'), encoding='utf-8').read()
for m in re.finditer(r'\b(\d+) tools\b', readme):
    n = int(m.group(1))
    check('README "%d tools" == %d reales' % (n, TOTAL), n == TOTAL,
          readme[max(0, m.start() - 60):m.end() + 20])
for m in re.finditer(r'\b(\d+) core tools\b', readme):
    n = int(m.group(1))
    check('README "%d core tools" == %d' % (n, CORE), n == CORE,
          readme[max(0, m.start() - 60):m.end() + 20])
for m in re.finditer(r'the other (\d+)\b', readme):
    n = int(m.group(1))
    ok = n in (TOTAL - len(LSP_BACKED), NON_LSP_CORE)
    check('README "the other %d" cuadra (no-LSP: %d con vault, %d core)' %
          (n, TOTAL - len(LSP_BACKED), NON_LSP_CORE), ok,
          readme[max(0, m.start() - 60):m.end() + 20])
check('README nombra los 5 vault_* como opcionales',
      '5 optional `vault_*`' in readme and len(VAULT_TOOLS) == 5, VAULT_TOOLS)

# ---- TOOLS.md ----------------------------------------------------------
toolsmd = open(os.path.join(REPO, 'docs', 'TOOLS.md'), encoding='utf-8').read()
documented = sorted(set(re.findall(r'^### `([a-z_]+)`', toolsmd, re.M)))
missing = [t for t in TOOLS if t not in documented]
extra = [t for t in documented if t not in TOOLS]
check('TOOLS.md documenta TODAS las tools', not missing, missing)
check('TOOLS.md no documenta tools inexistentes', not extra, extra)
# ...y el CONTRATO de cada una (description + tabla de parametros) es el bloque
# que genera scripts/tools_md.py desde tools/list: medido el 28-sep-2026, a
# mano, 35 de 41 descripciones y 127 parametros decian otra cosa que el
# servidor y 4 parametros faltaban, sin que ninguna bateria lo viera
import sys
sys.path.insert(0, os.path.join(REPO, 'scripts'))
import tools_md
TOOLS_FULL = resp['result']['tools']
sin_bloque = [t['name'] for t in TOOLS_FULL if tools_md.bloque_en(toolsmd, t['name']) is None]
check('TOOLS.md: cada tool tiene su bloque de contrato generado (scripts/tools_md.py)',
      not sin_bloque, sin_bloque)
drift = [t['name'] for t in TOOLS_FULL
         if tools_md.bloque_en(toolsmd, t['name']) not in (None, tools_md.render(t))]
check('TOOLS.md: ningun bloque de contrato difiere del tools/list vivo (python scripts/tools_md.py)',
      not drift, drift)

# ---- CAPABILITIES.json -------------------------------------------------
cap_path = os.path.join(REPO, 'docs', 'CAPABILITIES.json')
check('docs/CAPABILITIES.json existe', os.path.exists(cap_path))
if os.path.exists(cap_path):
    cap = json.load(open(cap_path, encoding='utf-8'))
    check('manifest: total', cap.get('tools') == TOTAL, cap.get('tools'))
    check('manifest: lista identica a tools/list',
          sorted(cap.get('toolNames', [])) == TOOLS,
          [t for t in TOOLS if t not in cap.get('toolNames', [])])
    check('manifest: core/optional', cap.get('coreTools') == CORE and
          cap.get('optionalTools') == len(VAULT_TOOLS), cap)
    check('manifest: lspBacked', sorted(cap.get('lspBacked', [])) == sorted(LSP_BACKED), cap.get('lspBacked'))
    # el mapa access del manifiesto es el anuncio vivo (nadie lo media; r11c H7)
    vivo = {t['name']: (t.get('_meta') or {}).get('access') for t in resp['result']['tools']}
    check('manifest: access == _meta.access de tools/list', cap.get('access') == vivo,
          [k for k in vivo if cap.get('access', {}).get(k) != vivo[k]])

mc.fin('docs consistency')
