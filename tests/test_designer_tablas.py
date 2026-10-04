"""E2E battery for v1.12.0 - the designer tables come from the SOURCE of the
active Delphi (Lsp.DesignerMetaGen), not from units compiled into the exe:
the table of each framework lands in the server's cache with the fingerprint
of that source in its name; info knows the data components (and whatever was
installed from source); prop no longer answers a runtimeClass; going down a
class-typed property the lint accepts what a DESCENDANT of the declared type
publishes (TLabel.TextSettings declares TTextSettings, which publishes
nothing, and holds a TLabelTextSettings) and still warns about what no class
of that family publishes; TBitBtn.Style is the TButtonStyle of Vcl.Buttons.

The 1.12.0 review added: the server's cache is ITS OWN here (LOCALAPPDATA of
the battery: with the real one, a check could pass on a table another exe
left); whoever asks never generates (an edit says it did not check, DSGN-052,
apart from the EDIT-076 header and without "try again"); while a new table
is generated the previous one answers; the purge deletes what is old, the
leftover .tmp and the tables of an uninstalled Delphi, and keeps what is
recent and what a NEWER server wrote; what a class streams by code
(DefineProperties: Left/Top, Explicit*) and the root object of a form are
not warned about; info says what a class streams by code and, for one that
publishes nothing, what its descendants publish.

1.13.0 (4-oct-2026): the header names the platform the source was read for
(the one of the installation's IDE: Win32 with bin/bds.exe, the usual one,
Win64 when there is only bin64/bds.exe); a
table that is there but cannot be read says DSGN-054 and does not judge; a
generation that fails says DSGN-053 and is remembered for a while (both
rules had no check).

Measured on 3-oct-2026 against the RTTI tables of 1.11.3: 100 % of the
properties identical (VCL 7.117, FMX 11.779) - designer-meta-por-version in
the vault. This battery checks what an agent sees.

Usage:  python tests/test_designer_tablas.py [path-to-DelphiLspMcp.exe]
"""
import glob, json, os, re, time
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('designer-tablas')
EXE = mc.copia_exe(BASE)
APPDATA = os.path.join(BASE, 'appdata')
os.makedirs(APPDATA, exist_ok=True)
CACHE = mc.cache_servidor('designer', APPDATA)
env = mc.entorno({'DELPHI_MCP_ROOTS': BASE, 'LOCALAPPDATA': APPDATA})


def J(t):
    try:
        return json.loads(t)
    except Exception:
        return {}


def tablas():
    return sorted(os.path.basename(f) for f in glob.glob(os.path.join(CACHE, '*')))


# la tabla se genera en segundo plano (segundos): mc.espera_info pregunta
# otra vez mientras info diga DSGN-051
espera_info = mc.espera_info


# 1) cache VACIA: la primera edicion de un form no espera a la tabla ni la
# genera: lo escribe y dice que no lo valido, aparte de los avisos y sin
# "vuelve a llamar" (en una edicion, repetirla insertaria otra vez)
DFM0 = os.path.join(BASE, 'Primera.dfm')
open(DFM0, 'w', encoding='utf-8', newline='\r\n').write(
    'object FormPrimera: TFormPrimera\n  Caption = \'uno\'\nend\n')
srv = mc.Stdio(EXE, env, nombre='dt')
call = srv.call
r = call('delphi_edit', {'path': DFM0, 'old': "  Caption = 'uno'", 'new': "  Caption = 'dos'"})
check('cache vacia: la edicion se escribe', "Caption = 'dos'" in open(DFM0, encoding='utf-8').read(), r[:300])
check('cache vacia: la edicion dice que no valido (DSGN-052) y que no se repita',
      mc.tiene(r, 'DSGN-052') and 'do not repeat it' in r, r[:600])
check('cache vacia: la nota no va bajo la cabecera de avisos del disenador (EDIT-076)',
      not mc.tiene(r, 'EDIT-076'), r[:600])

# 2) info espera a la que se esta generando y contesta del fuente
r = espera_info(call, {'command': 'info', 'classname': 'TButton', 'framework': 'vcl', 'filter': 'Caption'},
                lambda x: 'Caption' in x)
j = J(r)
check('info TButton (VCL): contesta de la tabla del Delphi activo',
      any(p.get('name') == 'Caption' for p in j.get('properties', [])), r[:400])
check('info: la nota dice que sale del fuente del Delphi activo (DSGN-018)',
      'source of the active Delphi' in j.get('note', ''), j.get('note', '')[:200])

# 3) la cache: una tabla por marco de ESTA instalacion, con la huella del
# fuente en el nombre y una cabecera que dice de donde salio y quien la hizo
ws = J(call('delphi_workspace', {}))
version = str(ws.get('activeDelphi') or '')
patron = re.compile(r'^tabla_%s_([\d.]*)_(vcl|fmx)_([0-9a-f]{12})_g(\d+)\.txt$' % re.escape(version))
ms = [m for m in (patron.match(n) for n in tablas()) if m]
check('cache: las tablas VCL y FMX de la %s, con su huella en el nombre' % version,
      sorted(m.group(2) for m in ms) == ['fmx', 'vcl'], str(tablas())[:400])
build = ms[0].group(1) if ms else 'x'
gen = int(ms[0].group(4)) if ms else 0
vcl = glob.glob(os.path.join(CACHE, 'tabla_%s_*_vcl_*.txt' % version))
cab = open(vcl[0], encoding='utf-8-sig').readline() if vcl else ''
check('cache: la cabecera dice de que build salio y que servidor la genero',
      cab.startswith('# designer table VCL of RAD Studio') and 'units read from' in cab and
      'by DelphiLspMcp' in cab, cab[:250])
check('cache: la cabecera dice con que plataforma se leyo el fuente (la del IDE)',
      re.search(r'compiler [\d.]+, Win(32|64)\)', cab) is not None, cab[:250])

# 4) lo que antes no estaba: los componentes de datos del propio RAD Studio
r = call('delphi_designer', {'command': 'info', 'classname': 'TDataSource', 'framework': 'vcl'})
check('info TDataSource: los componentes de datos estan (antes, DSGN-015)',
      any(p.get('name') == 'DataSet' for p in J(r).get('properties', [])), r[:300])
r = call('delphi_designer', {'command': 'info', 'classname': 'TClaseInventada', 'framework': 'vcl'})
check('info de una clase que no existe: DSGN-015 NOT_FOUND', mc.tiene(r, 'DSGN-015'), r[:200])

# 5) info dice lo que una clase guarda por codigo, y de una que no publica
# nada, lo que publican sus descendientes
j = J(call('delphi_designer', {'command': 'info', 'classname': 'TComponent', 'framework': 'vcl'}))
check('info TComponent: definedByCode trae Left y Top (DefineProperties)',
      'Left' in j.get('definedByCode', []) and 'Top' in j.get('definedByCode', []), str(j)[:300])
j = J(call('delphi_designer', {'command': 'info', 'classname': 'TTextSettings', 'framework': 'fmx'}))
check('info TTextSettings (FMX): lo que publican sus descendientes (DSGN-057)',
      'Trimming' in j.get('descendantsPublish', '') and 'DSGN-057' in j.get('descendantsNote', ''),
      str(j)[:400])

# 6) prop: el tipo declarado, sin runtimeClass (el dato "A" se fue con el volcador)
r = call('delphi_designer', {'command': 'prop', 'classname': 'TLabel', 'framework': 'fmx',
                             'prop': 'TextSettings'})
j = J(r)
check('prop TLabel.TextSettings (FMX): clase TTextSettings', j.get('type') == 'TTextSettings', r[:300])
check('prop: ya no hay runtimeClass', 'runtimeClass' not in j, r[:300])

# 7) el lint FMX: lo que publica un descendiente del tipo declarado no se
# niega; lo que no publica nadie de la familia, si. Y los nombres VIEJOS de
# FMX: TTextControl los lee por compatibilidad con un ayudante
# (TTextPropLoader: Font.Size, Font.Family...), asi que un TLabel con
# Font.Size CARGA; Font.Color no lo lee nadie, y Color solo TText (con
# TTextPropLoaderEx): en un TButton es el VCL-ismo de siempre
FMX = os.path.join(BASE, 'Etiqueta.fmx')
open(FMX, 'w', encoding='utf-8', newline='\r\n').write(
"""object FormEtiqueta: TFormEtiqueta
  object Label1: TLabel
    TextSettings.Trimming = Character
    TextSettings.Fnt.Size = 12.000000000000000000
    Font.Size = 12.000000000000000000
    Font.Color = claRed
  end
  object Button1: TButton
    Color = claRed
  end
end
""")
r = call('delphi_designer', {'command': 'lint', 'path': FMX})
lineas = r.splitlines()
check('lint FMX: TextSettings.Trimming (de un descendiente) no se avisa',
      not any('TextSettings.Trimming' in l for l in lineas), r[:900])
check('lint FMX: TextSettings.Fnt (de nadie de la familia) se avisa',
      any('"Fnt"' in l and 'descends from it' in l for l in lineas), r[:900])
check('lint FMX: Font.Size en un TLabel no se avisa (lo lee TTextControl por compatibilidad)',
      not any('Font.Size' in l for l in lineas), r[:900])
check('lint FMX: Font.Color en un TLabel se avisa (no lo lee nadie)',
      any('Font.Color' in l and '"Font"' in l for l in lineas), r[:900])
check('lint FMX: Color en un TButton se avisa (solo lo lee TText)',
      any('Color = claRed' in l and '"Color"' in l and 'TButton' in l for l in lineas), r[:900])

# 8) el lint VCL: TBitBtn.Style es el TButtonStyle de Vcl.Buttons, no el
# anidado de TCustomButton (bsSplitButton es de ese otro); y lo que el IDE
# escribe sin publicarlo (la raiz del form, Left/Top de un no visual, los
# Explicit*) no se avisa
DFM = os.path.join(BASE, 'Botones.dfm')
open(DFM, 'w', encoding='utf-8', newline='\r\n').write(
"""object FormBotones: TFormBotones
  TextHeight = 13
  PixelsPerInch = 96
  object Bit1: TBitBtn
    Style = bsNew
    ExplicitLeft = 5
  end
  object Bit2: TBitBtn
    Style = bsSplitButton
  end
  object ImageList1: TImageList
    Left = 10
    Top = 20
  end
end
""")
r = call('delphi_designer', {'command': 'lint', 'path': DFM})
check('lint VCL: TBitBtn Style = bsNew es valido', 'bsNew"' not in r, r[:600])
check('lint VCL: bsSplitButton no es de su TButtonStyle (y dice los validos)',
      'bsSplitButton' in r and 'bsAutoDetect' in r, r[:600])
check('lint VCL: ni la raiz (TextHeight, PixelsPerInch) ni lo guardado por codigo (Left/Top de un '
      'TImageList, ExplicitLeft) se avisan',
      not any(x in r for x in ('"TextHeight"', '"PixelsPerInch"', '"Left"', '"Top"', '"ExplicitLeft"')),
      r[:900])
check('lint VCL: un solo aviso (el de bsSplitButton)', mc.tiene(r, 'DSGN-038') and ' 1 designer' in r, r[:600])
srv.cierra()

# 9) la purga y la tabla de antes. Se quitan las de ahora (se regeneran) y se
# plantan: una de otra huella de HACE DOS HORAS (se borra), otra de otra
# huella de AHORA (se queda: otro proceso puede estar usandola, y es la que
# contesta mientras se genera la nueva), una de una generacion MAS NUEVA
# vieja (es de otro servidor: se queda), la de un Delphi que no esta (se
# borra al arrancar) y un .tmp viejo (se borra)
for f in glob.glob(os.path.join(CACHE, 'tabla_%s_*.txt' % version)):
    os.remove(f)
hace2h = time.time() - 7200


def planta(nombre, texto, viejo):
    p = os.path.join(CACHE, nombre)
    open(p, 'w', encoding='utf-8').write(texto)
    if viejo:
        os.utime(p, (hace2h, hace2h))
    return nombre


FALSA = '# falsa\nC Vcl.StdCtrls:TButton\nP Vcl.StdCtrls:TButton Caption o TCaption\nP Vcl.StdCtrls:TButton Marca o Integer\n'
vieja = planta('tabla_%s_%s_vcl_aaaaaaaaaaaa_g%d.txt' % (version, build, gen), FALSA, True)
reciente = planta('tabla_%s_%s_vcl_bbbbbbbbbbbb_g%d.txt' % (version, build, gen), FALSA, False)
nueva = planta('tabla_%s_%s_vcl_cccccccccccc_g%d.txt' % (version, build, gen + 97), FALSA, True)
otro = planta('tabla_99.0_99.0.1.1_vcl_dddddddddddd_g%d.txt' % gen, FALSA, True)
tmp = planta('tabla_%s_%s_vcl_eeeeeeeeeeee_g%d.txt.123.tmp' % (version, build, gen), 'medio', True)
srv = mc.Stdio(EXE, env, nombre='dt2')
call = srv.call
r = call('delphi_designer', {'command': 'info', 'classname': 'TButton', 'framework': 'vcl', 'filter': 'Marca'})
check('mientras se genera la nueva, contesta la tabla de antes (otra huella, misma build)',
      any(p.get('name') == 'Marca' for p in J(r).get('properties', [])), r[:300])
t0 = time.time()
while time.time() - t0 < 240 and len([n for n in tablas() if patron.match(n) and 'aaaa' not in n
                                      and 'bbbb' not in n and 'cccc' not in n]) < 2:
    time.sleep(2)
time.sleep(1)  # la purga va detras de escribir las dos
hay = tablas()
check('purga: la de otra huella de hace dos horas se borra', vieja not in hay, str(hay)[:500])
check('purga: la de otra huella de ahora se queda', reciente in hay, str(hay)[:500])
check('purga: la de una generacion mas nueva (otro servidor) se queda', nueva in hay, str(hay)[:500])
check('purga: la de un Delphi que no esta se borra', otro not in hay, str(hay)[:500])
check('purga: el .tmp viejo de un escritor que murio se borra', tmp not in hay, str(hay)[:500])
r = call('delphi_designer', {'command': 'info', 'classname': 'TButton', 'framework': 'vcl', 'filter': 'Marca'})
check('con la nueva generada, contesta la nueva (la falsa ya no)',
      not any(p.get('name') == 'Marca' for p in J(r).get('properties', [])), r[:300])

srv.cierra()

# 10) una tabla que esta pero no se puede leer (un disco, otro proceso que la
# tiene bloqueada): el disenador dice por que (DSGN-054) y no juzga, sin
# lanzar. La de ahora, con un bloqueo de lectura de Windows
import msvcrt
actual = [n for n in tablas() if patron.match(n) and '_vcl_' in n and
          not any(x in n for x in ('aaaa', 'bbbb', 'cccc'))]
check('hay una tabla VCL de ahora que bloquear', len(actual) == 1, str(tablas())[:400])
if actual:
    ruta = os.path.join(CACHE, actual[0])
    tam = os.path.getsize(ruta)
    fh = open(ruta, 'r+b')
    msvcrt.locking(fh.fileno(), msvcrt.LK_NBLCK, tam)
    try:
        srv = mc.Stdio(EXE, env, nombre='dt3')
        r = srv.call('delphi_designer', {'command': 'info', 'classname': 'TButton', 'framework': 'vcl'})
        check('una tabla que no se puede leer: DSGN-054 con el motivo', mc.tiene(r, 'DSGN-054'), r[:300])
        r = srv.call('delphi_designer', {'command': 'lint', 'path': DFM})
        check('...y el lint no juzga: dice lo mismo, sin avisos', mc.tiene(r, 'DSGN-054') and
              not mc.tiene(r, 'DSGN-038'), r[:300])
        srv.cierra()
    finally:
        fh.seek(0)
        msvcrt.locking(fh.fileno(), msvcrt.LK_UNLCK, tam)
        fh.close()

# 11) una generacion que falla (aqui, un FICHERO donde va la carpeta de las
# tablas) se dice con su motivo (DSGN-053) y se recuerda un rato: la llamada
# siguiente contesta en el acto, sin otra generacion de segundos de CPU
APPDATA2 = os.path.join(BASE, 'appdata-falla')
os.makedirs(mc.cache_servidor('', APPDATA2), exist_ok=True)
open(mc.cache_servidor('designer', APPDATA2), 'w').write('estorba')
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE, 'LOCALAPPDATA': APPDATA2}), nombre='dt4')
r = espera_info(srv.call, {'command': 'info', 'classname': 'TButton', 'framework': 'vcl'},
                lambda x: mc.tiene(x, 'DSGN-053'))
check('una generacion que falla: DSGN-053 con su motivo', mc.tiene(r, 'DSGN-053'), r[:400])
t0 = time.time()
r = srv.call('delphi_designer', {'command': 'info', 'classname': 'TLabel', 'framework': 'fmx'})
check('...recordada: la siguiente contesta DSGN-053 en el acto (%.1f s)' % (time.time() - t0),
      mc.tiene(r, 'DSGN-053') and time.time() - t0 < 5, r[:400])
srv.cierra()
mc.borra(BASE)
mc.fin('designer-tablas battery')
