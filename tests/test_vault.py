"""E2E battery for the knowledge-vault tools (vault_search / vault_read /
vault_append / vault_create / vault_patch).

Builds a synthetic Obsidian-style vault in temp and drives the server against
it: lazy-loading bootstrap, jailed reads, the mechanical rule-11 backup before
every modification, the governance files being read-only, and the tools not
existing at all when no vault is configured.

Usage:  python tests/test_vault.py [path-to-DelphiLspMcp.exe]
"""
import json, subprocess, threading, queue, time, os, sys, tempfile, shutil, glob

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
EXE = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    REPO, 'src', 'Compiled', 'Win64', 'Release', 'DelphiLspMcp.exe')

VAULT = os.path.join(tempfile.gettempdir(), 'delphi-vault-tests-%d' % os.getpid())
shutil.rmtree(VAULT, ignore_errors=True)
# The vault lives in its OWN isolated folder, deliberately NOT inside the
# workspace roots: the two jails are independent.
WORK = os.path.join(tempfile.gettempdir(), 'delphi-vault-work-%d' % os.getpid())
shutil.rmtree(WORK, ignore_errors=True)
os.makedirs(WORK, exist_ok=True)
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
# A CRLF note with accents and an em-dash: a vault edited on Windows looks like
# this, and it is what caught the stray-CR bug (LF-only fixtures hid it).
w('conventions/crlf.md',
  '# Convencion CRLF\r\n\r\n- Acentos: gestoria, accion, compilacion\r\n'
  '- Guion largo: memoria \u2014 indice\r\n- Ruta citada: D:\\Proyectos\\Algo\r\n')
w('backups/mcp/vieja/secreto.md', '# No es conocimiento\n\nEsto vive en backups.\n')
w('notas.bak.md', '# Copia rancia\n')
# a big note to exercise the MaxReadChars truncation (>100K chars)
w('projects/delphi/grande.md', '# Grande\n\n' + ('relleno de linea larga ' * 8 + '\n') * 700)

PASS = FAIL = 0
def check(name, ok, detail=''):
    global PASS, FAIL
    if ok:
        PASS += 1; print('PASS - ' + name)
    else:
        FAIL += 1; print('FAIL - %s | %s' % (name, str(detail)[:220]))

class Server:
    """One server instance with its own env (vault path / readonly / flags)."""
    def __init__(self, vault=VAULT, writable=True, extra_args=None):
        env = dict(os.environ)
        env['DELPHI_MCP_ROOTS'] = WORK            # the code jail: a DIFFERENT folder
        if vault is None:
            env.pop('DELPHI_MCP_VAULT_PATH', None)
        else:
            env['DELPHI_MCP_VAULT_PATH'] = vault
        env['DELPHI_MCP_VAULT_READONLY'] = '0' if writable else '1'
        self.p = subprocess.Popen([EXE] + (extra_args or []), env=env,
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, text=True, encoding='utf-8')
        self.q = queue.Queue(); self.rid = 10
        threading.Thread(target=self._reader, daemon=True).start()
        self._send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-06-18", "capabilities": {},
            "clientInfo": {"name": "vault-battery", "version": "1"}}})
        r = self._recv(1, 20)
        self.init = (r or {}).get('result', {})

    def _reader(self):
        for line in self.p.stdout:
            if line.strip():
                self.q.put(line.strip())

    def _send(self, o):
        self.p.stdin.write(json.dumps(o) + '\n'); self.p.stdin.flush()

    def _recv(self, rid, t=60):
        dl = time.time() + t
        while time.time() < dl:
            try:
                line = self.q.get(timeout=1)
            except queue.Empty:
                continue
            try:
                m = json.loads(line)
            except Exception:
                continue
            if m.get('id') == rid:
                return m
        return None

    def call(self, name, args, t=60):
        self.rid += 1
        self._send({"jsonrpc": "2.0", "id": self.rid, "method": "tools/call",
                    "params": {"name": name, "arguments": args}})
        r = self._recv(self.rid, t)
        if r is None:
            return '(timeout)'
        if 'error' in r:
            return 'MCPERROR ' + json.dumps(r['error'])[:200]
        c = r['result'].get('content', [])
        return c[0].get('text', '') if c else '(no content)'

    def rpc(self, method, params=None):
        self.rid += 1
        self._send({"jsonrpc": "2.0", "id": self.rid, "method": method,
                    "params": params or {}})
        return self._recv(self.rid, 20) or {}

    def tools(self):
        self.rid += 1
        self._send({"jsonrpc": "2.0", "id": self.rid, "method": "tools/list", "params": {}})
        r = self._recv(self.rid, 20)
        return [t['name'] for t in r['result']['tools']] if r else []

    def close(self):
        try:
            self.p.stdin.close()
        except Exception:
            pass
        self.p.terminate()

# ===========================================================================
# 1. Registration: with a vault (read+write), and without one
# ===========================================================================
s = Server()
names = s.tools()
check('registro: las 5 tools de vault existen con [Vault] Path + ReadOnly=0',
      all(t in names for t in ('vault_search', 'vault_read', 'vault_append',
                               'vault_create', 'vault_patch')), names)

# ===========================================================================
# 1b. Session wiring: instructions on initialize + the invocable /vault prompt
# ===========================================================================
instr = s.init.get('instructions', '')
check('initialize: con vault, "instructions" trae el protocolo de arranque',
      'vault_read' in instr and 'perezosa' in instr.lower(), instr[:200])
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
check('prompts/get: un prompt desconocido da error', 'error' in bad, bad)

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
      'RECHAZADO' in out, out[:150])
out = s.call('vault_read', {"path": "Codigo.pas"})
check('aislamiento: las tools de VAULT no sirven codigo (.md only)',
      'RECHAZADO' in out, out[:150])
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
      'Mostradas las lineas' in out and 'offset' in out, out[-220:])
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
    check('jaula: %s rechazado' % label, 'RECHAZADO' in out, out[:150])
out = s.call('vault_read', {"path": "conventions/estilo.txt"})
check('jaula: fichero que no es .md rechazado', 'RECHAZADO' in out, out[:150])
out = s.call('vault_read', {"path": "backups/mcp/vieja/secreto.md"})
check('exclusion: backups/ no es legible', 'RECHAZADO' in out, out[:150])

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
check('search content: subfolder acota', 'context.md' in out, out[:200])
out = s.call('vault_search', {"target": "content", "pattern": "no-existe-esto-xyz"})
check('search: sin resultados lo dice y recuerda el indice',
      'Sin resultados' in out, out[:150])
out = s.call('vault_search', {"target": "files", "pattern": "*.md", "subfolder": "../.."})
check('search: subfolder con .. rechazado', 'RECHAZADO' in out, out[:150])

# ===========================================================================
# 6. Governance files are never writable
# ===========================================================================
for gov in ('MEMORY.md', 'AGENTS-VAULT.md', 'AGENTS-VAULT-WRITE.md'):
    out = s.call('vault_append', {"path": gov, "content": "- intruso\n"})
    check('gobierno: %s no se puede escribir' % gov,
          'RECHAZADO' in out and 'GOBIERNO' in out.upper(), out[:150])
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
    check('R9 CRITICAL: gobierno/nombre con %s RECHAZADO' % label, 'RECHAZADO' in out, out[:130])
check('R9 CRITICAL: ningun intruso llego a MEMORY.md',
      'intruso' not in open(os.path.join(VAULT, 'MEMORY.md'), encoding='utf-8').read())
for probe in ('MEMORY.md ', 'MEMORY.md.'):
    out = s.call('vault_create', {"path": probe, "content": "x"})
    check('R9: create con "%s" tambien RECHAZADO' % probe, 'RECHAZADO' in out, out[:130])
out = s.call('vault_append', {"path": "backups/mcp/vieja/secreto.md", "content": "x"})
check('gobierno: escribir en backups/ rechazado', 'RECHAZADO' in out, out[:150])

# ===========================================================================
# 7. vault_append (with and without anchor) + the mechanical backup
# ===========================================================================
LOG = os.path.join(VAULT, 'projects', 'delphi', 'log.md')
before = open(LOG, encoding='utf-8').read()
out = s.call('vault_append', {"path": "projects/delphi/log.md",
                              "content": "- entrada nueva con acentos: gestoria\n"})
check('append: sin anchor anade al final', 'ANADIDO' in out, out[:200])
after = open(LOG, encoding='utf-8').read()
check('append: el contenido esta y lo viejo se conserva',
      'entrada nueva' in after and 'entrada antigua' in after, after[:200])

bk = glob.glob(os.path.join(VAULT, 'backups', 'mcp', '*', 'projects', 'delphi', 'log.md'))
check('BACKUP (regla 11): copia previa creada en backups/mcp/<stamp>/', len(bk) == 1, bk)
if bk:
    check('BACKUP: la copia es IDENTICA al original antes del cambio',
          open(bk[0], encoding='utf-8').read() == before, 'difiere')

# anchor
out = s.call('vault_append', {"path": "projects/delphi/context.md",
                              "content": "- linea insertada", "anchor": "## Estado"})
check('append: con anchor inserta tras el ancla', 'ANADIDO' in out, out[:200])
ctx = open(os.path.join(VAULT, 'projects', 'delphi', 'context.md'), encoding='utf-8').read()
check('append: la insercion va DESPUES del anchor y antes del resto',
      ctx.index('linea insertada') > ctx.index('## Estado')
      and ctx.index('linea insertada') < ctx.index('linea viva uno'), ctx[-250:])
out = s.call('vault_append', {"path": "projects/delphi/context.md",
                              "content": "x", "anchor": "no-existe-este-ancla"})
check('append: anchor inexistente da error claro', out.startswith('error'), out[:150])
out = s.call('vault_append', {"path": "projects/delphi/context.md",
                              "content": "x", "anchor": "linea viva"})
check('append: anchor duplicado se rechaza (pide uno unico)',
      'VARIAS veces' in out, out[:150])
out = s.call('vault_append', {"path": "projects/delphi/no-existe.md", "content": "x"})
check('append: nota inexistente redirige a vault_create',
      out.startswith('error') and 'vault_create' in out, out[:150])

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
      'CREADA' in out and 'wikilink' in out.lower(), out[:200])
check('create: la nota existe en disco',
      os.path.exists(os.path.join(VAULT, 'decisiones', 'nueva-decision.md')))
out = s.call('vault_create', {"path": "decisiones/nueva-decision.md", "content": "# Otra\n"})
check('create: NUNCA sobreescribe una nota existente',
      'RECHAZADO' in out and 'YA existe' in out, out[:200])
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
check('patch: sustituye el fragmento unico', 'MODIFICADA' in out, out[:200])
check('patch: el cambio esta en disco',
      'linea viva DOS (cerrada)' in open(CTX, encoding='utf-8').read())
out = s.call('vault_patch', {"path": "projects/delphi/context.md",
                             "old_text": "texto-que-no-esta", "new_text": "x"})
check('patch: old_text ausente da error', out.startswith('error') and 'no aparece' in out, out[:150])
out = s.call('vault_patch', {"path": "projects/delphi/log.md",
                             "old_text": "\n", "new_text": "x"})
check('patch: old_text duplicado se rechaza', 'VARIAS veces' in out, out[:150])

# R9: a patch that empties the note is a DELETE, and there is no delete here
VACIA = os.path.join(VAULT, 'conventions', 'vaciable.md')
w('conventions/vaciable.md', '# Unica\n')
_todo = open(VACIA, encoding='utf-8').read()
out = s.call('vault_patch', {"path": "conventions/vaciable.md",
                             "old_text": _todo.strip(), "new_text": ""})
check('R9: patch que VACIARIA la nota rechazado', 'RECHAZADO' in out, out[:150])
check('R9: la nota conserva su contenido',
      open(VACIA, encoding='utf-8').read().strip() != '', 'quedo vacia')

# ===========================================================================
# 10. Read-only vault ([Vault] ReadOnly=1): only the 2 read tools exist
# ===========================================================================
s.close()
s2 = Server(writable=False)
names = s2.tools()
check('ReadOnly=1: vault_read/search SI se registran',
      'vault_read' in names and 'vault_search' in names, names)
check('ReadOnly=1: las 3 tools de escritura NO se registran',
      not any(t in names for t in ('vault_append', 'vault_create', 'vault_patch')), names)
out = s2.call('vault_read', {"path": "conventions/estilo.md"})
check('ReadOnly=1: la lectura sigue funcionando', 'Estilo' in out, out[:120])
s2.close()

# ===========================================================================
# 11. Read-only CREDENTIAL: the gate refuses the write tools
# ===========================================================================
s3 = Server(extra_args=['--readonly'])
out = s3.call('vault_append', {"path": "projects/delphi/log.md", "content": "- intruso\n"})
check('credencial RO: vault_append rechazado en la puerta',
      'SOLO LECTURA' in out, out[:180])
out = s3.call('vault_create', {"path": "otra.md", "content": "x"})
check('credencial RO: vault_create rechazado en la puerta', 'SOLO LECTURA' in out, out[:180])
out = s3.call('vault_patch', {"path": "projects/delphi/log.md", "old_text": "a", "new_text": "b"})
check('credencial RO: vault_patch rechazado en la puerta', 'SOLO LECTURA' in out, out[:180])
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
pl4 = s4.rpc('prompts/list').get('result', {}).get('prompts', None)
check('sin vault: prompts/list no ofrece el prompt vault',
      not pl4, pl4)
s4.close()

# ===========================================================================
# 13. First run on a new machine: a configured path that does not exist yet is
#     SEEDED with the starter templates; an existing vault is never touched.
# ===========================================================================
FRESH = os.path.join(tempfile.gettempdir(), 'delphi-vault-fresh-%d' % os.getpid())
shutil.rmtree(FRESH, ignore_errors=True)
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
shutil.rmtree(FRESH, ignore_errors=True)

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
      'VAULT DE CONOCIMIENTO' in out, out[:180])
out = s7.call('delphi_edit', {"path": _note, "old": "contenido original", "new": "pisado"})
check('dentro-del-root: delphi_edit NO puede reescribir una nota',
      'VAULT DE CONOCIMIENTO' in out, out[:180])
check('dentro-del-root: la nota sigue intacta en disco',
      'contenido original' in open(_note, encoding='utf-8').read())
out = s7.call('delphi_textedit', {"path": os.path.join(INROOT, 'MEMORY.md'),
                                  "create": True, "content": "intruso"})
check('dentro-del-root: delphi_textedit NO puede tocar el indice',
      'VAULT DE CONOCIMIENTO' in out, out[:180])
out = s7.call('delphi_list', {"root": WORK, "pattern": "*.md"})
check('dentro-del-root: delphi_list no sirve notas del vault',
      'idea.md' not in out, out[:250])
out = s7.call('delphi_read', {"path": os.path.join(WORK, 'Codigo.pas')})
check('dentro-del-root: el codigo del workspace sigue accesible',
      'unit Codigo' in out, out[:120])
s7.close()

print('\n== vault battery: %d PASS / %d FAIL ==' % (PASS, FAIL))
shutil.rmtree(VAULT, ignore_errors=True)
shutil.rmtree(WORK, ignore_errors=True)
sys.exit(1 if FAIL else 0)
