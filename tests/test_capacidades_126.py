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

# H2 una propiedad mala en el fichero de un frame en linea: el lector la salta leyendo el form; la entrada dice el
# fichero del frame y su linea alli (el ayudante dice que fichero leia: protocolo 4), y lint lo mismo
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
LINEA_NOEXISTE = MARCO_V.split('\n').index('    NoExiste = 1') + 1
r = s.call('delphi_designer', {'command': 'preview', 'path': os.path.join(H2, 'UFV.dfm'), 'maxwidth': 100}, t=400)
j = mc.como_json(r)
mala = [x for x in (j.get('ignored') or []) if x.get('property') == 'NoExiste']
check('H2 la propiedad mala del frame, en el preview del form: su fichero (el del frame) y su linea alli (%d)'
      % LINEA_NOEXISTE,
      len(mala) == 1 and (mala[0].get('file') or '').endswith('UMarcoV.dfm') and mala[0].get('line') == LINEA_NOEXISTE
      and mc.es(j.get('ignoredNote') or '', 'SN_DESIGNER_PREVIEW_IGNORADAS'), (mala, r[:400]))
r = s.call('delphi_designer', {'command': 'preview', 'path': os.path.join(H2, 'UMarcoV.dfm'), 'maxwidth': 100}, t=400)
mala = [x for x in (mc.como_json(r).get('ignored') or []) if x.get('property') == 'NoExiste']
check('H2 ...y en el preview del propio frame, su linea sin fichero (es el suyo)',
      len(mala) == 1 and mala[0].get('line') == LINEA_NOEXISTE and 'file' not in mala[0], (mala, r[:300]))
r = s.call('delphi_designer', {'command': 'lint', 'path': os.path.join(H2, 'UFV.dfm')}, t=400)
check('H2 lint del form: lo que salto el lector, en el fichero del frame y su linea',
      'UMarcoV.dfm line %d:' % LINEA_NOEXISTE in r, r[:600])

# H4 layout: un control de dentro de un frame en linea que el form no sobrescribe esta escrito en el fichero del
# frame: su caja dice ese fichero y su linea alli (salia line=0 y nada mas; Hermes, dirigido de la 1.26)
r = s.call('delphi_designer', {'command': 'layout', 'path': os.path.join(H2, 'UFV.dfm')}, t=400)
cajas = {b.get('name'): b for b in (mc.como_json(r).get('boxes') or [])}
b = cajas.get('MarcoV1.Edit1') or {}
check('H4 layout VCL: MarcoV1.Edit1 en UMarcoV.dfm, linea %d; el frame en el form, sin fichero'
      % (MARCO_V.split('\n').index('  object Edit1: TEdit') + 1),
      (b.get('file') or '').endswith('UMarcoV.dfm') and b.get('line') == MARCO_V.split('\n').index('  object Edit1: TEdit') + 1
      and 'file' not in (cajas.get('MarcoV1') or {'file': 1}), (b, r[:400]))

# H5 un frame que no se puede leer (una cadena sin cerrar): lo que dice el preview del form nombra el fichero del frame
H5 = os.path.join(JAIL, 'roto')
os.makedirs(H5)
escribe(os.path.join(H5, 'UMarcoR.pas'), 'unit UMarcoR;\n\ninterface\n\nuses\n  %s;\n\ntype\n  TMarcoR = class(TFrame)\n'
        '    Edit1: TEdit;\n  end;\n\nimplementation\n\n{$R *.dfm}\n\nend.\n' % USOS_VCL)
escribe(os.path.join(H5, 'UMarcoR.dfm'), "object MarcoR: TMarcoR\n  Left = 0\n  Top = 0\n  Width = 200\n  Height = 60\n"
        "  TabOrder = 0\n  object Edit1: TEdit\n    Left = 8\n    Top = 8\n    Text = 'sin cerrar\n  end\nend\n")
escribe(os.path.join(H5, 'UFR.pas'), 'unit UFR;\n\ninterface\n\nuses\n  %s, UMarcoR;\n\ntype\n  TFormR = class(TForm)\n'
        '    MarcoR1: TMarcoR;\n  end;\n\nvar\n  FormR: TFormR;\n\nimplementation\n\n{$R *.dfm}\n\nend.\n' % USOS_VCL)
escribe(os.path.join(H5, 'UFR.dfm'), "object FormR: TFormR\n  Left = 0\n  Top = 0\n  Caption = 'R'\n  ClientHeight = 200\n"
        "  ClientWidth = 300\n  inline MarcoR1: TMarcoR\n    Left = 10\n    Top = 10\n    TabOrder = 0\n  end\nend\n")
r = s.call('delphi_designer', {'command': 'preview', 'path': os.path.join(H5, 'UFR.dfm'), 'maxwidth': 100}, t=400)
check('H5 un frame que no se lee: el preview del form nombra el fichero del frame', 'UMarcoR.dfm' in r, r[:600])

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
# H4 ...y en FMX, lo que vio Hermes: el Edit1 del frame que el form no sobrescribe, en el fichero del frame
escribe(os.path.join(M, 'UF3.pas'), 'unit UF3;\n\ninterface\n\nuses\n  %s, UMarcoF;\n\ntype\n  TFormG = class(TForm)\n'
        '    MarcoF1: TMarcoF;\n  end;\n\nvar\n  FormG: TFormG;\n\nimplementation\n\n{$R *.fmx}\n\nend.\n' % USOS_FMX)
escribe(os.path.join(M, 'UF3.fmx'), "object FormG: TFormG\n  Left = 0\n  Top = 0\n  Caption = 'G'\n  ClientHeight = 300\n"
        "  ClientWidth = 400\n  FormFactor.Width = 320\n  FormFactor.Height = 480\n  FormFactor.Devices = [Desktop]\n"
        "  DesignerMasterStyle = 0\n  inline MarcoF1: TMarcoF\n    Size.Width = 200.000000000000000000\n"
        "    Size.Height = 60.000000000000000000\n    Size.PlatformDefault = False\n  end\nend\n")
r = s.call('delphi_designer', {'command': 'layout', 'path': os.path.join(M, 'UF3.fmx')}, t=240)
b = {x.get('name'): x for x in (mc.como_json(r).get('boxes') or [])}.get('MarcoF1.Edit1') or {}
check('H4 layout FMX: MarcoF1.Edit1, que el form no sobrescribe, en UMarcoF.fmx linea 5 (salia line=0)',
      (b.get('file') or '').endswith('UMarcoF.fmx') and b.get('line') == 5, (b, r[:400]))

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

# ---- H: lo que encontro Hermes en el dirigido de la 1.26 (H1-H2, arriba, con el ciclo)
# H3 la version que escribe set-version se lee en view (no se veia sin abrir el .dproj), y si los numeros y la
# clave FileVersion no dicen lo mismo, view lo dice
V3 = os.path.join(JAIL, 'Ver')
s.call('delphi_create', {'kind': 'project-vcl', 'dir': V3, 'name': 'Ver'})
DV = os.path.join(V3, 'Ver.dproj')
t = s.call('delphi_config', {'command': 'set-version', 'project': DV, 'version': '2.1.0', 'include': True})
check('H3 fixture: set-version 2.1.0 con include', mc.es(t, 'SN_CONFIG_VERSION_OK_FMT'), t[:300])
j = mc.como_json(s.call('delphi_config', {'command': 'view', 'project': DV}))
check('H3 view dice la version que escribio set-version y que los binarios la llevan',
      j.get('version') == '2.1.0.0' and j.get('versionIncluded') is True and 'versionMismatch' not in j, str(j)[:400])
t = s.call('delphi_config', {'command': 'set-property', 'project': DV, 'name': 'VerInfo_MajorVer', 'value': '3'})
check('H3 fixture: los numeros a mano, descuadrados de la clave', not mc.fallo(t), t[:300])
j = mc.como_json(s.call('delphi_config', {'command': 'view', 'project': DV}))
check('H3 ...y con los numeros descuadrados, la version del binario (la clave) y lo que dicen los numeros',
      j.get('version') == '2.1.0.0' and '3.1.0.0' in (j.get('versionMismatch') or ''), str(j)[:400])

# ---- R: lo que el revisor del paisaje de la 1.26 dejo para David, y entra (David, 2-nov: "no dejemos mierdas")
# RD un create de un changeset que no es Pascal nace como el de textedit: en CRLF y sin un salto final que nadie
# escribio (medido: "uno\ndos" salia "uno\r\ndos\r\n"); un .pas, como delphi_create
RD = os.path.join(JAIL, 'rd')
os.makedirs(RD)
ID = mc.id_changeset(s.call('delphi_changeset', {'command': 'begin'}))
s.call('delphi_changeset', {'command': 'stage', 'id': ID, 'ops': [
    {'kind': 'create', 'path': os.path.join(RD, 'c.txt'), 'content': 'uno\ndos'},
    {'kind': 'create', 'path': os.path.join(RD, 'UC.pas'), 'content': 'unit UC;\n\ninterface\n\nimplementation\n\nend.'}]})
s.call('delphi_changeset', {'command': 'preview', 'id': ID})
t = s.call('delphi_changeset', {'command': 'commit', 'id': ID})
check('RD fixture: el changeset crea los dos', not mc.fallo(t), t[:300])
txt = open(os.path.join(RD, 'c.txt'), 'rb').read() if os.path.exists(os.path.join(RD, 'c.txt')) else b''
check('RD un .txt creado por un changeset: en CRLF y sin salto final, como textedit create', txt == b'uno\r\ndos', txt)
pas = open(os.path.join(RD, 'UC.pas'), 'rb').read() if os.path.exists(os.path.join(RD, 'UC.pas')) else b''
check('RD ...y un .pas, como delphi_create: en CRLF y con su salto final', pas.endswith(b'end.\r\n'), pas[-20:])

# RG insert en FMX de un control que se sale de su padre: la respuesta lo dice, como en VCL (se saltaba FMX con la
# razon de antes de que layout lo midiera, y leia el texto del aviso por su prefijo)
RG = os.path.join(JAIL, 'rg')
os.makedirs(RG)
escribe(os.path.join(RG, 'UG.pas'), 'unit UG;\n\ninterface\n\nuses\n  %s;\n\ntype\n  TFormG2 = class(TForm)\n  end;\n\n'
        'var\n  FormG2: TFormG2;\n\nimplementation\n\n{$R *.fmx}\n\nend.\n' % USOS_FMX)
escribe(os.path.join(RG, 'UG.fmx'), "object FormG2: TFormG2\n  Left = 0\n  Top = 0\n  Caption = 'G'\n  ClientHeight = 300\n"
        "  ClientWidth = 400\n  FormFactor.Width = 320\n  FormFactor.Height = 480\n  FormFactor.Devices = [Desktop]\n"
        "  DesignerMasterStyle = 0\nend\n")
r = s.call('delphi_designer', {'command': 'insert', 'path': os.path.join(RG, 'UG.fmx'), 'classname': 'TEdit',
                               'props': 'Position.X=380'}, t=400)
fuera = mc.como_json(r).get('outsideParent') or []
check('RG insert FMX de un TEdit que se sale del form (380 + 100 > 400): outsideParent lo dice, y es el suyo',
      len(fuera) == 1 and fuera[0].startswith('Edit1'), r[:500])

# RF dos capturas de adb a la vez del mismo dispositivo: cada una con SU fichero alli (era uno fijo,
# /sdcard/delphi_mcp_screen.png, sin cerrojo: una se llevaba la de la otra y la otra no encontraba la suya). Con un
# adb de mentira, sin dispositivo: el "dispositivo" es una carpeta junto a el, y cada screencap deja un PNG con una
# huella suya detras y espera, para que las dos se crucen
RF = os.path.join(JAIL, 'rf')
os.makedirs(RF)
ADB = de_mentira('AdbFalso',
                 "  var Dev := TPath.Combine(ExtractFilePath(ParamStr(0)), 'Dev');\n"
                 "  ForceDirectories(Dev);\n"
                 "  var A: TArray<string> := [];\n"
                 "  for var I := 1 to ParamCount do\n"
                 "    A := A + [ParamStr(I)];\n"
                 "  if (Length(A) >= 2) and (A[0] = '-s') then\n"
                 "    A := Copy(A, 2, MaxInt);\n"
                 "  if (Length(A) >= 4) and (A[0] = 'shell') and (A[1] = 'screencap') then\n"
                 "  begin\n"
                 "    TFile.WriteAllBytes(TPath.Combine(Dev, TPath.GetFileName(A[3])),\n"
                 "      TFile.ReadAllBytes(TPath.Combine(ExtractFilePath(ParamStr(0)), 'base.png')) +\n"
                 "      TEncoding.ASCII.GetBytes(TGUID.NewGuid.ToString));\n"
                 "    Sleep(3000);\n"
                 "  end\n"
                 "  else if (Length(A) >= 3) and (A[0] = 'pull') then\n"
                 "  begin\n"
                 "    if not TFile.Exists(TPath.Combine(Dev, TPath.GetFileName(A[1]))) then\n"
                 "    begin\n"
                 "      Writeln('adb: error: remote object ''' + A[1] + ''' does not exist');\n"
                 "      Halt(1);\n"
                 "    end;\n"
                 "    TFile.Copy(TPath.Combine(Dev, TPath.GetFileName(A[1])), A[2], True);\n"
                 "    Writeln(A[1] + ': 1 file pulled');\n"
                 "  end\n"
                 "  else if (Length(A) >= 3) and (A[0] = 'shell') and (A[1] = 'rm') then\n"
                 "  begin\n"
                 "    if TFile.Exists(TPath.Combine(Dev, TPath.GetFileName(A[2]))) then\n"
                 "      TFile.Delete(TPath.Combine(Dev, TPath.GetFileName(A[2])));\n"
                 "  end\n"
                 "  else if (Length(A) >= 3) and (A[0] = 'shell') and (A[1] = 'wm') and (A[2] = 'size') then\n"
                 "    Writeln('Physical size: 1x1')\n"
                 "  else if (Length(A) >= 3) and (A[0] = 'shell') and (A[1] = 'wm') then\n"
                 "    Writeln('Physical density: 160');\n")
import struct, zlib


def trozo(tipo, datos):
    return struct.pack('>I', len(datos)) + tipo + datos + struct.pack('>I', zlib.crc32(tipo + datos) & 0xffffffff)


with open(os.path.join(os.path.dirname(ADB), 'base.png'), 'wb') as f:
    f.write(b'\x89PNG\r\n\x1a\n' + trozo(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 2, 0, 0, 0)) +
            trozo(b'IDAT', zlib.compress(b'\x00\xff\x00\x00')) + trozo(b'IEND', b''))
# un APPDATA de prueba cuyo SDK de Android dice que su adb es el de mentira (FindAdb lee SDKAdbPath de los .sdk)
APPD_RF, _ = mc.appdata_perfil(os.path.join(BASE, 'rf-ad'), 'mcp-e2e-rf', '127.0.0.1')
CON_ADB = 0
for raiz, _, ficheros in os.walk(APPD_RF):
    for f in ficheros:
        if f.lower().endswith('.sdk'):
            p = os.path.join(raiz, f)
            t = open(p, encoding='utf-8-sig').read()
            if '<SDKAdbPath>' in t:
                CON_ADB += 1
                open(p, 'w', encoding='utf-8').write(
                    re.sub(r'<SDKAdbPath>[^<]*</SDKAdbPath>', lambda m: '<SDKAdbPath>%s</SDKAdbPath>' % ADB, t))
if CON_ADB == 0:
    for v in os.listdir(os.path.join(APPD_RF, 'Embarcadero', 'BDS')):
        open(os.path.join(APPD_RF, 'Embarcadero', 'BDS', v, 'AdbFalso.sdk'), 'w', encoding='utf-8').write(
            '<Project><PropertyGroup><SDKAdbPath>%s</SDKAdbPath></PropertyGroup></Project>\n' % ADB)


def captura(nombre, res):
    otro = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'APPDATA': APPD_RF, 'DELPHI_MCP_ADB_DEVICES': 'FALSO1'}),
                    nombre='126-' + nombre, t=120)
    try:
        res[nombre] = otro.call('delphi_adb', {'command': 'screenshot', 'device': 'FALSO1',
                                               'out': os.path.join(RF, nombre + '.png')}, t=90)
    finally:
        otro.cierra()


res = {}
hilos = [threading.Thread(target=captura, args=(n, res)) for n in ('a', 'b')]
for h in hilos:
    h.start()
    time.sleep(0.5)
for h in hilos:
    h.join(200)
pa, pb = (open(os.path.join(RF, n + '.png'), 'rb').read() if os.path.exists(os.path.join(RF, n + '.png')) else b''
          for n in ('a', 'b'))
check('RF dos capturas a la vez del mismo dispositivo: las dos salen, y cada una es la suya',
      pa and pb and pa != pb and not mc.fallo(res.get('a', '')) and not mc.fallo(res.get('b', '')),
      (len(pa), len(pb), pa == pb, res.get('a', '')[:300], res.get('b', '')[:300]))

# RA un search path con prefijo de dispositivo que no es una unidad ni un UNC (\\?\GLOBALROOT\Device\...): la puerta
# del build le quitaba el prefijo y juzgaba lo que quedaba, una ruta RELATIVA que caia dentro del proyecto, mientras
# dcc abre el dispositivo. Un volumen que no existe: nada se lee aunque pasara
PRA = os.path.join(JAIL, 'ra')
s.call('delphi_create', {'kind': 'project-console', 'dir': PRA, 'name': 'Ra'})
t = s.call('delphi_config', {'command': 'set-property', 'project': os.path.join(PRA, 'Ra.dproj'),
                             'name': 'DCC_UnitSearchPath', 'value': r'\\?\GLOBALROOT\Device\HarddiskVolume999\nada'})
check('RA fixture: el search path se escribe (lo juzga el build)', not mc.fallo(t), t[:300])
r = s.call('delphi_build', {'project': os.path.join(PRA, 'Ra.dproj'), 'platform': 'Win64', 'config': 'Debug'}, t=300)
check('RA el build niega un search path de dispositivo que no es una unidad ni un UNC (BUILD-050), como fuera de '
      'toda raiz', mc.rechazado(r) and mc.es(r, 'SR_BUILD_LECTURA_FUERA_FMT'), r[:400])

# R23 el filtro de delphi_test va al runner de DUnitX, un programa Delphi que lee su linea con ParamStr: con las
# comillas del CRT de C (EnComillas) un filtro con una comilla cerraba el argumento y lo de detras eran OTRAS
# opciones de DUnitX (el texto del agente elegia opciones). Se niega antes de nada, como RUN-025
otro = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_ALLOW_TESTS': '1'}), nombre='126-test', t=120)
try:
    r = otro.call('delphi_test', {'command': 'run', 'project': os.path.join(JAIL, 'noexiste', 'T.dproj'),
                                  'filter': 'NoExiste" --exitbehavior:Pause "'}, t=90)
finally:
    otro.cierra()
check('R23 un filtro de delphi_test con una comilla se niega (TEST-037): no puede colar opciones al runner',
      mc.rechazado(r) and mc.es(r, 'SR_TEST_FILTRO_COMILLA_FMT'), r[:300])

# R14 dos repositorios en carpetas que NTFS separa (ss y la eszett): delphi_projects lista los dos. GUARDA: el
# IndexOf de un TStringList SIN ordenar descarta por la longitud antes de comparar, y estos dos no se juntaban
# (medido el 2-nov-2026: AnsiCompareText los da por iguales, IndexOf no los junta); los junta una lista ORDENADA (R15)
R14 = os.path.join(JAIL, 'r14')
for nombre in ('Strasse', 'Stra' + chr(0xDF) + 'e'):
    d = os.path.join(R14, nombre)
    s.call('delphi_create', {'kind': 'project-console', 'dir': d, 'name': 'P'})
    s.call('delphi_git', {'command': 'init', 'repo': d})
j = mc.como_json(s.call('delphi_projects', {'root': R14}))
repos = j.get('repos') or []
check('R14 dos repositorios en Strasse y en la carpeta con eszett: delphi_projects lista los dos',
      len(repos) == 2, str(repos)[:400])

# R15 una lista ORDENADA de rutas (TStringList con Sorted y su dupIgnore por defecto) compara con el locale
# (AnsiCompareText, lingueistica) y juntaba dos carpetas que NTFS separa: la segunda desaparecia. Medido el
# 2-nov-2026 en un proceso Delphi: de Strasse, la eszett, ab y a-guion-blando-b quedaban 2, tambien con
# CaseSensitive (la lista "exacta" de V105); AnsiCompareFileName, el juez de NTFS, las separa
R15 = os.path.join(JAIL, 'r15')
ESZETT = 'Stra' + chr(0xDF) + 'e'
for nombre in ('Strasse', ESZETT):
    os.makedirs(os.path.join(R15, nombre))
s.call('delphi_create', {'kind': 'project-console', 'dir': os.path.join(R15, 'P'), 'name': 'P'})
r = s.call('delphi_config', {'command': 'add-searchpath', 'project': os.path.join(R15, 'P', 'P.dproj'),
                             'paths': ['..\\Strasse', '..\\' + ESZETT]})
j = mc.como_json(s.call('delphi_projects', {'root': os.path.join(R15, 'P')}))
contra = [c for g in (j.get('projects') or []) for f in (g.get('files') or []) for c in (f.get('compilesAgainst') or [])]
check('R15 compilesAgainst nombra las dos carpetas del search path, Strasse y la de la eszett',
      len(contra) == 2, r[:200] + ' | ' + json.dumps(j, ensure_ascii=False)[:500])
# ...y los perfiles del IDE (Lsp.Discovery: dos perfiles Strasse y con la eszett, delphi_paserver profiles los dos)
APPD15, HOST15 = mc.appdata_perfil(os.path.join(BASE, 'r15-ad'), 'Strasse', '127.0.0.1', 'Linux64')
mc.appdata_perfil(os.path.join(BASE, 'r15-ad'), ESZETT, '127.0.0.1', 'Linux64')
otro = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'APPDATA': APPD15, 'DELPHI_MCP_REMOTE_HOSTS': HOST15}),
                nombre='126-perfiles', t=60)
try:
    t = json.dumps(mc.como_json(otro.call('delphi_paserver', {'command': 'profiles'})), ensure_ascii=False)
finally:
    otro.cierra()
check('R15 delphi_paserver profiles lista el perfil Strasse y el de la eszett', 'Strasse' in t and ESZETT in t, t[:600])

# R13 la cuenta del servidor (delphi_workspace) la dice Windows por el SID del proceso, no el entorno: con
# USERDOMAIN=DOMINIOFALSO salia DOMINIOFALSO\<cuenta>
otro = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'USERDOMAIN': 'DOMINIOFALSO'}), nombre='126-cuenta', t=60)
try:
    cuenta = str((mc.como_json(otro.call('delphi_workspace', {})).get('server') or {}).get('account', ''))
finally:
    otro.cierra()
check('R13 la cuenta del servidor no sale del entorno (USERDOMAIN=DOMINIOFALSO), y trae su dominio',
      cuenta != '' and 'DOMINIOFALSO' not in cuenta and '\\' in cuenta, cuenta)

# R7 el vigia del ayudante y su fase de paquetes salen del plazo de la llamada: layout espera 30 s y le mandaba
# --timeout 60000 y --packagestimeout 50000, asi que su vigia no hablaba nunca y lo paraba el servidor sin el
# por que. Un ayudante de mentira contesta ERROR= con su linea de ordenes; preview (75 s) sigue en 60000 y 50000
ORDEN = de_mentira('DiceSuOrden', dice('PROTOCOL=' + PROTOCOLO) +
                   "  Writeln('ERROR=ORDEN ' + string(CmdLine));\n  Flush(Output);\n  Halt(1);\n")
otro = servidor_con(ORDEN, 'orden', PRUEBA)
try:
    lay = otro.call('delphi_designer', {'command': 'layout', 'path': os.path.join(PRUEBA, 'UP.dfm')}, t=120)
    pre = otro.call('delphi_designer', {'command': 'preview', 'path': os.path.join(PRUEBA, 'UP.dfm'), 'maxwidth': 100},
                    t=120)
finally:
    otro.cierra()
check('R7 layout (30 s) da al ayudante --timeout 15000 y --packagestimeout 15000',
      '--timeout 15000' in lay and '--packagestimeout 15000' in lay, re.findall(r'-\w*timeout \d+', lay) or lay[:700])
check('R7 ...y preview (75 s), --timeout 60000 y --packagestimeout 50000, como antes',
      '--timeout 60000' in pre and '--packagestimeout 50000' in pre, re.findall(r'-\w*timeout \d+', pre) or pre[:700])

# R8 lo que un contenedor hace con sus hijos se pregunta por SU herencia (la tabla del marco), no por una lista de
# nombres que mezclaba los dos marcos: el TTabControl de la VCL, de una sola area, se tomaba por uno de paginas como
# el de FMX (dos botones solapados en el no se decian), y un TListBox FMX, que desciende de TScrollBox, no se tomaba
# por uno de scroll (sus items de mas salian como que se salen y no se ven)
R8 = os.path.join(JAIL, 'r8')
s.call('delphi_create', {'kind': 'project-vcl', 'dir': os.path.join(R8, 'V'), 'name': 'V8'})
DFM8 = os.path.join(R8, 'V', 'UMain.dfm')
s.call('delphi_designer', {'command': 'insert', 'path': DFM8, 'classname': 'TTabControl', 'props': 'Width=300;Height=200'})
for pos in ('Left=20;Top=40', 'Left=30;Top=45'):
    s.call('delphi_designer', {'command': 'insert', 'path': DFM8, 'classname': 'TButton', 'parent': 'TabControl1',
                               'props': pos})
j = mc.como_json(s.call('delphi_designer', {'command': 'layout', 'path': DFM8}, t=120))
check('R8 layout VCL: dos botones solapados dentro de un TTabControl se dicen (no es uno de paginas)',
      any('Button1' in o and 'Button2' in o for o in j.get('overlapping') or []), str(j.get('overlapping'))[:400])
s.call('delphi_create', {'kind': 'project-fmx', 'dir': os.path.join(R8, 'F'), 'name': 'F8'})
FMX8 = os.path.join(R8, 'F', 'UMain.fmx')
s.call('delphi_designer', {'command': 'insert', 'path': FMX8, 'classname': 'TListBox', 'props': 'Width=120;Height=40'})
for _ in range(3):
    s.call('delphi_designer', {'command': 'insert', 'path': FMX8, 'classname': 'TListBoxItem', 'parent': 'ListBox1'})
j = mc.como_json(s.call('delphi_designer', {'command': 'layout', 'path': FMX8}, t=120))
check('R8 layout FMX: los items de un TListBox que no caben se alcanzan con su scroll, no "se salen"',
      j.get('boxes') and not (j.get('outsideParent') or []), str(j.get('outsideParent'))[:400])
# ...y el Align que una clase de la VCL no escribe es el que redeclara con default en su fuente (TCoolBar y
# TControlBar no lo redeclaran; TCategoryPanelGroup, TActionToolBar... si)
FUENTE_VCL = os.path.join(mc.raiz_del_ide(), 'source', 'vcl')
redeclaradas = set()
for f in os.listdir(FUENTE_VCL):
    if f.lower().endswith('.pas'):
        clase = None
        for linea in open(os.path.join(FUENTE_VCL, f), encoding='utf-8-sig', errors='replace'):
            m = re.match(r'\s+(T\w+)\s*=\s*class\b', linea)
            if m:
                clase = m.group(1)
            m = re.match(r'\s+property Align\s+default\s+(al\w+)', linea, re.I)
            if m and clase:
                redeclaradas.add((clase, m.group(1)))
DIS = open(os.path.join(mc.REPO, 'src', 'Server', 'Mcp.Tools.Designer.pas'), encoding='utf-8-sig').read()
cuerpo = DIS[DIS.index('function DefaultAlign('):]
cuerpo = cuerpo[:cuerpo.index('\nend;')]
declaradas = set()
for lista, al in re.findall(r"\[([^\]]*)\]\)\s*then\s*Exit\('(al\w+)'\)", cuerpo):
    for c in re.findall(r"'[\w.]+:(T\w+)'", lista):
        declaradas.add((c, al))
check('R8 DefaultAlign trae cada clase de la VCL que redeclara Align con default, con ese Align, y no las que no',
      bool(redeclaradas) and redeclaradas <= declaradas and not {c for c, _ in declaradas} & {'TCoolBar', 'TControlBar'},
      'faltan %s; declaradas %s' % (sorted(redeclaradas - declaradas), sorted(declaradas)))

s.cierra()
mc.borra(BASE)
mc.fin('capacidades 1.26')
