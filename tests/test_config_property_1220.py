# -*- coding: utf-8 -*-
r"""delphi_config set-property / remove-property / get-property (1.22.0): UNA propiedad
del .dproj por su nombre, en el grupo del build que digan platform y config, por EL
escritor de Lsp.Dproj (PonPropiedadDelBuild, el gemelo de EffectiveProperty). Hasta la
1.21.4 cada comando elegia el grupo a su manera (set-sdk / set-profile solo plataforma,
add-searchpath el suyo) y en un grupo de configuracion no escribia nadie: el keystore de
Android que el IDE deja en '$(Cfg_1_Android64)'!='' no tenia tool que lo quitase (un agente
lo midio el 21-oct-2026 con un keystore fuera de las raices; David: "es correcto que
rechace, el problema es que no hay tool para quitarlo").

Fixture: un proyecto de consola (delphi_create) y una carpeta lib\ con una unidad que el
.dpr usa. El juez de DONDE se escribe es msbuild: un DCC_UnitSearchPath puesto SOLO para
Win64 Release lo encuentra Release y Debug no (F2613).

  P0  get-property de lo que el proyecto trae (DCC_DcuOutput): el valor efectivo del build
      por defecto y en que grupos esta
  P1  set-property DCC_UnitSearchPath=lib para Win64 Release: CFG-136, y el grupo
      '$(Cfg_2_Win64)'!='' creado con su definidor como lo escribe el IDE, antes de los Import
  P2  msbuild lo lee donde se escribio: Win64 Release compila; Win64 Debug F2613
  P3  get-property para Win64 Release = lib; para Win64 Debug no esta (y dice donde esta)
  P4  el mismo valor otra vez: CFG-137 y el .dproj byte a byte
  P5  el keystore: set-property PF_KeyStoreDebug=<fuera> para Android64 Debug (CFG-136, el
      grupo del IDE); un build Win64 Release compila (la puerta juzga el build pedido);
      get-property para Android64 Debug lo da; remove-property: CFG-138 y ya no esta; otra
      vez: CFG-139
  P6  lo que se niega, sin tocar el .dproj: sin name (CFG-130); un nombre que no es
      (CFG-131); la estructura (Cfg_1, Platform: CFG-132); un evento y una opcion libre
      (PreBuildEvent, DCC_AdditionalSwitches: CFG-133); set-property sin value (CFG-134);
      un value con salto (CFG-135); una config que no declara (CFG-116); una plataforma que
      no es (CFG-082); un parametro que no es del comando (value en get-property)
  P7  el .dproj escrito lo carga MSXML6, el juez del IDE (si pywin32 esta; si no, no se mide)

Uso:  python tests/test_config_property_1220.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('config-property')
FUERA = mc.carpeta('config-property-fuera')  # fuera de la raiz del servidor, hermana de BASE
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='cp', t=600)
KEYSTORE = os.path.join(FUERA, 'x.keystore')


def config(proyecto, comando, **campos):
    args = {'project': proyecto, 'command': comando}
    args.update(campos)
    return srv.call('delphi_config', args)


def build(proyecto, config_='Release'):
    return srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64', 'config': config_}, 600)


def compila(r):
    return mc.como_json(r).get('success') is True


def detalle(r):
    return mc.como_json(r).get('firstError') or r[:400]


def lee(proyecto):
    with open(proyecto, encoding='utf-8-sig') as f:
        return f.read()


def carga_msxml(ruta):
    """True/False si MSXML6 (el cargador del IDE) carga el fichero; None si no hay pywin32."""
    try:
        import win32com.client
    except ImportError:
        return None
    doc = win32com.client.Dispatch('Msxml2.DOMDocument.6.0')
    setattr(doc, 'async', False)
    return bool(doc.load(ruta))


try:
    carpeta = os.path.join(BASE, 'fixture')
    salida = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Fixture', 'dir': carpeta})
    check('fixture creada (delphi_create)', mc.abre(salida, 'SK_CREATE_CREADO_PROYECTO_FMT'), salida[:200])
    proyecto = os.path.join(carpeta, 'Fixture.dproj')
    # una unidad que SOLO esta en lib\, y el .dpr la usa
    os.makedirs(os.path.join(carpeta, 'lib'))
    open(os.path.join(carpeta, 'lib', 'Ajena.pas'), 'w', encoding='utf-8').write(
        'unit Ajena;\r\ninterface\r\nimplementation\r\nend.\r\n')
    dpr = os.path.join(carpeta, 'Fixture.dpr')
    with open(dpr, encoding='utf-8-sig') as f:
        fuente = f.read()
    assert 'uses' in fuente, fuente[:200]
    with open(dpr, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(fuente.replace('uses', 'uses\r\n  Ajena,', 1))

    r = config(proyecto, 'get-property', name='DCC_DcuOutput')
    check('P0 get-property DCC_DcuOutput: CFG-140 con el build por defecto y donde esta',
          mc.es(r, 'SN_CFG_PROPERTY_GET_FMT') and 'Set in:' in r and 'by default' in r, r[:300])

    antes = lee(proyecto)
    r = config(proyecto, 'set-property', name='DCC_UnitSearchPath', value='lib', platform='Win64', config='Release')
    check('P1 set-property DCC_UnitSearchPath=lib para Win64 Release: CFG-136',
          mc.es(r, 'SN_CFG_PROPERTY_PUESTA_FMT') and "'$(Cfg_2_Win64)'!=''" in r, r[:300])
    xml = lee(proyecto)
    definidor = ('<PropertyGroup Condition="(\'$(Platform)\'==\'Win64\' and \'$(Cfg_2)\'==\'true\') '
                 'or \'$(Cfg_2_Win64)\'!=\'\'">')
    valores = '<PropertyGroup Condition="\'$(Cfg_2_Win64)\'!=\'\'">'
    check('P1 ...el definidor y el grupo de valores de Cfg_2_Win64, como los escribe el IDE',
          definidor in xml and valores in xml and '<DCC_UnitSearchPath>lib</DCC_UnitSearchPath>' in xml, xml[:1500])
    check('P1 ...definidor antes que valores, los dos antes del primer <Import>',
          xml.index(definidor) < xml.index(valores) < xml.index('<Import Project='), xml[:1500])
    check('P1 ...tras los valores de Release y antes de los de Cfg_2 no habia ninguno de plataforma',
          xml.index('<PropertyGroup Condition="\'$(Cfg_2)\'!=\'\'">') < xml.index(valores), xml[:1500])

    r = build(proyecto, 'Release')
    check('P2 msbuild lee el grupo: Win64 Release compila con la unidad de lib\\', compila(r), detalle(r))
    r = build(proyecto, 'Debug')
    check('P2 ...y Win64 Debug no la encuentra (F2613): el grupo es solo de Release',
          not compila(r) and 'Ajena' in r and 'F2613' in r, r[:400])

    r = config(proyecto, 'get-property', name='DCC_UnitSearchPath', platform='Win64', config='Release')
    check('P3 get-property para Win64 Release = lib', mc.es(r, 'SN_CFG_PROPERTY_GET_FMT') and '= lib.' in r, r[:300])
    r = config(proyecto, 'get-property', name='DCC_UnitSearchPath', platform='Win64', config='Debug')
    check('P3 ...para Win64 Debug no esta, y dice en que grupo esta',
          mc.es(r, 'SN_CFG_PROPERTY_GET_FMT') and 'not set' in r and "'$(Cfg_2_Win64)'!=''" in r, r[:300])

    r = config(proyecto, 'set-property', name='DCC_UnitSearchPath', value='lib', platform='Win64', config='Release')
    check('P4 el mismo valor otra vez: CFG-137', mc.es(r, 'SN_CFG_PROPERTY_YA_FMT'), r[:300])
    check('P4 ...y el .dproj byte a byte', lee(proyecto) == xml)

    r = config(proyecto, 'set-property', name='PF_KeyStoreDebug', value=KEYSTORE, platform='Android64', config='Debug')
    check('P5 set-property PF_KeyStoreDebug (de FUERA) para Android64 Debug: CFG-136',
          mc.es(r, 'SN_CFG_PROPERTY_PUESTA_FMT') and "'$(Cfg_1_Android64)'!=''" in r, r[:300])
    xml = lee(proyecto)
    check('P5 ...en el grupo del IDE, con su definidor',
          '<PropertyGroup Condition="\'$(Cfg_1_Android64)\'!=\'\'">' in xml and
          '\'$(Cfg_1_Android64)\'!=\'\'">' in xml.split('<PropertyGroup Condition="(\'$(Platform)\'==\'Android64\' and \'$(Cfg_1)\'==\'true\') or ')[1][:40],
          xml[:2000])
    r = build(proyecto, 'Release')
    check('P5 ...un build Win64 Release compila: la puerta juzga el build pedido, no ese grupo', compila(r), detalle(r))
    r = config(proyecto, 'get-property', name='PF_KeyStoreDebug', platform='Android64', config='Debug')
    check('P5 ...get-property para Android64 Debug lo da',
          mc.es(r, 'SN_CFG_PROPERTY_GET_FMT') and 'x.keystore' in r and 'not set' not in r, r[:300])
    r = config(proyecto, 'remove-property', name='PF_KeyStoreDebug', platform='Android64', config='Debug')
    check('P5 remove-property: CFG-138 con lo que valia', mc.es(r, 'SN_CFG_PROPERTY_QUITADA_FMT') and 'x.keystore' in r, r[:300])
    check('P5 ...y ya no esta en el .dproj', 'PF_KeyStoreDebug' not in lee(proyecto))
    r = config(proyecto, 'remove-property', name='PF_KeyStoreDebug', platform='Android64', config='Debug')
    check('P5 ...otra vez: CFG-139, nada que quitar', mc.es(r, 'SN_CFG_PROPERTY_NO_ESTABA_FMT'), r[:300])

    xml = lee(proyecto)
    negadas = [
        ('sin name', dict(), 'SR_CFG_NEED_NAME'),
        ('un nombre que no es (a<b)', dict(name='a<b', value='x'), 'SR_CFG_NAME_NO_ES_PROPIEDAD_FMT'),
        ('un nombre que empieza por digito', dict(name='1x', value='x'), 'SR_CFG_NAME_NO_ES_PROPIEDAD_FMT'),
        ('la estructura: Cfg_1', dict(name='Cfg_1', value='true'), 'SR_CFG_NAME_ES_ESTRUCTURA_FMT'),
        ('la estructura: Platform', dict(name='Platform', value='Win64'), 'SR_CFG_NAME_ES_ESTRUCTURA_FMT'),
        ('un evento de build', dict(name='PreBuildEvent', value='calc.exe'), 'SR_CFG_NAME_ES_TEXTO_LIBRE_FMT'),
        ('una opcion libre', dict(name='DCC_AdditionalSwitches', value='-x'), 'SR_CFG_NAME_ES_TEXTO_LIBRE_FMT'),
        ('sin value', dict(name='PF_X'), 'SR_CFG_NEED_VALUE'),
        ('un value con salto', dict(name='PF_X', value='a\nb'), 'SR_CFG_VALUE_CON_CONTROL'),
        ('una config que no declara', dict(name='PF_X', value='x', config='Nope'), 'SR_CFG_SET_ACTIVE_CONFIG_FMT'),
        ('una plataforma que no es', dict(name='PF_X', value='x', platform='Foo'), 'SR_CFG_PLATAFORMA_DELPHI_VALIDA_VALIDAS_FMT'),
    ]
    for titulo, campos, codigo in negadas:
        r = config(proyecto, 'set-property', **campos)
        check('P6 set-property %s: %s' % (titulo, codigo), mc.rechazado(r) and mc.es(r, codigo), r[:300])
    r = config(proyecto, 'get-property', name='PF_X', value='x')
    check('P6 value no es de get-property', mc.rechazado(r) and mc.es(r, 'SR_CONFIG_NO_ES_DEL_COMANDO_FMT'), r[:300])
    r = config(proyecto, 'remove-property', name='Base_Win64')
    check('P6 remove-property de la estructura: CFG-132', mc.rechazado(r) and mc.es(r, 'SR_CFG_NAME_ES_ESTRUCTURA_FMT'), r[:300])
    check('P6 ...nada de eso toco el .dproj', lee(proyecto) == xml)

    cargado = carga_msxml(proyecto)
    if cargado is None:
        print('    P7 no se mide: sin pywin32 no hay MSXML desde python')
    else:
        check('P7 el .dproj escrito lo carga MSXML6, el cargador del IDE', cargado, proyecto)
finally:
    srv.cierra()
    mc.borra(BASE)
    mc.borra(FUERA)
mc.fin('config property 1220')
