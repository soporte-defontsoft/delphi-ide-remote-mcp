# -*- coding: utf-8 -*-
"""Las lecturas ESCONDIDAS (P2 de las puertas, 1.18.0): lo que el servidor leia
de fuera de las raices sin que ninguna tool se lo pidiera (medida M1 del
9-oct-2026). Cada caso planta una victima FUERA de la raiz y llega a ella por
el camino que la leia:

  L1  el escaneo de directivas del build ({$I}/{$R}) recorria la carpeta del
      proyecto con TDirectory y cruzaba un junction: un fuente de detras con
      un {$I} de fuera NEGABA el build nombrando ese fuente
  L2  la sugerencia de paquetes de un .dpk (W1033) miraba las subcarpetas del
      workspace y leia el .dpk de detras de un junction: lo sugeria por su
      nombre. Control: el .dpk HERMANO de dentro si se sugiere
  L3  la mudanza de un proyecto cuyo .dpr nombra una unit de FUERA con ruta
      leia esa unit para re-apuntarla: ahora ni se lee ni se re-apunta, y se
      dice (SN_REUBICA_FALLOS_FMT)

Dos capas en cada uno: el recorredor (o la pregunta de ReapuntaUnits) y la
puerta de PatchLoadText. Mutantes: sin las dos, L1-L3 rojos; sin una sola,
la otra los sostiene (cada capa es la GUARDA de la otra).

Uso:  python tests/test_puerta_leer.py [exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('puerta-leer')
MINE = os.path.join(BASE, 'mio')
VICTIMA = os.path.join(BASE, 'victima')        # junto a la raiz, NO dentro
for d in (MINE, VICTIMA):
    os.makedirs(d, exist_ok=True)


def escribe(ruta, texto, bom=False):
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    with open(ruta, 'w', encoding='utf-8-sig' if bom else 'utf-8', newline='') as f:
        f.write(texto.replace('\n', '\r\n'))


def lee(ruta):
    return open(ruta, 'rb').read()


# la victima: un fuente con un {$I} de fuera, un .dpk que contiene UComun y una unit
escribe(os.path.join(VICTIMA, 'secreto.inc'), '// secreto\n')
escribe(os.path.join(VICTIMA, 'UVicDir.pas'),
        "unit UVicDir;\ninterface\nimplementation\n{$I %s}\nend.\n" % os.path.join(VICTIMA, 'secreto.inc'))
escribe(os.path.join(VICTIMA, 'PkgVictima.dpk'),
        "package PkgVictima;\nrequires\n  rtl;\ncontains\n  UComun in 'UComun.pas';\nend.\n")
escribe(os.path.join(VICTIMA, 'UFueraM.pas'),
        "unit UFueraM;\ninterface\nfunction DameDeFuera: Integer;\nimplementation\n"
        "function DameDeFuera: Integer;\nbegin\n  Result := 7;\nend;\nend.\n")
ANTES = {n: lee(os.path.join(VICTIMA, n)) for n in os.listdir(VICTIMA)}

EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': MINE}), nombre='puerta-leer', t=300)
call = srv.call
enlaces = []


def enlace(link, target):
    ok = mc.junction(link, target)
    if ok:
        enlaces.append(link)
    return ok


try:
    # L1: el escaneo de directivas del build no cruza a lo que no se puede leer
    APP = os.path.join(MINE, 'app')
    r = call('delphi_create', {'kind': 'project-console', 'dir': APP, 'name': 'App'})
    check('L1 fixture: proyecto creado', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    check('L1 fixture: junction en la carpeta del proyecto a la victima',
          enlace(os.path.join(APP, 'enlace'), VICTIMA))
    r = call('delphi_build', {'project': os.path.join(APP, 'App.dproj'), 'config': 'Debug'}, 600)
    j = mc.como_json(r)
    check('L1 build: el escaneo de directivas no cruza el junction (compila y no nombra el fuente de fuera)',
          j.get('success') is True and 'UVicDir' not in r and not mc.es(r, 'SR_BUILD_INCLUDE_OUTSIDE_FMT'),
          r[:400])

    # L2: la sugerencia de paquetes del workspace no lee el .dpk de detras de un junction
    PKA = os.path.join(MINE, 'pkgA')
    r = call('delphi_create', {'kind': 'project-package', 'dir': PKA, 'name': 'PkgA'})
    check('L2 fixture: paquete A creado', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    COMUN = os.path.join(MINE, 'comun')
    escribe(os.path.join(COMUN, 'UComun.pas'),
            "unit UComun;\ninterface\nfunction Comun: Integer;\nimplementation\n"
            "function Comun: Integer;\nbegin\n  Result := 1;\nend;\nend.\n")
    r = call('delphi_create', {'kind': 'unit', 'name': 'UA', 'project': os.path.join(PKA, 'PkgA.dpk'),
                               'content': "unit UA;\r\n\r\ninterface\r\n\r\nuses\r\n  UComun;\r\n\r\n"
                                          "function A: Integer;\r\n\r\nimplementation\r\n\r\n"
                                          "function A: Integer;\r\nbegin\r\n  Result := Comun;\r\nend;\r\n\r\nend.\r\n"})
    check('L2 fixture: la unit A usa UComun', mc.abre(r, 'SK_CREATE_CREADA_UNIT_LINEAS_FMT'), r[:200])
    r = call('delphi_config', {'project': os.path.join(PKA, 'PkgA.dproj'), 'command': 'add-searchpath',
                               'path': COMUN})
    check('L2 fixture: search path a comun', mc.abre(r, 'SN_CONFIG_PATH_ADDED_FMT'), r[:200])
    # el hermano de dentro que contiene UComun (el control); el de fuera, tras el junction
    escribe(os.path.join(MINE, 'pkgB', 'PkgB.dpk'),
            "package PkgB;\nrequires\n  rtl;\ncontains\n  UComun in '..\\comun\\UComun.pas';\nend.\n", bom=True)
    check('L2 fixture: junction en la raiz a la victima', enlace(os.path.join(MINE, 'enlace'), VICTIMA))
    r = call('delphi_build', {'project': os.path.join(PKA, 'PkgA.dproj'), 'config': 'Debug', 'target': 'Build'}, 600)
    j = mc.como_json(r)
    check('L2 control: UComun entra implicita y se sugiere el .dpk HERMANO de dentro (PkgB)',
          'UComun' in (j.get('implicitImports') or []) and 'PkgB' in (j.get('requiresSuggested') or []), r[:500])
    check('L2 ...y el de detras del junction ni se sugiere ni se nombra (PkgVictima)', 'PkgVictima' not in r, r[:500])

    # L3: la mudanza no lee la unit de fuera que nombra el .dpr
    MOV = os.path.join(MINE, 'mov', 'app3')
    r = call('delphi_create', {'kind': 'project-console', 'dir': MOV, 'name': 'App3'})
    check('L3 fixture: proyecto creado', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    DPR = os.path.join(MOV, 'App3.dpr')
    REL = os.path.relpath(os.path.join(VICTIMA, 'UFueraM.pas'), MOV)
    crudo = lee(DPR)
    bom = crudo.startswith(b'\xef\xbb\xbf')
    texto = crudo.decode('utf-8-sig')
    with open(DPR, 'w', encoding='utf-8-sig' if bom else 'utf-8', newline='') as f:
        f.write(texto.replace('uses', "uses\r\n  UFueraM in '%s'," % REL, 1))
    check('L3 fixture: el .dpr nombra la unit de fuera con ruta', ("in '%s'" % REL) in lee(DPR).decode('utf-8-sig'))
    DEST = os.path.join(MINE, 'mov', 'sub', 'app3')
    r = call('delphi_move', {'path': MOV, 'dest': DEST})
    nuevo = lee(os.path.join(DEST, 'App3.dpr')).decode('utf-8-sig') if os.path.isfile(os.path.join(DEST, 'App3.dpr')) else ''
    check('L3 move: la unit de fuera ni se lee ni se re-apunta, y se dice (App3.dpr en los fallos)',
          mc.es(r, 'SN_REUBICA_FALLOS_FMT') and 'App3.dpr' in r and ("in '%s'" % REL) in nuevo and
          'DameDeFuera' not in r, r[:400] + ' | ' + nuevo[:300])

    check('victima intacta: sus ficheros y sus bytes',
          sorted(os.listdir(VICTIMA)) == sorted(ANTES) and
          all(lee(os.path.join(VICTIMA, n)) == b for n, b in ANTES.items()), sorted(os.listdir(VICTIMA)))
finally:
    srv.mata()
    for l in enlaces:
        if os.path.isjunction(l):
            os.rmdir(l)  # el ENLACE, nunca lo de detras

mc.borra(BASE)
check('BASE eliminada con su copia del exe', not os.path.exists(BASE), BASE)
mc.fin('puerta leer')
