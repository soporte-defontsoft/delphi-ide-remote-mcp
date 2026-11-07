# -*- coding: utf-8 -*-
"""1.29 (informe de un agente del 7-nov-2026): delphi_create de un data module o un form siempre anadia
Application.CreateForm al .dpr, como el IDE por defecto; un proyecto que los crea a demanda (una funcion los crea
cuando un frame los pide antes) acababa con los dos caminos y EComponentError. autocreate=no lo registra sin
CreateForm, como "Available forms" en las opciones del proyecto; delphi_config add-unit tambien lo lleva.

  C1 datamodule autocreate=no: en el uses del .dpr y en el .dproj, sin CreateForm
  C2 control: datamodule sin decir nada: con su CreateForm (como el IDE)
  C3 form-vcl autocreate=no: sin CreateForm
  C4 add-unit autocreate=no de una unit que ya lo tenia: su CreateForm se va
  C5 autocreate=quizas: CREATE-041 y nada creado
  C6 autocreate en un frame (que no se crea al arrancar): no va con ese kind

Uso:  python tests/test_autocreate_129.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
BASE = mc.carpeta('autocreate_129')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
P = os.path.join(JAIL, 'App')
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='ac129', t=120)


def dpr():
    return open(os.path.join(P, 'App.dpr'), encoding='utf-8-sig').read()


try:
    srv.call('delphi_create', {'kind': 'project-vcl', 'name': 'App', 'dir': P})
    DPROJ = os.path.join(P, 'App.dproj')
    r = srv.call('delphi_create', {'kind': 'datamodule', 'name': 'UIconos', 'project': DPROJ, 'autocreate': 'no'})
    t = dpr()
    check('C1 datamodule autocreate=no: registrado sin CreateForm',
          not mc.fallo(r) and 'UIconos' in t and 'CreateForm(TDMUIconos' not in t
          and 'UIconos.pas' in open(DPROJ, encoding='utf-8-sig').read(), (r[:200], t))
    r = srv.call('delphi_create', {'kind': 'datamodule', 'name': 'UDatos', 'project': DPROJ})
    check('C2 control: un datamodule sin decir nada lleva su CreateForm', 'CreateForm(TDMUDatos, DMUDatos)' in dpr(),
          (r[:200], dpr()))
    r = srv.call('delphi_create', {'kind': 'form-vcl', 'name': 'UOpciones', 'project': DPROJ, 'autocreate': 'false'})
    check('C3 form-vcl autocreate=false: sin CreateForm', not mc.fallo(r) and 'CreateForm(TFormUOpciones' not in dpr(),
          (r[:200], dpr()))
    r = srv.call('delphi_config', {'command': 'add-unit', 'project': DPROJ, 'path': os.path.join(P, 'UDatos.pas'),
                                   'autocreate': 'no'})
    check('C4 add-unit autocreate=no de una unit que ya lo tenia: su CreateForm se va',
          not mc.fallo(r) and 'CreateForm(TDMUDatos' not in dpr() and 'UDatos' in dpr(), (r[:200], dpr()))
    r = srv.call('delphi_create', {'kind': 'datamodule', 'name': 'UMal', 'project': DPROJ, 'autocreate': 'quizas'})
    check('C5 autocreate=quizas: CREATE-041 y nada creado',
          mc.es(r, 'SR_CREATE_AUTOCREATE_NO_ES_SINO_FMT') and not os.path.exists(os.path.join(P, 'UMal.pas')), r[:200])
    r = srv.call('delphi_create', {'kind': 'frame-vcl', 'name': 'UMarco', 'project': DPROJ, 'autocreate': 'no'})
    check('C6 autocreate con un frame: no va con ese kind', mc.es(r, 'SR_CREATE_NO_VA_CON_KIND_FMT'), r[:200])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('delphi_create autocreate (1.29)')
