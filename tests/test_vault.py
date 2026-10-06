"""E2E battery for the knowledge-vault tools (vault_search / vault_read /
vault_append / vault_create / vault_patch).

Builds a synthetic Obsidian-style vault in temp and drives the server against
it: lazy-loading bootstrap, jailed reads, the mechanical rule-11 backup before
every modification, the governance files being read-only, and the tools not
existing at all when no vault is configured.

Usage:  python tests/test_vault.py [path-to-DelphiLspMcp.exe]
"""
import json, os, glob, subprocess, zipfile
import mcp_cliente as mc
from mcp_cliente import check

# su propia copia del servidor (antes el compilado corria EN SU SITIO: logs y
# __delphi-temp en la carpeta de build), fuera del vault y de la jaula
SRV = mc.carpeta('vault-srv')
EXE = mc.copia_exe(SRV)

VAULT = mc.carpeta('vault')
# The vault lives in its OWN isolated folder, deliberately NOT inside the
# workspace roots: the two jails are independent.
WORK = mc.carpeta('vault-work')
with open(os.path.join(WORK, 'Codigo.pas'), 'wb') as f:
    f.write(b'unit Codigo;\r\ninterface\r\nimplementation\r\nend.\r\n')

def w(rel, text):
    p = os.path.join(VAULT, rel.replace('/', os.sep))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, 'wb') as f:                      # UTF-8, no BOM, like a vault
        f.write(text.encode('utf-8'))
    return p

# --- the synthetic vault ----------------------------------------------------
w('AGENTS-VAULT.md', '# Reglas del vault\n\n1. Carga perezosa.\n2. Backup antes de tocar.\n')
w('MEMORY.md', '# MEMORY\n\n- [Contexto Delphi](projects/delphi/context.md) - el proyecto MCP\n'
               '- [Convenciones](conventions/estilo.md) - como escribir codigo\n')
w('AGENTS-VAULT-WRITE.md', '# Como escribir\n\nArbol de decision y plantillas.\n')
w('projects/delphi/context.md',
  '# Contexto Delphi\n\nProyecto con acentos: compilacion, gestoria, accion.\n'
  'Enlaza a [[Convenciones]].\n\n## Estado\n\n- linea viva uno\n- linea viva dos\n')
w('projects/delphi/log.md', '# Bitacora\n\n- entrada antigua\n')
w('conventions/estilo.md', '# Estilo\n\nEscribe en espanol. UTF-8 siempre.\n')
# fuera de projects/, para que "subfolder acota" tenga algo que quitar
w('conventions/fuera.md', '# Fuera\n\n- linea viva de fuera\n')
# A CRLF note with accents and an em-dash: a vault edited on Windows looks like
# this, and it is what caught the stray-CR bug (LF-only fixtures hid it).
w('conventions/crlf.md',
  '# Convencion CRLF\r\n\r\n- Acentos: gestoria, accion, compilacion\r\n'
  '- Guion largo: memoria \u2014 indice\r\n- Ruta citada: D:\\Proyectos\\Algo\r\n')
w('backups/mcp/vieja/secreto.md', '# No es conocimiento\n\nEsto vive en backups.\n')
w('notas.bak.md', '# Copia rancia\n')
# a big note to exercise the MaxReadChars truncation (>100K chars)
w('projects/delphi/grande.md', '# Grande\n\n' + ('relleno de linea larga ' * 8 + '\n') * 700)

class Server(mc.Stdio):
    """One server instance with its own env (vault path / readonly / flags).
    Without a vault, DELPHI_MCP_VAULT_PATH is simply absent: mc.entorno()
    drops every DELPHI_MCP_* of whoever launches the battery."""
    def __init__(self, vault=VAULT, writable=True, extra_args=()):
        env = {'DELPHI_MCP_ROOTS': WORK,            # the code jail: a DIFFERENT folder
               'DELPHI_MCP_VAULT_READONLY': '0' if writable else '1'}
        if vault is not None:
            env['DELPHI_MCP_VAULT_PATH'] = vault
        super().__init__(EXE, mc.entorno(env), nombre='vault-battery', args=extra_args)
        # this battery looks at the initialize RESULT (instructions, capabilities)
        self.init = (self.init or {}).get('result', {})

    def rpc(self, method, params=None):
        return self.request(method, params or {}, 20) or {}

    def tools(self):
        r = self.request('tools/list', {}, 20)
        return [t['name'] for t in r['result']['tools']] if r else []

    def close(self):
        self.cierra(0)  # fin de stdin y a matar, sin esperar: como antes

# ===========================================================================
# 1. Registration: with a vault (read+write), and without one
# ===========================================================================
s = Server()
names = s.tools()
check('registro: las 5 tools de vault existen con VaultPath + VaultReadOnly=0',
      all(t in names for t in ('vault_search', 'vault_read', 'vault_append',
                               'vault_create', 'vault_patch')), names)

# ===========================================================================
# 1b. Session wiring: instructions on initialize + the invocable /vault prompt
# ===========================================================================
instr = s.init.get('instructions', '')
check('initialize: con vault, "instructions" trae el protocolo de arranque',
      'vault_read' in instr and instr.strip() == mc.catalogo()['SD_VAULT_INSTRUCTIONS'].strip(), instr[:200])
check('initialize: instructions es CORTO (viaja en cada prompt)',
      0 < len(instr) < 2000, len(instr))
check('initialize: declara la capability prompts',
      'prompts' in s.init.get('capabilities', {}), s.init.get('capabilities'))
pl = s.rpc('prompts/list').get('result', {}).get('prompts', [])
check('prompts/list: expone el prompt "vault"',
      any(p.get('name') == 'vault' for p in pl), pl)
pg = s.rpc('prompts/get', {"name": "vault"}).get('result', {})
ptxt = (pg.get('messages') or [{}])[0].get('content', {}).get('text', '')
check('prompts/get vault: devuelve reglas + indice',
      'AGENTS-VAULT.md' in ptxt and 'MEMORY.md' in ptxt and 'Carga perezosa' in ptxt,
      ptxt[:200])
bad = s.rpc('prompts/get', {"name": "no-existe"})
# -32602 con su etiqueta, como resources/read (era -32603 sin etiqueta: el
# check de antes, "hay error", pasaba con los dos)
check('prompts/get: un prompt desconocido da error',
      bad.get('error', {}).get('code') == -32602 and
      mc.abre(bad.get('error', {}).get('message', ''), 'SR_VAULT_PROMPT_NO_EXISTE_FMT'), bad)
bad = s.rpc('prompts/get', {})
check('prompts/get sin name: -32602 y dice que falta',
      bad.get('error', {}).get('code') == -32602 and
      mc.abre(bad.get('error', {}).get('message', ''), 'SR_SYS_MISSING_METHOD_PARAM_FMT'), bad)
bad = s.rpc('resources/read', {})
check('resources/read sin uri: -32602 y dice que falta',
      bad.get('error', {}).get('code') == -32602 and
      mc.abre(bad.get('error', {}).get('message', ''), 'SR_SYS_MISSING_METHOD_PARAM_FMT'), bad)

# a vault can override the instructions with its own "skill" file
w('VAULT-INSTRUCTIONS.md', 'Vault de PRUEBA: escribe siempre en espanol. '
                           'Arranca con vault_read sin path.')
s_own = Server()
own = s_own.init.get('instructions', '')
check('instructions: el VAULT-INSTRUCTIONS.md del vault MANDA sobre el generico',
      'Vault de PRUEBA' in own, own[:150])
s_own.close()
os.remove(os.path.join(VAULT, 'VAULT-INSTRUCTIONS.md'))

# ===========================================================================
# 1c. The vault is an ISOLATED folder, outside the workspace roots: the two
#     jails are independent, and neither reaches into the other.
# ===========================================================================
check('aislamiento: el vault esta FUERA del workspace de codigo',
      not VAULT.lower().startswith(WORK.lower()), (VAULT, WORK))
out = s.call('vault_read', {"path": "conventions/estilo.md"})
check('aislamiento: vault_read llega al vault aunque este fuera de los roots',
      'Estilo' in out, out[:150])
out = s.call('delphi_read', {"path": os.path.join(VAULT, 'MEMORY.md')})
check('aislamiento: las tools de CODIGO no pueden leer el vault',
      mc.rechazado(out) and mc.es(out, 'SR_VAULT_NOT_CODE'), out[:150])
out = s.call('vault_read', {"path": "Codigo.pas"})
check('aislamiento: las tools de VAULT no sirven codigo (.md only)',
      mc.rechazado(out) and mc.es(out, 'SR_VAULT_NOTA_MD_VAULT_SOLO_FMT'), out[:150])
out = s.call('delphi_read', {"path": os.path.join(WORK, 'Codigo.pas')})
check('aislamiento: el workspace de codigo sigue funcionando normal',
      'unit Codigo' in out, out[:120])

# ===========================================================================
# 2. Bootstrap: vault_read with NO path = rules + index
# ===========================================================================
out = s.call('vault_read', {})
check('bootstrap: sin path devuelve AGENTS-VAULT.md + MEMORY.md',
      'AGENTS-VAULT.md' in out and 'MEMORY.md' in out
      and 'Carga perezosa' in out and 'Contexto Delphi' in out, out[:200])

# ===========================================================================
# 3. Reading a note: numbering, offset/limit, accents, truncation
# ===========================================================================
out = s.call('vault_read', {"path": "projects/delphi/context.md"})
check('read: nota con numeros de linea', '1|# Contexto Delphi' in out, out[:150])
check('read: acentos/UTF-8 intactos', 'compilacion, gestoria, accion' in out, out[:200])
out = s.call('vault_read', {"path": "projects/delphi/context.md", "offset": 6, "limit": 2})
check('read: offset/limit acota', '6|' in out and '1|# Contexto' not in out, out[:200])
out = s.call('vault_read', {"path": "projects/delphi/grande.md"})
check('read: nota enorme PAGINADA con el offset exacto de continuacion',
      mc.es(out, 'SN_VAULT_MORE_FMT') and 'offset' in out, out[-220:])
check('read: la pagina cabe en el presupuesto por-resultado',
      len(out) < 75000, len(out))
# the continuation offset the server hands back must actually work
import re as _re
_m = _re.search(r'offset:\s*(\d+)', out)
if _m:
    nxt = int(_m.group(1))
    out2 = s.call('vault_read', {"path": "projects/delphi/grande.md", "offset": nxt})
    check('read: continuar con ese offset devuelve la linea siguiente',
          ('\n%d|' % nxt) in out2 or out2.startswith('%d|' % nxt) or ('%d|' % nxt) in out2,
          out2[:150])

# R8/R9: the BOOTSTRAP is served as WHOLE FILES - the same thing you get
# reading the vault locally. It never cuts a file in half; when rules + index
# do not fit together, the second is asked for by name.
out = s.call('vault_read', {})
check('R8: el arranque cabe en una respuesta', len(out) < 75000, len(out))
check('R9: el arranque NO va numerado (es documentacion, se lee entera)',
      '1|# ' not in out and 'Carga perezosa' in out, out[:150])
check('R9: el arranque trae los ficheros ENTEROS (no cortados a media linea)',
      open(os.path.join(VAULT, 'AGENTS-VAULT.md'), encoding='utf-8').read().strip() in out,
      out[:200])

# barra invertida y barra normal valen igual
out = s.call('vault_read', {"path": r"projects\delphi\log.md"})
check('read: acepta separador Windows', 'Bitacora' in out, out[:120])

# FIDELIDAD: una nota CRLF se sirve linea a linea, sin CR colgando, con los
# caracteres no-ASCII intactos y SIN enmascarar rutas (el texto se usa para
# construir anchors de vault_patch, y debe casar byte a byte con el disco).
out = s.call('vault_read', {"path": "conventions/crlf.md"})
# splitlines() consumes the OUTPUT's own line separator; whatever \r remains
# afterwards would be a stray CR carried over from the note content.
served = [l.split('|', 1)[1] for l in out.splitlines()
          if '|' in l and l.split('|')[0].strip().isdigit()]
check('CRLF: ninguna linea arrastra un CR', not any('\r' in l for l in served), served[:4])
check('CRLF: acentos y guion largo intactos',
      any('gestoria' in l for l in served) and any('\u2014' in l for l in served), served[:6])
disk_crlf = open(os.path.join(VAULT, 'conventions', 'crlf.md'), encoding='utf-8').read()
check('FIDELIDAD: cada linea servida existe TAL CUAL en el disco (anchors validos)',
      all(l in disk_crlf for l in served if l.strip()), served[:6])
check('FIDELIDAD: una ruta citada en la nota NO se enmascara (srvd:)',
      any('D:\\Proyectos\\Algo' in l for l in served), served[:6])

# ===========================================================================
# 4. Jail: no escapes, no non-md, no excluded folders
# ===========================================================================
for probe, label in ((r'..\..\Windows\System32\drivers\etc\hosts', 'escape con ..'),
                     (r'C:\Windows\win.ini', 'ruta absoluta'),
                     (r'..\otro-vault\x.md', 'salto a carpeta hermana')):
    out = s.call('vault_read', {"path": probe})
    check('jaula: %s rechazado' % label, mc.rechazado(out) and mc.es(out, 'SR_VAULT_JAIL'), out[:150])
out = s.call('vault_read', {"path": "conventions/estilo.txt"})
check('jaula: fichero que no es .md rechazado', mc.rechazado(out) and mc.es(out, 'SR_VAULT_NOTA_MD_VAULT_SOLO_FMT'), out[:150])
out = s.call('vault_read', {"path": "backups/mcp/vieja/secreto.md"})
check('exclusion: backups/ no es legible', mc.rechazado(out) and mc.es(out, 'SR_VAULT_ESTA_CARPETA_EXCLUIDA_BACKUPS_FMT'), out[:150])

# ===========================================================================
# 5. Search: files and content
# ===========================================================================
out = s.call('vault_search', {"target": "files", "pattern": "*.md"})
check('search files: encuentra notas del vault',
      'conventions\\estilo.md' in out or 'conventions/estilo.md' in out, out[:250])
check('search files: NO lista backups/ ni *.bak*',
      'secreto.md' not in out and 'notas.bak.md' not in out, out[:250])
out = s.call('vault_search', {"target": "files", "pattern": "*context*"})
check('search files: filtra por patron', 'context.md' in out and 'estilo.md' not in out, out[:200])
out = s.call('vault_search', {"target": "content", "pattern": "UTF-8"})
check('search content: ruta + linea + texto',
      'estilo.md' in out and ':' in out and 'UTF-8' in out, out[:200])
out = s.call('vault_search', {"target": "content", "pattern": "linea viva",
                              "subfolder": "projects"})
check('search content: subfolder acota', 'context.md' in out and 'fuera.md' not in out, out[:200])
out = s.call('vault_search', {"target": "content", "pattern": "no-existe-esto-xyz"})
check('search: sin resultados lo dice y recuerda el indice',
      mc.es(out, 'SN_VAULT_SIN_RESULTADOS_RECUERDA_INDICE_FMT'), out[:150])
out = s.call('vault_search', {"target": "files", "pattern": "[a-"})
check('search files: una mascara rota es INVALID_PARAM (salia INTERNAL)',
      mc.abre(out, 'SR_VAULT_PATTERN_MASCARA_INVALIDA_FMT') and mc.resultado(out) == 'INVALID_PARAM', out[:150])
# (revision de la 1.13.0) la expresion de content es del AGENTE (Lsp.Regex):
# una que agota los pasos del motor lo DICE, no "sin resultados" en
# silencio - el gemelo de delphi_search; y una mal escrita, antes de leer
with open(os.path.join(VAULT, 'conventions', 'aes.md'), 'w', encoding='utf-8') as f:
    f.write('# aes\n\n' + 'a' * 40 + 'b\n')
out = s.call('vault_search', {"target": "content", "pattern": "(a+)+$"})
check('search content: una regex que se dispara lo dice, con la nota y la linea (SEARCH-005)',
      mc.rechazado(out) and mc.tiene(out, 'SEARCH-005') and 'aes.md' in out, out[:300])
out = s.call('vault_search', {"target": "content", "pattern": "(sin cerrar"})
check('search content: una regex mal escrita es INVALID_PARAM',
      mc.abre(out, 'SR_VAULT_PATTERN_REGEX_INVALIDA_FMT') and mc.resultado(out) == 'INVALID_PARAM', out[:200])
os.remove(os.path.join(VAULT, 'conventions', 'aes.md'))
out = s.call('vault_search', {"target": "files", "pattern": "*.md", "subfolder": "../.."})
check('search: subfolder con .. rechazado', mc.rechazado(out) and mc.es(out, 'SR_VAULT_JAIL'), out[:150])

# ===========================================================================
# 6. Governance files are never writable
# ===========================================================================
for gov in ('MEMORY.md', 'AGENTS-VAULT.md', 'AGENTS-VAULT-WRITE.md'):
    out = s.call('vault_append', {"path": gov, "content": "- intruso\n"})
    check('gobierno: %s no se puede escribir' % gov,
          mc.rechazado(out) and mc.es(out, 'SR_VAULT_GOVERNANCE'), out[:150])
check('gobierno: MEMORY.md intacto en disco',
      'intruso' not in open(os.path.join(VAULT, 'MEMORY.md'), encoding='utf-8').read())

# R9 CRITICAL: Windows trims trailing/leading spaces and dots when opening, so
# "MEMORY.md " reached the REAL governance file while the check compared the
# untrimmed name. Every variant of the trick must be refused.
for probe, label in (('MEMORY.md ', 'espacio final'),
                     (' MEMORY.md', 'espacio inicial'),
                     ('MEMORY.md.', 'punto final'),
                     ('MEMORY.md  ', 'dos espacios'),
                     ('notas /idea.md', 'espacio en la carpeta')):
    out = s.call('vault_append', {"path": probe, "content": "- intruso\n"})
    check('R9 CRITICAL: gobierno/nombre con %s RECHAZADO' % label, mc.rechazado(out) and mc.es(out, 'SR_GUARD_NOMBRE_EMPIEZA_TERMINA_PUNTO_FMT'), out[:130])
check('R9 CRITICAL: ningun intruso llego a MEMORY.md',
      'intruso' not in open(os.path.join(VAULT, 'MEMORY.md'), encoding='utf-8').read())
for probe in ('MEMORY.md ', 'MEMORY.md.'):
    out = s.call('vault_create', {"path": probe, "content": "x"})
    check('R9: create con "%s" tambien RECHAZADO' % probe, mc.rechazado(out) and mc.es(out, 'SR_GUARD_NOMBRE_EMPIEZA_TERMINA_PUNTO_FMT'), out[:130])
out = s.call('vault_append', {"path": "backups/mcp/vieja/secreto.md", "content": "x"})
check('gobierno: escribir en backups/ rechazado', mc.rechazado(out) and mc.es(out, 'SR_VAULT_ESTA_CARPETA_EXCLUIDA_BACKUPS_FMT'), out[:150])

# ===========================================================================
# 7. vault_append (with and without anchor) + the mechanical backup
# ===========================================================================
LOG = os.path.join(VAULT, 'projects', 'delphi', 'log.md')
before = open(LOG, encoding='utf-8').read()
out = s.call('vault_append', {"path": "projects/delphi/log.md",
                              "content": "- entrada nueva con acentos: gestoria\n"})
check('append: sin anchor anade al final', mc.abre(out, 'SK_VAULT_ANADIDO_COPIA_PREVIA_FMT'), out[:200])
after = open(LOG, encoding='utf-8').read()
check('append: el contenido esta y lo viejo se conserva',
      'entrada nueva' in after and 'entrada antigua' in after, after[:200])
# una nota con el atributo de solo lectura: SYS-029 (salia SYS-028 "acceso
# denegado", y un agente lo tomaba por un permiso; octava revision)
RO_NOTA = os.path.join(VAULT, 'projects', 'delphi', 'ro.md')
open(RO_NOTA, 'w', encoding='utf-8').write('# fija\n')
os.chmod(RO_NOTA, 0o444)
try:
    out = s.call('vault_append', {"path": "projects/delphi/ro.md", "content": "- x\n"})
    check('append: una nota +R es SYS-029 y no se toca',
          mc.abre(out, 'SR_SOLO_LECTURA_ATRIBUTO_FMT') and
          open(RO_NOTA, encoding='utf-8').read() == '# fija\n', out[:200])
finally:
    os.chmod(RO_NOTA, 0o666)

bk = glob.glob(os.path.join(VAULT, 'backups', 'mcp', '*', 'projects', 'delphi', 'log.md'))
check('BACKUP (regla 11): copia previa creada en backups/mcp/<stamp>/', len(bk) == 1, bk)
if bk:
    check('BACKUP: la copia es IDENTICA al original antes del cambio',
          open(bk[0], encoding='utf-8').read() == before, 'difiere')

# anchor
out = s.call('vault_append', {"path": "projects/delphi/context.md",
                              "content": "- linea insertada", "anchor": "## Estado"})
check('append: con anchor inserta tras el ancla', mc.abre(out, 'SK_VAULT_ANADIDO_COPIA_PREVIA_FMT'), out[:200])
ctx = open(os.path.join(VAULT, 'projects', 'delphi', 'context.md'), encoding='utf-8').read()
check('append: la insercion va DESPUES del anchor y antes del resto',
      ctx.index('linea insertada') > ctx.index('## Estado')
      and ctx.index('linea insertada') < ctx.index('linea viva uno'), ctx[-250:])
out = s.call('vault_append', {"path": "projects/delphi/context.md",
                              "content": "x", "anchor": "no-existe-este-ancla"})
check('append: anchor inexistente da error claro', mc.resultado(out) in ('INVALID_PARAM', 'NOT_FOUND') and mc.es(out, 'SR_VAULT_ANCHOR_APARECE_NOTA_LEE'), out[:150])
out = s.call('vault_append', {"path": "projects/delphi/context.md",
                              "content": "x", "anchor": "linea viva"})
check('append: anchor duplicado se rechaza (pide uno unico)',
      mc.es(out, 'SR_VAULT_ANCHOR_APARECE_VARIAS_VECES'), out[:150])
out = s.call('vault_append', {"path": "projects/delphi/no-existe.md", "content": "x"})
check('append: nota inexistente redirige a vault_create',
      mc.resultado(out) in ('INVALID_PARAM', 'NOT_FOUND') and mc.es(out, 'SR_VAULT_NOTA_EXISTE_VAULT_APPEND_FMT') and 'vault_create' in out, out[:150])

# el fichero resultante sigue siendo UTF-8 sin BOM
raw = open(LOG, 'rb').read()
check('UTF-8: el fichero escrito NO lleva BOM', not raw.startswith(b'\xef\xbb\xbf'), raw[:6])
check('UTF-8: los acentos se guardaron como UTF-8', 'gestoria' in raw.decode('utf-8'), raw[:80])

# ===========================================================================
# 8. vault_create
# ===========================================================================
out = s.call('vault_create', {"path": "decisiones/nueva-decision.md",
                              "content": "# Decision\n\nProbamos el vault remoto.\n"})
check('create: crea la nota y recuerda enlazarla en el indice',
      mc.abre(out, 'SK_VAULT_CREADA_NOTA_RECUERDA_ENLAZARLA_FMT'), out[:200])
check('create: la nota existe en disco',
      os.path.exists(os.path.join(VAULT, 'decisiones', 'nueva-decision.md')))
out = s.call('vault_create', {"path": "decisiones/nueva-decision.md", "content": "# Otra\n"})
check('create: NUNCA sobreescribe una nota existente',
      mc.rechazado(out) and mc.es(out, 'SR_VAULT_NOTA_EXISTE_VAULT_CREATE_FMT'), out[:200])
check('create: el rechazo dejo la nota original intacta',
      'Probamos el vault remoto' in open(os.path.join(
          VAULT, 'decisiones', 'nueva-decision.md'), encoding='utf-8').read())

# ===========================================================================
# 9. vault_patch
# ===========================================================================
CTX = os.path.join(VAULT, 'projects', 'delphi', 'context.md')
before_ctx = open(CTX, encoding='utf-8').read()
out = s.call('vault_patch', {"path": "projects/delphi/context.md",
                             "old_text": "- linea viva dos", "new_text": "- linea viva DOS (cerrada)"})
check('patch: sustituye el fragmento unico', mc.abre(out, 'SN_VAULT_MODIFICADA_SUSTITUCION_COPIA_PREVIA_FMT'), out[:200])
check('patch: el cambio esta en disco',
      'linea viva DOS (cerrada)' in open(CTX, encoding='utf-8').read())
out = s.call('vault_patch', {"path": "projects/delphi/context.md",
                             "old_text": "texto-que-no-esta", "new_text": "x"})
check('patch: old_text ausente da error', mc.resultado(out) in ('INVALID_PARAM', 'NOT_FOUND') and mc.es(out, 'SR_VAULT_OLD_TEXT_APARECE_NOTA'), out[:150])
out = s.call('vault_patch', {"path": "projects/delphi/log.md",
                             "old_text": "\n", "new_text": "x"})
check('patch: old_text duplicado se rechaza', mc.es(out, 'SR_VAULT_OLD_TEXT_APARECE_VARIAS'), out[:150])

# decima revision: una nota CRLF con un old y un new de VARIAS lineas: el old
# llega con LF (asi lo manda un agente) y casaba solo de una linea; el new de
# varias lineas metia LF en la nota (Pos directo + VaultSave tal cual)
CRLFN = os.path.join(VAULT, 'conventions', 'crlf.md')
out = s.call('vault_patch', {"path": "conventions/crlf.md",
                             "old_text": "- Acentos: gestoria, accion, compilacion\n- Guion largo: memoria \u2014 indice",
                             "new_text": "- Acentos: gestoria, accion, compilacion\n- Linea nueva\n- Guion largo: memoria \u2014 indice"})
_b = open(CRLFN, 'rb').read()
check('patch CRLF: un old de dos lineas (con LF) casa en una nota CRLF',
      mc.abre(out, 'SN_VAULT_MODIFICADA_SUSTITUCION_COPIA_PREVIA_FMT'), out[:200])
check('patch CRLF: el new de varias lineas sale en CRLF, sin LF sueltos',
      b'- Linea nueva\r\n' in _b and _b.count(b'\n') == _b.count(b'\r\n'), _b)

# R9: a patch that empties the note is a DELETE, and there is no delete here
VACIA = os.path.join(VAULT, 'conventions', 'vaciable.md')
w('conventions/vaciable.md', '# Unica\n')
_todo = open(VACIA, encoding='utf-8').read()
out = s.call('vault_patch', {"path": "conventions/vaciable.md",
                             "old_text": _todo.strip(), "new_text": ""})
check('R9: patch que VACIARIA la nota rechazado', mc.rechazado(out) and mc.es(out, 'SR_VAULT_WOULD_EMPTY'), out[:150])
check('R9: la nota conserva su contenido',
      open(VACIA, encoding='utf-8').read().strip() != '', 'quedo vacia')

# ===========================================================================
# 10. Read-only vault (VaultReadOnly=1). Desde v0.98 el vault es del
# workspace ACTIVO, asi que las tools de escritura se registran igualmente
# (otro workspace del mismo servidor podria escribir); tools/list no las
# anuncia a quien no puede usarlas (6-oct-2026), y si las llama igual, CADA
# peticion se rechaza diciendo por que.
# ===========================================================================
s.close()
s2 = Server(writable=False)
names = s2.tools()
check('ReadOnly=1: vault_read/search SI se registran',
      'vault_read' in names and 'vault_search' in names, names)
check('ReadOnly=1: las de escritura NO se anuncian (solo rechazarian)',
      not any(t in names for t in ('vault_append', 'vault_create', 'vault_patch')), names)
out = s2.call('vault_append', {"path": "projects/delphi/log.md", "content": "- x\n"})
check('ReadOnly=1: vault_append rechazado (vault de solo lectura)',
      mc.rechazado(out) and mc.es(out, 'SR_VAULT_READONLY'), out[:200])
out = s2.call('vault_read', {"path": "conventions/estilo.md"})
check('ReadOnly=1: la lectura sigue funcionando', 'Estilo' in out, out[:120])
s2.close()

# ===========================================================================
# 11. Read-only CREDENTIAL: the gate refuses the write tools
# ===========================================================================
s3 = Server(extra_args=['--readonly'])
out = s3.call('vault_append', {"path": "projects/delphi/log.md", "content": "- intruso\n"})
check('credencial RO: vault_append rechazado en la puerta',
      mc.es(out, 'SR_READ_ONLY_FMT'), out[:180])
out = s3.call('vault_create', {"path": "otra.md", "content": "x"})
check('credencial RO: vault_create rechazado en la puerta', mc.es(out, 'SR_READ_ONLY_FMT'), out[:180])
out = s3.call('vault_patch', {"path": "projects/delphi/log.md", "old_text": "a", "new_text": "b"})
check('credencial RO: vault_patch rechazado en la puerta', mc.es(out, 'SR_READ_ONLY_FMT'), out[:180])
out = s3.call('vault_read', {"path": "conventions/estilo.md"})
check('credencial RO: vault_read PERMITIDO (es lectura pura)', 'Estilo' in out, out[:120])
check('credencial RO: no se escribio nada',
      'intruso' not in open(LOG, encoding='utf-8').read())
s3.close()

# ===========================================================================
# 12. No vault configured: the tools do not exist at all
# ===========================================================================
s4 = Server(vault=None)
names = s4.tools()
check('sin vault: NINGUNA tool vault_* aparece en tools/list',
      not any(t.startswith('vault_') for t in names), [t for t in names if 'vault' in t])
check('sin vault: las tools de Delphi siguen ahi', 'delphi_read' in names, names[:5])
check('sin vault: initialize NO trae instructions de vault',
      'vault_read' not in s4.init.get('instructions', ''), s4.init.get('instructions', '')[:150])
check('sin vault: NO se declara la capability prompts',
      'prompts' not in s4.init.get('capabilities', {}), s4.init.get('capabilities'))
_m4 = s4.rpc('prompts/list')
pl4 = _m4.get('result', {}).get('prompts', None)
# sin vault el metodo no existe (-32601) o no ofrece nada; un {} (no contesto) no vale
check('sin vault: prompts/list no ofrece el prompt vault',
      _m4.get('error', {}).get('code') == -32601 or pl4 == [], _m4)
s4.close()

# ===========================================================================
# 13. First run on a new machine: a configured path that does not exist yet is
#     SEEDED with the starter templates; an existing vault is never touched.
# ===========================================================================
FRESH = os.path.join(mc.RAIZ, 'vault-fresh')  # sin mc.carpeta(): NO debe existir
mc.borra(FRESH)
check('siembra: la carpeta no existe antes de arrancar', not os.path.exists(FRESH))
s5 = Server(vault=FRESH)
check('siembra: el server crea la carpeta del vault', os.path.isdir(FRESH), FRESH)
for f in ('AGENTS-VAULT.md', 'MEMORY.md', 'AGENTS-VAULT-WRITE.md', 'VAULT-INSTRUCTIONS.md'):
    check('siembra: crea %s' % f, os.path.exists(os.path.join(FRESH, f)))
check('siembra: crea el proyecto de ejemplo (context/progress/log)',
      all(os.path.exists(os.path.join(FRESH, 'projects', 'example-project', n))
          for n in ('context.md', 'progress.md', 'log.md')))
check('siembra: las tools de vault SI se registran sobre el vault recien creado',
      'vault_read' in s5.tools(), s5.tools())
out = s5.call('vault_read', {})
check('siembra: el bootstrap del vault nuevo ya devuelve reglas + indice',
      'Vault rules' in out and 'MEMORY' in out, out[:200])
seeded_raw = open(os.path.join(FRESH, 'MEMORY.md'), 'rb').read()
check('siembra: las plantillas se escriben en UTF-8 sin BOM',
      not seeded_raw.startswith(b'\xef\xbb\xbf'), seeded_raw[:6])
s5.close()

# second start over the SAME vault: must not re-seed nor touch anything
marker = os.path.join(FRESH, 'MEMORY.md')
with open(marker, 'ab') as f:
    f.write(b'\n- [Mi nota](mia.md) - editada por el usuario\n')
mine = open(marker, encoding='utf-8').read()
s6 = Server(vault=FRESH)
check('siembra: un vault YA existente no se vuelve a sembrar (no pisa MEMORY.md)',
      open(marker, encoding='utf-8').read() == mine, 'MEMORY.md fue modificado')
s6.close()
mc.borra(FRESH)

# ===========================================================================
# 14. The vault INSIDE a workspace root: it still belongs to the vault_* tools
#     alone. Otherwise delphi_edit could rewrite a note behind the vault's
#     back - no backup, and the governance files unprotected.
# ===========================================================================
INROOT = os.path.join(WORK, 'AI-Memory')            # vault inside the code jail
os.makedirs(INROOT, exist_ok=True)
for rel, txt in (('MEMORY.md', '# MEMORY\n\n- indice\n'),
                 ('AGENTS-VAULT.md', '# Reglas\n\n1. Carga perezosa.\n'),
                 ('notas/idea.md', '# Idea\n\ncontenido original\n')):
    p_ = os.path.join(INROOT, rel.replace('/', os.sep))
    os.makedirs(os.path.dirname(p_), exist_ok=True)
    open(p_, 'wb').write(txt.encode('utf-8'))

s7 = Server(vault=INROOT)                            # roots = WORK, vault inside it
out = s7.call('vault_read', {"path": "notas/idea.md"})
check('dentro-del-root: vault_read SI llega a la nota', 'contenido original' in out, out[:150])
_note = os.path.join(INROOT, 'notas', 'idea.md')
out = s7.call('delphi_read', {"path": _note})
check('dentro-del-root: delphi_read NO puede leer el vault',
      mc.es(out, 'SR_VAULT_NOT_CODE'), out[:180])
out = s7.call('delphi_edit', {"path": _note, "old": "contenido original", "new": "pisado"})
check('dentro-del-root: delphi_edit NO puede reescribir una nota',
      mc.es(out, 'SR_VAULT_NOT_CODE'), out[:180])
check('dentro-del-root: la nota sigue intacta en disco',
      'contenido original' in open(_note, encoding='utf-8').read())
out = s7.call('delphi_textedit', {"path": os.path.join(INROOT, 'MEMORY.md'),
                                  "create": True, "content": "intruso"})
check('dentro-del-root: delphi_textedit NO puede tocar el indice',
      mc.es(out, 'SR_VAULT_NOT_CODE'), out[:180])
out = s7.call('delphi_list', {"root": WORK, "pattern": "*.md"})
check('dentro-del-root: delphi_list no sirve notas del vault',
      mc.como_json(out).get('total') == 0 and mc.como_json(out).get('files') == []
      and 'idea.md' not in out, out[:250])
# ...y a traves de una JUNCTION de la raiz que apunte al vault: ni list ni
# search entran, y copy=true / package no se lo llevan. La lista de la 1.7.1
# lo tenia como SOSPECHA sin medir (hacia falta una junction en las raices):
# los recorredores siguen un enlace solo si lo de detras se puede LEER
# (EnlaceLegible), y el vault no se lee como codigo (SR_VAULT_NOT_CODE)
PROY = os.path.join(WORK, 'proy')
os.makedirs(PROY, exist_ok=True)
open(os.path.join(PROY, 'a.txt'), 'w').write('a\n')
ATAJO = os.path.join(PROY, 'atajo')
subprocess.run(['cmd', '/c', 'mklink', '/J', ATAJO, INROOT], capture_output=True)
check('junction-al-vault: fixture (la junction de la raiz llega al vault)',
      os.path.isjunction(ATAJO) and os.path.exists(os.path.join(ATAJO, 'MEMORY.md')), ATAJO)
out = s7.call('delphi_list', {"root": PROY, "pattern": "*.md"})
check('junction-al-vault: delphi_list no entra',
      mc.como_json(out).get('total') == 0 and 'idea.md' not in out, out[:200])
out = s7.call('delphi_search', {"root": PROY, "query": "contenido original", "pattern": "*.md"})
check('junction-al-vault: delphi_search no entra', mc.como_json(out).get('total') == 0, out[:200])
COPIA = os.path.join(WORK, 'copia')
out = s7.call('delphi_move', {"path": PROY, "dest": COPIA, "copy": True})
check('junction-al-vault: copy=true copia a.txt y NO el vault, y lo dice como no seguido',
      os.path.exists(os.path.join(COPIA, 'a.txt')) and not os.path.exists(os.path.join(COPIA, 'atajo'))
      and mc.es(out, 'SN_COPY_LINKS_NOT_FOLLOWED_FMT'), (out[:300], os.listdir(COPIA) if os.path.isdir(COPIA) else None))
Z = os.path.join(WORK, 'proy.zip')
out = s7.call('delphi_package', {"dir": PROY, "outfile": Z})
nombres = zipfile.ZipFile(Z).namelist() if os.path.exists(Z) else []
check('junction-al-vault: delphi_package mete a.txt y NO el vault',
      not mc.rechazado(out) and any(n.endswith('a.txt') for n in nombres)
      and not any(('MEMORY.md' in n) or ('idea.md' in n) for n in nombres), (out[:200], nombres))
mc.borra(ATAJO)  # el enlace, nunca lo de detras
out = s7.call('delphi_read', {"path": os.path.join(WORK, 'Codigo.pas')})
check('dentro-del-root: el codigo del workspace sigue accesible',
      'unit Codigo' in out, out[:120])
s7.close()

# ===========================================================================
# EL VAULT ES EL QUE CADA WORKSPACE DECLARA. No se hereda nada: no hay vault
# "por defecto" (el codigo solo registra un [Workspace.X] si trae token, y el
# env DELPHI_MCP_VAULT_PATH es solo para un arranque local por stdio). Varios
# workspaces PUEDEN compartir el mismo vault - pero solo el que declaran.
#
# Por HTTP con tokens, que es como funciona produccion. Las tools vault_*
# se registran si CUALQUIERA tiene vault, y el workspace sin vault puede
# llamarlas aunque tools/list ya no se las anuncie: su rechazo es lo unico
# que ese agente tiene. Decia "este servidor no tiene vault ([Vault] Path en
# settings.ini)" y las dos mitades eran falsas desde v0.98 (medido el
# 2026-09-20).
# ===========================================================================
HPORT = mc.puerto_libre()
HDIR = mc.carpeta('vault-http-ws')
os.makedirs(os.path.join(HDIR, 'codigo'))
os.makedirs(os.path.join(HDIR, 'vault-compartido'))
open(os.path.join(HDIR, 'vault-compartido', 'MEMORY.md'), 'w',
     encoding='utf-8').write('# indice compartido\n')
_hexe = mc.copia_exe(HDIR)
open(os.path.join(HDIR, 'settings.ini'), 'w', encoding='utf-8').write(
    '[Server]\nPort=%d\nBindIP=127.0.0.1\n\n'
    '[Workspace.ConVault]\nToken=tok-con-vault\nRoots=%s\nVaultPath=%s\n'
    'VaultReadOnly=1\n\n'
    '[Workspace.MismoVault]\nToken=tok-mismo-vault\nRoots=%s\nVaultPath=%s\n'
    'VaultReadOnly=1\n\n'
    '[Workspace.PorDefecto]\nToken=tok-por-defecto\nRoots=%s\nVaultPath=%s\n\n'
    '[Workspace.SinVault]\nToken=tok-sin-vault\nRoots=%s\n\n'
    '[Workspace.Escribe]\nToken=tok-escribe\nReadOnlyToken=tok-escribe-ro\nRoots=%s\n'
    'VaultPath=%s\nVaultReadOnly=0\n'
    % (HPORT, os.path.join(HDIR, 'codigo'), os.path.join(HDIR, 'vault-compartido'),
       os.path.join(HDIR, 'codigo'), os.path.join(HDIR, 'vault-compartido'),
       os.path.join(HDIR, 'codigo'), os.path.join(HDIR, 'vault-compartido'),
       os.path.join(HDIR, 'codigo'),
       os.path.join(HDIR, 'codigo'), os.path.join(HDIR, 'vault-compartido')))
_henv = mc.entorno()  # ni DELPHI_MCP_TOKEN ni VAULT_PATH heredados: manda el settings.ini
# sin puerto en la linea de comandos: el del settings.ini
_hp = mc.lanza_http(_hexe, None, _henv, espera_en=HPORT, cwd=HDIR)


def _http(token, method, params, rid=1):
    # JSON a secas (Accept application/json) y sin sesion: cada llamada suelta
    st, _, raw = mc.post('http://127.0.0.1:%d/mcp' % HPORT,
                         {"jsonrpc": "2.0", "id": rid, "method": method, "params": params},
                         token=token, accept='application/json', t=60)
    if st >= 400:
        return {'http': st, 'body': raw[:200]}
    return json.loads(raw)


def _texto(resp):
    try:
        return resp['result']['content'][0]['text']
    except Exception:
        return json.dumps(resp)[:300]


_INIT = {"protocolVersion": "2025-06-18", "capabilities": {},
         "clientInfo": {"name": "vault-battery", "version": "1"}}
try:
    for _tok in ('tok-con-vault', 'tok-mismo-vault', 'tok-por-defecto', 'tok-sin-vault'):
        _http(_tok, 'initialize', _INIT)

    _leen = []
    for _tok in ('tok-con-vault', 'tok-mismo-vault'):
        _leen.append(_texto(_http(_tok, 'tools/call',
                                  {"name": "vault_read", "arguments": {}}, 5)))
    check('por-workspace: dos workspaces distintos comparten el MISMO vault',
          all('indice compartido' in t for t in _leen), [t[:80] for t in _leen])

    # SIN VaultReadOnly= (la clave ausente): solo lectura POR DEFECTO. La bateria
    # probaba 0 y 1 y no el defecto, que es la regla que importa (David, 28-sep:
    # "por defecto readonly el vault de cada workspace, y parametro para write")
    _def = _texto(_http('tok-por-defecto', 'tools/call', {"name": "vault_read", "arguments": {}}, 7))
    check('por defecto (sin VaultReadOnly=): el workspace LEE su vault', 'indice compartido' in _def, _def[:120])
    _def = _texto(_http('tok-por-defecto', 'tools/call',
                        {"name": "vault_append", "arguments": {"path": "MEMORY.md", "content": "- x\n"}}, 8))
    check('por defecto (sin VaultReadOnly=): NO escribe (solo lectura salvo VaultReadOnly=0)',
          mc.rechazado(_def) and mc.es(_def, 'SR_VAULT_READONLY'), _def[:200])

    _sin = _texto(_http('tok-sin-vault', 'tools/call',
                        {"name": "vault_read", "arguments": {}}, 6))
    check('por-workspace: el que NO lo declara no lo ve (no se hereda nada)',
          mc.resultado(_sin) == 'DENIED' and mc.abre(_sin, 'SR_VAULT_UNSET')
          and 'indice compartido' not in _sin, _sin[:150])
    check('por-workspace: el rechazo habla de TU workspace, no del servidor',
          mc.es(_sin, 'SR_VAULT_UNSET') and '[Workspace.' in _sin, _sin[:200])
    check('por-workspace: manda a la clave que existe de verdad',
          'VaultPath' in _sin and '[Workspace.' in _sin and '[Vault]' not in _sin,
          _sin[:200])
    check('por-workspace: y ofrece camino (pedirselo al operador)',
          'delphi_report' in _sin, _sin[:200])

    # Escribir sin vault NO es "vault de solo lectura": son dos cosas y decir
    # la segunda mandaba al agente a quitar un ReadOnly que no existe. Este
    # token es de ESCRITURA, asi que la razon no puede venir de la credencial.
    _esc = _texto(_http('tok-sin-vault', 'tools/call',
                        {"name": "vault_append",
                         "arguments": {"path": "MEMORY.md", "content": "x"}}, 8))
    check('por-workspace: escribir sin vault dice SIN VAULT, no "solo lectura"',
          mc.es(_esc, 'SR_VAULT_UNSET') and
          not mc.es(_esc, 'SR_VAULT_READONLY') and not mc.es(_esc, 'SR_READ_ONLY_FMT'), _esc[:200])
    # Y el de verdad-solo-lectura (VaultReadOnly=1) nombra SU clave, no [Vault]
    _ro = _texto(_http('tok-con-vault', 'tools/call',
                       {"name": "vault_append",
                        "arguments": {"path": "MEMORY.md", "content": "x"}}, 9))
    check('por-workspace: el vault de solo lectura nombra VaultReadOnly, no [Vault]',
          mc.es(_ro, 'SR_VAULT_READONLY') and 'VaultReadOnly' in _ro and '[Vault]' not in _ro,
          _ro[:200])

    # tools/list anuncia a cada workspace las vault_* que le SIRVEN (6-oct-2026):
    # ninguna al que no tiene vault, y las de escritura no a uno de solo
    # lectura. Siguen llamables - las llamadas de arriba son las mismas y su
    # rechazo dice por que.
    def _nombres(tok, rid):
        _l = _http(tok, 'tools/list', {}, rid)
        return [t['name'] for t in _l.get('result', {}).get('tools', [])]
    _sinv = _nombres('tok-sin-vault', 70)
    check('por-workspace: al que no tiene vault no se le anuncia ninguna vault_*',
          not any(t.startswith('vault_') for t in _sinv) and 'delphi_read' in _sinv,
          [t for t in _sinv if t.startswith('vault_')] or _sinv[:5])
    for _tok in ('tok-con-vault', 'tok-por-defecto'):
        _ro_n = _nombres(_tok, 71)
        check('por-workspace (%s, solo lectura): vault_read/search SI, las de escritura NO' % _tok,
              'vault_read' in _ro_n and 'vault_search' in _ro_n and
              not any(t in _ro_n for t in ('vault_append', 'vault_create', 'vault_patch')),
              [t for t in _ro_n if t.startswith('vault_')])
    # el control positivo por HTTP: con VaultReadOnly=0 se anuncian las cinco
    # (sin el, "no se anuncian" pasaria tambien si el filtro las ocultase a
    # todo workspace con nombre - revision del 6-oct-2026)
    _esc = _nombres('tok-escribe', 72)
    check('por-workspace (VaultReadOnly=0): se le anuncian las cinco vault_*',
          all(t in _esc for t in ('vault_read', 'vault_search', 'vault_append',
                                  'vault_create', 'vault_patch')),
          [t for t in _esc if t.startswith('vault_')])
    # ...y a SU credencial de solo lectura no se le anuncian las de escritura,
    # ni la tabla de delphi_help le ofrece escribir en la memoria
    _esc_ro = _nombres('tok-escribe-ro', 73)
    check('por-workspace (VaultReadOnly=0, credencial RO): leer SI, escribir NO',
          'vault_read' in _esc_ro and not any(t in _esc_ro for t in
                                              ('vault_append', 'vault_create', 'vault_patch')),
          [t for t in _esc_ro if t.startswith('vault_')])
    _tabla_ro = _texto(_http('tok-escribe-ro', 'tools/call', {'name': 'delphi_help', 'arguments': {}}, 74))
    _tabla_rw = _texto(_http('tok-escribe', 'tools/call', {'name': 'delphi_help', 'arguments': {}}, 75))
    check('por-workspace: la tabla de delphi_help ofrece escribir la memoria a la credencial RW y no a la RO',
          'vault_append' in _tabla_rw and 'vault_append' not in _tabla_ro, _tabla_ro[-300:])
finally:
    _hp.kill()
    _hp.wait(10)  # su exe esta en HDIR: muerto del todo antes de barrerla
    mc.borra(HDIR)

for _d in (VAULT, WORK, SRV):
    mc.borra(_d)
mc.fin('vault battery')
