# -*- coding: utf-8 -*-
r"""El juez de una edicion del disenador, con el plazo de la edicion (R4 del revisor del paisaje de la 1.27).

Una edicion tiene lo que espera un cliente (ESPERA_DEL_CLIENTE_MS) para juzgarse: pasado, DSGN-185 y nada
escrito. Pero cada juez se lanzaba con el plazo de un preview (RENDER_TIEMPO_MS; su vigia MARGEN_DEL_VIGIA_MS
antes): uno colgado contestaba a los 75 s, cuando el cliente ya se habia rendido al minuto, y un segundo juez
de la misma edicion volvia a tener el plazo entero.

  J1 insert con el renderizador del juez suspendido y sin reanudar (andamio de un juez colgado): DSGN-185,
     el form como estaba, y la respuesta entre lo que espera un cliente (no antes: el juez tuvo su plazo) y
     el plazo de un preview menos un margen (antes, el servidor lo paraba ahi). Las tres constantes, del
     fuente (Lsp.FormRender).
  J2 control: repetir el insert escribe, una sola vez.
  J3 (A3 del revisor del paisaje de la 1.27) delphi_edit de un form con un frame en linea: lo escrito lo
     juzga DESPUES el lector del IDE (AvisosDelLector), y ese juez tenia el plazo de un preview, con la
     edicion ya en disco. Con su renderizador suspendido, la edicion escrita, sin fallo, y la respuesta
     entre lo que espera un cliente y el plazo de un preview menos un margen: lo que le queda a la
     llamada, contado desde que empezo (PlazoDelCliente).
  J4 ...y la respuesta DICE que el lector no confirmo el form (EDIT-131, con su porque): se callaba, y el
     silencio se leia como que el form carga.
  J5 delphi_designer lint del mismo form, con su lector suspendido: el plazo del cliente desde que empezo
     la llamada, como las ediciones (tenia el de un preview), y DSGN-154 en vez de CLEAN.
  J6 ...y DSGN-154 (y EDIT-131) dicen por que se le pregunto al lector: un frame en linea, no '0 line(s) hold a
     property' de un form que no tiene ninguna.

Rojo contra a92f053: J1 (75,1 s). Mutante: Pet.PlazoMs := 0 en JuezDelIde (Lsp.FormRender) -> J1 rojo.
Rojo contra c582da0 (produccion del 4-nov): J3 (75,2 s, con la edicion ya escrita al suspender el juez), J4 (la
respuesta, sin una palabra del lector), J5 (75,2 s) y J6 ('0 line(s) hold a property', medido).

Uso:  python tests/test_juez_plazo_127.py [exe]
"""
import os, threading, time
import mcp_cliente as mc
from mcp_cliente import check

ESPERA_S = mc.entero_del_fuente('Server/Lsp.FormRender.pas', 'ESPERA_DEL_CLIENTE_MS') / 1000
RENDER_S = mc.entero_del_fuente('Server/Lsp.FormRender.pas', 'RENDER_TIEMPO_MS') / 1000

BASE = mc.carpeta('juez_plazo_127')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_conversor=True, con_render=True)
s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='juez-plazo-127', t=400)
d = lambda **kw: s.call('delphi_designer', kw, t=400)
rpid = 0
suspendido = False
rpid3 = 0
suspendido3 = False
rpid5 = 0
suspendido5 = False
try:
    # las tablas listas: con la cache fria el juez no llega a lanzarse y J1 seria otro rojo
    tablas = mc.espera_tablas(s.call)
    check('fixture: las tablas del disenador listas', all(mc.tabla_lista(r) for _, r in tablas),
          [r[:160] for _, r in tablas])
    F1 = os.path.join(JAIL, 'colgado')
    os.makedirs(F1)
    r = s.call('delphi_create', {'kind': 'project-vcl', 'dir': F1, 'name': 'Colgado'})
    DFM1 = os.path.join(F1, 'UMain.dfm')
    check('fixture: el proyecto nace', not mc.fallo(r) and os.path.isfile(DFM1), r[:200])
    # la caja de paquetes hecha: sus ayudantes de vida corta no son el juez
    r = d(command='preview', path=DFM1, maxwidth=100)
    check('fixture: el preview dibuja', not mc.fallo(r) and 'screenshotBytes' in r, r[:200])
    antes = open(DFM1, 'rb').read()
    resp = []
    hilo = threading.Thread(target=lambda: resp.append(d(command='insert', path=DFM1, classname='TButton')))
    t0 = time.time()
    hilo.start()
    fin = time.time() + 30
    while time.time() < fin and not rpid:
        rpid = mc.renderizador_hijo_de(s.p.pid)
        time.sleep(0.002)
    suspendido = bool(rpid) and mc.suspende(rpid)
    hilo.join(300)
    dt = time.time() - t0
    r = resp[0] if resp else ''
    escrito = open(DFM1, 'rb').read()
    check('J1 un juez colgado se para en el plazo de la edicion: DSGN-185 entre %.0f y %.0f s y el form como estaba'
          % (ESPERA_S, RENDER_S - 2),
          suspendido and mc.rechazado(r) and mc.es(r, 'SR_DESIGNER_JUEZ_TARDO_FMT') and escrito == antes and
          ESPERA_S <= dt < RENDER_S - 2,
          ('%.1f s' % dt, 'suspendido=%s' % suspendido, r[:260]))
    r = d(command='insert', path=DFM1, classname='TButton')
    cuerpo = open(DFM1, encoding='utf-8', errors='replace').read()
    check('J2 control: repetir escribe, y una sola vez', 'Button1' in cuerpo and 'Button2' not in cuerpo and not mc.fallo(r),
          r[:200])

    # J3: un form con un frame en linea (esa carga no la juzga ninguna tabla: va al lector del IDE)
    F3 = os.path.join(JAIL, 'escrito')
    os.makedirs(F3)
    for nombre, texto in (
            ('UMarco.pas', "unit UMarco;\n\ninterface\n\nuses\n  System.Classes, Vcl.Forms, Vcl.StdCtrls, Vcl.Controls;\n\n"
                           "type\n  TFrameUMarco = class(TFrame)\n    EdMarco: TEdit;\n  end;\n\nimplementation\n\n"
                           "{$R *.dfm}\n\nend.\n"),
            ('UMarco.dfm', "object FrameUMarco: TFrameUMarco\n  Left = 0\n  Top = 0\n  Width = 320\n  Height = 240\n"
                           "  TabOrder = 0\n  object EdMarco: TEdit\n    Left = 10\n    Top = 10\n    Width = 121\n"
                           "    Height = 23\n    TabOrder = 0\n  end\nend\n"),
            ('UConMarco.pas', "unit UConMarco;\n\ninterface\n\nuses\n  System.Classes, Vcl.Forms, Vcl.StdCtrls, Vcl.Controls, "
                              "UMarco;\n\ntype\n  TFConMarco = class(TForm)\n    Marco1: TFrameUMarco;\n  end;\n\n"
                              "implementation\n\n{$R *.dfm}\n\nend.\n"),
            ('UConMarco.dfm', "object FConMarco: TFConMarco\n  Caption = 'Antes'\n  ClientWidth = 400\n  ClientHeight = 300\n"
                              "  inline Marco1: TFrameUMarco\n    Left = 24\n    Top = 30\n    TabOrder = 0\n  end\nend\n")):
        with open(os.path.join(F3, nombre), 'w', newline='\r\n') as f:
            f.write(texto)
    DFM3 = os.path.join(F3, 'UConMarco.dfm')
    resp = []
    hilo = threading.Thread(target=lambda: resp.append(
        s.call('delphi_edit', {'path': DFM3, 'old': "Caption = 'Antes'", 'new': "  Caption = 'Despues'"}, t=400)))
    t0 = time.time()
    hilo.start()
    fin = time.time() + 30
    while time.time() < fin and not rpid3:
        p = mc.renderizador_hijo_de(s.p.pid)
        if p and p != rpid:
            rpid3 = p
        time.sleep(0.002)
    # el juez que se suspende es el de DESPUES de escribir: la edicion ya esta en disco
    ya_escrito = bool(rpid3) and b'Despues' in open(DFM3, 'rb').read()
    suspendido3 = bool(rpid3) and mc.suspende(rpid3)
    hilo.join(300)
    dt = time.time() - t0
    r = resp[0] if resp else ''
    check('J3 delphi_edit de un form: el lector del IDE que juzga lo escrito tiene lo que le queda a la llamada, '
          'no el plazo de un preview: respuesta entre %.0f y %.0f s, la edicion escrita y sin fallo' % (ESPERA_S, RENDER_S - 2),
          suspendido3 and ya_escrito and not mc.fallo(r) and ESPERA_S <= dt < RENDER_S - 2 and
          b'Despues' in open(DFM3, 'rb').read(),
          ('%.1f s' % dt, 'suspendido=%s' % suspendido3, 'ya_escrito=%s' % ya_escrito, r[:260]))
    check('J4 ...y la respuesta lo DICE: el lector del IDE no confirmo que el form carga (EDIT-131), con su porque',
          mc.es(r, 'SN_EDIT_LECTOR_SIN_CONFIRMAR_FMT') and 'UConMarco.dfm' in r, r[-600:])
    edit3 = [r]

    # J5: el lint del mismo form, con su lector suspendido
    resp = []
    hilo = threading.Thread(target=lambda: resp.append(d(command='lint', path=DFM3)))
    t0 = time.time()
    hilo.start()
    fin = time.time() + 30
    while time.time() < fin and not rpid5:
        p = mc.renderizador_hijo_de(s.p.pid)
        if p and p not in (rpid, rpid3):
            rpid5 = p
        time.sleep(0.002)
    suspendido5 = bool(rpid5) and mc.suspende(rpid5)
    hilo.join(300)
    dt = time.time() - t0
    r = resp[0] if resp else ''
    check('J5 delphi_designer lint: su lector del IDE tiene lo que le queda a la llamada, no el plazo de un preview: '
          'respuesta entre %.0f y %.0f s, y DSGN-154 (no CLEAN)' % (ESPERA_S, RENDER_S - 2),
          suspendido5 and ESPERA_S <= dt < RENDER_S - 2 and mc.es(r, 'SN_DESIGNER_LINT_SIN_LECTOR_FMT') and
          not mc.es(r, 'SN_DESIGNER_LINT_OK_FMT'),
          ('%.1f s' % dt, 'suspendido=%s' % suspendido5, r[:400]))
    POR_FRAME = mc.catalogo()['SF_DSGN_LECTOR_POR_FRAME']
    check('J6 ...y dice el motivo real: un frame en linea, sin contar lineas que no hay (ni el lint ni la edicion)',
          POR_FRAME in r and '0 line(s)' not in r and POR_FRAME in ''.join(edit3), (r[:400], edit3[0][-400:]))
finally:
    # el renderizador suspendido, si sigue vivo, se reanuda: lo recoge el servidor
    if suspendido:
        mc.reanuda(rpid)
    if suspendido3:
        mc.reanuda(rpid3)
    if suspendido5:
        mc.reanuda(rpid5)
    s.cierra()
mc.borra(BASE)
mc.fin('el juez con el plazo de la edicion 1.27 (R4)')
