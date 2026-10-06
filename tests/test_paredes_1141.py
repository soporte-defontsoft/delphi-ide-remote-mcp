# -*- coding: utf-8 -*-
"""Las paredes de Hermes (1.14.1).

Tres informes de Hermes en la VM 13.2 (5-oct-2026, con la 1.13.1) que seguian
vivos en la 1.14.0, medidos el 6-oct-2026 antes de tocar nada.

  P1  delphi_diagnostics de una unidad SIN ajustes de proyecto (ningun
      .delphilsp.json ni .dproj desde su carpeta hacia arriba) contesta
      LSP-035 NOT_FOUND en el acto: el motor sin ajustes no publica NUNCA
      (medido: 4,5 min con una unidad valida, 80 s con un error de sintaxis;
      Hermes se fue a los 300 s de su cliente creyendo caido el transporte).
      Antes: "in-progress, llama otra vez" para siempre
  P2  ...y no arranca un motor para nada: el servidor no tiene ni un
      DelphiLSP hijo despues
  P3  (guarda) una unidad que NINGUN proyecto lista pero que vive junto a uno
      SI se analiza con los ajustes de ese proyecto: su E2029, no LSP-035 (la
      regla es "sin ajustes", no "sin registrar"; medido el mismo dia)
  P4  (guarda) delphi_config add-unit con unit= ANADE la unidad: "unit" es
      un alias de path desde la 0.64 (ApplyArgAliases). El rechazo "con el
      esquema entero" que conto Hermes no salio del servidor: su puente
      valida en local antes de enviar (el esquema no prohibe propiedades
      extra; medido el 6-oct-2026)
  P5  delphi_build target=<plataforma> (Win32, win64): BUILD-004 dice que es
      una plataforma y que va en platform=, con su nombre canonico
  P6  (guarda) un target que no es plataforma: BUILD-004 sin esa pista
  P7  delphi_list POR PAGINAS, como su hermana delphi_search: cortaba en 500
      y lo de detras no se alcanzaba (Hermes en la raiz de referencia de un
      ERP: las 500 primeras eran copias de backups\\). 720 ficheros: pagina de
      500 con hasMore/nextOffset y LIST-010; byFolder dice donde estan (la
      carpeta de las copias primero); recorrer nextOffset llega a TODOS sin
      repetir; maxresults=50 da 50; un offset pasado el final, 0 y sin mas
  P8  ...y el modo dirs=true igual: 510 carpetas, 500 + 10, LIST-013
  P9  la purga del arranque recorre cada SITIO una vez: la misma raiz de red
      declarada en dos workspaces (una con barra final) da UNA linea de
      purga, no dos (lo vio el log de la VM 13.2 el 6-oct-2026 con
      N:\\CodeSandBox en Claude y Hermes). Necesita DELPHI_MCP_TEST_NETDIR
      (una carpeta de una unidad de red conectada); sin ella, NOTA

Usage:  python tests/test_paredes_1141.py [path-to-DelphiLspMcp.exe]
"""
import os, subprocess, time
import random
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('paredes_1141')
EXEDIR = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
SUELTA = os.path.join(JAIL, 'Suelta')
PROY = os.path.join(JAIL, 'Proy')
for d in (EXEDIR, SUELTA):
    os.makedirs(d)
EXE = mc.copia_exe(EXEDIR)

# una unidad valida, en una carpeta sin proyecto ni ajustes en ningun sitio
# de la jaula que la nombre
USUELTA = os.path.join(SUELTA, 'USuelta.pas')
with open(USUELTA, 'w', newline='\r\n') as f:
    f.write('unit USuelta;\n\ninterface\n\nfunction Suma(A, B: Integer): Integer;\n\n'
            'implementation\n\nfunction Suma(A, B: Integer): Integer;\nbegin\n'
            '  Result := A + B;\nend;\n\nend.\n')

# P7/P8: un arbol que no cabe en una pagina, con las copias delante (como en
# la raiz de Hermes) y lo vivo detras
LISTA = os.path.join(JAIL, 'Lista')
for sub, n in (('backups\\Old', 600), ('src\\Live', 120)):
    d = os.path.join(LISTA, sub)
    os.makedirs(d)
    for i in range(n):
        with open(os.path.join(d, 'U%s%03d.pas' % (sub[0], i)), 'w') as f:
            f.write('unit U%s%03d;\ninterface\nimplementation\nend.\n' % (sub[0], i))
MUCHAS = os.path.join(JAIL, 'Muchas')
for i in range(510):
    os.makedirs(os.path.join(MUCHAS, 'c%03d' % i))

TOKEN = 'pared-1141'
with open(os.path.join(EXEDIR, 'settings.ini'), 'w') as f:
    f.write('\n'.join(['[Workspace.Pared]', 'Token=%s' % TOKEN, 'Roots=%s' % JAIL, '']))

cat = mc.catalogo()
puerto = mc.puerto_libre()
salida = open(os.path.join(BASE, 'servidor.txt'), 'wb')
env = mc.entorno({'DELPHI_MCP_BIND_IP': '127.0.0.1'})
proc = mc.lanza_http(EXE, puerto, env, stdout=salida, stderr=subprocess.STDOUT)
c = mc.Http(puerto, TOKEN, t=120, respaldo_json=True)
c.session('paredes-1141')


def llama(tool, args, t=120):
    return mc.texto(c.call_msg(tool, args, t), True)


def pista(nombre, *valores):
    tx = cat[nombre]
    return tx % valores if valores else tx


try:
    # ------------------------------------------------------------- P1/P2
    t0 = time.time()
    t = llama('delphi_diagnostics', {'path': USUELTA}, 120)
    dt = time.time() - t0
    check('P1 diagnostics de una unidad sin ajustes de proyecto: LSP-035 NOT_FOUND, no "in-progress"',
          mc.abre(t, 'SR_LSP_LINT_SIN_AJUSTES_FMT') and mc.resultado(t) == 'NOT_FOUND'
          and 'in-progress' not in t, t[:400])
    check('P1 ...en el acto (%.1f s), no tras la espera del lint' % dt, dt < 15, '%.1f s' % dt)
    check('P1 ...y dice la salida: add-unit o crear el proyecto',
          'add-unit' in t and 'delphi_create' in t, t[:400])
    check('P2 ...sin arrancar un motor para nada: ningun DelphiLSP hijo del servidor',
          mc.hijos_lsp(proc.pid) == [], mc.hijos_lsp(proc.pid))

    # ---------------------------------------------------------------- P3
    r = llama('delphi_create', {'kind': 'project-vcl', 'name': 'Proy', 'dir': PROY}, 120)
    UFUERA = os.path.join(PROY, 'UFuera.pas')
    with open(UFUERA, 'w', newline='\r\n') as f:
        f.write('unit UFuera;\n\ninterface\n\nfunction Doble(A: Integer): Integer;\n\n'
                'implementation\n\nfunction Doble(A: Integer): Integer;\nbegin\n'
                '  Result := A * 2 +;\nend;\n\nend.\n')
    t = llama('delphi_diagnostics', {'path': UFUERA}, 180)
    if mc.como_json(t).get('status') == 'in-progress':  # el primer lint de un motor frio
        t = llama('delphi_diagnostics', {'path': UFUERA}, 180)
    check('P3 (guarda) una unidad sin registrar JUNTO a un proyecto se analiza con sus ajustes: E2029, no LSP-035',
          'E2029' in t and not mc.es(t, 'SR_LSP_LINT_SIN_AJUSTES_FMT'), '%s | %s' % (r[:150], t[:400]))

    # ---------------------------------------------------------------- P4
    DPROJ = os.path.join(PROY, 'Proy.dproj')
    t = llama('delphi_config', {'project': DPROJ, 'command': 'add-unit', 'unit': UFUERA})
    with open(os.path.join(PROY, 'Proy.dpr'), encoding='utf-8-sig') as f:
        dpr = f.read()
    check('P4 (guarda) delphi_config add-unit con unit= anade la unidad: alias de path',
          mc.abre(t, 'SN_UNIT_ADDED_FMT') and 'UFuera' in dpr, t[:400])

    # ------------------------------------------------------------- P5/P6
    t = llama('delphi_build', {'project': DPROJ, 'target': 'Win32'})
    check('P5 delphi_build target=Win32: BUILD-004 dice que es una plataforma y que va en platform=',
          mc.abre(t, 'SR_BUILD_TARGET_FMT')
          and pista('SF_BUILD_TARGET_ES_PLATAFORMA_FMT', 'Win32', 'Win32') in t, t[:500])
    t = llama('delphi_build', {'project': DPROJ, 'target': 'win64'})
    check('P5 ...en minusculas tambien, con el nombre canonico (Win64)',
          pista('SF_BUILD_TARGET_ES_PLATAFORMA_FMT', 'win64', 'Win64') in t, t[:500])
    t = llama('delphi_build', {'project': DPROJ, 'target': 'Rebuild'})
    check('P6 (guarda) un target que no es plataforma: BUILD-004 sin esa pista',
          mc.abre(t, 'SR_BUILD_TARGET_FMT') and 'is a platform' not in t, t[:400])

    # ---------------------------------------------------------------- P7
    p1 = mc.como_json(llama('delphi_list', {'root': LISTA}))
    check('P7 delphi_list de 720: pagina de 500 con hasMore y nextOffset=500',
          p1.get('total') == 720 and p1.get('shown') == 500 and len(p1.get('files', [])) == 500
          and p1.get('hasMore') is True and p1.get('nextOffset') == 500,
          {k: p1.get(k) for k in ('total', 'shown', 'hasMore', 'nextOffset')})
    check('P7 ...LIST-010 dice cuantas de cuantas y la pagina siguiente',
          pista('SN_LIST_CAPPED_FMT', 500, 720, 500) in p1.get('shownNote', ''), p1.get('shownNote'))
    bf = p1.get('byFolder', [])
    check('P7 ...byFolder dice DONDE estan, la carpeta de las copias primero',
          bf[:2] == ['backups\\Old = 600', 'src\\Live = 120'], bf)
    vistos, ofs, paginas = [], 0, 0
    while paginas < 10:
        pg = mc.como_json(llama('delphi_list', {'root': LISTA, 'offset': ofs}))
        paginas += 1
        vistos += [e['path'] for e in pg.get('files', [])]
        if not pg.get('hasMore'):
            break
        ofs = pg['nextOffset']
    check('P7 ...recorrer nextOffset llega a las 720 y sin repetir (lo vivo tambien)',
          len(vistos) == 720 and len(set(vistos)) == 720
          and sum(1 for v in vistos if 'Live' in v) == 120, (paginas, len(vistos), len(set(vistos))))
    p50 = mc.como_json(llama('delphi_list', {'root': LISTA, 'maxresults': 50}))
    check('P7 ...maxresults=50 da 50 y la siguiente en 50',
          p50.get('shown') == 50 and p50.get('nextOffset') == 50, {k: p50.get(k) for k in ('shown', 'nextOffset')})
    pfin = mc.como_json(llama('delphi_list', {'root': LISTA, 'offset': 10000}))
    check('P7 ...un offset pasado el final: 0 y sin mas',
          pfin.get('total') == 720 and pfin.get('shown') == 0 and pfin.get('hasMore') is False,
          {k: pfin.get(k) for k in ('total', 'shown', 'hasMore')})

    # ---------------------------------------------------------------- P8
    d1 = mc.como_json(llama('delphi_list', {'root': MUCHAS, 'dirs': True}))
    d2 = mc.como_json(llama('delphi_list', {'root': MUCHAS, 'dirs': True, 'offset': d1.get('nextOffset', 0)}))
    check('P8 dirs=true por paginas: 500 + 10 de 510, sin repetir, con LIST-013',
          d1.get('total') == 510 and len(d1.get('dirs', [])) == 500 and d1.get('nextOffset') == 500
          and pista('SN_LIST_DIRS_CAPPED_FMT', 500, 510, 500) in d1.get('shownNote', '')
          and len(d2.get('dirs', [])) == 10 and d2.get('hasMore') is False
          and not set(d1.get('dirs', [])) & set(d2.get('dirs', [])),
          ({k: d1.get(k) for k in ('total', 'shown', 'nextOffset')}, len(d2.get('dirs', []))))
finally:
    proc.kill()
proc.wait(10)
salida.close()

# ---------------------------------------------------------------------- P9
NETDIR = os.environ.get('DELPHI_MCP_TEST_NETDIR', '').strip().rstrip('\\')
if NETDIR:
    # una carpeta PROPIA de esta pasada, que se borra al acabar
    NETBASE = os.path.join(NETDIR, 'paredes1141-%d-%d' % (os.getpid(), random.randint(1000, 9999)))
    os.makedirs(os.path.join(NETBASE, '__delphi-temp'))
    try:
        with open(os.path.join(EXEDIR, 'settings.ini'), 'w') as f:
            f.write('\n'.join(['[Workspace.Uno]', 'Token=uno-1141', 'Roots=%s' % NETBASE,
                               '[Workspace.Dos]', 'Token=dos-1141', 'Roots=%s\\' % NETBASE, '']))
        salida2 = open(os.path.join(BASE, 'servidor-red.txt'), 'wb')
        proc2 = mc.lanza_http(EXE, mc.puerto_libre(), env, stdout=salida2, stderr=subprocess.STDOUT)
        try:
            def purgas():
                with open(os.path.join(BASE, 'servidor-red.txt'), encoding='utf-8', errors='replace') as fh:
                    return [l for l in fh.read().splitlines()
                            if 'Temporary folders under' in l and os.path.basename(NETBASE) in l]
            fin = time.time() + 60
            while time.time() < fin and not purgas():
                time.sleep(0.5)
            time.sleep(5)  # la segunda, si la hubiera, sale detras de la primera
            ps = purgas()
            check('P9 la misma raiz de red en dos workspaces: UNA purga, no dos', len(ps) == 1, ps)
        finally:
            proc2.kill()
            proc2.wait(10)
            salida2.close()
    finally:
        mc.borra(NETBASE)
    check('P9 ...y la carpeta de prueba no queda en la unidad de red', not os.path.exists(NETBASE), NETBASE)
else:
    print('NOTA P9: sin DELPHI_MCP_TEST_NETDIR (una carpeta de una unidad de red conectada) no se '
          'mide la purga de una raiz de red repetida')

mc.fin('paredes 1.14.1 battery')
