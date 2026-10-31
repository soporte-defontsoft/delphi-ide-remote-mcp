# -*- coding: utf-8 -*-
"""A13 de la 1.23: de que marco es un designer lo dice EsDesignerFmx (un .fmx, o
un .dfm cuya unidad lleva el CLASSGROUP de FMX: un modulo de datos de un
proyecto FMX vive en un .dfm, como lo escribe el IDE). layout lo preguntaba por
la extension: un .dfm de FMX se media con la tabla de la VCL.

  V1 layout de un .dfm de FMX (CLASSGROUP 'FMX.Controls.TControl'): DSGN de
     "layout no mide FMX", no una medida de la VCL (ROJO hasta la 1.23)
  V2 (guarda) el mismo modulo sin CLASSGROUP es de la VCL: layout lo mide

Uso:  python tests/test_es_vcl_1230.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('test_es_vcl_1230')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))

PAS = ('unit {u};\r\n\r\ninterface\r\n\r\nuses\r\n  System.SysUtils, System.Classes;\r\n\r\n'
       'type\r\n  T{n} = class(TDataModule)\r\n  private\r\n  public\r\n  end;\r\n\r\n'
       'var\r\n  {n}: T{n};\r\n\r\nimplementation\r\n\r\n{grupo}{{$R *.dfm}}\r\n\r\nend.\r\n')
DFM = 'object {n}: T{n}\r\n  Height = 150\r\n  Width = 215\r\nend\r\n'


def modulo(unidad, nombre, fmx):
    grupo = "{%CLASSGROUP 'FMX.Controls.TControl'}\r\n\r\n" if fmx else ''
    with open(os.path.join(JAIL, unidad + '.pas'), 'w', encoding='utf-8-sig', newline='') as f:
        f.write(PAS.format(u=unidad, n=nombre, grupo=grupo))
    ruta = os.path.join(JAIL, unidad + '.dfm')
    with open(ruta, 'w', encoding='utf-8', newline='') as f:
        f.write(DFM.format(n=nombre))
    return ruta


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='test-es-vcl', t=300)
try:
    fmx = modulo('UDatosFmx', 'DatosFmx', True)
    vcl = modulo('UDatosVcl', 'DatosVcl', False)
    r = srv.call('delphi_designer', {'command': 'layout', 'path': fmx}, t=120)
    check('V1 layout de un .dfm de FMX (CLASSGROUP de FMX): lo que dice FMX, no una medida de la VCL; sin renderizador, DSGN-027',
          mc.es(r, 'SR_DESIGNER_LAYOUT_FMX_FMT'), r[:300])
    r = srv.call('delphi_designer', {'command': 'layout', 'path': vcl}, t=120)
    check('V2 (guarda) el mismo modulo sin CLASSGROUP es de la VCL: layout lo mide',
          not mc.es(r, 'SR_DESIGNER_LAYOUT_FMX_FMT') and not mc.es(r, 'SR_DESIGNER_NOT_FORM'), r[:300])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('de que marco es un designer, A13 de la 1.23')
