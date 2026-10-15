# -*- coding: utf-8 -*-
"""CFG-042 anunciaba " [CFG-043] + Application.CreateForm" sin escribirlo (Hermes,
informe 1938c sobre la 1.19.2; medido el 15-oct): un form VCL en un proyecto de
CONSOLA entra en la uses y en el .dproj, pero no hay Application.Run ni otro
CreateForm donde colgarlo; CFG-046 lo decia en la linea siguiente y el .dpr no lo
tenia. El mensaje miraba si el form NECESITA CreateForm, no si InsertCreateForm lo
escribio (P9 lo arreglo solo para los paquetes; esto es su gemelo). Ahora CFG-043
sale solo cuando el CreateForm esta en el .dpr.

  F1 create form-vcl en un proyecto de consola: sin CFG-043, con CFG-046, y el .dpr
     sin CreateForm (ROJO en produccion)
  F2 add-unit de un form existente en otro proyecto de consola: lo mismo (ROJO)
  C1 control: form-vcl en un proyecto VCL: CFG-043 y el CreateForm en el .dpr

Uso:  python tests/test_createform_consola_1193.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('createform_consola_1193')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='createform-consola', t=180)


def crea(**kw):
    return s.call('delphi_create', kw, t=180)


def dpr(carpeta, nombre):
    return open(os.path.join(JAIL, carpeta, nombre + '.dpr'), encoding='utf-8-sig').read()


try:
    crea(kind='project-console', name='PCons1', dir=os.path.join(JAIL, 'cons1'))
    r = crea(kind='form-vcl', name='UFrmCons', project=os.path.join(JAIL, 'cons1', 'PCons1.dproj'))
    d = dpr('cons1', 'PCons1')
    check('F1 create form-vcl en un proyecto de consola: sin CFG-043, con CFG-046, y el .dpr sin CreateForm',
          not mc.rechazado(r) and 'CFG-042' in r and 'CFG-043' not in r and 'CFG-046' in r
          and 'CreateForm' not in d and 'UFrmCons' in d, (r[:700], d[:400]))

    crea(kind='project-console', name='PCons2', dir=os.path.join(JAIL, 'cons2'))
    r = s.call('delphi_config', {'command': 'add-unit',
                                 'project': os.path.join(JAIL, 'cons2', 'PCons2.dproj'),
                                 'path': os.path.join(JAIL, 'cons1', 'UFrmCons.pas')}, t=180)
    d = dpr('cons2', 'PCons2')
    check('F2 add-unit de un form existente en otro proyecto de consola: sin CFG-043, el .dpr sin CreateForm',
          not mc.rechazado(r) and 'CFG-042' in r and 'CFG-043' not in r and 'CFG-046' in r
          and 'CreateForm' not in d and 'UFrmCons' in d, (r[:700], d[:400]))

    crea(kind='project-vcl', name='PVcl', dir=os.path.join(JAIL, 'vcl'))
    r = crea(kind='form-vcl', name='UFrmVcl', project=os.path.join(JAIL, 'vcl', 'PVcl.dproj'))
    d = dpr('vcl', 'PVcl')
    check('C1 control: form-vcl en un proyecto VCL: CFG-043 y el CreateForm en el .dpr',
          not mc.rechazado(r) and 'CFG-043' in r and 'Application.CreateForm(TFormUFrmVcl' in d,
          (r[:700], d[:600]))
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('CFG-043 solo cuando el CreateForm se escribe 1.19.3 (Hermes 1938c)')
