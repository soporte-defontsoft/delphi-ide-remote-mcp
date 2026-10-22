# -*- coding: utf-8 -*-
r"""Todo fichero que el IDE carga como XML (.dproj, .groupproj, .deployproj) lo juzga el parser del IDE (MSXML 6)
antes de que el servidor lo escriba (1.22.1). La 1.22.0 lo prometia en el CHANGELOG para "el guardado que llama
todo escritor de un fichero de proyecto", pero el juez vivia en PatchSaveConSuSalto, el de los editores del
.dproj, y cinco escritores guardaban sin el (revisor Opus de la 1.22.0, H5): add-project / remove-project del
.groupproj, la mudanza que re-apunta un .dproj o un .groupproj, el .dproj de delphi_create y el create de un
changeset. Ahora lo pregunta PatchSaveText, el escritor de abajo, por la clase de fichero (Lsp.Patch.EsXmlDelIde).

  X0 control: un changeset crea un .dproj bien formado (commit, y el fichero esta)
  X1 el preview de un changeset que crea un .dproj que MSXML no carga (R&D sin escapar): CFG-142, con la linea
     (ROJA contra la 1.22.0: preview limpio)
  X2 ...y el commit lo niega: el fichero no existe (ROJA: lo escribia)
  X3 add-project sobre un .groupproj con R&D sin escapar: CFG-142 y el grupo byte a byte (ROJA: lo guardaba)

Uso:  python tests/test_xml_ide_1221.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('xml-ide')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='xi', t=600)

DPROJ_BUENO = ('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\r\n'
               '    <PropertyGroup>\r\n'
               '        <ProjectGuid>{0B3A6C2E-5D1F-4A7B-9C8D-2E4F6A8B0C1D}</ProjectGuid>\r\n'
               '    </PropertyGroup>\r\n'
               '</Project>\r\n')
DPROJ_MALO = DPROJ_BUENO.replace('</ProjectGuid>', '</ProjectGuid>\r\n        <Description>R&D</Description>')
GRUPO_MALO = ('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\r\n'
              '    <PropertyGroup>\r\n'
              '        <ProjectGuid>{8CE8EDB2-1C71-4284-B6E5-466F36010B99}</ProjectGuid>\r\n'
              '        <Description>R&D</Description>\r\n'
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


def cs(args):
    return srv.call('delphi_changeset', args)


def begin():
    r = cs({'command': 'begin'})
    assert mc.abre(r, 'SN_CHANGESET_BEGUN_FMT'), r[:300]
    return mc.id_changeset(r)


try:
    bueno = os.path.join(BASE, 'Bueno.dproj')
    cid = begin()
    cs({'command': 'stage', 'id': cid, 'kind': 'create', 'path': bueno, 'content': DPROJ_BUENO})
    cs({'command': 'preview', 'id': cid})  # el commit pide un preview limpio antes (CHSET-016)
    r = cs({'command': 'commit', 'id': cid})
    check('X0 control: un changeset crea un .dproj bien formado',
          mc.abre(r, 'SN_CHANGESET_COMMITTED_FMT') and os.path.exists(bueno), r[:300])

    malo = os.path.join(BASE, 'Malo.dproj')
    cid = begin()
    r = cs({'command': 'stage', 'id': cid, 'kind': 'create', 'path': malo, 'content': DPROJ_MALO})
    r = cs({'command': 'preview', 'id': cid})
    check('X1 el preview de crear un .dproj que MSXML no carga dice CFG-142, con la linea',
          mc.es(r, 'SR_PATCH_XML_MAL_FORMADO_FMT') and 'line 4' in r, r[:400])
    r = cs({'command': 'commit', 'id': cid})
    check('X2 ...y el commit lo niega: el fichero no existe', not os.path.exists(malo), r[:400])

    r = srv.call('delphi_create', {'kind': 'project-console', 'name': 'App', 'dir': os.path.join(BASE, 'app')})
    check('fixture: el proyecto que entra en el grupo (delphi_create)', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
    grupo = os.path.join(BASE, 'Todo.groupproj')
    open(grupo, 'w', encoding='utf-8-sig', newline='').write(GRUPO_MALO)
    antes = open(grupo, 'rb').read()
    r = srv.call('delphi_config', {'project': grupo, 'command': 'add-project',
                                   'path': os.path.join(BASE, 'app', 'App.dproj')})
    check('X3 add-project sobre un .groupproj con R&D sin escapar: CFG-142 y el grupo byte a byte',
          mc.es(r, 'SR_PATCH_XML_MAL_FORMADO_FMT') and open(grupo, 'rb').read() == antes, r[:400])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('juez XML del IDE en todo escritor (1.22.1)')
