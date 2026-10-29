# -*- coding: utf-8 -*-
"""V173a y V173c (1.23.1): ni el motor ni el ayudante del IDE corren con el
cerrojo de escritura del servidor cogido (EnterFileEdit, uno por proceso).

V173a: tras un delphi_edit de un .fmx, el lint que corre DENTRO del cerrojo
(Lsp.Patch.DesignerLint) juzgaba la clase raiz por su cadena de ancestros y,
con la base del usuario en otra unidad, arrancaba el motor (Lsp.Herencia):
un textedit de OTRO fichero esperaba (medido contra 13f78f3: 1,86 s de los 2,60
del edit, con el motor frio). La regla "con el cerrojo, sin motor" vivia en
cada llamador (AConMotor) y dos jueces del lint no la pasaban; ahora el lint,
con el cerrojo cogido, veda el motor entero (Lsp.Patch.LintDeForm:
VedaElMotor). Quien necesita el motor para decidir lo que escribe (add-unit,
el rename de una unidad) no esta vedado: test_raiz_de_diseno_1202.

V173c: delphi_designer set simple, props y Name juzgaban con el cerrojo de la
tool (el ayudante del IDE, el motor de los heredados); ahora cogen el cerrojo
solo para leer y para escribir (AbreFormParaJuzgar), como insert.

  Q1 (V173a) A edita UMain.fmx (TFormMain = class(TBaseForm), la base en UBase),
     motor FRIO; B, medio segundo despues, escribe un .txt: B no espera a A
  Q2 (V173c) A renombra Button1 (set Name: los heredados los dice el motor),
     motor FRIO; B no espera a A
  Q3 (V173c) A pone Position.X de Button1 (set simple: el ayudante del IDE),
     servidor nuevo; B no espera a A
  Q4 (control) el rename sigue preguntando al motor, ahora FUERA del cerrojo:
     un nombre que la base ya publica (Heredado1) se niega (DSGN-NOMBRE_OCUPADO)
  Q5 (V177) delphi_config add-unit de un data module cuya base esta en OTRA
     unidad (lo que es su raiz lo dice la cadena, por el motor), motor FRIO: B no
     espera a A (medido contra 7d0416d: 1,91 s de 2,33), y se registra como el
     data module que es ({Datos: TDataModule}: test_raiz_de_diseno_1202 P1)
  Q6 (V177) fix-references de ese data module, movido a mano, que el .dproj YA
     registra (su DesignClass: el juez contesta por el registro, sin motor),
     motor FRIO: ni A arranca el motor ni B espera (medido contra el primer
     V177, que lo juzgaba antes por la cadena siempre y con el cerrojo de
     ArreglaReferencias cogido: A 2,34 s, B 1,87; 7d0416d: A 0,13, B 0,02)
  Q7 (V177) el mismo fix-references con la unidad SIN registro de designer en el
     .dproj (el juez va a la cadena, el motor), motor FRIO: B no espera a A, y
     se re-apunta como el data module que es

Cada caso con un servidor recien lanzado (el motor frio es el que tarda). Si
A no tarda lo bastante para separar "espera" de "no espera", el caso sale
como NOTA, no en falso verde (como test_lector_cerrojo_120).

Uso:  python tests/test_cerrojo_motor_v173.py [ruta-al-exe]
"""
import os, sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
TOKEN = 'cerrojo-motor-v173'
B_DELAY = 0.5      # B entra cuando A ya tiene (o tenia) el cerrojo
MIN_A = 1.0        # A tiene que durar al menos esto para separar "espera" de "no espera"

WORK = mc.carpeta('cerrojo-motor-v173')
JAIL = os.path.join(WORK, 'jaula')
os.makedirs(JAIL)
EXE = mc.copia_exe(WORK, src=exe_src, con_render=True, con_conversor=True)
with open(os.path.join(WORK, 'settings.ini'), 'w') as f:
    f.write('[Workspace.Bateria]\nToken=%s\nRoots=%s\n' % (TOKEN, JAIL))
TXT = os.path.join(JAIL, 'notas.txt')
open(TXT, 'wb').write(b'uno\r\ndos\r\n')
P = os.path.join(JAIL, 'Ficha')
PAS = os.path.join(P, 'UMain.pas')
FMX = os.path.join(P, 'UMain.fmx')
# la base del usuario, de solo codigo y en OTRA unidad, con un componente publicado
BASE_PAS = ('unit UBase;\r\n\r\ninterface\r\n\r\nuses\r\n  System.Classes, FMX.Forms, FMX.StdCtrls;\r\n\r\n'
            'type\r\n  TBaseForm = class(TForm)\r\n    Heredado1: TButton;\r\n  end;\r\n\r\n'
            'implementation\r\n\r\nend.\r\n')


def servidor():
    port = mc.puerto_libre()
    proc = mc.lanza_http(EXE, port, mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1'}))
    cli = mc.Http(port, TOKEN, t=300)
    cli.session('cerrojo-motor')
    for fw, r in mc.espera_tablas(cli.call):
        assert mc.tabla_lista(r), (fw, r[:200])
    return proc, cli


NOTAS = []


def no_espera(clave, que, a, b_old, b_new, escrito):
    """A y B por un servidor NUEVO; check de que B no espero a A. escrito(ra) dice si A hizo lo suyo."""
    proc, cli = servidor()
    try:
        (ra, a_t), (rb, b_t), _ = mc.a_la_vez(
            cli.call, a, ('delphi_textedit', {'path': TXT, 'old': b_old, 'new': b_new}, 300), B_DELAY)
    finally:
        proc.kill()
    print('  (%s: A tardo %.2f s; B %.2f s)' % (clave, a_t, b_t))
    check('%s preparacion: A contesto y escribio, y B tambien' % clave,
          escrito(ra) and not mc.fallo(rb) and b_new.encode() in open(TXT, 'rb').read(),
          (ra[:300], rb[:200]))
    if a_t < MIN_A:
        NOTAS.append('%s no se mide: A tardo %.2f s, demasiado poco para separar espera de no espera' % (clave, a_t))
        return
    # con el motor/ayudante DENTRO del cerrojo B espera casi todo (13f78f3: 1,86 s de 2,60);
    # fuera, nada
    check('%s %s: B (otro fichero) tarda menos de la mitad de lo que A pasa tras su entrada' % (clave, que),
          b_t < (a_t - B_DELAY) / 2, (a_t, b_t))


# --- preparacion: el proyecto, con un servidor que luego se cierra
proc, cli = servidor()
try:
    r = cli.call('delphi_create', {'kind': 'project-fmx', 'name': 'Ficha', 'dir': P})
    assert not mc.fallo(r), r[:300]
    r = cli.call('delphi_create', {'kind': 'unit', 'name': 'UBase', 'project': os.path.join(P, 'Ficha.dproj'),
                                   'content': BASE_PAS})
    assert not mc.fallo(r), r[:300]
    r = cli.call('delphi_edit', {'path': PAS, 'old': '  TFormMain = class(TForm)',
                                 'new': '  TFormMain = class(TBaseForm)'})
    assert not mc.fallo(r), r[:300]
    r = cli.call('delphi_edit', {'path': PAS, 'adduses': 'UBase', 'section': 'interface'})
    assert not mc.fallo(r), r[:300]
    r = cli.call('delphi_designer', {'command': 'insert', 'path': FMX, 'classname': 'TButton',
                                     'component': 'Button1'}, t=300)
    assert not mc.fallo(r), r[:300]
finally:
    proc.kill()

try:
    no_espera('Q1', 'edit de un .fmx con su base en otra unidad (V173a)',
              ('delphi_edit', {'path': FMX, 'old': '    Position.X = 10.000000000000000000',
                               'new': '    Position.X = 11.000000000000000000'}, 300), 'dos', 'tres',
              lambda ra: not mc.fallo(ra) and b'Position.X = 11.0' in open(FMX, 'rb').read())
    no_espera('Q2', 'designer set Name (V173c)',
              ('delphi_designer', {'command': 'set', 'path': FMX, 'component': 'Button1', 'prop': 'Name',
                                   'value': 'Boton2'}, 300), 'tres', 'cuatro',
              lambda ra: not mc.fallo(ra) and b'Boton2: TButton' in open(FMX, 'rb').read())
    no_espera('Q3', 'designer set simple (V173c)',
              ('delphi_designer', {'command': 'set', 'path': FMX, 'component': 'Boton2', 'prop': 'Position.X',
                                   'value': '12'}, 300), 'cuatro', 'cinco',
              lambda ra: not mc.fallo(ra) and b'Position.X = 12.0' in open(FMX, 'rb').read())

    # Q4: el rename sigue preguntando al motor por los heredados (fuera del cerrojo)
    proc, cli = servidor()
    try:
        antes = open(FMX, 'rb').read()
        r = cli.call('delphi_designer', {'command': 'set', 'path': FMX, 'component': 'Boton2', 'prop': 'Name',
                                         'value': 'Heredado1'}, t=300)
    finally:
        proc.kill()
    check('Q4 control: renombrar a un nombre que la base ya publica (Heredado1) se niega y no escribe',
          mc.rechazado(r) and mc.es(r, 'SR_DESIGNER_NOMBRE_OCUPADO_FMT') and open(FMX, 'rb').read() == antes,
          r[:300])

    # Q5 (V177): add-unit, con lo que es su raiz por la cadena (el motor), fuera del cerrojo
    PV = os.path.join(JAIL, 'vcl')
    proc, cli = servidor()
    try:
        r = cli.call('delphi_create', {'kind': 'project-vcl', 'name': 'PRaiz', 'dir': PV})
        assert not mc.fallo(r), r[:300]
    finally:
        proc.kill()
    for nombre, texto in (('UBaseDM.pas', 'unit UBaseDM;\r\n\r\ninterface\r\n\r\nuses\r\n  System.Classes;\r\n\r\n'
                                          'type\r\n  TBaseDM = class(TDataModule)\r\n  end;\r\n\r\nimplementation\r\n\r\n'
                                          '{$R *.dfm}\r\n\r\nend.\r\n'),
                          ('UBaseDM.dfm', 'object BaseDM: TBaseDM\r\n  Height = 150\r\n  Width = 215\r\nend\r\n'),
                          ('UDatos.pas', 'unit UDatos;\r\n\r\ninterface\r\n\r\nuses\r\n  System.Classes, UBaseDM;\r\n\r\n'
                                         'type\r\n  TDatos = class(TBaseDM)\r\n  end;\r\n\r\nvar\r\n  Datos: TDatos;\r\n\r\n'
                                         'implementation\r\n\r\n{$R *.dfm}\r\n\r\nend.\r\n'),
                          ('UDatos.dfm', 'inherited Datos: TDatos\r\nend\r\n')):
        open(os.path.join(PV, nombre), 'wb').write(texto.encode('ascii'))
    DPRV = os.path.join(PV, 'PRaiz.dpr')
    no_espera('Q5', 'add-unit de un data module con su base en otra unidad (V177)',
              ('delphi_config', {'project': os.path.join(PV, 'PRaiz.dproj'), 'command': 'add-unit',
                                 'path': os.path.join(PV, 'UDatos.pas')}, 300), 'cinco', 'seis',
              lambda ra: not mc.fallo(ra) and
              b"UDatos in 'UDatos.pas' {Datos: TDataModule}" in open(DPRV, 'rb').read())

    # Q6 (V177): fix-references de UDatos movido a mano; el .dproj lo registra (Q5)
    def mueve(de, a):
        os.makedirs(os.path.join(PV, a))
        for ext in ('.pas', '.dfm'):
            os.rename(os.path.join(PV, de, 'UDatos' + ext), os.path.join(PV, a, 'UDatos' + ext))
    DPROJV = os.path.join(PV, 'PRaiz.dproj')
    mueve('', 'Sub')
    check('Q6 preparacion: el .dproj registra UDatos con su DesignClass (el juez contesta por el registro)',
          b'<DesignClass>TDataModule</DesignClass>' in open(DPROJV, 'rb').read())
    proc, cli = servidor()
    try:
        (ra, a_t), (rb, b_t), _ = mc.a_la_vez(
            cli.call, ('delphi_config', {'project': DPROJV, 'command': 'fix-references'}, 300),
            ('delphi_textedit', {'path': TXT, 'old': 'seis', 'new': 'siete'}, 300), B_DELAY)
    finally:
        proc.kill()
    print('  (Q6: A tardo %.2f s; B %.2f s)' % (a_t, b_t))
    check('Q6 fix-references de una unidad registrada: re-apuntada como data module, y B escribio',
          not mc.fallo(ra) and b"UDatos in 'Sub\\UDatos.pas' {Datos: TDataModule}" in open(DPRV, 'rb').read()
          and not mc.fallo(rb), (ra[:300], rb[:200]))
    check('Q6 ...sin arrancar el motor (A tarda menos de %.1f s) y sin que B espere' % MIN_A,
          a_t < MIN_A and b_t < MIN_A, (a_t, b_t))

    # Q7 (V177): el mismo, con la unidad SIN registro de designer en el .dproj
    dproj = open(DPROJV, 'rb').read()
    ini = dproj.index(b'<DCCReference Include="Sub\\UDatos.pas">')
    fin = dproj.index(b'</DCCReference>', ini) + len(b'</DCCReference>')
    open(DPROJV, 'wb').write(dproj[:ini] + b'<DCCReference Include="Sub\\UDatos.pas"/>' + dproj[fin:])
    mueve('Sub', 'Sub2')
    no_espera('Q7', 'fix-references de una unidad sin registro de designer (V177)',
              ('delphi_config', {'project': DPROJV, 'command': 'fix-references'}, 300), 'siete', 'ocho',
              lambda ra: not mc.fallo(ra) and
              b"UDatos in 'Sub2\\UDatos.pas' {Datos: TDataModule}" in open(DPRV, 'rb').read())
finally:
    mc.borra(WORK)

for n in NOTAS:
    print('NOTA: ' + n)
mc.fin('el motor y el ayudante fuera del cerrojo V173')
