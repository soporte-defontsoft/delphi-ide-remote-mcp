"""Contrato E2E de imports: se analizan todos los atributos XML y archivos locales.
Las fixtures contienen Exec con Command vacio: incluso el binario antiguo
solo puede llegar a un error de validacion de MSBuild, sin ejecutar un comando.
El rechazo debe venir del escaner y nombrar la tarea, no de otro error.
"""
import os
from xml.sax.saxutils import escape
import mcp_cliente as mc

BASE = mc.carpeta('build-imports')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': BASE}), nombre='imp', t=600)
casos = (
    ('simples', "<Import Project='%s'/>", 'fixture.targets'),
    ('espacios', '<Import Project = "%s"/>', 'fixture.targets'),
    ('entidad', '<Import Project="%s"/>', 'R&D.targets'),
    ('tabuladores', '<Import Project\t=\t"%s"/>', 'fixture.targets'),
    ('deploy', '<Import Project="%s"/>', 'fixture.deployproj'),
    ('usertools', '<Import Project="%s"/>', 'fixture-usertools.proj.targets'),
)
try:
    for nombre, forma, importado in casos:
        carpeta = os.path.join(BASE, nombre)
        salida = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Fixture', 'dir': carpeta})
        mc.check(nombre + ': fixture creada', mc.abre(salida, 'SK_CREATE_CREADO_PROYECTO_FMT'), salida[:200])
        proyecto = os.path.join(carpeta, 'Fixture.dproj')
        with open(proyecto, encoding='utf-8-sig') as f:
            xml = f.read()
        xml = xml.replace('</Project>', forma % escape(importado, {'"': '&quot;'}) + '</Project>')
        with open(proyecto, 'w', encoding='utf-8-sig', newline='') as f:
            f.write(xml)
        destino = os.path.join(carpeta, importado)
        with open(destino, 'w', encoding='utf-8') as f:
            f.write('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><Target Name="Fixture" BeforeTargets="Build"><Message Text="fixture"/></Target></Project>')
        r = srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64'}, 600)
        mc.check(nombre + ': control inocuo compila', mc.como_json(r).get('success') is True, mc.como_json(r).get('firstError') or r[:400])
        with open(destino, 'w', encoding='utf-8') as f:
            f.write('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><Target Name="Fixture" BeforeTargets="Build"><Exec Command=""/></Target></Project>')
        r = srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64'}, 600)
        mc.check(nombre + ': escaner rechaza la tarea del import',
                 mc.rechazado(r) and mc.es(r, 'SR_BUILD_HAZARD_FMT') and
                 'a <exec> task' in r, r[:400])
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('contrato de imports de build')
