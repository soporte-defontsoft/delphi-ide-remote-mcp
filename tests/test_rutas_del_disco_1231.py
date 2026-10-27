# -*- coding: utf-8 -*-
"""Dos rutas son la misma cuando el DISCO lo dice (V105, 1.23.1): la clase de
V82 ampliada. Unos 100 sitios comparaban o guardaban rutas con el pliegue del
idioma - .ToLower (LCMAP_LINGUISTIC_CASING), AnsiLowerCase, MatchText,
IndexText, AnsiSameText, un TStringList sin mayusculas - o con SameText (solo
ASCII). Ahora van por los cuatro jueces del disco de Lsp.Rutas: SameFileName,
RutaEnLista, RutaDentroDe y ClaveDeRuta. Medido el 27-oct: en tr-TR, .ToLower
lleva la I a la i sin punto (__DELPHI-PATCH no era la papelera: se podia
escribir en ella); en es-ES lleva la I con punto a la i y el signo Kelvin a la
k, que NTFS separa. Lo de es-ES se mide aqui, sin cambiar el locale:

  R1 __DELPHI<I con punto>-PATCH no es la papelera para NTFS: se escribe (GUARD-004 antes)
  R2 __DELPHI-PATCH (mayusculas ASCII) SI lo es: se niega (control)
  R3 search: una carpeta W<I con punto>N32 no es Win32, su fuente se encuentra (antes, oculta)
  R4 search: WIN32 si es Win32, su fuente sigue oculta (control)
  R5 list: Pk y P<Kelvin> son dos carpetas, cada una con su fichero (antes, una con los dos)

Uso:  python tests/test_rutas_del_disco_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('rutas_del_disco_1231')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='rutas-disco', t=300)

I_CON_PUNTO = 'İ'
KELVIN = 'K'


def escribe(ruta, texto):
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    with open(ruta, 'w', encoding='utf-8') as f:
        f.write(texto)


try:
    call = srv.call
    # la jaula: la papelera por su nombre, como la da el disco
    R1 = os.path.join(JAIL, 'R1')
    os.makedirs(R1)
    r = call('delphi_textedit', {'path': os.path.join(R1, '__DELPH' + I_CON_PUNTO + '-PATCH', 'nota.txt'),
                                 'create': True, 'content': 'x'})
    check('R1 __DELPH<I con punto>-PATCH no es la papelera para NTFS: se escribe (era GUARD-004)',
          not mc.fallo(r) and os.path.isfile(os.path.join(R1, '__DELPH' + I_CON_PUNTO + '-PATCH', 'nota.txt')),
          r[:300])
    r = call('delphi_textedit', {'path': os.path.join(R1, '__DELPHI-PATCH', 'nota.txt'), 'create': True,
                                 'content': 'x'})
    check('R2 __DELPHI-PATCH (mayusculas ASCII) SI es la papelera: se niega',
          mc.abre(r, 'SR_GUARD_DEAD_TRASH') and not os.path.exists(os.path.join(R1, '__DELPHI-PATCH')), r[:300])

    # search: las carpetas de artefactos por su nombre, como el disco
    R3 = os.path.join(JAIL, 'R3')
    escribe(os.path.join(R3, 'W' + I_CON_PUNTO + 'N32', 'UConPunto.pas'), 'unit UConPunto; // MARCAV105\n')
    escribe(os.path.join(R3, 'WIN32', 'UWin32.pas'), 'unit UWin32; // MARCAV105\n')
    r = call('delphi_search', {'root': R3, 'query': 'MARCAV105'})
    check('R3 search: W<I con punto>N32 no es Win32, su fuente se encuentra (estaba oculta)',
          'UConPunto.pas' in r, r[:400])
    check('R4 search: WIN32 si es Win32, su fuente sigue oculta', 'UWin32.pas' not in r, r[:400])

    # list: cada carpeta una vez, por la clave del disco
    R5 = os.path.join(JAIL, 'R5')
    escribe(os.path.join(R5, 'Pk', 'a.pas'), 'unit a;\n')
    escribe(os.path.join(R5, 'P' + KELVIN, 'b.pas'), 'unit b;\n')
    r = call('delphi_list', {'root': R5})
    try:
        carpetas = json.loads(r).get('folders', [])
    except ValueError:
        carpetas = []
    check('R5 list: Pk y P<Kelvin> son dos carpetas, cada una con su fichero (era una con los dos)',
          len(carpetas) == 2 and all(len(c.get('files', [])) == 1 for c in carpetas), r[:400])
finally:
    srv.cierra()
mc.borra(BASE)
mc.fin('las rutas como las da el disco 1.23.1 (V105)')
