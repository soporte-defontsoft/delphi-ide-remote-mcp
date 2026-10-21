# -*- coding: utf-8 -*-
"""Punto 9 de la 1.18.2 (Hermes): delphi_completion no filtraba por el prefijo
que hay bajo el cursor. El motor (DelphiLSP) contesta el ambito ENTERO y filtra
el cliente, como el IDE al teclear; aqui se cortaba a 50 en el orden del motor
y lo util podia no llegar nunca (medido por Hermes el 13-oct: 1164 candidatos
con el cursor dentro de Writeln, y Writeln no salia en los 50 primeros). Y el
tope contaba indices de la lista cruda, los <error> saltados incluidos.

  P1 con el cursor tras "Writ" dentro de Writeln: prefix = Writ, Writeln esta
     y TODOS empiezan por Writ (ROJO en produccion)
  P2 matching dice cuantos casan, y si pasan del tope, truncated y la nota
     de como acotarlos (guarda de forma)
  P3 el control: con el cursor tras un punto (miembros) no hay prefijo y
     contesta igual

Uso:  python tests/test_completion_prefijo_1182.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('completion_prefijo_1182')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
SKIP = None

DPR = ("program Pref;\r\n\r\n{$APPTYPE CONSOLE}\r\n\r\nuses\r\n  System.SysUtils, System.Classes;\r\n\r\n"
       "var\r\n  L: TStringList;\r\n\r\nbegin\r\n  L := TStringList.Create;\r\n  Writeln('x');\r\n"
       "  L.Free;\r\n  Zqxv;\r\nend.\r\n")
LINEA_W = 12    # 0-based: "  Writeln('x');"
LINEA_L = 13    # 0-based: "  L.Free;"
LINEA_Z = 14    # 0-based: "  Zqxv;" (un nombre que no casa con nada)

srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='completion', t=240)
try:
    d = os.path.join(JAIL, 'Pref')
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'Pref', 'dir': d})
    dpr = os.path.join(d, 'Pref.dpr')
    open(dpr, 'w', encoding='utf-8-sig', newline='').write(DPR)
    r = srv.call('delphi_completion', {'path': dpr, 'line': LINEA_W, 'character': 6}, t=240)
    try:
        j = json.loads(r)
    except Exception:
        j = {}
    if 'items' not in j:
        # (revisor de baterias, 18-oct-2026) sin items salia SIN CHECKS y run_all
        # la daba por buena: unos ajustes del motor inservibles (lo que cambio la
        # 1.20.2) caian justo ahi. Neutra solo sin RAD Studio; con el, roja
        _inst = (mc.como_json(srv.call('delphi_installs', {})) or {}).get('installs', [])
        if not any(i.get('active') for i in _inst):
            SKIP = 'no hay RAD Studio activo en esta maquina: %s' % r[:200]
        else:
            check('P0 la completion contesta con items (hay RAD Studio: sin ellos, el motor no tiene buenos ajustes)',
                  False, r[:300])
    else:
        labels = [i.get('label', '') for i in j['items']]
        check('P1 cursor tras "Writ": prefix=Writ, Writeln esta y todos empiezan por Writ',
              j.get('prefix') == 'Writ' and 'Writeln' in labels and
              all(x.lower().startswith('writ') for x in labels), (j.get('prefix'), labels[:8], j.get('total')))
        check('P2 matching dice cuantos casan (y truncated solo si pasan del tope)',
              isinstance(j.get('matching'), int) and j['matching'] >= len(labels) and
              (j.get('truncated') is True) == (j['matching'] > len(labels)), (j.get('matching'), len(labels)))
        r = srv.call('delphi_completion', {'path': dpr, 'line': LINEA_L, 'character': 4, 'trigger': '.'}, t=240)
        try:
            j = json.loads(r)
        except Exception:
            j = {}
        # (un control vale en los dos: produccion no tenia 'truncated' y sus 50
        # primeros no llegaban a Free; aqui, que contesta miembros sin prefijo)
        check('P3 control: tras un punto (miembros) no hay prefijo y contesta miembros',
              'prefix' not in j and len(j.get('items', [])) > 0 and j.get('total', 0) > 0, r[:300])
        # M8 del revisor de cierre: el tope nunca se ejercitaba. Los miembros de
        # un TStringList (los suyos, TStrings, TPersistent, TObject) pasan de el:
        # truncated y su nota (LSP-042), y total cuenta lo que no se ensena
        check('P4 los miembros de TStringList pasan del tope: truncated, total > items y la nota LSP-042',
              j.get('truncated') is True and j.get('total', 0) > len(j.get('items', [])) and 'LSP-042' in r,
              (j.get('truncated'), j.get('total'), len(j.get('items', []))))
        # 1.21.4: con prefijo y ninguno que empiece por el, la nota LSP-049 (Luna,
        # 20-oct-2026: items=[] sin decir por que costaba un turno)
        r = srv.call('delphi_completion', {'path': dpr, 'line': LINEA_Z, 'character': 6}, t=240)
        j = mc.como_json(r) or {}
        check('P5 prefijo que no casa con nada: matching 0, items vacio y la nota LSP-049',
              j.get('prefix') == 'Zqxv' and j.get('matching') == 0 and j.get('items') == [] and 'LSP-049' in r,
              r[:300])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('delphi_completion filtra por el prefijo 1182 (punto 9)', sin_checks=SKIP)
