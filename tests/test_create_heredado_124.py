# -*- coding: utf-8 -*-
"""V76 y V77 de la 1.24, de punta a punta: lo que escribe el servidor tiene que compilar y
abrir. V76: delphi_create hereda de un form o frame del proyecto (ningun escritor creaba un
form heredado). V77: insert de un frame del proyecto (DSGN-015; a mano eran tres llamadas mas).

  H1 kind=form-vcl con ancestor: inherited en el form, class(TFormBase) y su unidad en el uses
  H2 se dibuja con lo del ancestro
  H3 un frame heredado de otro frame
  H4 FMX igual
  H5 un ancestor que el proyecto no lista: CREATE-038, nada creado
  H6 un frame de ancestro de una form: CREATE-039, nada creado
  H7 ancestor con un kind que no lo lleva: se dice
  I1 insert de un frame del proyecto en el heredado, con su campo
  B1 todo eso COMPILA con dcc (delphi_build): el juez de verdad
  B2 check-binding lo da por bueno

ROJO contra un build sin los arreglos.

Uso:  python tests/test_create_heredado_124.py [ruta-a-DelphiLspMcp.exe]
"""
import json
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('create_heredado_124')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), con_render=True)


def J(r):
    try:
        return json.loads(r)
    except ValueError:
        return {}


def lee(*partes):
    return open(os.path.join(*partes), encoding='utf-8-sig').read()


srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='create-heredado', t=400)
try:
    def crea(**a):
        return srv.call('delphi_create', a, t=120)

    # ---- VCL
    DIR = os.path.join(JAIL, 'App')
    r = crea(kind='project-vcl', name='App', dir=DIR)
    check('fixture: proyecto VCL', not mc.rechazado(r), r[:200])
    DPR = os.path.join(DIR, 'App.dpr')
    DPROJ = os.path.join(DIR, 'App.dproj')
    r = crea(kind='form-vcl', name='UBase', project=DPROJ, formname='FormBase', dir='base')
    check('fixture: el ancestro, en otra carpeta', not mc.rechazado(r), r[:200])
    r = srv.call('delphi_designer', {'command': 'insert', 'path': os.path.join(DIR, 'base', 'UBase.dfm'), 'classname': 'TButton', 'component': 'ButtonBase'}, t=240)
    check('fixture: un boton en el ancestro', not mc.rechazado(r), r[:300])

    r = crea(kind='form-vcl', name='UHija', project=DPROJ, formname='FormHija', ancestor='TFormBase', dir='forms')
    dfm = lee(DIR, 'forms', 'UHija.dfm')
    pas = lee(DIR, 'forms', 'UHija.pas')
    check('H1 form heredado: inherited, class(TFormBase) y su unidad en el uses',
          not mc.rechazado(r) and dfm.startswith('inherited FormHija: TFormHija') and 'TFormHija = class(TFormBase)' in pas and
          'UBase;' in pas.split('type')[0], (r[:300], dfm, pas[:300]))
    HIJA = os.path.join(DIR, 'forms', 'UHija.dfm')
    r = srv.call('delphi_designer', {'command': 'preview', 'path': HIJA, 'component': 'ButtonBase', 'out': os.path.join(JAIL, 'h.png')}, t=240)
    check('H2 se dibuja con lo del ancestro', len(J(r).get('componentRect', '').split(',')) == 4, r[:400])

    r = crea(kind='frame-vcl', name='UFr', project=DPROJ, formname='Frame1', dir='frames')
    check('fixture: un frame', not mc.rechazado(r), r[:200])
    r = crea(kind='frame-vcl', name='UFrHijo', project=DPROJ, formname='FrameHijo', ancestor='TFrame1', dir='frames2')
    check('H3 un frame heredado de otro frame', not mc.rechazado(r) and lee(DIR, 'frames2', 'UFrHijo.dfm').startswith('inherited FrameHijo: TFrameHijo') and
          'Caption' not in lee(DIR, 'frames2', 'UFrHijo.dfm') and 'class(TFrame1)' in lee(DIR, 'frames2', 'UFrHijo.pas'), r[:300])

    r = crea(kind='form-vcl', name='UNada', project=DPROJ, ancestor='TNoEsta')
    check('H5 un ancestor que el proyecto no lista: CREATE-038, nada creado',
          mc.abre(r, 'SR_CREATE_ANCESTRO_NO_ESTA_FMT') and not os.path.exists(os.path.join(DIR, 'UNada.pas')), r[:300])
    r = crea(kind='form-vcl', name='UNada', project=DPROJ, ancestor='TFrame1')
    check('H6 un frame de ancestro de una form: CREATE-039, nada creado',
          mc.abre(r, 'SR_CREATE_ANCESTRO_OTRA_RAIZ_FMT') and not os.path.exists(os.path.join(DIR, 'UNada.pas')), r[:300])
    r = crea(kind='unit', name='UNada', project=DPROJ, ancestor='TFormBase')
    check('H7 ancestor con kind=unit: se dice, no se ignora', mc.abre(r, 'SR_CREATE_NO_VA_CON_KIND_FMT') and 'ancestor' in r, r[:300])

    # ---- V77: el frame dentro del heredado, en otra carpeta las dos cosas
    r = srv.call('delphi_designer', {'command': 'insert', 'path': HIJA, 'classname': 'TFrame1'}, t=240)
    check('I1 insert del frame en el heredado: inline, campo y unidad',
          not mc.rechazado(r) and 'inline Frame11: TFrame1' in lee(DIR, 'forms', 'UHija.dfm') and
          'Frame11: TFrame1;' in lee(DIR, 'forms', 'UHija.pas') and 'UFr' in lee(DIR, 'forms', 'UHija.pas').split('type')[0], r[:600])

    r = srv.call('delphi_build', {'project': DPROJ, 'platform': 'Win64', 'config': 'Debug'}, t=300)
    check('B1 todo compila con dcc', J(r).get('success') is True, r[:600])
    r = srv.call('delphi_designer', {'command': 'check-binding', 'path': HIJA}, t=120)
    j = J(r)
    check('B2 check-binding: nada que decir del form contra su clase',
          not j.get('missingFields') and not j.get('orphanFields') and not mc.rechazado(r), r[:500])

    # ---- FMX
    DIRF = os.path.join(JAIL, 'AppF')
    crea(kind='project-fmx', name='AppF', dir=DIRF)
    DPROJF = os.path.join(DIRF, 'AppF.dproj')
    crea(kind='form-fmx', name='UBaseF', project=DPROJF, formname='FormBaseF', dir='base')
    r = crea(kind='form-fmx', name='UHijaF', project=DPROJF, formname='FormHijaF', ancestor='TFormBaseF', dir='forms')
    check('H4 FMX: form heredado', not mc.rechazado(r) and lee(DIRF, 'forms', 'UHijaF.fmx').startswith('inherited FormHijaF: TFormHijaF') and
          'class(TFormBaseF)' in lee(DIRF, 'forms', 'UHijaF.pas'), r[:300])
    r = srv.call('delphi_build', {'project': DPROJF, 'platform': 'Win64', 'config': 'Debug'}, t=300)
    check('H4b FMX compila', J(r).get('success') is True, r[:500])
finally:
    srv.cierra()

mc.borra(BASE)
mc.fin('formas heredadas y frames del proyecto (V76, V77)')
