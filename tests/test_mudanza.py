# -*- coding: utf-8 -*-
"""La mudanza de un proyecto y los grupos de proyectos (1.6.0).

Lo que paso el 24-sep-2026 reorganizando el repo por las tools: mover el
servidor un nivel mas adentro lo dejo sin compilar - 16 `in '..\\vendor'` del
.dpr, 16 DCCReference, un {$I} y los search paths -, y el .groupproj de la raiz
seguia apuntando al sitio viejo, sin una tool que editara un grupo. Aqui:

  G  delphi_config add-project / remove-project en un .groupproj: lo que
     escribe "Add existing project" del IDE (item, tres targets, agregados)
  M  delphi_move de la carpeta de un proyecto un nivel mas adentro: toda ruta
     relativa que cruzaba el borde, re-apuntada (unit de fuera, {$I}, search
     path, salida, el grupo de fuera); lo de dentro, intacto; y COMPILA
  C  la copia de una carpeta de units: sus directivas re-apuntadas, el
     original intacto (un PROYECTO no se copia: nunca vive en dos sitios)
  F  fix-references: lo movido por fuera de las tools se busca por su nombre;
     una coincidencia se re-apunta, varias se dicen y no se adivina

Usage:  python tests/test_mudanza.py [path-to-DelphiLspMcp.exe]
"""
import json
import os
import re
import shutil
import subprocess
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('mudanza')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='mud', t=600)
call = srv.call


def ruta(*p):
    return os.path.join(JAIL, *p)


def leer(*p):
    try:
        return open(ruta(*p), encoding='utf-8-sig').read()
    except OSError:
        return '(no existe %s)' % os.path.join(*p)


def bytes_de(*p):
    return open(ruta(*p), 'rb').read()


GRUPO_VACIO = (
    '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\r\n'
    '    <PropertyGroup>\r\n'
    '        <ProjectGuid>{8CE8EDB2-1C71-4284-B6E5-466F36010B99}</ProjectGuid>\r\n'
    '    </PropertyGroup>\r\n'
    '    <ProjectExtensions>\r\n'
    '        <Borland.Personality>Default.Personality.12</Borland.Personality>\r\n'
    '        <Borland.ProjectType/>\r\n'
    '        <BorlandProject>\r\n'
    '            <Default.Personality/>\r\n'
    '        </BorlandProject>\r\n'
    '    </ProjectExtensions>\r\n'
    '    <Import Project="$(BDS)\\Bin\\CodeGear.Group.Targets" '
    'Condition="Exists(\'$(BDS)\\Bin\\CodeGear.Group.Targets\')"/>\r\n'
    '</Project>\r\n')

try:
    # ------------------------------------------------------------ el mundo
    os.makedirs(ruta('lib'))
    open(ruta('lib', 'ULib.pas'), 'w', newline='\r\n').write(
        'unit ULib;\n\ninterface\n\nfunction Doble(X: Integer): Integer;\n\n'
        'implementation\n\nfunction Doble(X: Integer): Integer;\nbegin\n'
        '  Result := X * 2;\nend;\n\nend.\n')
    os.makedirs(ruta('inc'))
    open(ruta('inc', 'comun.inc'), 'w', newline='\r\n').write('// comun\n')
    APP = ruta('app')
    r = call('delphi_create', {'kind': 'project-console', 'name': 'App', 'dir': APP})
    check('mundo: el proyecto se crea', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    DPROJ = os.path.join(APP, 'App.dproj')
    r = call('delphi_create', {'kind': 'unit', 'name': 'UDentro', 'project': DPROJ})
    r = call('delphi_config', {'project': DPROJ, 'command': 'add-unit',
                               'path': ruta('lib', 'ULib.pas')})
    check('mundo: la unit de FUERA entra como ..\\lib',
          "'..\\lib\\ULib.pas'" in leer('app', 'App.dpr'), r[:200])
    r = call('delphi_edit', {'path': os.path.join(APP, 'App.dpr'), 'old': 'program App;',
                             'new': 'program App;\n\n{$I ..\\inc\\comun.inc}'})
    # la salida a ..\bin y el search path a ..\lib: se plantan en el .dproj
    # (ninguna tool escribe una salida con ..), como los dejaria un operador
    dp = open(DPROJ, encoding='utf-8-sig', newline='').read()
    dp = dp.replace('<DCC_ExeOutput>.\\$(Platform)\\$(Config)</DCC_ExeOutput>',
                    '<DCC_ExeOutput>..\\bin\\$(Platform)\\$(Config)</DCC_ExeOutput>'
                    '<DCC_UnitSearchPath>..\\lib;$(DCC_UnitSearchPath)</DCC_UnitSearchPath>', 1)
    open(DPROJ, 'w', encoding='utf-8-sig', newline='').write(dp)
    check('mundo: salida ..\\bin y search path ..\\lib plantados',
          '..\\bin\\$(Platform)' in leer('app', 'App.dproj') and
          '>..\\lib;' in leer('app', 'App.dproj'), leer('app', 'App.dproj')[:100])
    r = call('delphi_create', {'kind': 'project-console', 'name': 'Otro', 'dir': ruta('otro')})
    r = call('delphi_create', {'kind': 'project-console', 'name': 'App', 'dir': ruta('dup')})
    open(ruta('Todo.groupproj'), 'w', encoding='utf-8-sig', newline='').write(GRUPO_VACIO)
    # lo de FUERA que apunta DENTRO de app: un .inc de app incluido por una
    # unit de fuera, y un proyecto HERMANO (ni arriba ni abajo de app) que
    # lista una unit de app y busca en ella
    open(os.path.join(APP, 'dentro.inc'), 'w', newline='\r\n').write('// dentro\n')
    os.makedirs(ruta('fuera'))
    open(ruta('fuera', 'UFuera.pas'), 'w', newline='\r\n').write(
        'unit UFuera;\n\ninterface\n\n{$I ..\\app\\dentro.inc}\n\nimplementation\n\nend.\n')
    r = call('delphi_create', {'kind': 'project-console', 'name': 'Hermano', 'dir': ruta('hermano')})
    HDPROJ = ruta('hermano', 'Hermano.dproj')
    call('delphi_config', {'project': HDPROJ, 'command': 'add-unit',
                           'path': os.path.join(APP, 'UDentro.pas')})
    hp = open(HDPROJ, encoding='utf-8-sig', newline='').read().replace(
        '<DCC_ExeOutput>', '<DCC_UnitSearchPath>..\\app;$(DCC_UnitSearchPath)</DCC_UnitSearchPath><DCC_ExeOutput>', 1)
    open(HDPROJ, 'w', encoding='utf-8-sig', newline='').write(hp)
    GRUPO = ruta('Todo.groupproj')

    # ------------------------------------------------------------ G: grupos
    r = call('delphi_config', {'project': GRUPO, 'command': 'add-project', 'path': DPROJ})
    g = leer('Todo.groupproj')
    check('G1 add-project: el item, los tres targets y los agregados, como el IDE',
          mc.abre(r, 'SN_GRUPO_ANADIDO_FMT') and
          g.count('<Projects Include="app\\App.dproj">') == 1 and
          g.count('<MSBuild Projects="app\\App.dproj"') == 3 and
          '<Target Name="App:Clean">' in g and '<Target Name="App:Make">' in g and
          re.search(r'<Target Name="Build">\s*<CallTarget Targets="App"/>', g) is not None and
          re.search(r'<Target Name="Make">\s*<CallTarget Targets="App:Make"/>', g) is not None,
          r[:200] + ' | ' + g[:300])
    r = call('delphi_config', {'project': GRUPO, 'command': 'add-project',
                               'path': ruta('otro', 'Otro.dproj')})
    g = leer('Todo.groupproj')
    check('G1b ...el segundo se suma a la lista y a los agregados',
          mc.abre(r, 'SN_GRUPO_ANADIDO_FMT') and
          re.search(r'<CallTarget Targets="App;Otro"/>', g) is not None and
          re.search(r'<CallTarget Targets="App:Clean;Otro:Clean"/>', g) is not None, g[-600:])
    antes = bytes_de('Todo.groupproj')
    r = call('delphi_config', {'project': GRUPO, 'command': 'add-project', 'path': DPROJ})
    check('G2 anadir el que ya esta: YA estaba, sin tocar el fichero',
          mc.es(r, 'SN_GRUPO_YA_ESTABA_FMT') and bytes_de('Todo.groupproj') == antes, r[:200])
    r = call('delphi_config', {'project': GRUPO, 'command': 'add-project',
                               'path': ruta('dup', 'App.dproj')})
    # error: y no RECHAZADO: no es politica, es una llamada que no cabe
    check('G3 otro proyecto con el MISMO nombre: error (dos targets App no caben)',
          mc.resultado(r) == 'INVALID_PARAM' and mc.es(r, 'SR_GRUPO_TARGET_DUP_FMT') and bytes_de('Todo.groupproj') == antes,
          r[:200])
    r = call('delphi_config', {'project': GRUPO, 'command': 'remove-project',
                               'path': ruta('otro', 'Otro.dproj')})
    g = leer('Todo.groupproj')
    check('G4 remove-project: fuera el item, sus targets y su nombre en los agregados',
          mc.abre(r, 'SN_GRUPO_QUITADO_FMT') and 'Otro' not in g and
          re.search(r'<CallTarget Targets="App"/>', g) is not None and
          os.path.exists(ruta('otro', 'Otro.dproj')), r[:200] + ' | ' + g[-400:])
    j = mc.como_json(call('delphi_config', {'project': GRUPO}))
    check('G5 view del grupo: lista su proyecto',
          [p.get('include') for p in j.get('projects', [])] == ['app\\App.dproj'], str(j)[:200])
    r = call('delphi_config', {'project': DPROJ, 'command': 'add-project',
                               'path': ruta('otro', 'Otro.dproj')})
    check('G6 add-project sobre un PROYECTO: rechazado como llamada erronea, es una orden de un grupo',
          mc.resultado(r) == 'INVALID_PARAM' and mc.es(r, 'SR_GRUPO_SOLO_GRUPO_FMT'), r[:200])
    # G7 un grupo con Build pero SIN Clean ni Make: se anade a Build y se crean
    #    los que faltan (eran dos caminos: todos o ninguno)
    G7P = ruta('G7.groupproj')
    open(G7P, 'w', encoding='utf-8-sig', newline='').write(GRUPO_VACIO.replace('</Project>',
        '    <Target Name="Build">\r\n        <CallTarget Targets="Otro"/>\r\n    </Target>\r\n</Project>'))
    r = call('delphi_config', {'project': G7P, 'command': 'add-project', 'path': DPROJ})
    g7 = open(G7P, encoding='utf-8-sig').read()
    check('G7 Build existente y Clean/Make que faltan: a la lista de Build, y los otros dos creados',
          mc.abre(r, 'SN_GRUPO_ANADIDO_FMT') and 'Targets="Otro;App"' in g7 and
          'Targets="App:Clean"' in g7 and 'Targets="App:Make"' in g7 and not mc.es(r, 'SN_GRUPO_SIN_AGREGADO_FMT'),
          r[:200] + ' | ' + g7[-500:])

    # ------------------------------------------------------------ M: la mudanza
    r = call('delphi_move', {'path': APP, 'dest': ruta('src', 'app')})
    NUEVO = ruta('src', 'app')
    dpr = leer('src', 'app', 'App.dpr')
    dproj = leer('src', 'app', 'App.dproj')
    check('M la respuesta dice que re-apunto las rutas que cruzaban el borde',
          mc.abre(r, 'SK_MOVE_MOVIDO_FMT') and mc.es(r, 'SN_REUBICA_FMT'), r[:400])
    check('M1 la unit de FUERA: ..\\..\\lib en el .dpr; la de dentro, intacta',
          "'..\\..\\lib\\ULib.pas'" in dpr and "'UDentro.pas'" in dpr, dpr[:400])
    check('M1b ...y en el DCCReference del .dproj',
          'Include="..\\..\\lib\\ULib.pas"' in dproj and 'Include="UDentro.pas"' in dproj,
          dproj[:200])
    check('M2 {$I} re-apuntado; el resto del .dpr, intacto',
          '{$I ..\\..\\inc\\comun.inc}' in dpr and '{$APPTYPE CONSOLE}' in dpr, dpr[:300])
    check('M3 search path y salida que salian: re-apuntados; la de las dcu (dentro): intacta',
          '>..\\..\\lib;' in dproj and '..\\..\\bin\\$(Platform)\\$(Config)' in dproj and
          '.\\$(Platform)\\$(Config)\\dcu' in dproj, dproj[:200])
    g = leer('Todo.groupproj')
    check('M4 el grupo de FUERA sigue al proyecto (item y targets)',
          g.count('src\\app\\App.dproj') == 4 and 'app\\App.dproj"' not in g.replace('src\\app\\App.dproj"', ''),
          g[:400])
    b = mc.como_json(call('delphi_build', {'project': os.path.join(NUEVO, 'App.dproj'),
                                           'platform': 'Win32'}, t=600))
    check('M5 y COMPILA en su sitio nuevo (con la unit de fuera y el .inc)',
          b.get('success') is True, str(b)[:300])
    check('M6 una unit de FUERA con un {$I} que apuntaba dentro: re-apuntado',
          '{$I ..\\src\\app\\dentro.inc}' in leer('fuera', 'UFuera.pas'), leer('fuera', 'UFuera.pas'))
    check('M7 un proyecto HERMANO: su unit de dentro y su search path siguen a lo movido',
          "'..\\src\\app\\UDentro.pas'" in leer('hermano', 'Hermano.dpr') and
          'Include="..\\src\\app\\UDentro.pas"' in leer('hermano', 'Hermano.dproj') and
          '>..\\src\\app;' in leer('hermano', 'Hermano.dproj'),
          leer('hermano', 'Hermano.dpr')[:300])

    # ------------------------------------------------------------ C: la copia
    # Un PROYECTO no se copia (nunca vive en dos sitios: regla de la casa); lo
    # que si se copia es una carpeta de units, y sus directivas que salen
    # tienen que seguir llegando desde la copia.
    r = call('delphi_move', {'path': NUEVO, 'dest': ruta('copia'), 'copy': True})
    check('C1 copiar la carpeta de un PROYECTO sigue RECHAZADO (nunca en dos sitios)',
          mc.rechazado(r) and mc.es(r, 'SR_MOVE_COPY_PROJECT_FMT') and not os.path.exists(ruta('copia')), r[:200])
    os.makedirs(ruta('modulos'))
    open(ruta('modulos', 'UMod.pas'), 'w', newline='\r\n').write(
        'unit UMod;\n\ninterface\n\n{$I ..\\inc\\comun.inc}\n\nimplementation\n\nend.\n')
    r = call('delphi_move', {'path': ruta('modulos'), 'dest': ruta('src', 'modulos2'), 'copy': True})
    check('C2 la copia de una carpeta de units re-apunta SU {$I}; el original, intacto',
          '{$I ..\\..\\inc\\comun.inc}' in leer('src', 'modulos2', 'UMod.pas') and
          '{$I ..\\inc\\comun.inc}' in leer('modulos', 'UMod.pas'), r[:300])

    # ------------------------------------------------------------ F: fix-references
    os.makedirs(ruta('lib2'))
    shutil.move(ruta('lib', 'ULib.pas'), ruta('lib2', 'ULib.pas'))  # a mano: por fuera
    r = call('delphi_config', {'project': os.path.join(NUEVO, 'App.dproj'),
                               'command': 'fix-references'})
    check('F1 una unit movida por fuera: se encuentra por su nombre y se re-apunta',
          '1 re-apuntadas' in r and "'..\\..\\lib2\\ULib.pas'" in leer('src', 'app', 'App.dpr') and
          'Include="..\\..\\lib2\\ULib.pas"' in leer('src', 'app', 'App.dproj'), r[:300])
    for d in ('amb1', 'amb2', 'amb3'):
        os.makedirs(ruta(d))
    open(ruta('amb1', 'UAmb.pas'), 'w', newline='\r\n').write(
        'unit UAmb;\n\ninterface\n\nimplementation\n\nend.\n')
    call('delphi_config', {'project': ruta('dup', 'App.dproj'), 'command': 'add-unit',
                           'path': ruta('amb1', 'UAmb.pas')})
    shutil.move(ruta('amb1', 'UAmb.pas'), ruta('amb2', 'UAmb.pas'))
    shutil.copy(ruta('amb2', 'UAmb.pas'), ruta('amb3', 'UAmb.pas'))
    r = call('delphi_config', {'project': ruta('dup', 'App.dproj'), 'command': 'fix-references'})
    check('F2 dos candidatas del mismo nombre: se DICE y no se adivina',
          mc.es(r, 'SN_ARREGLA_VARIOS_FMT') and 'UAmb' in r and "'..\\amb1\\UAmb.pas'" in leer('dup', 'App.dpr'),
          r[:400])
    open(ruta('Fix.groupproj'), 'w', encoding='utf-8-sig', newline='').write(
        GRUPO_VACIO.replace('    <ProjectExtensions>',
                            '    <ItemGroup>\r\n        <Projects Include="viejo\\Otro.dproj">\r\n'
                            '            <Dependencies/>\r\n        </Projects>\r\n    </ItemGroup>\r\n'
                            '    <ProjectExtensions>'))
    r = call('delphi_config', {'project': ruta('Fix.groupproj'), 'command': 'fix-references'})
    check('F3 un grupo con un proyecto que ya no esta: se encuentra y se re-apunta',
          '1 re-apuntadas' in r and 'Include="otro\\Otro.dproj"' in leer('Fix.groupproj'), r[:300])

    # ------------------------------------------------------------ X: una ruta con &
    # Nueve sitios escribian rutas en atributos XML a mano, sin escapar: una
    # carpeta R&D dejaba el .dproj (o el grupo) sin ser XML. UN escritor
    # (XmlAtributo) y sus lectores desescapando.
    import xml.etree.ElementTree as ET

    def xml_valido(p):
        try:
            ET.parse(p)
            return True
        except ET.ParseError:
            return False
    os.makedirs(ruta('R&D', 'lib'))
    open(ruta('R&D', 'lib', 'UAmp.pas'), 'w', newline='\r\n').write(
        'unit UAmp;\n\ninterface\n\nimplementation\n\nend.\n')
    DP = os.path.join(NUEVO, 'App.dproj')
    r = call('delphi_config', {'project': DP, 'command': 'add-unit',
                               'path': ruta('R&D', 'lib', 'UAmp.pas')})
    check('X1 una unit de una carpeta R&D: el .dproj sigue siendo XML valido',
          xml_valido(DP) and 'R&amp;D' in leer('src', 'app', 'App.dproj') and
          "'..\\..\\R&D\\lib\\UAmp.pas'" in leer('src', 'app', 'App.dpr'), r[:200])
    r = call('delphi_config', {'project': DP, 'command': 'remove-unit',
                               'path': ruta('R&D', 'lib', 'UAmp.pas')})
    # QUITADA: que la haya encontrado y quitado, no que nunca llegara a entrar
    check('X2 ...y remove-unit la vuelve a encontrar (el lector desescapa)',
          mc.abre(r, 'SN_UNIT_REMOVED_FMT') and 'UAmp' not in leer('src', 'app', 'App.dproj') and
          xml_valido(DP), r[:200])
    r = call('delphi_create', {'kind': 'project-console', 'name': 'Rd', 'dir': ruta('R&D', 'rd')})
    r = call('delphi_config', {'project': GRUPO, 'command': 'add-project',
                               'path': ruta('R&D', 'rd', 'Rd.dproj')})
    j = mc.como_json(call('delphi_config', {'project': GRUPO}))
    check('X3 un proyecto de R&D en el grupo: XML valido y view devuelve la ruta entera',
          xml_valido(GRUPO) and
          any(p.get('include') == 'R&D\\rd\\Rd.dproj' and p.get('exists') for p in j.get('projects', [])),
          r[:200] + ' | ' + str(j)[:300])

    # ------------------------------------------- X: el TEXTO de un elemento con &
    # Los search paths, las salidas, el deploy y el .profile se escribian a
    # mano como texto de elemento: una mudanza hacia R&D dejaba el .dproj sin
    # ser XML, y los lectores tomaban R&amp;D por el nombre de una carpeta
    # (26-sep-2026). UN escritor (XmlElemento) y lectores desescapando.
    os.makedirs(ruta('comun'))
    open(ruta('comun', 'UComun.pas'), 'w', newline='\r\n').write(
        'unit UComun;\n\ninterface\n\nimplementation\n\nend.\n')
    r = call('delphi_config', {'project': DP, 'command': 'add-searchpath',
                               'path': '..\\..\\comun'})
    r = call('delphi_move', {'path': ruta('comun'), 'dest': ruta('R&D', 'comun')})
    j = mc.como_json(call('delphi_config', {'project': DP, 'section': 'searchpaths'}))
    rutas = [p for v in (j.get('searchPaths') or {}).values() for p in v]
    check('X4 una carpeta del search path se muda a R&D: el .dproj sigue siendo XML y view da la ruta de verdad',
          xml_valido(DP) and 'R&amp;D\\comun' in leer('src', 'app', 'App.dproj') and
          '..\\..\\R&D\\comun' in rutas, r[:200] + ' | ' + str(rutas))
    r = call('delphi_config', {'project': DP, 'command': 'fix-references'})
    check('X5 ...y fix-references no la da por perdida (su lector desescapa)',
          mc.abre(r, 'SN_ARREGLA_FMT') and not mc.es(r, 'SN_ARREGLA_RUTAS_FMT') and
          'R&amp;D' not in r, r[:300])
    # add-deployfile rechaza & en la ruta (por esa puerta no entra); lo que
    # se prueba es el LECTOR: una entrada con &amp; como la escribe el IDE
    open(os.path.join(NUEVO, 'datos.txt'), 'w').write('x')
    r = call('delphi_config', {'project': DP, 'command': 'add-deployfile', 'platform': 'Win64',
                               'path': os.path.join(NUEVO, 'datos.txt')})
    DEP = os.path.join(NUEVO, 'App.deployproj')
    if os.path.exists(DEP):
        dep = open(DEP, encoding='utf-8-sig', newline='').read()
        open(DEP, 'w', encoding='utf-8-sig', newline='').write(
            dep.replace('datos.txt', 'datos&amp;mas.txt'))
    j = mc.como_json(call('delphi_config', {'project': DP, 'section': 'deploy'}))
    lineas = [l for v in (j.get('deployFiles') or {}).values() for l in v]
    check('X6 una entrada de deploy con &amp; (como la escribe el IDE): view la da entera',
          os.path.exists(DEP) and xml_valido(DEP) and
          any('datos&mas.txt' in l and '&amp;' not in l for l in lineas),
          r[:200] + ' | ' + str(lineas)[:300])

    # ------------------------------------------------ R: la revision del 26-sep
    # Tres revisores independientes encontraron huecos en la mudanza, los
    # grupos y el XML; cada check prueba uno y falla con el codigo de antes.
    def escribe(texto, *p):
        os.makedirs(os.path.dirname(ruta(*p)), exist_ok=True)
        open(ruta(*p), 'w', encoding='utf-8', newline='\r\n').write(texto)

    UNIT = 'unit %s;\n\ninterface\n\n%s\n\nimplementation\n\nend.\n'
    # R1 {$I jedi.inc} que el compilador encuentra por el include path (no esta
    #    junto a la unit): no se toca; se reescribia a ..\jedi.inc (F1026)
    escribe('// jedi\n', 'r1', 'incs', 'jedi.inc')
    escribe(UNIT % ('UJedi', '{$I jedi.inc}'), 'r1', 'src', 'UJedi.pas')
    r = call('delphi_move', {'path': ruta('r1', 'src', 'UJedi.pas'),
                             'dest': ruta('r1', 'src', 'sub', 'UJedi.pas')})
    check('R1 {$I jedi.inc} resuelto por el include path: no se reescribe al mover la unit',
          '{$I jedi.inc}' in leer('r1', 'src', 'sub', 'UJedi.pas'), r[:300])

    # R2 una unit con FORM que lista un proyecto HERMANO (no de encima): al
    #    moverla, el hermano conserva el form (la mudanza iba antes que el .dfm)
    call('delphi_create', {'kind': 'project-vcl', 'name': 'Base2', 'dir': ruta('r2', 'app')})
    call('delphi_create', {'kind': 'form-vcl', 'name': 'UFicha', 'project': ruta('r2', 'app', 'Base2.dpr')})
    call('delphi_create', {'kind': 'project-console', 'name': 'Herm2', 'dir': ruta('r2', 'herm')})
    H2 = ruta('r2', 'herm', 'Herm2.dproj')
    call('delphi_config', {'project': H2, 'command': 'add-unit', 'path': ruta('r2', 'app', 'UFicha.pas')})
    r = call('delphi_move', {'path': ruta('r2', 'app', 'UFicha.pas'),
                             'dest': ruta('r2', 'app', 'forms', 'UFicha.pas')})
    linea = [l for l in leer('r2', 'herm', 'Herm2.dpr').split('\n') if 'UFicha in' in l]
    check('R2 unit con form de un proyecto HERMANO: re-apuntada y con su form (.dpr y DCCReference)',
          len(linea) == 1 and "forms\\UFicha.pas'" in linea[0] and '{' in linea[0] and
          '<Form>' in leer('r2', 'herm', 'Herm2.dproj') and not mc.es(r, 'SN_REUBICA_FALLOS_FMT') and not mc.es(r, 'SN_REUBICA_SALTADAS_FMT'),
          str(linea) + ' | ' + r[:300])
    # R3 y un RENAME de esa unit: el hermano pasa a la nueva (se buscaba por el
    #    nombre NUEVO en su .dpr, no se encontraba y se contaba como hecho)
    r = call('delphi_move', {'path': ruta('r2', 'app', 'forms', 'UFicha.pas'),
                             'dest': ruta('r2', 'app', 'forms', 'UFichaNueva.pas')})
    check('R3 rename de una unit de un proyecto HERMANO: el hermano lista la nueva',
          'UFichaNueva in' in leer('r2', 'herm', 'Herm2.dpr') and
          'UFicha in' not in leer('r2', 'herm', 'Herm2.dpr') and not mc.es(r, 'SN_REUBICA_FALLOS_FMT') and not mc.es(r, 'SN_REUBICA_SALTADAS_FMT'),
          leer('r2', 'herm', 'Herm2.dpr')[:400] + ' | ' + r[:300])

    # R4 grupos con DEPENDENCIAS, como las escribe el IDE: DependsOnTargets en
    #    los targets del que depende y <Dependencies> en su item
    call('delphi_create', {'kind': 'project-console', 'name': 'Pkg4', 'dir': ruta('r4', 'pkg')})
    call('delphi_create', {'kind': 'project-console', 'name': 'App4', 'dir': ruta('r4', 'app')})

    def grupo_con_deps(nombre):
        t4 = GRUPO_VACIO.replace('    <ProjectExtensions>',
            '    <ItemGroup>\r\n'
            '        <Projects Include="pkg\\Pkg4.dproj">\r\n            <Dependencies/>\r\n        </Projects>\r\n'
            '        <Projects Include="app\\App4.dproj">\r\n            <Dependencies>pkg\\Pkg4.dproj</Dependencies>\r\n        </Projects>\r\n'
            '    </ItemGroup>\r\n    <ProjectExtensions>')
        t4 = t4.replace('</Project>',
            '    <Target Name="Pkg4">\r\n        <MSBuild Projects="pkg\\Pkg4.dproj"/>\r\n    </Target>\r\n'
            '    <Target Name="Pkg4:Clean">\r\n        <MSBuild Projects="pkg\\Pkg4.dproj" Targets="Clean"/>\r\n    </Target>\r\n'
            '    <Target Name="Pkg4:Make">\r\n        <MSBuild Projects="pkg\\Pkg4.dproj" Targets="Make"/>\r\n    </Target>\r\n'
            '    <Target Name="App4" DependsOnTargets="Pkg4">\r\n        <MSBuild Projects="app\\App4.dproj"/>\r\n    </Target>\r\n'
            '    <Target Name="App4:Clean" DependsOnTargets="Pkg4:Clean">\r\n        <MSBuild Projects="app\\App4.dproj" Targets="Clean"/>\r\n    </Target>\r\n'
            '    <Target Name="App4:Make" DependsOnTargets="Pkg4:Make">\r\n        <MSBuild Projects="app\\App4.dproj" Targets="Make"/>\r\n    </Target>\r\n'
            '    <Target Name="Build">\r\n        <CallTarget Targets="Pkg4;App4"/>\r\n    </Target>\r\n'
            '    <Target Name="Clean">\r\n        <CallTarget Targets="Pkg4:Clean;App4:Clean"/>\r\n    </Target>\r\n'
            '    <Target Name="Make">\r\n        <CallTarget Targets="Pkg4:Make;App4:Make"/>\r\n    </Target>\r\n'
            '</Project>')
        open(ruta('r4', nombre), 'w', encoding='utf-8-sig', newline='').write(t4)
        return ruta('r4', nombre)

    GA = grupo_con_deps('A.groupproj')
    GB = grupo_con_deps('B.groupproj')
    r = call('delphi_config', {'project': GA, 'command': 'remove-project', 'path': ruta('r4', 'app', 'App4.dproj')})
    ga = open(GA, encoding='utf-8-sig').read()
    check('R4a quitar un proyecto CON DependsOnTargets: fuera sus tres targets (la regex los exigia sin nada)',
          mc.abre(r, 'SN_GRUPO_QUITADO_FMT') and 'App4' not in ga and xml_valido(GA), r[:200] + ' | ' + ga[-600:])
    r = call('delphi_config', {'project': GB, 'command': 'remove-project', 'path': ruta('r4', 'pkg', 'Pkg4.dproj')})
    gb = open(GB, encoding='utf-8-sig').read()
    check('R4b quitar la DEPENDENCIA: fuera de los DependsOnTargets y de las <Dependencies> de los demas',
          mc.abre(r, 'SN_GRUPO_QUITADO_FMT') and 'Pkg4' not in gb and '<Dependencies/>' in gb and
          'Name="App4">' in gb and xml_valido(GB), r[:200] + ' | ' + gb[-700:])
    GC = grupo_con_deps('C.groupproj')
    r = call('delphi_move', {'path': ruta('r4', 'pkg'), 'dest': ruta('r4', 'libs', 'pkg')})
    gc = open(GC, encoding='utf-8-sig').read()
    check('R4c mover la carpeta de la dependencia: sus <Dependencies> tambien siguen a lo movido',
          '<Dependencies>libs\\pkg\\Pkg4.dproj</Dependencies>' in gc and 'Include="libs\\pkg\\Pkg4.dproj"' in gc,
          gc[:900])

    # R5 un proyecto con & en el NOMBRE: add-project escribia Name= y Targets=
    #    a mano y el grupo dejaba de ser XML
    os.makedirs(ruta('r5'))
    open(ruta('r5', 'Rd&x.dproj'), 'w', encoding='utf-8-sig', newline='').write(
        open(DP, encoding='utf-8-sig', newline='').read())
    G5 = ruta('r5', 'G5.groupproj')
    open(G5, 'w', encoding='utf-8-sig', newline='').write(GRUPO_VACIO)
    r = call('delphi_config', {'project': G5, 'command': 'add-project', 'path': ruta('r5', 'Rd&x.dproj')})
    g5 = open(G5, encoding='utf-8-sig').read()
    check('R5 add-project de "Rd&x.dproj": el grupo sigue siendo XML (Name="Rd&amp;x")',
          mc.abre(r, 'SN_GRUPO_ANADIDO_FMT') and xml_valido(G5) and 'Name="Rd&amp;x"' in g5, r[:200] + ' | ' + g5[-500:])
    r = call('delphi_config', {'project': G5, 'command': 'remove-project', 'path': ruta('r5', 'Rd&x.dproj')})
    check('R5b ...y remove-project lo quita entero', mc.abre(r, 'SN_GRUPO_QUITADO_FMT') and 'Rd&amp;x' not in
          open(G5, encoding='utf-8-sig').read() and xml_valido(G5), r[:200])

    # R6 una directiva SIN comillas cuya ruta nueva lleva un espacio: con comillas
    escribe('// x\n', 'r6', 'a b', 'x.inc')
    escribe(UNIT % ('UEsp', '{$I ..\\x.inc}'), 'r6', 'a b', 'src', 'UEsp.pas')
    r = call('delphi_move', {'path': ruta('r6', 'a b', 'src', 'UEsp.pas'), 'dest': ruta('r6', 'UEsp.pas')})
    check("R6 {$I ..\\x.inc} movida a donde la ruta nueva lleva un espacio: {$I 'a b\\x.inc'}",
          "{$I 'a b\\x.inc'}" in leer('r6', 'UEsp.pas'), leer('r6', 'UEsp.pas')[:200] + ' | ' + r[:200])

    # R7 {$R a.res a.rc}: el .rc (segunda ruta) tambien se re-apunta
    escribe('', 'r7', 'res', 'a.res')
    escribe('', 'r7', 'res', 'a.rc')
    escribe(UNIT % ('URes', '{$R ..\\res\\a.res ..\\res\\a.rc}'), 'r7', 'src', 'URes.pas')
    r = call('delphi_move', {'path': ruta('r7', 'src', 'URes.pas'), 'dest': ruta('r7', 'src', 'sub', 'URes.pas')})
    check('R7 {$R a.res a.rc}: las DOS rutas re-apuntadas',
          '{$R ..\\..\\res\\a.res ..\\..\\res\\a.rc}' in leer('r7', 'src', 'sub', 'URes.pas'),
          leer('r7', 'src', 'sub', 'URes.pas')[:200])

    # R8 (D3) el icono, un fichero desplegado y un .optset importado del .dproj
    call('delphi_create', {'kind': 'project-console', 'name': 'App8', 'dir': ruta('r8', 'app')})
    for f in (('res', 'app.ico'), ('data', 'x.db'), ('opts', 'r.optset')):
        escribe('', 'r8', *f)
    D8 = ruta('r8', 'app', 'App8.dproj')
    d8 = open(D8, encoding='utf-8-sig', newline='').read().replace('</Project>',
        '    <PropertyGroup><Icon_MainIcon>..\\res\\app.ico</Icon_MainIcon></PropertyGroup>\r\n'
        '    <ItemGroup><DeployFile LocalName="..\\data\\x.db" Configuration="Release" Class="File"/></ItemGroup>\r\n'
        '    <Import Project="..\\opts\\r.optset" Condition="Exists(\'..\\opts\\r.optset\')"/>\r\n</Project>')
    open(D8, 'w', encoding='utf-8-sig', newline='').write(d8)
    r = call('delphi_move', {'path': ruta('r8', 'app'), 'dest': ruta('r8', 'sub', 'app')})
    d8 = leer('r8', 'sub', 'app', 'App8.dproj')
    check('R8 icono, DeployFile y .optset del .dproj siguen a lo que queda fuera',
          '<Icon_MainIcon>..\\..\\res\\app.ico<' in d8 and 'LocalName="..\\..\\data\\x.db"' in d8 and
          'Project="..\\..\\opts\\r.optset"' in d8 and "Exists('..\\..\\opts\\r.optset')" in d8 and xml_valido(ruta('r8', 'sub', 'app', 'App8.dproj')),
          d8[-500:] + ' | ' + r[:200])

    # R9 fix-references de un grupo no dice si EXISTE algo fuera de la jaula
    FUERA9 = os.path.join(BASE, 'fuera9')
    os.makedirs(FUERA9, exist_ok=True)
    open(os.path.join(FUERA9, 'Existe.dproj'), 'w').write('<Project/>')
    G9 = ruta('G9.groupproj')
    open(G9, 'w', encoding='utf-8-sig', newline='').write(GRUPO_VACIO.replace('    <ProjectExtensions>',
        '    <ItemGroup>\r\n        <Projects Include="..\\fuera9\\Existe.dproj"/>\r\n'
        '        <Projects Include="..\\fuera9\\NoExiste.dproj"/>\r\n    </ItemGroup>\r\n    <ProjectExtensions>'))
    r = call('delphi_config', {'project': G9, 'command': 'fix-references'})
    check('R9 fix-references de un grupo: de lo de FUERA de la jaula no dice ni si existe',
          mc.abre(r, 'SN_ARREGLA_FMT') and 'NoExiste' not in r and 'Existe.dproj' not in r, r[:300])

    # R10 las entidades de una lista que la mudanza NO toca quedan byte a byte
    call('delphi_create', {'kind': 'project-console', 'name': 'App10', 'dir': ruta('r10', 'app')})
    os.makedirs(ruta('r10', 'lib10'))
    D10 = ruta('r10', 'app', 'App10.dproj')
    d10 = open(D10, encoding='utf-8-sig', newline='').read().replace('</Project>',
        '    <PropertyGroup><DCC_UnitSearchPath>..\\lib10;C:\\x&#38;y;$(DCC_UnitSearchPath)</DCC_UnitSearchPath></PropertyGroup>\r\n</Project>')
    open(D10, 'w', encoding='utf-8-sig', newline='').write(d10)
    r = call('delphi_move', {'path': ruta('r10', 'app'), 'dest': ruta('r10', 'sub', 'app')})
    d10 = leer('r10', 'sub', 'app', 'App10.dproj')
    check('R10 un trozo con &#38; que no se toca queda como estaba (se re-escapaba la lista entera)',
          '>..\\..\\lib10;C:\\x&#38;y;$(DCC_UnitSearchPath)<' in d10 and '&amp;#38;' not in d10, d10[-300:])

    # R11 mover un JUNCTION a una victima de fuera: lo de detras no se recorre
    #     ni se intenta reescribir (antes lo paraba solo el escritor, y lo decia)
    VIC = os.path.join(BASE, 'fuera11')
    os.makedirs(os.path.join(VIC, 'victima'), exist_ok=True)
    open(os.path.join(VIC, 'x.inc'), 'w').write('// x\n')
    open(os.path.join(VIC, 'victima', 'UVic.pas'), 'w', newline='\r\n').write(UNIT % ('UVic', '{$I ..\\x.inc}'))
    antes11 = open(os.path.join(VIC, 'victima', 'UVic.pas'), 'rb').read()
    os.makedirs(ruta('r11'))
    subprocess.run(['cmd', '/c', 'mklink', '/J', ruta('r11', 'enlace'), os.path.join(VIC, 'victima')],
                   capture_output=True)
    try:
        r = call('delphi_move', {'path': ruta('r11', 'enlace'), 'dest': ruta('r11', 'enlace2')})
        check('R11 mover un junction: la victima de fuera sale intacta y no se intento reescribir',
              open(os.path.join(VIC, 'victima', 'UVic.pas'), 'rb').read() == antes11 and not mc.es(r, 'SN_REUBICA_FALLOS_FMT') and not mc.es(r, 'SN_REUBICA_SALTADAS_FMT'),
              r[:300])
    finally:
        for j in (ruta('r11', 'enlace'), ruta('r11', 'enlace2')):
            if os.path.isjunction(j):
                os.rmdir(j)  # el ENLACE, nunca lo de detras

    # X7 (D2) una carpeta R&D en el search path, por la tool: se rechazaba el &
    #    (la razon era el XML, y el escritor ya escapa)
    r = call('delphi_config', {'project': DP, 'command': 'add-searchpath', 'path': ruta('R&D', 'lib')})
    j = mc.como_json(call('delphi_config', {'project': DP, 'section': 'searchpaths'}))
    rutas = [p for v in (j.get('searchPaths') or {}).values() for p in v]
    check('X7 add-searchpath de una carpeta R&D: aceptado, escapado en el .dproj y view da la ruta',
          mc.abre(r, 'SN_CONFIG_PATH_ADDED_FMT') and xml_valido(DP) and any(p.endswith('R&D\\lib') for p in rutas),
          r[:200] + ' | ' + str(rutas))
    r = call('delphi_config', {'project': DP, 'command': 'remove-searchpath', 'path': ruta('R&D', 'lib')})
    check('X7b ...y remove-searchpath la encuentra y la quita (compara el valor de verdad)',
          mc.abre(r, 'SN_CONFIG_PATH_REMOVED_FMT') and 'R&amp;D\\lib;' not in leer('src', 'app', 'App.dproj'), r[:200])

    # ------------------------------------------------ W: el muro del 26-sep
    # Ninguna tool creaba un fuente SUELTO (.pas/.inc) sin darlo de alta en
    # un proyecto, y el lector del uses se paraba en el primer ';': un .dpr con
    # el uses partido en ramas {$IFDEF} (el del nodo de escritorio) no se podia
    # tocar sin que add-unit escribiera en la rama equivocada.
    os.makedirs(ruta('w'))
    r = call('delphi_create', {'kind': 'unit', 'name': 'USola', 'dir': ruta('w', 'comun')})
    check('W1 kind=unit SIN proyecto y con dir absoluto: una unit SUELTA, que nadie lista',
          mc.abre(r, 'SN_CREATE_UNIT_SUELTA_FMT') and os.path.exists(ruta('w', 'comun', 'USola.pas')) and
          'unit USola;' in leer('w', 'comun', 'USola.pas') and 'USola' not in leer('src', 'app', 'App.dpr'), r[:200])
    r = call('delphi_create', {'kind': 'unit', 'name': 'UOtra', 'dir': 'relativa'})
    check('W1b sin proyecto y con dir RELATIVO: sigue pidiendo el proyecto (o una carpeta absoluta)',
          mc.rechazado(r) and mc.es(r, 'SR_CREATE_UNIT_NEED_PROJECT') and not os.path.exists(ruta('relativa')), r[:200])
    r = call('delphi_create', {'kind': 'include', 'name': 'comun.inc', 'dir': ruta('w', 'comun'),
                               'content': "  COMUN = 'x';\n"})
    check('W2 kind=include con su content: un .inc, con CRLF',
          mc.abre(r, 'SN_CREATE_INCLUDE_FMT') and bytes_de('w', 'comun', 'comun.inc').endswith(b"  COMUN = 'x';\r\n"), r[:200])
    r = call('delphi_create', {'kind': 'include', 'name': 'comun', 'dir': ruta('w', 'comun'), 'content': '// otro'})
    check('W2b un .inc que ya existe: no se sobreescribe',
          mc.rechazado(r) and mc.es(r, 'SR_CREATE_YA_EXISTE_SOBREESCRIBE_FMT') and os.path.exists(ruta('w', 'comun', 'comun.inc')) and
          b'otro' not in bytes_de('w', 'comun', 'comun.inc'), r[:200])
    r = call('delphi_create', {'kind': 'include', 'name': 'vacio', 'dir': ruta('w', 'comun')})
    check('W2c kind=include sin content: rechazado', mc.rechazado(r) and mc.es(r, 'SR_CREATE_INCLUDE_CONTENT') and
          not os.path.exists(ruta('w', 'comun', 'vacio.inc')), r[:200])

    # un .dpr con el uses partido en ramas, como el del nodo (cada rama con su ';')
    call('delphi_create', {'kind': 'project-console', 'name': 'Ramas', 'dir': ruta('w', 'ramas')})
    for u in ('UWin', 'ULin', 'UNueva'):
        call('delphi_create', {'kind': 'unit', 'name': u, 'dir': ruta('w', 'ramas')})
    open(ruta('w', 'ramas', 'Ramas.dpr'), 'w', encoding='utf-8', newline='\r\n').write(
        "program Ramas;\n\n{$APPTYPE CONSOLE}\n\nuses\n  System.SysUtils,\n{$IFDEF MSWINDOWS}\n"
        "  UWin in 'UWin.pas';\n{$ELSE}\n  ULin in 'ULin.pas';\n{$ENDIF}\n\nbegin\nend.\n")
    DPRR = ruta('w', 'ramas', 'Ramas.dproj')
    antes_r = bytes_de('w', 'ramas', 'Ramas.dpr')
    r = call('delphi_config', {'project': DPRR, 'command': 'add-unit', 'path': ruta('w', 'ramas', 'UNueva.pas')})
    check('W3 add-unit a un uses partido en ramas: se niega (no sabe en cual) y no toca nada',
          mc.resultado(r) == 'INVALID_PARAM' and mc.es(r, 'SR_USES_EN_RAMAS_FMT') and bytes_de('w', 'ramas', 'Ramas.dpr') == antes_r, r[:250])
    r = call('delphi_config', {'project': DPRR, 'command': 'remove-unit', 'path': ruta('w', 'ramas', 'ULin.pas')})
    check('W3b ...y remove-unit tampoco lo reescribe', mc.resultado(r) == 'INVALID_PARAM' and mc.es(r, 'SR_USES_EN_RAMAS_FMT') and
          bytes_de('w', 'ramas', 'Ramas.dpr') == antes_r, r[:250])
    j = mc.como_json(call('delphi_config', {'project': DPRR, 'section': 'units'}))
    nombres = [u.get('unit') for u in (j.get('units') or [])]
    check('W4 la vista lista las units de LAS DOS ramas (se leia solo la primera)',
          'UWin' in nombres and 'ULin' in nombres, str(nombres))

    # ------------------------------------------------ el lector de directivas
    # Cuatro lectores de directivas usaban su regex sobre el texto crudo: una
    # directiva COMENTADA (tambien con //) contaba (David, 27-sep: "incluso //")
    escribe('// x\n', 'r12', 'x.inc')
    escribe(UNIT % ('UCom', '// {$I ..\\viejo.inc}\n{$I ..\\x.inc}'), 'r12', 'src', 'UCom.pas')
    r = call('delphi_move', {'path': ruta('r12', 'src', 'UCom.pas'), 'dest': ruta('r12', 'src', 'sub', 'UCom.pas')})
    ucom = leer('r12', 'src', 'sub', 'UCom.pas')
    check('R12 una directiva COMENTADA con // no se re-apunta; la de verdad si',
          '// {$I ..\\viejo.inc}' in ucom and '{$I ..\\..\\x.inc}' in ucom, ucom[:250])
    call('delphi_create', {'kind': 'project-console', 'name': 'Plano', 'dir': ruta('w', 'plano')})
    for u in ('UA', 'UB'):
        call('delphi_create', {'kind': 'unit', 'name': u, 'dir': ruta('w', 'plano')})
    open(ruta('w', 'plano', 'Plano.dpr'), 'w', encoding='utf-8', newline='\r\n').write(
        "program Plano;\n\n{$APPTYPE CONSOLE}\n\nuses\n  System.SysUtils, // {$IFDEF X} ya no hace falta\n"
        "  UA in 'UA.pas';\n\nbegin\nend.\n")
    r = call('delphi_config', {'project': ruta('w', 'plano', 'Plano.dproj'), 'command': 'add-unit',
                               'path': ruta('w', 'plano', 'UB.pas')})
    check('W5 un // {$IFDEF} COMENTADO dentro del uses no lo parte en ramas: add-unit entra',
          mc.abre(r, 'SN_UNIT_ADDED_FMT') and "UB in 'UB.pas'" in leer('w', 'plano', 'Plano.dpr'), r[:250])

    # W6 el AVISO de delphi_edit (David, 27-sep): un comentario de llave que cita
    #    una directiva de llave-dolar se cierra en el primer } (no bloquea)
    UA = ruta('w', 'plano', 'UA.pas')
    r = call('delphi_edit', {'path': UA, 'old': 'implementation',
                             'new': 'implementation\n\n{ cita {$IFDEF X} aqui }'})
    check('W6 delphi_edit avisa de un comentario de llave con otra llave dentro (y lo aplica)',
          mc.es(r, 'SN_AVISO_LLAVE_ANIDADA_FMT') and '{$IFDEF X}' in leer('w', 'plano', 'UA.pas'), r[:400])
    r = call('delphi_edit', {'path': UA, 'edits': json.dumps([
        {'old': 'interface', 'new': 'interface\n\n{ otra {$I x.inc} }'}])})
    check('W6b ...tambien dentro de una TANDA (la tanda se comia los avisos del motor)',
          mc.abre(r, 'SN_PATCH_EDITS_OK_FMT') and mc.es(r, 'SN_AVISO_LLAVE_ANIDADA_FMT'), r[:400])
    r = call('delphi_edit', {'path': UA, 'old': 'interface',
                             'new': 'interface\n\n// {$IFDEF X}\n(* { dentro *)\n{ normal }'})
    check('W6c un // o un (* *) con llaves dentro, o un comentario normal: sin aviso',
          not mc.es(r, 'SN_AVISO_LLAVE_ANIDADA_FMT') and mc.abre(r, 'SK_EDIT_ESCRITO_EN_FMT'), r[:300])
finally:
    srv.mata()
    mc.borra(BASE)

mc.fin('test_mudanza')
