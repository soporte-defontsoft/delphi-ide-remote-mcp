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

Only the Samples (they are on every machine with RAD Studio): the warnings
of a family whose real class a package registers without source (the
ListView appearances) are counted apart while that policy is pending.

Usage:  python tests/test_designer_corpus.py [path-to-DelphiLspMcp.exe]
"""
import glob, json, os, re, shutil, time
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('designer-corpus')
EXE = mc.copia_exe(BASE)
APPDATA = os.path.join(BASE, 'appdata')
os.makedirs(APPDATA, exist_ok=True)
env = mc.entorno({'DELPHI_MCP_ROOTS': BASE, 'LOCALAPPDATA': APPDATA})
srv = mc.Stdio(EXE, env, nombre='dc')
call = srv.call


def J(t):
    try:
        return json.loads(t)
    except Exception:
        return {}


version = str(J(call('delphi_workspace', {})).get('activeDelphi') or '')
SAMPLES = os.path.join(os.environ.get('PUBLIC', r'C:\Users\Public'), 'Documents', 'Embarcadero',
                       'Studio', version, 'Samples')
if not os.path.isdir(SAMPLES):
    print('NOTA: no hay Samples de RAD Studio %s en %s: nada que medir' % (version, SAMPLES))
    srv.cierra()
    mc.borra(BASE)
    mc.fin('designer-corpus battery')
    raise SystemExit(0)

# los forms de TEXTO de los Samples, a la raiz del servidor (los binarios se
# leen al vuelo, pero aqui se mide el lint, no el conversor)
FORMS = os.path.join(BASE, 'forms')
copiados = []
for d, dirs, fs in os.walk(SAMPLES):
    dirs[:] = [x for x in dirs if x.lower() not in ('__history', '__recovery', 'win32', 'win64')]
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
check('corpus: los forms de texto de los Samples (%d)' % len(copiados), len(copiados) > 100, str(len(copiados)))

# que las dos tablas esten (se generan en segundo plano; info espera un rato):
# la espera de la casa, mc.espera_info (este bucle era su gemelo)
a = mc.espera_info(call, {'command': 'info', 'classname': 'TButton', 'framework': 'vcl', 'filter': 'Caption'},
                   cond=lambda r: 'Caption' in r, tope=300)
b = mc.espera_info(call, {'command': 'info', 'classname': 'TButton', 'framework': 'fmx', 'filter': 'Text'},
                   cond=lambda r: '"Text"' in r, tope=300)
listo = 'Caption' in a and '"Text"' in b
check('corpus: las tablas VCL y FMX del Delphi activo estan', listo, (a + ' | ' + b)[:300])

falsos, familia, notas, ejemplos = 0, 0, 0, []
for dst in copiados:
    r = call('delphi_designer', {'command': 'lint', 'path': dst}, t=120)
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
            if len(ejemplos) < 8:
                ejemplos.append('%s:%s %s -> %s' % (os.path.relpath(dst, FORMS), m.group(1), m.group(2)[:60], msg[:120]))
check('corpus: ni un aviso sobre los forms que el IDE escribio (%d forms)' % len(copiados),
      falsos == 0, ' || '.join(ejemplos))
if familia:
    print('NOTA: corpus: %d avisos de familia (clases que registra un paquete sin fuente: politica pendiente)' % familia)
print('NOTA: corpus: %d notas de clase sin fuente o ambigua (no juzgan)' % notas)

srv.cierra()
mc.borra(BASE)
mc.fin('designer-corpus battery')
