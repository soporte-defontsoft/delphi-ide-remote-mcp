# -*- coding: utf-8 -*-
r"""Lo de la 1.26.

  D1 un Deploy que falla en una carpeta cuyo nombre lleva E0017 y el del vigia de un
     remote-run: deployLockedNote leia la consola entera y mandaba matar un trabajo que
     no existe. El E0017 de verdad lo clasifica msbuild y llega a errors[], con el nombre
     del vigia en LA MISMA linea (medido el 1-nov-2026 contra un PAServer con un programa
     vivo; el camino bueno se mide en vivo, una bateria no tiene PAServer).
  C1 preview de un form cuyo frame lleva otro que cierra el ciclo: RENDER-026 dice en que
     fichero esta el inline que se salto, que no es el pedido (Qwen, dirigido de la 1.25.1:
     no se sabia que bloque faltaba).
  F1 el renderizador que sigue cargando los paquetes del IDE al vencer --packagestimeout
     contesta RENDER-027 con cuantos llevaba, no RENDER-007 "algo del form espera". La
     carga lenta, con un paquete en una direccion de TEST-NET: Windows tarda ~21 s en
     decir que no existe (medido el 2-nov-2026), y el vigia corta a los 2.
  F2 un ayudante que el SERVIDOR para mientras decia PHASE=packages: DSGN-187, no DSGN-062;
     y uno que ya dijo PHASE=form, DSGN-062. Con ayudantes de mentira, como
     test_protocolo_render_125: lo que se mide es lo que el servidor lee.
  P1-P7 lo que encontro el revisor del paisaje de la 1.26 (ver cada uno abajo).
  H1-H2 lo que encontro Hermes en el dirigido de la 1.26: la nota DSGN-114 del preview prometia
     "line says where each one is" para un inline que se salto (RENDER-026) y para una propiedad
     escrita en el fichero de un frame, que no traen linea.

Uso:  python tests/test_capacidades_126.py [exe]
"""
import json, os, re, shutil, subprocess, threading, time
import mcp_cliente as mc
from mcp_cliente import check

# el protocolo, de su fuente: el numero, la clave de la fase y el codigo del vigia
INC = open(os.path.join(mc.REPO, 'src', 'Render', 'FormRenderProtocolo.inc'), encoding='ascii').read()
PROTOCOLO = re.search(r'FR_PROTOCOLO_VERSION = (\d+);', INC).group(1)
FASE = re.search(r"FR_PHASE = '([A-Z]+=)'", INC).group(1)
FASE_PAQUETES = re.search(r"FR_FASE_PAQUETES = '(\w+)'", INC).group(1)
FASE_FORM = re.search(r"FR_FASE_FORM = '(\w+)'", INC).group(1)
RC_TIEMPO = int(re.search(r'FR_RC_TIMEOUT = (\d+);', INC).group(1))

BASE = mc.carpeta('capacidades_126')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_conversor=True, con_render=True)
# un perfil falso con su host permitido: msbuild llega a intentar el Deploy y falla
APPD, HOST = mc.appdata_perfil(BASE, 'mcp-e2e-noprof', '127.0.0.1', 'Linux64')
D1 = os.path.join(JAIL, 'E0017-20261101-173717596-a1d40549.wait.exe')
DPROJ = os.path.join(D1, 'Bloqueo.dproj')
s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'APPDATA': APPD, 'DELPHI_MCP_REMOTE_HOSTS': HOST,
                              'DELPHI_MCP_ALLOW_REMOTE_RUN': '1', 'DELPHI_MCP_REMOTE_RUN_PROJECTS': DPROJ}),
             nombre='capacidades-126', t=400)

# ---- D: lo que dice la consola no es lo que clasifica msbuild
s.call('delphi_create', {'kind': 'project-console', 'dir': D1, 'name': 'Bloqueo'})
s.call('delphi_config', {'command': 'add-platform', 'platform': 'Linux64', 'project': DPROJ})
t = s.call('delphi_build', {'project': DPROJ, 'platform': 'Linux64', 'config': 'Debug', 'target': 'Deploy',
                            'profile': 'mcp-e2e-noprof', 'verbosity': 'normal'}, t=400)
r = mc.como_json(t)
check('D1 fixture: el Deploy falla', r.get('success') is False, t[:600])
check('D1 un Deploy que falla en una carpeta que se llama como el vigia no manda matar a nadie',
      'deployLockedNote' not in r, r.get('deployLockedNote'))

# ---- C: que bloque se salto
def escribe(ruta, texto):
    with open(ruta, 'wb') as f:
        f.write(texto.encode('ascii').replace(b'\n', b'\r\n'))


C1 = os.path.join(JAIL, 'ciclo')
os.makedirs(C1)
for uni, clase, otro in (('UUno', 'TFrUno', 'TFrDos'), ('UDos', 'TFrDos', 'TFrUno')):
    usa = 'UDos' if uni == 'UUno' else 'UUno'
    escribe(os.path.join(C1, uni + '.pas'),
            'unit %s;\n\ninterface\n\nuses\n  Vcl.Forms, %s;\n\ntype\n  %s = class(TFrame)\n    Dentro: %s;\n  end;\n\n'
            'implementation\n\n{$R *.dfm}\n\nend.\n' % (uni, usa, clase, otro))
    escribe(os.path.join(C1, uni + '.dfm'),
            'object %s: %s\n  Left = 0\n  Top = 0\n  Width = 100\n  Height = 80\n  TabOrder = 0\n'
            '  inline Dentro: %s\n    Left = 0\n    Top = 0\n  end\nend\n' % (clase[1:], clase, otro))
r = s.call('delphi_designer', {'command': 'preview', 'path': os.path.join(C1, 'UUno.dfm'), 'maxwidth': 100}, t=400)
check('C1 RENDER-026 dice en que fichero esta el inline que se salto: UDos.dfm, no el pedido',
      mc.es(r, 'SR_RENDER_FRAME_CICLICO_FMT') and 'Its inline in UDos.dfm' in r, r[:500])
# H1 (Hermes, dirigido de la 1.26) ese inline no es una propiedad con su linea: RENDER-026 ya dice su fichero y que
# hacer, y la nota DSGN-114 ("line says where each one is") prometia una linea que la entrada no trae
nota = mc.como_json(r).get('ignoredNote') or ''
check('H1 un frame que se contiene a si mismo no lleva la nota DSGN-114, que promete una linea que no trae',
      not mc.es(nota, 'SN_DESIGNER_PREVIEW_IGNORADAS'), nota[:300])

# H2 una propiedad mala en el fichero de un frame en linea: el lector la salta leyendo el form, sin linea en el
# form (no esta en el), y la nota dice que hacer con una sin linea; el preview del frame si la da
H2 = os.path.join(JAIL, 'marcov')
os.makedirs(H2)
USOS_VCL = 'Vcl.Forms, Vcl.Controls, Vcl.StdCtrls'
escribe(os.path.join(H2, 'UMarcoV.pas'), 'unit UMarcoV;\n\ninterface\n\nuses\n  %s;\n\ntype\n  TMarcoV = class(TFrame)\n'
        '    Edit1: TEdit;\n  end;\n\nimplementation\n\n{$R *.dfm}\n\nend.\n' % USOS_VCL)
MARCO_V = ("object MarcoV: TMarcoV\n  Left = 0\n  Top = 0\n  Width = 200\n  Height = 60\n  TabOrder = 0\n"
           "  object Edit1: TEdit\n    Left = 8\n    Top = 8\n    Width = 121\n    Height = 23\n    TabOrder = 0\n"
           "    NoExiste = 1\n  end\nend\n")
escribe(os.path.join(H2, 'UMarcoV.dfm'), MARCO_V)
escribe(os.path.join(H2, 'UFV.pas'), 'unit UFV;\n\ninterface\n\nuses\n  %s, UMarcoV;\n\ntype\n  TFormV = class(TForm)\n'
        '    MarcoV1: TMarcoV;\n  end;\n\nvar\n  FormV: TFormV;\n\nimplementation\n\n{$R *.dfm}\n\nend.\n' % USOS_VCL)
escribe(os.path.join(H2, 'UFV.dfm'), "object FormV: TFormV\n  Left = 0\n  Top = 0\n  Caption = 'V'\n  ClientHeight = 200\n"
        "  ClientWidth = 300\n  inline MarcoV1: TMarcoV\n    Left = 10\n    Top = 10\n    TabOrder = 0\n  end\nend\n")
r = s.call('delphi_designer', {'command': 'preview', 'path': os.path.join(H2, 'UFV.dfm'), 'maxwidth': 100}, t=400)
j = mc.como_json(r)
mala = [x for x in (j.get('ignored') or []) if x.get('property') == 'NoExiste']
nota = j.get('ignoredNote') or ''
TEXTO_114 = mc.catalogo()['SN_DESIGNER_PREVIEW_IGNORADAS']
check('H2 la propiedad mala del frame sale sin linea en el preview del form, y la nota dice que hacer con una '
      'sin linea (no solo "line says where each one is")',
      len(mala) == 1 and 'line' not in mala[0] and mc.es(nota, 'SN_DESIGNER_PREVIEW_IGNORADAS')
      and 'without line' in TEXTO_114 and nota.startswith(TEXTO_114.split(' - ')[0]) and 'without line' in nota,
      (mala, nota[:400]))
r = s.call('delphi_designer', {'command': 'preview', 'path': os.path.join(H2, 'UMarcoV.dfm'), 'maxwidth': 100}, t=400)
mala = [x for x in (mc.como_json(r).get('ignored') or []) if x.get('property') == 'NoExiste']
check('H2 ...y el preview del frame, al que manda la nota, la da con su linea',
      len(mala) == 1 and mala[0].get('line') == MARCO_V.split('\n').index('    NoExiste = 1') + 1, (mala, r[:300]))

# ---- F: la fase de los paquetes
F1 = os.path.join(JAIL, 'fases')
os.makedirs(F1)
DFM = os.path.join(F1, 'UF.dfm')
escribe(DFM, "object UF: TUF\n  Left = 0\n  Top = 0\n  ClientHeight = 60\n  ClientWidth = 80\nend\n")
LISTA = os.path.join(F1, 'paquetes.lst')
with open(LISTA, 'w', encoding='utf-8-sig') as f:
    f.write('\\\\192.0.2.1\\nada\\Nada370.bpl\n')
t0 = time.time()
u = subprocess.run([os.path.join(os.path.dirname(EXE), 'DelphiFormRenderVcl.exe'), '--path', DFM,
                    '--out', os.path.join(F1, 'o.png'), '--packages', 'all', '--knownfile', LISTA,
                    '--root', 'form', '--fidelity', 'print', '--style', 'none',
                    '--timeout', '20000', '--packagestimeout', '2000'],
                   capture_output=True, timeout=120, cwd=F1)
dt = time.time() - t0
salida = u.stdout.decode('utf-8', 'replace')
check('F1 cargando los paquetes al vencer --packagestimeout: RENDER-027 con cuantos llevaba, a los 2 s y no a los '
      '20 del plazo entero, con su codigo de tiempo (%.1f s)' % dt,
      u.returncode == RC_TIEMPO and mc.es(salida, 'SR_RENDER_PAQUETES_CARGANDO_FMT') and '(0 of 1)' in salida
      and (FASE + FASE_PAQUETES) in salida.splitlines() and dt < 15,
      (u.returncode, salida[-500:]))

PRUEBA = os.path.join(JAIL, 'prueba')
os.makedirs(PRUEBA)
escribe(os.path.join(PRUEBA, 'UP.pas'), 'unit UP;\n\ninterface\n\nuses\n  Vcl.Forms;\n\ntype\n  TUP = class(TForm)\n  end;\n\n'
        'implementation\n\n{$R *.dfm}\n\nend.\n')
escribe(os.path.join(PRUEBA, 'UP.dfm'), "object UP: TUP\n  Left = 0\n  Top = 0\n  ClientHeight = 60\n  ClientWidth = 80\nend\n")


def de_mentira(nombre, cuerpo):
    """Un ayudante de mentira: un programa de consola con ese cuerpo (entre begin y end.), compilado aqui."""
    d = os.path.join(JAIL, 'stubs', nombre)
    s.call('delphi_create', {'kind': 'project-console', 'name': nombre, 'dir': d})
    escribe(os.path.join(d, nombre + '.dpr'), 'program %s;\n\n{$APPTYPE CONSOLE}\n\nuses\n  System.SysUtils, System.IOUtils;\n\n'
            'begin\n%send.\n' % (nombre, cuerpo))
    j = mc.como_json(s.call('delphi_build', {'project': os.path.join(d, nombre + '.dproj'), 'platform': 'Win64',
                                             'config': 'Release'}, t=120)) or {}
    check('fixture: el ayudante de mentira %s compila' % nombre, j.get('success') is True, str(j)[:300])
    return os.path.join(d, 'Win64', 'Release', nombre + '.exe')


def dice(*lineas):
    return ''.join("  Writeln('%s');\n" % x for x in lineas) + '  Flush(Output);\n'


def se_queda(nombre, fases):
    """Su protocolo, esas fases, y se queda esperando a que lo paren."""
    return de_mentira(nombre, dice('PROTOCOL=' + PROTOCOLO, *[FASE + x for x in fases]) + '  Sleep(600000);\n')


def servidor_con(ayudante, nombre, raiz, cual='DelphiFormRenderVcl.exe'):
    """Un servidor nuevo con ese ayudante en el sitio de uno de los renderizadores."""
    d = os.path.join(BASE, 'srv-' + nombre)
    exe = mc.copia_exe(d, con_render=True)
    shutil.copy(ayudante, os.path.join(d, cual))
    return mc.Stdio(exe, mc.entorno({'DELPHI_MCP_ROOTS': raiz}), nombre='126-' + nombre, t=240)


def preview_con(ayudante, nombre, res):
    otro = servidor_con(ayudante, nombre, PRUEBA)
    try:
        res[nombre] = otro.call('delphi_designer', {'command': 'preview', 'path': os.path.join(PRUEBA, 'UP.dfm'),
                                                    'maxwidth': 100}, t=200)
    finally:
        otro.cierra()


mentiras = {'Paquetes': se_queda('Paquetes', [FASE_PAQUETES]), 'Form': se_queda('Form', [FASE_PAQUETES, FASE_FORM])}
res = {}
hilos = [threading.Thread(target=preview_con, args=(a, n, res)) for n, a in mentiras.items()]
for h in hilos:
    h.start()
for h in hilos:
    h.join(400)
r = res.get('Paquetes', '(sin respuesta)')
check('F2 el servidor para a un ayudante que lo ultimo que dijo es que cargaba los paquetes: DSGN-187, no '
      '"algo del form espera"', mc.es(r, 'SR_DESIGNER_RENDER_PAQUETES_TIEMPO_FMT')
      and not mc.es(r, 'SR_DESIGNER_RENDER_TIEMPO_FMT'), r[:400])
r = res.get('Form', '(sin respuesta)')
check('F2 ...y uno que ya habia pasado al form: DSGN-062, lo de siempre (cuenta la ULTIMA fase)',
      mc.es(r, 'SR_DESIGNER_RENDER_TIEMPO_FMT') and not mc.es(r, 'SR_DESIGNER_RENDER_PAQUETES_TIEMPO_FMT'), r[:400])

# ---- P: lo que encontro el revisor del paisaje de la 1.26
# P1 un texto cortado por la cabeza no parte un emoji (las filas de una tanda lo cortaban a 70 a mano)
MD = os.path.join(JAIL, 'cortes.md')
LINEA = 'a' * 69 + '\U0001F600' + 'zz'
with open(MD, 'w', encoding='utf-8', newline='') as f:
    f.write(LINEA + '\n')
r = s.call('delphi_textedit', {'path': MD, 'edits': [{'old': LINEA, 'new': 'hecho'}]})
check('P1 la fila de una tanda corta el ancla sin partir el emoji del caracter 70: ni medio caracter ni U+FFFD',
      not mc.fallo(r) and '�' not in r and not any(0xD800 <= ord(c) <= 0xDFFF for c in r)
      and open(MD, encoding='utf-8').read() == 'hecho\n', ascii(r[:300]))

# P2 las ops de un changeset codificadas dos veces se desenvuelven, como los edits de una tanda
A = os.path.join(JAIL, 'ops.txt')
with open(A, 'w', newline='') as f:
    f.write('uno\r\ndos\r\n')
ID = mc.id_changeset(s.call('delphi_changeset', {'command': 'begin'}))
t = s.call('delphi_changeset', {'command': 'stage', 'id': ID,
                                'ops': json.dumps(json.dumps([{'kind': 'edit', 'path': A, 'old': 'uno', 'new': 'UNO'}]))})
check('P2 ops codificadas dos veces (una cadena JSON dentro de la cadena): se apilan, no SR_CHANGESET_OPS_LISTA',
      not mc.fallo(t) and not mc.es(t, 'SR_CHANGESET_OPS_LISTA_FMT'), t[:300])
s.call('delphi_changeset', {'command': 'rollback', 'id': ID})

# P3 layout FMX: la linea del Edit1 del form, no la del inherited Edit1 del frame que va antes
M = os.path.join(JAIL, 'marco')
os.makedirs(M)
USOS_FMX = 'System.SysUtils, System.Types, System.UITypes, System.Classes, FMX.Types, FMX.Controls, FMX.Forms, FMX.Edit, FMX.Controls.Presentation'
escribe(os.path.join(M, 'UMarcoF.pas'), 'unit UMarcoF;\n\ninterface\n\nuses\n  %s;\n\ntype\n  TMarcoF = class(TFrame)\n'
        '    Edit1: TEdit;\n  end;\n\nimplementation\n\n{$R *.fmx}\n\nend.\n' % USOS_FMX)
escribe(os.path.join(M, 'UMarcoF.fmx'), 'object MarcoF: TMarcoF\n  Size.Width = 200.000000000000000000\n'
        '  Size.Height = 60.000000000000000000\n  Size.PlatformDefault = False\n  object Edit1: TEdit\n    TabOrder = 0\n'
        '    Position.X = 8.000000000000000000\n    Position.Y = 8.000000000000000000\n  end\nend\n')
escribe(os.path.join(M, 'UF2.pas'), 'unit UF2;\n\ninterface\n\nuses\n  %s, UMarcoF;\n\ntype\n  TFormF = class(TForm)\n'
        '    MarcoF1: TMarcoF;\n    Edit1: TEdit;\n  end;\n\nvar\n  FormF: TFormF;\n\nimplementation\n\n{$R *.fmx}\n\nend.\n' % USOS_FMX)
FORM_F = ("object FormF: TFormF\n  Left = 0\n  Top = 0\n  Caption = 'F'\n  ClientHeight = 300\n  ClientWidth = 400\n"
          "  FormFactor.Width = 320\n  FormFactor.Height = 480\n  FormFactor.Devices = [Desktop]\n  DesignerMasterStyle = 0\n"
          "  inline MarcoF1: TMarcoF\n    Size.Width = 200.000000000000000000\n    Size.Height = 60.000000000000000000\n"
          "    Size.PlatformDefault = False\n    inherited Edit1: TEdit\n      Text = 'del marco'\n    end\n  end\n"
          "  object Edit1: TEdit\n    TabOrder = 1\n    Position.X = 8.000000000000000000\n"
          "    Position.Y = 100.000000000000000000\n  end\nend\n")
escribe(os.path.join(M, 'UF2.fmx'), FORM_F)
LINEA_DEL_FORM = FORM_F.split('\n').index('  object Edit1: TEdit') + 1
LINEA_DEL_MARCO = FORM_F.split('\n').index('    inherited Edit1: TEdit') + 1
r = s.call('delphi_designer', {'command': 'layout', 'path': os.path.join(M, 'UF2.fmx')}, t=240)
cajas = {b.get('name'): b.get('line') for b in (mc.como_json(r).get('boxes') or [])}
check('P3 layout FMX: el Edit1 del form en SU linea (%d), no en la del inherited del frame (%d); el del frame, en la suya'
      % (LINEA_DEL_FORM, LINEA_DEL_MARCO),
      cajas.get('Edit1') == LINEA_DEL_FORM and cajas.get('MarcoF1.Edit1') == LINEA_DEL_MARCO, (cajas, r[:300]))

# P4 un set que el juez no pudo preguntar porque el ayudante se paro por tiempo (RENDER-027) no se niega como
# si el valor rompiera el form (DSGN-158): se escribe y readerNote lo dice. El de mentira se para con la
# propuesta (lleva claRed) y carga el form de antes
J4 = os.path.join(JAIL, 'juez')
os.makedirs(J4)
escribe(os.path.join(J4, 'UC.pas'), 'unit UC;\n\ninterface\n\nuses\n  %s;\n\ntype\n  TFormC = class(TForm)\n'
        '    Edit1: TEdit;\n  end;\n\nvar\n  FormC: TFormC;\n\nimplementation\n\n{$R *.fmx}\n\nend.\n' % USOS_FMX)
escribe(os.path.join(J4, 'UC.fmx'), "object FormC: TFormC\n  Left = 0\n  Top = 0\n  Caption = 'C'\n  ClientHeight = 480\n"
        "  ClientWidth = 640\n  FormFactor.Width = 320\n  FormFactor.Height = 480\n  FormFactor.Devices = [Desktop]\n"
        "  DesignerMasterStyle = 0\n  object Edit1: TEdit\n    Position.X = 10.000000000000000000\n"
        "    Position.Y = 10.000000000000000000\n    TabOrder = 0\n  end\nend\n")
JUEZ = de_mentira('SeParaConLaPropuesta',
                  "  Writeln('PROTOCOL=%s');\n"
                  "  var Ruta := '';\n"
                  "  for var I := 1 to ParamCount - 1 do\n"
                  "    if ParamStr(I) = '--path' then\n"
                  "      Ruta := ParamStr(I + 1);\n"
                  "  var Texto := TFile.ReadAllText(Ruta);\n"
                  "  if Texto.Contains('claRed') then\n"
                  "  begin\n"
                  "    Writeln('%s%s');\n"
                  "    Writeln('ERROR=ZZTIEMPOZZ');\n"
                  "    Flush(Output);\n"
                  "    Halt(%d);\n"
                  "  end;\n"
                  "  for var L in Texto.Split([#13#10, #10]) do\n"
                  "    Writeln('WRITTEN=' + L);\n"
                  "  Flush(Output);\n" % (PROTOCOLO, FASE, FASE_PAQUETES, RC_TIEMPO))
otro = servidor_con(JUEZ, 'juez', J4, 'DelphiFormRenderFmx.exe')
try:
    r = otro.call('delphi_designer', {'command': 'set', 'path': os.path.join(J4, 'UC.fmx'), 'component': 'Edit1',
                                      'prop': 'FontColor', 'value': 'claRed'}, t=240)
finally:
    otro.cierra()
nota = mc.como_json(r).get('readerNote') or ''
check('P4 el juez que se paro por tiempo no juzgo: el valor se escribe sin juzgar (DSGN-159), no DSGN-158',
      not mc.rechazado(r) and not mc.es(r, 'SR_DESIGNER_SET_ROMPE_CARGA_FMT') and mc.abre(nota, 'SN_DESIGNER_SET_SIN_JUZGAR_FMT')
      and b'FontColor = claRed' in open(os.path.join(J4, 'UC.fmx'), 'rb').read(), r[:400])

# P5 una conversion que su vigia para (RENDER-007) no culpa al form: es el tiempo del conversor (V102)
C5 = os.path.join(JAIL, 'conversor')
os.makedirs(C5)
escribe(os.path.join(C5, 'UP.dfm'), "object UP: TUP\n  Left = 0\n  Top = 0\n  ClientHeight = 60\n  ClientWidth = 80\nend\n")
CONV = de_mentira('ConversorParado', dice('PROTOCOL=' + PROTOCOLO, 'ERROR=ZZTIEMPOZZ') + '  Halt(%d);\n' % RC_TIEMPO)
otro = servidor_con(CONV, 'conversor', C5)
try:
    r = otro.call('delphi_designer', {'command': 'to-binary', 'path': os.path.join(C5, 'UP.dfm')}, t=240)
finally:
    otro.cierra()
TIEMPO_DEL_CONVERSOR = mc.catalogo()['SF_DSGN_CONVERSOR_TIEMPO_FMT'].split('%')[0].strip()
check('P5 el conversor parado por su vigia: el tiempo del conversor, no "algo del form espera"',
      mc.es(r, 'SR_DSGN_CONVERSOR_FALLO_FMT') and TIEMPO_DEL_CONVERSOR in r and 'ZZTIEMPOZZ' not in r, r[:400])

# P6 el ancla de vault_append en CRLF casa (vault_patch ya la pasaba a LF; append no)
VAULT = os.path.join(BASE, 'vault')
os.makedirs(VAULT)
with open(os.path.join(VAULT, 'nota.md'), 'wb') as f:
    f.write(b'# Nota\r\n\r\nuno\r\ndos\r\ntres\r\n')
otro = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_VAULT_PATH': VAULT,
                                 'DELPHI_MCP_VAULT_READONLY': '0'}), nombre='126-vault', t=120)
try:
    r = otro.call('vault_append', {'path': 'nota.md', 'content': '- tras dos', 'anchor': 'uno\r\ndos'})
finally:
    otro.cierra()
check('P6 vault_append con un ancla de dos lineas en CRLF: se anade tras ella',
      mc.abre(r, 'SK_VAULT_ANADIDO_COPIA_PREVIA_FMT') and b'dos\r\n- tras dos' in open(os.path.join(VAULT, 'nota.md'), 'rb').read(),
      r[:300])

# P7 una carpeta de proyecto con una coma: las salidas que suple el build van entre comillas (msbuild partia
# por ',' lo que iba sin ellas)
P7 = os.path.join(JAIL, 'Con,Coma')
s.call('delphi_create', {'kind': 'project-console', 'dir': P7, 'name': 'Coma'})
# sin su carpeta de .dcu, como un proyecto antiguo: esa es la que suple el build
t = s.call('delphi_config', {'command': 'remove-property', 'project': os.path.join(P7, 'Coma.dproj'), 'name': 'DCC_DcuOutput'})
check('P7 fixture: el proyecto se queda sin DCC_DcuOutput', not mc.fallo(t), t[:300])
j = mc.como_json(s.call('delphi_build', {'project': os.path.join(P7, 'Coma.dproj'), 'platform': 'Win64', 'config': 'Debug'}, t=300)) or {}
check('P7 un proyecto en una carpeta con coma, con la carpeta de .dcu suplida por el build, compila',
      j.get('success') is True and 'outputSupplied' in j, str(j)[:500])

s.cierra()
mc.borra(BASE)
mc.fin('capacidades 1.26')
