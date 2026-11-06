# -*- coding: utf-8 -*-
r"""Los fallos LEIDOS que encontro el revisor del paisaje sobre TODO src antes del ritual de la 1.28 (J12-J20 de
la lista de cierre, seccion J), que David paso a la 1.29: cada uno con la entrada que lo dispara, rojo contra el
build de antes del arreglo y verde despues.

  R12 (J12) un ancla con un CR suelto dentro de una tanda: es un BLOQUE, como fuera de ella (la tanda miraba
      solo el LF, la tomaba por una linea y la regla de una linea la negaba con EDIT-001 diciendo que se mandara
      en edits: el agente daba vueltas)
  R13 (J13) un fichero llamado lote-123456789 (sin extension) borrado y restaurado con un comodin desde la
      papelera vuelve con SU nombre (el lector quitaba TODO sufijo de 9 cifras y volvia como "lote")
  R14 (J14) mover un fichero desde un __delphi-temp viejo: llega, y no deja una papelera DENTRO de la temporal
      (de un temporal no se restaura nada: la regla de GuardaContenidoActual, que el move rehacia sin ella)
  R15 (J15) una unidad junto a un unico .dproj que la sesion no puede leer (un enlace duro cuyo otro nombre
      esta fuera de las raices): diagnostics sigue sin configuracion, no GUARD-041 por un fichero que el agente
      ni nombro (BuscaDproj adoptaba el candidato unico sin la puerta de lectura)
  R17 (J17) adduses Graphics en el .dpr de un proyecto VCL con un Graphics.pas en una subcarpeta que dcc no
      mira: entra como unidad de biblioteca (dcc toma Vcl.Graphics), como lo juzga removeuses; adduses miraba el
      nombre crudo y lo mandaba a add-unit (USES-021)
  R20 (J20) un proyecto FMX con su icono de macOS (Icns_MainIcns, que escribe nuestro scaffold) en una carpeta
      suya: al mover la carpeta, MOVE-023 nombra el .dproj (no estaba en la lista de rutas del .dproj y el move
      callaba)

Uso:  python tests/test_revisor_paisaje_129.py [exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('revisor_paisaje_129')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='revisor-paisaje-129', t=300)


def escribe(ruta, texto):
    with open(ruta, 'wb') as f:
        f.write(b'\xef\xbb\xbf' + texto.replace('\n', '\r\n').encode('utf-8'))


try:
    # --- R12 (J12) ---------------------------------------------------------------
    U12 = os.path.join(JAIL, 'UJ12.pas')
    escribe(U12, 'unit UJ12;\n\ninterface\n\nimplementation\n\nprocedure P;\nvar\n  X, Y: Integer;\nbegin\n'
                 '  X := 1;\n  Y := 2;\nend;\n\nend.\n')
    r = s.call('delphi_edit', {'path': U12, 'edits': [{'old': '  X := 1;\r  Y := 2;', 'new': '  X := 10;\n  Y := 20;'}]})
    check('R12 un ancla con un CR suelto en una tanda: es un bloque y se aplica',
          mc.es(r, 'SN_PATCH_EDITS_OK_FMT') and '  X := 10;\r\n  Y := 20;' in mc.lee(U12), (r[:300], mc.lee(U12)[-80:]))
    # --- R13 (J13) ---------------------------------------------------------------
    L13 = os.path.join(JAIL, 'lote-123456789')
    open(L13, 'wb').write(b'datos del lote\r\n')
    r = s.call('delphi_delete', {'path': L13})
    papelera = [os.path.join(dp, f) for dp, _, fs in os.walk(JAIL) for f in fs if f.startswith('lote-123456789-')]
    r2 = s.call('delphi_move', {'path': os.path.join(os.path.dirname(papelera[0]), 'lote-123456789-*'),
                                'dest': JAIL}) if papelera else ''
    check('R13 lote-123456789 vuelve de la papelera con su nombre, no como "lote"',
          os.path.isfile(L13) and not os.path.exists(os.path.join(JAIL, 'lote')), (r[:200], r2[:300]))
    # --- R14 (J14) ---------------------------------------------------------------
    T14 = os.path.join(JAIL, mc.TEMPORALES, 'viejo')
    os.makedirs(T14)
    open(os.path.join(T14, 'x.txt'), 'wb').write(b'x\r\n')
    r = s.call('delphi_move', {'path': os.path.join(T14, 'x.txt'), 'dest': os.path.join(JAIL, 'x14.txt')})
    dentro = [os.path.join(dp, d) for dp, ds, _ in os.walk(os.path.join(JAIL, mc.TEMPORALES)) for d in ds
              if d == mc.PAPELERA]
    check('R14 mover desde un __delphi-temp viejo: llega y no deja una papelera dentro de la temporal',
          os.path.isfile(os.path.join(JAIL, 'x14.txt')) and not dentro, (r[:300], dentro))
    # --- R15 (J15) ---------------------------------------------------------------
    D15 = os.path.join(JAIL, 'J15')
    os.makedirs(D15)
    FUERA15 = os.path.join(BASE, 'P15.dproj')  # fuera de la raiz (la raiz es JAIL)
    open(FUERA15, 'wb').write(b'<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"></Project>\r\n')
    os.link(FUERA15, os.path.join(D15, 'P15.dproj'))
    U15 = os.path.join(D15, 'U15.pas')
    escribe(U15, 'unit U15;\n\ninterface\n\nprocedure Hola;\n\nimplementation\n\nprocedure Hola;\nbegin\nend;\n\nend.\n')
    r = s.call('delphi_diagnostics', {'path': U15}, 240)
    # sin un proyecto que la sirva, la respuesta de siempre (LSP-035), no la de un fichero que nadie nombro
    check('R15 diagnostics junto a un .dproj ilegible: como sin proyecto (LSP-035), no GUARD-041/042',
          mc.abre(r, 'SR_LSP_LINT_SIN_AJUSTES_FMT') and 'GUARD-04' not in r, r[:300])
    # --- R17 (J17) ---------------------------------------------------------------
    D17 = os.path.join(JAIL, 'P17')
    s.call('delphi_create', {'kind': 'project-vcl', 'name': 'P17', 'dir': D17})
    os.makedirs(os.path.join(D17, 'Otros'))
    escribe(os.path.join(D17, 'Otros', 'Graphics.pas'), 'unit Graphics;\n\ninterface\n\nimplementation\n\nend.\n')
    DPR17 = os.path.join(D17, 'P17.dpr')
    r = s.call('delphi_edit', {'path': DPR17, 'adduses': 'Graphics'})
    check('R17 adduses Graphics con un Graphics.pas que dcc no mira: entra como de biblioteca',
          not mc.es(r, 'SR_ADDUSES_UNIDAD_DEL_PROYECTO_FMT') and 'Graphics' in mc.lee(DPR17).split('begin')[0],
          r[:300])
    # --- R20 (J20) ---------------------------------------------------------------
    D20 = os.path.join(JAIL, 'P20')
    s.call('delphi_create', {'kind': 'project-fmx', 'name': 'P20', 'dir': D20})
    os.makedirs(os.path.join(D20, 'iconos'))
    open(os.path.join(D20, 'iconos', 'app.icns'), 'wb').write(b'icns')
    DPROJ20 = os.path.join(D20, 'P20.dproj')
    r0 = s.call('delphi_config', {'command': 'set-property', 'project': DPROJ20, 'name': 'Icns_MainIcns',
                                  'value': 'iconos' + chr(92) + 'app.icns'})
    r = s.call('delphi_move', {'path': os.path.join(D20, 'iconos'), 'dest': os.path.join(D20, 'arte')})
    # un move no re-apunta (un operador no lo hace): NOMBRA lo que apunta dentro de lo movido (MOVE-023)
    check('R20 mover la carpeta del icono de macOS: MOVE-023 nombra el .dproj que apunta a ella',
          mc.es(r, 'SN_REFERENCIAS_CRUZAN_FMT') and 'P20.dproj' in r, (r0[:150], r[:500]))
finally:
    s.cierra()
    mc.borra(BASE)
mc.fin('revisor del paisaje 1.29 (J12-J20)')
