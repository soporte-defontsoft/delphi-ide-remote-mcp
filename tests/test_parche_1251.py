# -*- coding: utf-8 -*-
r"""Lo que fallaba en la 1.25.0 publicada, medido el 1-nov-2026 antes de planear la 1.26.

  T1 insert cuyo juez tarda mas de lo que espera un cliente (el renderizador suspendido
     mas de 50 s, de andamio: un form que espera al cargarse): en la 1.25.0 el cliente se
     rendia al minuto, el servidor seguia y ESCRIBIA, y el reintento duplicaba el control
     (medido en la VM: FileListBox2). Ahora no escribe tarde: DSGN-185, y el form no cambia.
  T1b repetir escribe, y una sola vez.
  T2 control: insert normal, escribe y no da DSGN-185.
  C1 preview de un frame inline que se contiene a si mismo: el renderizador caia a
     los 3,3 s con $C0000005 y DSGN-061 culpaba a un paquete. Ahora RENDER-026, con
     la cadena.
  C2 lint de ese frame: decia CLEAN de un form que no se carga.
  C3 control: un frame inline dos veces en un form, sin ciclo, se dibuja.
  C4 preview y lint no culpan del ciclo al codigo de un componente (Luna y Qwen, dirigido).
  I1 insert de un frame en si mismo: DSGN-186, no "no esta en la tabla" con la receta a mano,
     que llevaba a escribir el ciclo.
  I2 insert que cierra un ciclo por otro frame (UUno ya tiene a UDos, UDos en UUno): lo
     escribia con ok:true y la unidad de los dos con el uses circular. Ahora DSGN-186
     y nada escrito.
  I3 control: el primer insert de esos, sin ciclo, se escribe.
  I4 un control en un form que YA tiene el ciclo se inserta: el no lo cierra (mi primer
     arreglo le contestaba DSGN-186, cazado en vivo).
  I5 el ciclo se puede quitar a mano con delphi_edit, y lint queda limpio.
  N1 insert que escribe sin poder preguntar el orden: su DSGN-145 decia "Nothing was written"
     de lo que acababa de escribir (Qwen). N2 set index= en ese caso si niega, y lo dice.
  O1 VCL: el frame insertado con tres controles recibe TabOrder 3 (recibia 0,
     repetido), y el boton siguiente el 4.
  O2 control: un boton insertado sigue recibiendo el ultimo.
  E1 delphi_delete del propio enlace en un __delphi-temp: FILE-053 ya no manda
     solo a borrar el fichero real, que es lo vivo; nada se borra.

Rojo contra la 1.25.0: T1, C1, C2, O1, E1. Rojo sin este ultimo arreglo: C4, I1, I2.

Uso:  python tests/test_parche_1251.py [exe]
"""
import os, subprocess, threading, time
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('parche_1251')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_conversor=True, con_render=True)
s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='parche-1251', t=400)
d = lambda **kw: s.call('delphi_designer', kw, t=400)


def carpeta(nombre):
    p = os.path.join(JAIL, nombre)
    os.makedirs(p)
    return p


def escribe(ruta, texto):
    with open(ruta, 'wb') as f:
        f.write(texto.encode('ascii').replace(b'\n', b'\r\n'))


def unidad(ruta, nombre, clase, base, campos, usos):
    escribe(ruta, 'unit %s;\n\ninterface\n\nuses\n  %s;\n\ntype\n  %s = class(%s)\n%s  end;\n\nimplementation\n\n{$R *.dfm}\n\nend.\n'
            % (nombre, usos, clase, base, ''.join('    %s\n' % c for c in campos)))


# ---- T: el juez que tarda
F1 = carpeta('lento')
s.call('delphi_create', {'kind': 'project-vcl', 'dir': F1, 'name': 'Lento'})
DFM1 = os.path.join(F1, 'UMain.dfm')
r = d(command='preview', path=DFM1, maxwidth=100)   # la caja de paquetes hecha: sus ayudantes de vida corta no son el juez
antes = open(DFM1, 'rb').read()
resp = []
hilo = threading.Thread(target=lambda: resp.append(d(command='insert', path=DFM1, classname='TButton')))
t0 = time.time()
hilo.start()
rpid = 0
fin = time.time() + 30
while time.time() < fin and not rpid:
    rpid = mc.renderizador_hijo_de(s.p.pid)
    time.sleep(0.002)
suspendido = bool(rpid) and mc.suspende(rpid)
try:
    time.sleep(52)
finally:  # un renderizador suspendido no se queda asi si la bateria se corta aqui (revisor de baterias de la 1.27)
    if suspendido:
        mc.reanuda(rpid)
hilo.join(300)
r = resp[0] if resp else ''
dt = time.time() - t0
escrito = open(DFM1, 'rb').read()
check('T1 un juez que tarda: nada escrito tarde (DSGN-185) y el form como estaba',
      suspendido and mc.rechazado(r) and mc.es(r, 'SR_DESIGNER_JUEZ_TARDO_FMT') and escrito == antes,
      ('%.0f s' % dt, 'suspendido=%s' % suspendido, r[:260]))
if escrito == antes:
    r = d(command='insert', path=DFM1, classname='TButton')
cuerpo = open(DFM1, encoding='utf-8', errors='replace').read()
check('T1b repetir escribe, y una sola vez', 'Button1' in cuerpo and 'Button2' not in cuerpo and not mc.rechazado(r), r[:200])

F2 = carpeta('normal')
s.call('delphi_create', {'kind': 'project-vcl', 'dir': F2, 'name': 'Normal'})
DFM2 = os.path.join(F2, 'UMain.dfm')
r = d(command='insert', path=DFM2, classname='TButton')
check('T2 control: un insert normal escribe', 'Button1' in open(DFM2, encoding='utf-8', errors='replace').read() and not mc.rechazado(r), r[:200])

# ---- O: el TabOrder de lo que se suelta
r = d(command='insert', path=DFM2, classname='TButton')
r = d(command='insert', path=DFM2, classname='TButton')
s.call('delphi_create', {'kind': 'frame-vcl', 'name': 'UMarco', 'project': os.path.join(F2, 'Normal.dproj')})
CLASE_FRAME = 'TFrameUMarco'
r = d(command='insert', path=DFM2, classname=CLASE_FRAME)
check('O1 el frame insertado tras tres controles recibe el TabOrder 3', 'TabOrder = 3' in r, r[:300])
r = d(command='insert', path=DFM2, classname='TButton')
check('O2 control: el boton siguiente recibe el 4', 'TabOrder = 4' in r, r[:300])

# ---- C: el frame que se contiene a si mismo
F3 = carpeta('ciclo')
unidad(os.path.join(F3, 'UAuto.pas'), 'UAuto', 'TAuto', 'TFrame', ['Dentro: TAuto;'], 'Vcl.Forms')
AUTO = os.path.join(F3, 'UAuto.dfm')
escribe(AUTO, 'object Auto: TAuto\n  Left = 0\n  Top = 0\n  Width = 100\n  Height = 80\n  TabOrder = 0\n'
              '  inline Dentro: TAuto\n    Left = 0\n    Top = 0\n  end\nend\n')
r = d(command='preview', path=AUTO, maxwidth=100)
check('C1 preview de un frame que se contiene a si mismo: RENDER-026 con la cadena, sin culpar a un paquete',
      mc.es(r, 'SR_RENDER_FRAME_CICLICO_FMT') and 'UAuto.dfm' in r and not mc.es(r, 'SR_DESIGNER_RENDER_FALLO_FMT'), r[:300])
r = d(command='lint', path=AUTO)
check('C2 lint no dice CLEAN de ese frame', mc.es(r, 'SR_RENDER_FRAME_CICLICO_FMT') and not mc.es(r, 'SN_DESIGNER_LINT_OK_FMT'), r[:300])

F4 = carpeta('dos')
unidad(os.path.join(F4, 'UHoja.pas'), 'UHoja', 'THoja', 'TFrame', [], 'Vcl.Forms')
escribe(os.path.join(F4, 'UHoja.dfm'), 'object Hoja: THoja\n  Left = 0\n  Top = 0\n  Width = 40\n  Height = 30\n  TabOrder = 0\nend\n')
unidad(os.path.join(F4, 'UDos.pas'), 'UDos', 'TDos', 'TForm', ['H1: THoja;', 'H2: THoja;'], 'Vcl.Forms, UHoja')
DOS = os.path.join(F4, 'UDos.dfm')
escribe(DOS, "object Dos: TDos\n  Left = 0\n  Top = 0\n  Caption = 'Dos'\n  ClientHeight = 90\n  ClientWidth = 120\n"
             '  inline H1: THoja\n    Left = 0\n    Top = 0\n    TabOrder = 0\n  end\n'
             '  inline H2: THoja\n    Left = 50\n    Top = 0\n    TabOrder = 1\n  end\nend\n')
r = d(command='preview', path=DOS, maxwidth=100)
check('C3 control: el mismo frame dos veces, sin ciclo, se dibuja', 'screenshotBytes' in r and not mc.es(r, 'SR_RENDER_FRAME_CICLICO_FMT'), r[:220])

r = d(command='preview', path=AUTO, maxwidth=100)
r2 = d(command='lint', path=AUTO)
check('C4 preview y lint no culpan del ciclo al codigo de un componente',
      mc.es(r, 'SR_RENDER_FRAME_CICLICO_FMT') and mc.es(r2, 'SR_RENDER_FRAME_CICLICO_FMT') and
      not mc.es(r, 'SN_DESIGNER_PREVIEW_IGNORADAS_NO_CONFIRMADAS_FMT') and
      mc.catalogo()['SF_DSGN_LECTOR_DEL_CODIGO_FMT'].split('): ', 1)[1][:40] not in r2,  # del catalogo, no en ingles a mano
      (r[:300], r2[:300]))

# ---- I: insert no cierra un ciclo
F6 = carpeta('insert_ciclo')
s.call('delphi_create', {'kind': 'project-vcl', 'dir': F6, 'name': 'Cic'})
DPROJ6 = os.path.join(F6, 'Cic.dproj')
s.call('delphi_create', {'kind': 'frame-vcl', 'name': 'UUno', 'project': DPROJ6})
s.call('delphi_create', {'kind': 'frame-vcl', 'name': 'UDos', 'project': DPROJ6})
UNO, DOS = os.path.join(F6, 'UUno.dfm'), os.path.join(F6, 'UDos.dfm')


def bytes_de(*rutas):
    return [open(p, 'rb').read() for p in rutas]


antes = bytes_de(UNO, os.path.join(F6, 'UUno.pas'))
r = d(command='insert', path=UNO, classname='TFrameUUno')
check('I1 un frame en si mismo: DSGN-186, sin la receta a mano, y nada escrito',
      mc.rechazado(r) and mc.es(r, 'SR_DESIGNER_INSERT_FRAME_CICLICO_FMT') and not mc.es(r, 'SR_DESIGNER_CLASS_FMT') and
      bytes_de(UNO, os.path.join(F6, 'UUno.pas')) == antes, r[:300])
r = d(command='insert', path=UNO, classname='TFrameUDos')
check('I3 control: UDos en UUno, sin ciclo, se escribe', 'FrameUDos1' in open(UNO, encoding='utf-8', errors='replace').read() and not mc.rechazado(r), r[:220])
antes = bytes_de(DOS, os.path.join(F6, 'UDos.pas'))
r = d(command='insert', path=DOS, classname='TFrameUUno')
check('I2 UUno en UDos cerraria el ciclo: DSGN-186 con la cadena y nada escrito',
      mc.rechazado(r) and mc.es(r, 'SR_DESIGNER_INSERT_FRAME_CICLICO_FMT') and 'UDos.dfm > UUno.dfm > UDos.dfm' in r and
      bytes_de(DOS, os.path.join(F6, 'UDos.pas')) == antes, r[:420])

r = d(command='insert', path=AUTO, classname='TButton')
check('I4 un control en un form que ya tiene el ciclo se inserta, sin DSGN-186',
      not mc.es(r, 'SR_DESIGNER_INSERT_FRAME_CICLICO_FMT') and not mc.rechazado(r) and 'Button1' in open(AUTO, encoding='utf-8', errors='replace').read(), r[:300])
# su DSGN-145, y sin la frase de "nada escrito" del catalogo: 'Nothing was written' not in r, a mano, pasaba
# tambien sin la nota (revisor de baterias de la 1.27)
NADA_ESCRITO = mc.catalogo()['SF_DESIGNER_ORDEN_NADA_ESCRITO'].strip()[:40]
# ...ni ninguna otra del catalogo que lo diga: el trozo de UNA dejaba pasar las demas (revisor del
# diff de la cola de la 1.27); que la frase siga en el catalogo es parte del check
FRASE_NADA = 'Nothing was written'
CON_FRASE = [n for n, t in mc.catalogo().items() if FRASE_NADA in t]
check('N1 ese insert escribe, y su nota (DSGN-145) no dice que no escribio',
      mc.es(r, 'SN_DESIGNER_ULTIMO_SIN_JUEZ_FMT') and NADA_ESCRITO not in r and len(CON_FRASE) > 1 and
      FRASE_NADA not in r, (r[:900], len(CON_FRASE)))
antes = open(AUTO, 'rb').read()
r = d(command='set', path=AUTO, component='Button1', index=1)
check('N2 set index= sin poder preguntar el orden niega y lo dice', mc.rechazado(r) and NADA_ESCRITO in r and open(AUTO, 'rb').read() == antes, r[:400])
r = s.call('delphi_edit', {'path': AUTO, 'old': '  inline Dentro: TAuto\r\n    Left = 0\r\n    Top = 0\r\n  end', 'new': ''})
r2 = d(command='lint', path=AUTO)
check('I5 el ciclo se quita con delphi_edit y lint ya no lo ve',
      not mc.rechazado(r) and 'inline Dentro' not in open(AUTO, encoding='utf-8', errors='replace').read() and not mc.es(r2, 'SR_RENDER_FRAME_CICLICO_FMT'), (r[:220], r2[:220]))

# ---- E: el propio enlace dentro de un __delphi-temp
F5 = carpeta('enlace')
TEMP = os.path.join(F5, mc.TEMPORALES)
os.makedirs(TEMP)
VIVO = os.path.join(F5, 'vivo')
os.makedirs(VIVO)
with open(os.path.join(VIVO, 'dato.txt'), 'w') as f:
    f.write('dato')
ENL = os.path.join(TEMP, 'enlace')
subprocess.run(['cmd', '/c', 'mklink', '/J', ENL, VIVO], capture_output=True)
r = s.call('delphi_delete', {'path': ENL})
check('E1 FILE-053 sobre el propio enlace dice que el enlace es del operador; lo vivo sigue',
      mc.es(r, 'SR_FILE_DELETE_TEMP_ENLACE_FMT') and 'operator' in r and os.path.exists(os.path.join(VIVO, 'dato.txt')), r[:420])

s.cierra()
mc.borra(BASE)
mc.fin('parche 1.25.1')
