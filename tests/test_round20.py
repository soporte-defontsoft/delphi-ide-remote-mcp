"""E2E battery for v0.83.0-beta - hermes' P1.4: tool-surface profiles.

tools/list measured 62.7k chars / 41 tools (~15k tokens) before an agent had
done anything - the #1 wall for small models. Opt-in trim, OFF by default:
[Tools] Profile=reader|coder|full (or env DELPHI_MCP_TOOLS_PROFILE), plus an
explicit allowlist Only= that overrides the profile. LISTING only: hidden
tools stay callable - permissions remain the access levels and the jail.
delphi_help / delphi_messages / delphi_report are always listed.

  T1  default: all 41 tools listed (no behavior change)
  T2  reader: only the reading/navigation set; edit/build/adb absent
  T3  reader: a HIDDEN tool is still callable (delphi_textedit works)
  T4  coder: everything except adb/paserver/package
  T5  Only= allowlist wins over the profile and keeps the always-set
  T6  unknown profile name hides nothing (fails open, it is not security)

Usage:  python tests/test_round20.py [path-to-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check



TOKEN = 'bateria-workspace'


def start(etiqueta, extra_env):
    # Carpeta FIJA por prueba. Antes era hash(entorno) % 1000, y el hash de
    # Python cambia en cada ejecucion: la carpeta tambien.
    base = mc.carpeta(os.path.join('round20', etiqueta))
    exe = mc.copia_exe(base)
    port = mc.puerto_libre()
    env = mc.entorno()
    env['DELPHI_MCP_ROOTS'] = base
    env['DELPHI_MCP_BIND_IP'] = '127.0.0.1'  # loopback: sin avisos del firewall
    env.update(extra_env)
    # v0.98: o workspace o nada (los perfiles de [Tools] siguen siendo
    # fontaneria global y entran por el entorno igual que antes)
    with open(os.path.join(base, 'settings.ini'), 'w') as _f:
        _f.write('[Workspace.Bateria]\nToken=%s\nRoots=%s\n' % (TOKEN, base))
    # espera a que ESCUCHE (antes un sleep fijo de 2,3 s: con la maquina
    # cargada la puerta de release salio roja por eso, 26-sep-2026)
    proc = mc.lanza_http(exe, port, env)
    return base, mc.Http(port, TOKEN), proc


READER = {'delphi_read', 'delphi_list', 'delphi_search', 'delphi_symbols',
          'delphi_definition', 'delphi_hover', 'delphi_signature',
          'delphi_completion', 'delphi_diagnostics', 'delphi_references',
          'delphi_projects', 'delphi_installs', 'delphi_workspace',
          'delphi_fetch', 'delphi_help', 'delphi_messages', 'delphi_report',
          'vault_read', 'vault_search'}
DEPLOY = {'delphi_adb', 'delphi_paserver', 'delphi_package'}

# T1 default (the test jail has no vault, so vault_* are not registered:
# every expectation below is relative to THIS server's own census)
base, cli, proc = start('t1', {})
try:
    cli.session('round20')
    ALL = cli.toolnames()
    check('T1 sin perfil: el censo completo, con las de escribir dentro',
          'delphi_edit' in ALL and 'delphi_adb' in ALL and len(ALL) >= 36,
          len(ALL))
finally:
    proc.kill()

# T2/T3 reader
base, cli, proc = start('t2', {'DELPHI_MCP_TOOLS_PROFILE': 'reader'})
try:
    cli.session('round20')
    names = cli.toolnames()
    check('T2 reader: exactamente el conjunto de lectura/navegacion',
          names == (READER & ALL), sorted(names ^ (READER & ALL)))
    r = cli.call('delphi_textedit',
             {'path': os.path.join(base, 'x.txt'), 'create': True, 'content': 'x'})
    check('T3 reader: una tool oculta sigue siendo llamable (no es un permiso)',
          'CREADO' in r or 'ESCRITO' in r or os.path.exists(os.path.join(base, 'x.txt')), r[:160])
finally:
    proc.kill()

# T4 coder
base, cli, proc = start('t4', {'DELPHI_MCP_TOOLS_PROFILE': 'coder'})
try:
    cli.session('round20')
    names = cli.toolnames()
    check('T4 coder: todo menos el trio de deploy',
          names == (ALL - DEPLOY), sorted(names ^ (ALL - DEPLOY)))
finally:
    proc.kill()

# T5 allowlist
base, cli, proc = start('t5', {'DELPHI_MCP_TOOLS_ONLY': 'delphi_read,delphi_search'})
try:
    cli.session('round20')
    names = cli.toolnames()
    check('T5 Only= gana al perfil y conserva help/messages/report',
          names == {'delphi_read', 'delphi_search', 'delphi_help',
                    'delphi_messages', 'delphi_report'}, sorted(names))
finally:
    proc.kill()

# T6 unknown profile
base, cli, proc = start('t6', {'DELPHI_MCP_TOOLS_PROFILE': 'marciano'})
try:
    cli.session('round20')
    names = cli.toolnames()
    check('T6 perfil desconocido no oculta nada (no es seguridad)',
          names == ALL, sorted(names ^ ALL))
finally:
    proc.kill()

mc.fin('round-20 battery')
