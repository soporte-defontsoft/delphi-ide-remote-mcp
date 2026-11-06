# -*- coding: utf-8 -*-
r"""Los fallos de hoy que encontro el revisor del paisaje sobre TODO src antes del ritual de la 1.28 (J1-J11
de la lista de cierre, seccion J), los que se ven desde fuera. J2 va en test_set_propiedad_usuario_1192
(S17b), J10 en test_remoterun, J7 y J8 en test_paisaje (sus reglas, con mutante); J9 (delete del disenador
con el cerrojo) no tiene una prueba de fuera barata: lo que hace delete lo cubren las del disenador.

  R1 (J1) insert=metodo de un metodo GENERICO que ya tiene su implementacion: negado entero y el fichero
     como estaba (escribia una segunda: E2004 en dcc)
  R2 (J3) set-property con un $(X) en el valor: sin la pisada falsa ("msbuild reads ... instead")
  R2b control: un grupo de esa plataforma escrito DESPUES gana de verdad, y eso si se dice
  R3 (J4) un form de clase TBaseForm llamado FormMain: create kind=form-vcl ancestor=TBaseForm lo hereda
     (era CREATE-038: se buscaba por T + su nombre)
  R4 (J5) una DCCReference ".\UMain.pas" con el .dpr 'UMain.pas': view la ve y remove-unit la quita
  R5 (J6) create kind=include con project=<algo que no es un proyecto>: negado y nada creado
  R6 (J11) get-sdk active=xyz: PAS-073 antes de nada (se tomaba por un no sin decirlo); active=on pasa

Rojo contra eefa8b8 (cfg036): R1-R6.

Uso:  python tests/test_revisor_paisaje_1280.py [exe]
"""
import json, os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('revisor_paisaje_1280')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
s = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='revisor-paisaje-1280', t=300)


def escribe(ruta, texto):
    with open(ruta, 'wb') as f:
        f.write(b'\xef\xbb\xbf' + texto.replace('\n', '\r\n').encode('utf-8'))


def proyecto(nombre):
    d = os.path.join(JAIL, nombre)
    s.call('delphi_create', {'kind': 'project-vcl', 'name': nombre, 'dir': d})
    return d, os.path.join(d, nombre + '.dpr'), os.path.join(d, nombre + '.dproj')


try:
    # --- R1 (J1) ----------------------------------------------------------------
    D1, _, _ = proyecto('PGen')
    UGEN = os.path.join(D1, 'UGen.pas')
    escribe(UGEN, 'unit UGen;\n\ninterface\n\ntype\n  TFoo = class\n  public\n    procedure Bar<T>(X: T);\n'
                  '  end;\n\nimplementation\n\nprocedure TFoo.Bar<T>(X: T);\nbegin\nend;\n\nend.\n')
    antes = mc.lee(UGEN)
    r = s.call('delphi_edit', {'path': UGEN, 'insert': 'metodo', 'inclass': 'TFoo',
                               'code': 'procedure Bar<T>(X: T);\nbegin\nend;'})
    check('R1 insert=metodo de un metodo generico que ya esta entero: negado y el fichero como estaba',
          mc.es(r, 'SR_EDIT_EXISTE_ENTERO_DECLARACION_LINEA_FMT') and mc.lee(UGEN) == antes,
          (r[:300], mc.lee(UGEN)[-160:]))

    # --- R2 (J3) ----------------------------------------------------------------
    D2, _, DPROJ2 = proyecto('PProp')
    r = s.call('delphi_config', {'command': 'set-property', 'project': DPROJ2, 'name': 'MiSalida',
                                 'value': '.\\$(Platform)\\bin', 'platform': 'Win32', 'config': 'Debug'})
    check('R2 set-property con $(Platform) en el valor: puesta y sin la pisada falsa',
          mc.es(r, 'SN_CFG_PROPERTY_PUESTA_FMT') and 'msbuild reads' not in r, r[:400])
    # control: un grupo de Win32 escrito al final, que msbuild lee despues que el de Win32 Debug
    b = open(DPROJ2, 'rb').read()
    i = b.rfind(b'</Project>')
    b = (b[:i] + b'    <PropertyGroup Condition="\'$(Platform)\'==\'Win32\'">\r\n        <MiOtra>tarde</MiOtra>\r\n'
         b'    </PropertyGroup>\r\n' + b[i:])
    open(DPROJ2, 'wb').write(b)
    r = s.call('delphi_config', {'command': 'set-property', 'project': DPROJ2, 'name': 'MiOtra',
                                 'value': 'temprano', 'platform': 'Win32', 'config': 'Debug'})
    check('R2b control: un grupo posterior que gana de verdad SI se dice, con lo que lee msbuild',
          mc.es(r, 'SN_CFG_PROPERTY_PUESTA_FMT') and 'msbuild reads tarde instead' in r, r[:400])

    # --- R3 (J4) ----------------------------------------------------------------
    D3, _, DPROJ3 = proyecto('PBase')
    for f in ('UMain.pas', 'UMain.dfm', 'PBase.dpr'):
        p = os.path.join(D3, f)
        b = open(p, 'rb').read()
        n = b.replace(b'TFormMain', b'TBaseForm')
        assert n != b, f
        open(p, 'wb').write(n)
    r = s.call('delphi_create', {'kind': 'form-vcl', 'name': 'UHija', 'project': DPROJ3, 'ancestor': 'TBaseForm'})
    hija = os.path.join(D3, 'UHija.pas')
    check('R3 un form de clase TBaseForm llamado FormMain: create ancestor=TBaseForm lo hereda (era CREATE-038)',
          not mc.rechazado(r) and os.path.exists(hija) and '(TBaseForm)' in mc.lee(hija), r[:300])

    # --- R4 (J5) ----------------------------------------------------------------
    D4, _, DPROJ4 = proyecto('PRef')
    b = open(DPROJ4, 'rb').read()
    n = b.replace(b'<DCCReference Include="UMain.pas">', b'<DCCReference Include=".\\UMain.pas">')
    assert n != b, b[-600:]
    open(DPROJ4, 'wb').write(n)
    r = s.call('delphi_config', {'command': 'view', 'project': DPROJ4, 'section': 'units'})
    try:
        u = json.loads(r).get('units', [])
    except Exception:
        u = []
    check('R4a una DCCReference ".\\UMain.pas" con el .dpr UMain.pas: view la ve en el .dproj (decia dproj:false)',
          any(x.get('unit') == 'UMain' and x.get('dproj', True) is True for x in u), r[:300])
    r = s.call('delphi_config', {'command': 'remove-unit', 'project': DPROJ4, 'path': os.path.join(D4, 'UMain.pas')})
    check('R4b remove-unit la quita tambien del .dproj (quedaba huerfana)',
          mc.abre(r, 'SN_UNIT_REMOVED_FMT') and 'UMain.pas' not in mc.lee(DPROJ4), (r[:300], mc.lee(DPROJ4)[-500:]))

    # --- R5 (J6) ----------------------------------------------------------------
    D5, _, _ = proyecto('PInc')
    r = s.call('delphi_create', {'kind': 'include', 'name': 'Notas', 'project': os.path.join(D5, '.gitignore'),
                                 'content': '{$DEFINE SONDA}'})
    check('R5 create kind=include con project=.gitignore: negado y nada creado (lo creaba y callaba)',
          mc.rechazado(r) and mc.es(r, 'SR_UNIT_PROJECT_EXT_FMT') and not os.path.exists(os.path.join(D5, 'Notas.inc')),
          r[:300])

    # --- R6 (J11) ---------------------------------------------------------------
    r = s.call('delphi_paserver', {'command': 'get-sdk', 'name': 'NoExiste', 'active': 'xyz'})
    check('R6 get-sdk active=xyz: PAS-073 antes de nada (se tomaba por un no sin decirlo)',
          mc.rechazado(r) and mc.es(r, 'SR_PASERVER_ACTIVE_NO_ES_SINO_FMT'), r[:300])
    r = s.call('delphi_paserver', {'command': 'get-sdk', 'name': 'NoExiste', 'active': 'on'})
    check('R6b active=on es de la gramatica: sigue hasta el perfil (no PAS-073)',
          not mc.es(r, 'SR_PASERVER_ACTIVE_NO_ES_SINO_FMT'), r[:300])
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('revisor del paisaje 1.28 (J1-J11)')
