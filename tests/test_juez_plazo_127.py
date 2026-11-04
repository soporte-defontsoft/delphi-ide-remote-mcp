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

Rojo contra a92f053: J1 (75,1 s). Mutante: Pet.PlazoMs := 0 en JuezDelIde (Lsp.FormRender) -> J1 rojo.

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
finally:
    # el renderizador suspendido, si sigue vivo, se reanuda: lo recoge el servidor
    if suspendido:
        mc.reanuda(rpid)
    s.cierra()
mc.borra(BASE)
mc.fin('el juez con el plazo de la edicion 1.27 (R4)')
