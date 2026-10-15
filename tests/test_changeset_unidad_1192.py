# -*- coding: utf-8 -*-
"""B de la 1.19.2 (Hermes sobre la 1.19.1, informe 115330; medido el 15-oct en
hermes1191\\diagh2077): delphi_changeset movia y borraba un fichero de Delphi como
un fichero SUELTO. move de una unidad con form de un proyecto: COMMIT COMPLETE con
la cabecera vieja ("unit UFormMov;" en UFormMovida.pas), el .dfm huerfano y el
.dpr apuntando a un .pas que ya no existe; delete: el .dfm huerfano y el .dpr
roto. delphi_move y delphi_delete los hacen ENTEROS (su .dfm/.fmx, su cabecera,
los proyectos que los listan, las rutas relativas que cruzan). Ahora el
changeset lo dice AL APILAR (CHSET-033), como dice CHSET-018 de un .dproj: un
preview que dice limpio de lo que el commit va a romper, miente.

  U1 move de una unidad con form: negado al apilar (CHSET-033, delphi_move), nada
     movido, el .dpr igual (ROJO en produccion)
  U2 delete de una unidad: el preview la deja sin resolver (nombrando
     delphi_delete) y el commit se niega; nada borrado (ROJO)
  U3 move de un .txt a un destino .pas: negado (ROJO)
  U4 move de un .dfm solo: negado (ROJO)
  U5 move de un .dproj: negado (ROJO)
  U6 move de una unidad a un .txt: negado por el origen (ROJO)
  C1 control: move de un .txt: commit, movido
  C2 control: delete de un .txt: commit, borrado
  C3 control: una edicion de un .pas por changeset sigue valiendo
  C4 control: delete + create del MISMO .pas (reescribirlo en su sitio): vale

Uso:  python tests/test_changeset_unidad_1192.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('changeset_unidad_1192')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))

s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='changeset-unidad', t=300)


def cs(**kw):
    return s.call('delphi_changeset', kw, t=120)


def abre():
    r = cs(command='begin')
    return r.split('CHANGESET ', 1)[1].split(' ', 1)[0]


def apila(**kw):
    """Un changeset de UNA operacion: (respuesta del stage, del commit o '')."""
    i = abre()
    st = cs(command='stage', id=i, **kw)
    if mc.rechazado(st):
        cs(command='rollback', id=i)
        return st, ''
    cs(command='preview', id=i)
    return st, cs(command='commit', id=i)


def negado_033(r):
    return mc.rechazado(r) and 'CHSET-033' in r


try:
    # cada caso con SUS ficheros, y los controles primero: en produccion las
    # negativas se ejecutan y la de antes le quitaba al siguiente su fichero
    d = os.path.join(JAIL, 'P')
    s.call('delphi_create', {'kind': 'project-vcl', 'name': 'P', 'dir': d}, t=120)
    DPR = os.path.join(d, 'P.dpr')
    for u in ('UFicha', 'UFicha2', 'UFicha3', 'UEdita', 'UEdita2'):
        s.call('delphi_create', {'kind': 'form-vcl', 'name': u, 'project': DPR}, t=120)
    for t in ('ctl.txt', 'notas.txt'):
        s.call('delphi_textedit', {'path': os.path.join(d, t), 'create': True, 'content': 'notas\n'})

    # los controles
    CTL = os.path.join(d, 'ctl.txt')
    st, cm = apila(kind='move', path=CTL, dest=os.path.join(d, 'ctl2.txt'))
    check('C1 control: move de un .txt: commit y movido',
          not mc.rechazado(st) and 'CHSET-025' in cm and os.path.exists(os.path.join(d, 'ctl2.txt'))
          and not os.path.exists(CTL), (st[:200], cm[:200]))
    st, cm = apila(kind='delete', path=os.path.join(d, 'ctl2.txt'))
    check('C2 control: delete de un .txt: commit y borrado',
          not mc.rechazado(st) and 'CHSET-025' in cm and not os.path.exists(os.path.join(d, 'ctl2.txt')),
          (st[:200], cm[:200]))
    EDITA = os.path.join(d, 'UEdita.pas')
    linea = next(l for l in mc.lee(EDITA).splitlines() if l.strip().startswith('TFormUEdita = class'))
    st, cm = apila(kind='edit', path=EDITA, old=linea, new=linea + '  // editada')
    check('C3 control: editar un .pas por changeset sigue valiendo',
          not mc.rechazado(st) and 'CHSET-025' in cm and '// editada' in mc.lee(EDITA), (st[:200], cm[:200]))

    # C4: borrar y volver a crear el MISMO .pas es reescribirlo en su sitio: vale
    EDITA2 = os.path.join(d, 'UEdita2.pas')
    nuevo = mc.lee(EDITA2).replace('implementation', '// reescrita\nimplementation', 1)
    i = abre()
    cs(command='stage', id=i, kind='delete', path=EDITA2)
    cs(command='stage', id=i, kind='create', path=EDITA2, content=nuevo)
    pv = cs(command='preview', id=i)
    cm = cs(command='commit', id=i)
    check('C4 control: delete + create del MISMO .pas en un lote: preview limpio y se aplica',
          '"unresolved":0' in pv and 'CHSET-025' in cm and '// reescrita' in mc.lee(EDITA2), (pv[:300], cm[:200]))

    PAS, DFM = os.path.join(d, 'UFicha.pas'), os.path.join(d, 'UFicha.dfm')
    dpr_antes, pas_antes, dfm_antes = mc.lee(DPR), mc.lee(PAS), mc.lee(DFM)
    st, cm = apila(kind='move', path=PAS, dest=os.path.join(d, 'UFichaNueva.pas'))
    check('U1 move de una unidad con form: CHSET-033 al apilar, nada movido, el .dpr igual',
          negado_033(st) and 'delphi_move' in st and cm == '' and mc.lee(PAS) == pas_antes
          and mc.lee(DFM) == dfm_antes and mc.lee(DPR) == dpr_antes, (st[:300], cm[:200]))
    PAS2 = os.path.join(d, 'UFicha2.pas')
    i = abre()
    st = cs(command='stage', id=i, kind='delete', path=PAS2)
    pv = cs(command='preview', id=i)
    cm = cs(command='commit', id=i)
    cs(command='rollback', id=i)
    # (el preview lleva el FRAGMENTO, sin etiqueta: un SF_ no la lleva; la del
    # apilado es CHSET-033)
    check('U2 delete de una unidad: el preview la deja sin resolver (delphi_delete), el commit '
          'se niega y nada se borra',
          not mc.rechazado(st) and 'UFicha2.pas' in pv and 'delphi_delete' in pv and '"unresolved":0' not in pv
          and mc.rechazado(cm) and os.path.exists(PAS2), (pv[:300], cm[:200]))
    TXT = os.path.join(d, 'notas.txt')
    st, cm = apila(kind='move', path=TXT, dest=os.path.join(d, 'UNotas.pas'))
    check('U3 move de un .txt a un destino .pas: CHSET-033', negado_033(st) and os.path.exists(TXT), st[:300])
    DFM2 = os.path.join(d, 'UFicha2.dfm')
    st, cm = apila(kind='move', path=DFM2, dest=os.path.join(d, 'Otra.dfm'))
    check('U4 move de un .dfm solo: CHSET-033', negado_033(st) and os.path.exists(DFM2), st[:300])
    st, cm = apila(kind='move', path=os.path.join(d, 'P.dproj'), dest=os.path.join(d, 'Q.dproj'))
    check('U5 move de un .dproj: CHSET-033', negado_033(st) and os.path.exists(os.path.join(d, 'P.dproj')), st[:300])
    PAS3 = os.path.join(d, 'UFicha3.pas')
    st, cm = apila(kind='move', path=PAS3, dest=os.path.join(d, 'UFicha3.txt'))
    check('U6 move de una unidad a un nombre que no es de Delphi: CHSET-033 por el ORIGEN',
          negado_033(st) and os.path.exists(PAS3), st[:300])
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('changeset: un fichero de Delphi se mueve y se borra entero 1.19.2 (B)')
