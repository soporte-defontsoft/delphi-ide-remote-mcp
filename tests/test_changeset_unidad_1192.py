# -*- coding: utf-8 -*-
"""B de la 1.19.2 (Hermes sobre la 1.19.1, informe 115330; medido el 15-oct en
hermes1191\\diagh2077): delphi_changeset movia y borraba un fichero de Delphi como
un fichero SUELTO, COMMIT COMPLETE y el .dpr roto SIN DECIRLO. La 1.19.2 lo nego al
apilar (CHSET-033) porque delphi_move y delphi_delete lo hacian ENTERO. Desde V19
(1.23) las tres mueven y borran como el operador, lo nombrado y nada mas, y las
tres lo DICEN con la misma nota (Lsp.ProjectUnits.NotaDeMudanza): el par partido
(FILE-051) y lo que aun apunta a lo movido o lo borrado (MOVE-023, FILE-046).

  U1 move de una unidad con form: commit, movida sola, el .dpr igual, y la nota
     (el .dpr y el par partido) - ROJO en produccion (CHSET-033)
  U2 delete de una unidad: preview limpio, commit, borrada; FILE-046 nombra el
     .dpr y FILE-051 el form que queda (ROJO)
  U3 move de un .txt a un destino .pas: commit (ROJO)
  U4 move de un .dfm solo: commit, y el par partido (ROJO)
  U5 move de un .dproj: commit (ROJO)
  U6 move de una unidad a un .txt: commit (ROJO)
  C1 control: move de un .txt: commit, movido
  C2 control: delete de un .txt: commit, borrado
  C3 control: una edicion de un .pas por changeset sigue valiendo
  C4 control: delete + create del MISMO .pas (reescribirlo en su sitio): vale, y
     no es un borrado (sin FILE-046)
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


def nombra(r, p):
    """La nota nombra el fichero p con su ruta entera, como la ensena el servidor."""
    return mc.virtual(mc.larga(p)).lower() in (r or '').lower()


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
          not mc.rechazado(st) and mc.es(cm, 'SN_CHANGESET_COMMITTED_FMT') and os.path.exists(os.path.join(d, 'ctl2.txt'))
          and not os.path.exists(CTL), (st[:200], cm[:200]))
    st, cm = apila(kind='delete', path=os.path.join(d, 'ctl2.txt'))
    check('C2 control: delete de un .txt: commit y borrado',
          not mc.rechazado(st) and mc.es(cm, 'SN_CHANGESET_COMMITTED_FMT') and not os.path.exists(os.path.join(d, 'ctl2.txt')),
          (st[:200], cm[:200]))
    EDITA = os.path.join(d, 'UEdita.pas')
    linea = next(l for l in mc.lee(EDITA).splitlines() if l.strip().startswith('TFormUEdita = class'))
    st, cm = apila(kind='edit', path=EDITA, old=linea, new=linea + '  // editada')
    check('C3 control: editar un .pas por changeset sigue valiendo',
          not mc.rechazado(st) and mc.es(cm, 'SN_CHANGESET_COMMITTED_FMT') and '// editada' in mc.lee(EDITA), (st[:200], cm[:200]))

    # C4: borrar y volver a crear el MISMO .pas es reescribirlo en su sitio: vale
    EDITA2 = os.path.join(d, 'UEdita2.pas')
    nuevo = mc.lee(EDITA2).replace('implementation', '// reescrita\nimplementation', 1)
    i = abre()
    cs(command='stage', id=i, kind='delete', path=EDITA2)
    cs(command='stage', id=i, kind='create', path=EDITA2, content=nuevo)
    pv = cs(command='preview', id=i)
    cm = cs(command='commit', id=i)
    check('C4 control: delete + create del MISMO .pas en un lote: preview limpio, se aplica y no es un borrado',
          '"unresolved":0' in pv and mc.es(cm, 'SN_CHANGESET_COMMITTED_FMT') and '// reescrita' in mc.lee(EDITA2) and
          not mc.es(cm, 'SN_REFERENCIAS_A_LO_BORRADO_FMT'), (pv[:300], cm[:400]))

    PAS, DFM = os.path.join(d, 'UFicha.pas'), os.path.join(d, 'UFicha.dfm')
    dpr_antes, pas_antes, dfm_antes = mc.lee(DPR), mc.lee(PAS), mc.lee(DFM)
    NUEVA = os.path.join(d, 'UFichaNueva.pas')
    st, cm = apila(kind='move', path=PAS, dest=NUEVA)
    check('U1 move de una unidad con form: commit, movida SOLA (cabecera igual), el .dpr y el .dfm igual',
          not mc.rechazado(st) and mc.es(cm, 'SN_CHANGESET_COMMITTED_FMT') and mc.lee(NUEVA) == pas_antes and not os.path.exists(PAS)
          and mc.lee(DFM) == dfm_antes and mc.lee(DPR) == dpr_antes, (st[:300], cm[:300]))
    check('U1 ...y la nota de delphi_move: el .dpr que aun la lista (MOVE-023) y el par partido (FILE-051)',
          mc.es(cm, 'SN_REFERENCIAS_CRUZAN_FMT') and nombra(cm, DPR) and
          mc.es(cm, 'SN_FILE_PAR_PARTIDO_FMT') and 'UFicha.*' in cm, cm[:900])
    PAS2 = os.path.join(d, 'UFicha2.pas')
    i = abre()
    st = cs(command='stage', id=i, kind='delete', path=PAS2)
    pv = cs(command='preview', id=i)
    cm = cs(command='commit', id=i)
    check('U2 delete de una unidad: preview limpio, commit y borrada',
          not mc.rechazado(st) and '"unresolved":0' in pv and mc.es(cm, 'SN_CHANGESET_COMMITTED_FMT') and not os.path.exists(PAS2),
          (pv[:300], cm[:300]))
    check('U2 ...FILE-046 nombra el .dpr que aun la lista y FILE-051 el form que se queda',
          mc.es(cm, 'SN_REFERENCIAS_A_LO_BORRADO_FMT') and nombra(cm, DPR) and
          mc.es(cm, 'SN_FILE_PAR_PARTIDO_FMT') and os.path.exists(os.path.join(d, 'UFicha2.dfm')), cm[:900])
    TXT = os.path.join(d, 'notas.txt')
    st, cm = apila(kind='move', path=TXT, dest=os.path.join(d, 'UNotas.pas'))
    check('U3 move de un .txt a un destino .pas: commit, movido',
          mc.es(cm, 'SN_CHANGESET_COMMITTED_FMT') and os.path.exists(os.path.join(d, 'UNotas.pas')) and not os.path.exists(TXT), cm[:300])
    DFM3 = os.path.join(d, 'UFicha3.dfm')
    st, cm = apila(kind='move', path=DFM3, dest=os.path.join(d, 'Otra.dfm'))
    check('U4 move de un .dfm solo: commit, movido, y el par partido (su unit se queda)',
          mc.es(cm, 'SN_CHANGESET_COMMITTED_FMT') and os.path.exists(os.path.join(d, 'Otra.dfm')) and not os.path.exists(DFM3)
          and mc.es(cm, 'SN_FILE_PAR_PARTIDO_FMT'), cm[:600])
    st, cm = apila(kind='move', path=os.path.join(d, 'P.dproj'), dest=os.path.join(d, 'Q.dproj'))
    check('U5 move de un .dproj: commit, movido', mc.es(cm, 'SN_CHANGESET_COMMITTED_FMT') and os.path.exists(os.path.join(d, 'Q.dproj'))
          and not os.path.exists(os.path.join(d, 'P.dproj')), cm[:300])
    PAS3 = os.path.join(d, 'UFicha3.pas')
    st, cm = apila(kind='move', path=PAS3, dest=os.path.join(d, 'UFicha3.txt'))
    check('U6 move de una unidad a un nombre que no es de Delphi: commit, movida',
          mc.es(cm, 'SN_CHANGESET_COMMITTED_FMT') and os.path.exists(os.path.join(d, 'UFicha3.txt')) and not os.path.exists(PAS3), cm[:300])
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('changeset: un fichero de Delphi se mueve y se borra como el operador, y lo dice (B de la 1.19.2, V19)')
