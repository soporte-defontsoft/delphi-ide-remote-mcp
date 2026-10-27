"""E2E battery for v1.12.0 - the designer lint over a CORPUS of forms the IDE
wrote and that load: the Samples that come with RAD Studio. Every warning
there is a lie (or a sample that does not load, which is worth knowing).

Why it exists: the 1.12.0 tables are read from the SOURCE of every folder
in the IDE's library paths, third parties included, and a reviewer ported
the lint to Python and ran it over real forms before the tag: 230 warnings
in the Samples and 2.121 in David's forms, none real - enumerations with
the same name in two units (FireDAC and IBX TIBProtocol), what a class
streams by code (DefineProperties: Left/Top of a non-visual, TField.Lookup,
QuickReport FontSize), the root class of a form sharing its name with a
demo's, an unnamed 'object TMemo' whose properties went to its parent.
Unit checks catch each rule; this catches the next one nobody thought of.

Only the Delphi Samples (they are on every machine with RAD Studio; the CPP
folder is C++Builder, and this server is for Delphi only): the warnings
of a family whose real class a package registers without source (the
ListView appearances) are counted apart while that policy is pending.

Usage:  python tests/test_designer_corpus.py [path-to-DelphiLspMcp.exe]
"""
import atexit, glob, json, os, re, shutil, time
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('designer-corpus')
# con los renderizadores: desde la 1.20 el lint pregunta al LECTOR del IDE lo
# que las tablas no juzgan (DSGN-061), y sin ellos cada form que lo necesita
# contestaba DSGN-154 "no se le pudo preguntar" (revisor de baterias,
# 18-oct-2026: el corpus no media al lector desde la 1.20)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)
APPDATA = os.path.join(BASE, 'appdata')
os.makedirs(APPDATA, exist_ok=True)
# por HTTP, para lintar EN PARALELO (mc.en_paralelo): en serie por stdio el
# corpus era la mitad de run_all, 30 de 60 minutos (auditoria de las baterias,
# 18-oct-2026); medido con 96 forms, 8 hilos 3,1 veces mas rapido y las mismas
# respuestas. Una muestra rotatoria no: sus avisos pendientes saldrian rojos o
# verdes segun el dia
TOKEN = 'designer-corpus'
with open(os.path.join(BASE, 'srv', 'settings.ini'), 'w') as f:
    f.write('[Workspace.Corpus]\nToken=%s\nRoots=%s\n' % (TOKEN, BASE))
PORT = mc.puerto_libre()
proc = mc.lanza_http(EXE, PORT, mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1', 'LOCALAPPDATA': APPDATA}))
cli = mc.Http(PORT, TOKEN, t=300)
cli.session('dc')
call = cli.call


def para():
    proc.kill()
    proc.wait()


# un servidor HTTP no muere con la bateria (el de stdio si: se le cierra la
# entrada), y uno huerfano tiene cogida la carpeta para la siguiente pasada
# (medido el 18-oct-2026, al reventar un lint por su plazo)
atexit.register(para)


def J(t):
    try:
        return json.loads(t)
    except Exception:
        return {}


version = str(J(call('delphi_workspace', {})).get('activeDelphi') or '')
# los Samples cuelgan del BDSCOMMONDIR que pone el rsvars.bat del IDE (r5-L4: se componia a mano)
SAMPLES = os.path.join(mc.variable_de_rsvars(call, 'BDSCOMMONDIR'), 'Samples')
if not os.path.isdir(SAMPLES):
    print('NOTA: no hay Samples de RAD Studio %s en %s: nada que medir' % (version, SAMPLES))
    para()
    mc.borra(BASE)
    mc.fin('designer-corpus battery')
    raise SystemExit(0)

# los forms de TEXTO de los Samples, a la raiz del servidor (los binarios se
# leen al vuelo, pero aqui se mide el lint, no el conversor)
FORMS = os.path.join(BASE, 'forms')
copiados = []
con_pas = 0
for d, dirs, fs in os.walk(SAMPLES):
    # la carpeta CPP es de C++Builder: este MCP es solo de Delphi (David,
    # 18-oct-2026), y sus forms no los escribio el IDE de Delphi
    dirs[:] = [x for x in dirs if x.lower() not in ('__history', '__recovery', 'win32', 'win64') and
               not (d == SAMPLES and x.lower() == 'cpp')]
    for f in fs:
        if f.lower().endswith(('.dfm', '.fmx')):
            src = os.path.join(d, f)
            with open(src, 'rb') as h:
                if h.read(3) == b'TPF':
                    continue
            dst = os.path.join(FORMS, os.path.relpath(src, SAMPLES))
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copyfile(src, dst)
            copiados.append(dst)
            # ...con su .pas: sin el no corria el form contra su clase
            # (check-binding) ni se encontraba el maestro de una vista FMX, que
            # declara la vista con su R *.<Vista>.fmx (18-oct-2026: un Sample
            # con TLabel sin campo "no cargaba" y nadie lo habia medido aqui)
            pas = os.path.splitext(src)[0] + '.pas'
            if os.path.isfile(pas):
                shutil.copyfile(pas, os.path.splitext(dst)[0] + '.pas')
                con_pas += 1
check('corpus: los forms de texto de los Samples (%d)' % len(copiados), len(copiados) > 100, str(len(copiados)))
check('corpus: con su .pas los que lo tienen (%d)' % con_pas, con_pas > 100, con_pas)

# que las dos tablas esten (se generan en segundo plano; info espera un rato):
# la espera de la casa, mc.espera_info (este bucle era su gemelo)
a = mc.espera_info(call, {'command': 'info', 'classname': 'TButton', 'framework': 'vcl', 'filter': 'Caption'},
                   cond=lambda r: 'Caption' in r, tope=300)
b = mc.espera_info(call, {'command': 'info', 'classname': 'TButton', 'framework': 'fmx', 'filter': 'Text'},
                   cond=lambda r: '"Text"' in r, tope=300)
listo = 'Caption' in a and '"Text"' in b
check('corpus: las tablas VCL y FMX del Delphi activo estan', listo, (a + ' | ' + b)[:300])

# (revisor de baterias, 18-oct-2026) un lint que no contesta (un error, un
# timeout) no dejaba ninguna linea "line N:" y contaba como limpio; y el
# parser del IDE (DSGN-123, juez desde el 8-oct) no tiene esa forma de linea:
# los dos cuentan. Y el LECTOR del IDE (DSGN-061 de la 1.20) habla cuando las
# tablas callan: lo que dice de un form del IDE es un aviso falso como otro,
# con linea o sin ella (SF_DSGN_LECTOR_SIN_LINEA_FMT); y si no se le pudo
# preguntar (DSGN-154) se cuenta por su motivo, nunca por falta de
# renderizador (este arnes los pone)
LINEA_N = re.compile(r'\s*line (\d+): (.*?)\s+->\s+(.*)$')
# los avisos VERDADEROS, medidos: un Sample que de verdad falla (el form, y lo
# que tiene que decir su aviso). Si uno deja de salir, se quita de aqui.
#  - FireDAC InterBase Admin (2015): un TStringGrid y ninguna unidad del
#    proyecto usa FMX.Grid.Style. Compilado tal cual, el exe no lleva TStyledGrid
#    (0) y con la unidad si (31): FMX pinta su aviso en lugar del grid (V69 de
#    la 1.23.1, medido el 27-oct-2026)
VERDADEROS = {os.path.join('Object Pascal', 'Database', 'FireDAC', 'Samples', 'DBMS Specific', 'InterBase',
                           'Admin', 'AdminUtility.fmx'): 'FMX.Grid.Style'}
vistos_verdaderos = set()
falsos, familia, notas, ejemplos, sin_lint = 0, 0, 0, [], []
sin_lector, sin_render = {}, []
# t=300: un lint puede preguntar al lector mas de una vez, y el lector tiene 75
# s (RENDER_TIEMPO_MS; 8 forms de los Samples los agotan, RENDER-007)
# y lo que los renderizadores dejan ver en el escritorio mientras tanto: NADA
# (ventanas en la barra, cuadros modales, el foco; 18/19-oct-2026: lo vio David)
vigilante = mc.VigilanteDeEscritorio().arranca()
respuestas = mc.en_paralelo(PORT, TOKEN, 'delphi_designer',
                            [{'command': 'lint', 'path': dst} for dst in copiados], t=300, nombre='dc')
vigilante.para()
check('corpus: ningun renderizador puso una ventana en la barra ni abrio un cuadro de dialogo',
      vigilante.ventanas == 0 and vigilante.cuadros == 0, vigilante.resumen())
check('corpus: ningun renderizador robo el foco', vigilante.foco == 0, vigilante.resumen())
for dst, r in zip(copiados, respuestas):
    rel = os.path.relpath(dst, FORMS)
    if not any(mc.abre(r, c) for c in ('SN_DESIGNER_LINT_OK_FMT', 'SN_DESIGNER_LINT_BAD_FMT',
                                        'SN_DESIGNER_LINT_NOTAS_FMT', 'SN_DESIGNER_LINT_SIN_LECTOR_FMT')):
        sin_lint.append('%s: %s' % (rel, r[:100]))
    if mc.es(r, 'SN_DESIGNER_LINT_SIN_LECTOR_FMT'):
        if mc.es(r, 'SR_DESIGNER_SIN_RENDER_FMT'):
            sin_render.append(rel)
        else:
            m = re.search(r'could not be asked: (\[[A-Z]+-\d+[^\]]*\])?', r)
            motivo = (m.group(1) if m and m.group(1) else 'sin id')
            sin_lector.setdefault(motivo, []).append(rel)
    # los avisos del bloque de DSGN-038 sin linea de este fichero: los del
    # lector y los del form contra su clase (check-binding)
    bloque = None
    for l in r.splitlines():
        if not l.startswith(' '):
            bloque = 'bad' if mc.abre(l, 'SN_DESIGNER_LINT_BAD_FMT') else 'otro'
        elif bloque == 'bad' and l.strip() and not LINEA_N.match(l):
            if rel in VERDADEROS and VERDADEROS[rel] in l:
                vistos_verdaderos.add(rel)
                continue
            falsos += 1
            ejemplos.append('%s aviso sin linea: %s' % (rel, l.strip()[:160]))
    if mc.es(r, 'SN_DSGN_PARSER_FMT'):
        falsos += 1
        ejemplos.append('%s parser del IDE: %s' % (os.path.relpath(dst, FORMS), r[:160]))
    for l in r.splitlines():
        m = re.match(r'\s*line (\d+): (.*?)\s+->\s+(.*)$', l)
        if not m:
            continue
        msg = m.group(3)
        if 'DSGN-039' in msg or 'DSGN-055' in msg:
            notas += 1          # una clase sin fuente, o ambigua: no juzga, lo dice
        elif 'descends from it' in msg:
            familia += 1        # politica pendiente (ver la cabecera)
        else:
            falsos += 1
            ejemplos.append('%s:%s %s -> %s' % (os.path.relpath(dst, FORMS), m.group(1), m.group(2)[:60], msg[:120]))
check('corpus: el lint CONTESTA de cada form (limpio, avisos, notas o sin confirmar)',
      not sin_lint, ' || '.join(sin_lint[:5]))
check('corpus: al lector se le pregunta (el arnes pone los renderizadores)',
      not sin_render, ' || '.join(sin_render[:5]))
# (18-oct-2026) TODOS, uno por linea: el detalle de check se recorta y con
# los 8 primeros no se podia medir cuantos ni cuales eran
for motivo, forms in sorted(sin_lector.items()):
    print('NOTA: corpus: %d forms sin confirmar por el lector, %s:' % (len(forms), motivo))
    for f in forms:
        print('    ' + f)
for e in ejemplos:
    print('AVISO: ' + e)
check('corpus: ni un aviso sobre los forms que el IDE escribio (%d forms; %d avisos, arriba)' % (len(copiados), falsos),
      falsos == 0, ' || '.join(ejemplos[:3]))
check('corpus: los avisos VERDADEROS medidos siguen saliendo (%d)' % len(VERDADEROS),
      vistos_verdaderos == set(VERDADEROS), sorted(set(VERDADEROS) - vistos_verdaderos))
if familia:
    print('NOTA: corpus: %d avisos de familia (clases que registra un paquete sin fuente: politica pendiente)' % familia)
print('NOTA: corpus: %d notas de clase sin fuente o ambigua (no juzgan)' % notas)

para()
mc.borra(BASE)
mc.fin('designer-corpus battery')
