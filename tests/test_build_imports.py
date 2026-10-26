"""Contrato E2E de imports: se analizan todos los atributos XML y archivos locales.
Las fixtures contienen Exec con Command vacio: incluso el binario antiguo
solo puede llegar a un error de validacion de MSBuild, sin ejecutar un comando.
El rechazo debe venir del escaner y nombrar la tarea, no de otro error.
"""
import os
from xml.sax.saxutils import escape
import mcp_cliente as mc

BASE = mc.carpeta('build-imports')
# FUERA de la raiz del servidor (DELPHI_MCP_ROOTS = BASE), hermana de BASE
FUERA = mc.carpeta('build-imports-fuera')
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

    # BUILD-017 (17-oct y 19-oct-2026): el Import que el IDE escribe para el
    # manifiesto de despliegue lleva Condition="Exists(<el mismo>)"; sin el
    # fichero msbuild no lo importa, y se negaba TODO proyecto recien creado en
    # el IDE hasta su primer despliegue (y el worktree de un repo que ignora el
    # .deployproj). Rojo contra la 1.21.0. Solo ESA forma, literal.
    IDE_DEP = ('<Import Project="$(MSBuildProjectName).deployproj" '
               'Condition="Exists(\'$(MSBuildProjectName).deployproj\')"/>')
    carpeta = os.path.join(BASE, 'cond')
    salida = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Fixture', 'dir': carpeta})
    mc.check('cond: fixture creada', mc.abre(salida, 'SK_CREATE_CREADO_PROYECTO_FMT'), salida[:200])
    proyecto = os.path.join(carpeta, 'Fixture.dproj')
    with open(proyecto, encoding='utf-8-sig') as f:
        xml_cond = f.read()

    def con_import(linea):
        with open(proyecto, 'w', encoding='utf-8-sig', newline='') as f:
            f.write(xml_cond.replace('</Project>', linea + '</Project>'))

    con_import(IDE_DEP)
    r = srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64'}, 600)
    mc.check('cond: el Import del IDE con Exists de si mismo y SIN el .deployproj compila (era BUILD-017)',
             mc.como_json(r).get('success') is True, mc.como_json(r).get('firstError') or r[:400])
    # con el fichero, se lee y se escanea como cualquier otro: un Exec dentro se niega
    dep = os.path.join(carpeta, 'Fixture.deployproj')
    with open(dep, 'w', encoding='utf-8') as f:
        f.write('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><Target Name="Fixture" BeforeTargets="Build"><Exec Command=""/></Target></Project>')
    r = srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64'}, 600)
    mc.check('cond: ...y CON el .deployproj se escanea: un <Exec> dentro se niega',
             mc.rechazado(r) and mc.es(r, 'SR_BUILD_HAZARD_FMT') and 'a <exec> task' in r, r[:400])
    os.remove(dep)
    # otra condicion (Exists de OTRO fichero) no se evalua aqui: sigue negado
    con_import('<Import Project="cond.targets" Condition="Exists(\'otro.targets\')"/>')
    r = srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64'}, 600)
    mc.check('cond: un Import que falta con la condicion de OTRO fichero sigue negado (BUILD-017)',
             mc.rechazado(r) and mc.es(r, 'SR_BUILD_HAZARD_FMT') and 'not there to be checked (cond.targets)' in r,
             r[:400])

    # V1 (1.23): un LocalCommand/RemoteCommand de un DeployFile es una linea de
    # ordenes LIBRE que el Deploy entrega a un ejecutor (local, o el destino por
    # PAServer). HazardScan los niega si no estan vacios; los que genera el
    # servidor van vacios (plantilla). ROJO contra el build sin el arreglo.
    con_import(IDE_DEP)
    DEP_H = '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><ItemGroup><DeployFile Include="Fixture.exe">'
    DEP_T = '</DeployFile></ItemGroup></Project>'
    for tag in ('LocalCommand', 'RemoteCommand'):
        with open(dep, 'w', encoding='utf-8') as f:
            f.write(DEP_H + '<%s>cmd /c echo marca</%s>' % (tag, tag) + DEP_T)
        r = srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64'}, 600)
        mc.check('cond: un <%s> no vacio de un DeployFile se niega (V1)' % tag,
                 mc.rechazado(r) and mc.es(r, 'SR_BUILD_HAZARD_FMT') and tag in r, r[:400])
    # guarda: los comandos VACIOS (lo que genera el servidor) NO se niegan
    with open(dep, 'w', encoding='utf-8') as f:
        f.write(DEP_H + '<LocalCommand/><RemoteCommand/>' + DEP_T)
    r = srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64'}, 600)
    mc.check('cond: un DeployFile con LocalCommand/RemoteCommand VACIOS compila (V1 guarda)',
             mc.como_json(r).get('success') is True, mc.como_json(r).get('firstError') or r[:400])
    os.remove(dep)

    # A25 (1.23): el deny de un <Import> UNC pasa por los jueces EsUnc /
    # EsPrefijoDeDispositivo, SIN estrecharse: un UNC (dos barras) o un prefijo
    # de dispositivo/NT se niegan igual que antes; una letra no cae por aqui.
    # Rojo contra un mutante que solo mirase EsUnc (dejaria pasar el prefijo).
    bs = chr(92)  # barra invertida sin teclearla (evita escapes en el anclaje)
    for forma in (bs * 2 + 'host' + bs + 'x.targets',
                  '//host/x.targets',
                  bs * 2 + '?' + bs + 'UNC' + bs + 'host' + bs + 'x.targets',
                  bs * 2 + '.' + bs + 'x.targets'):
        con_import('<Import Project="%s"/>' % forma)
        r = srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64'}, 600)
        mc.check('cond: un <Import> %r se niega como UNC (A25, no se debilita)' % forma,
                 mc.rechazado(r) and mc.es(r, 'SR_BUILD_HAZARD_FMT') and
                 'an <Import> from a UNC path' in r, r[:400])
    # una letra FUERA de las raices NO cae por el deny UNC (se niega por 'fuera')
    con_import('<Import Project="%s"/>' % ('C:' + bs + 'fuera' + bs + 'x.targets'))
    r = srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64'}, 600)
    mc.check('cond: un <Import> con letra no cae por el deny UNC (A25)',
             'an <Import> from a UNC path' not in r, r[:400])

    # Un Import de un fichero FUERA de las raices, INOCUO a proposito: la puerta
    # de leer no lo deja leer (bloque de las puertas de la 1.18.0) y el build lo
    # cargaria de alli. Hasta 22c83e1 el escaner lo leia, lo veia limpio y
    # msbuild lo cargaba de fuera: este check, contra ese binario, compila.
    carpeta = os.path.join(BASE, 'fuera')
    salida = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Fixture', 'dir': carpeta})
    mc.check('fuera: fixture creada', mc.abre(salida, 'SK_CREATE_CREADO_PROYECTO_FMT'), salida[:200])
    proyecto = os.path.join(carpeta, 'Fixture.dproj')
    externo = os.path.join(FUERA, 'externo.targets')
    with open(externo, 'w', encoding='utf-8') as f:
        f.write('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><Target Name="Fixture" BeforeTargets="Build"><Message Text="fixture"/></Target></Project>')
    with open(proyecto, encoding='utf-8-sig') as f:
        xml = f.read()
    xml = xml.replace('</Project>', '<Import Project="%s"/></Project>' % escape(externo, {'"': '&quot;'}))
    with open(proyecto, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(xml)
    r = srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64'}, 600)
    mc.check('fuera: un Import de fuera de las raices se rechaza aunque sea inocuo (no se lee)',
             mc.rechazado(r) and mc.es(r, 'SR_BUILD_HAZARD_FMT') and
             'outside the workspace' in r, r[:400])
    # el control: el mismo Import, con el fichero DENTRO de la raiz, compila
    dentro = os.path.join(carpeta, 'externo.targets')
    with open(dentro, 'w', encoding='utf-8') as f:
        f.write('<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003"><Target Name="Fixture" BeforeTargets="Build"><Message Text="fixture"/></Target></Project>')
    with open(proyecto, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(xml.replace(escape(externo, {'"': '&quot;'}), escape(dentro, {'"': '&quot;'})))
    r = srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64'}, 600)
    mc.check('fuera: ...y el mismo Import con el fichero dentro de la raiz compila',
             mc.como_json(r).get('success') is True, mc.como_json(r).get('firstError') or r[:400])

    # A39 (1.23): un <Import> ANIDADO que usa $(MSBuildProjectDirectory) /
    # $(ProjectDir) / $(MSBuildProjectName). msbuild los fija al PROYECTO que
    # compila (constantes en toda la cadena, medido con el oraculo de msbuild);
    # el escaner los expandia con el fichero que IMPORTA, asi que resolvia y
    # escaneaba OTRO fichero que el que msbuild importa. Exploit: un benigno
    # donde miraba el escaner (carpeta del .targets anidado) y el hazard donde
    # lo importa msbuild (carpeta del proyecto). ROJO contra produccion (sin A39).
    carpeta = os.path.join(BASE, 'a39')
    salida = srv.call('delphi_create', {'kind': 'project-console', 'name': 'Fixture', 'dir': carpeta})
    mc.check('a39: fixture creada', mc.abre(salida, 'SK_CREATE_CREADO_PROYECTO_FMT'), salida[:200])
    proyecto = os.path.join(carpeta, 'Fixture.dproj')
    sub = os.path.join(carpeta, 'sub')
    os.makedirs(sub, exist_ok=True)
    NS = '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">'
    # el .targets anidado importa via $(MSBuildProjectDirectory): msbuild -> la
    # carpeta del PROYECTO (carpeta\evil.targets); el escaner con el bug -> la
    # del fichero que importa (carpeta\sub\evil.targets)
    with open(os.path.join(sub, 'mid.targets'), 'w', encoding='utf-8') as f:
        f.write(NS + '<Import Project="$(MSBuildProjectDirectory)\\evil.targets"/></Project>')
    # donde lo importa msbuild: el HAZARD (un <Exec>)
    with open(os.path.join(carpeta, 'evil.targets'), 'w', encoding='utf-8') as f:
        f.write(NS + '<Target Name="X" BeforeTargets="Build"><Exec Command=""/></Target></Project>')
    # donde miraba el escaner con el bug: INOCUO (sin tarea que ejecute)
    with open(os.path.join(sub, 'evil.targets'), 'w', encoding='utf-8') as f:
        f.write(NS + '<Target Name="Y" BeforeTargets="Build"><Message Text="ok"/></Target></Project>')
    with open(proyecto, encoding='utf-8-sig') as f:
        xml = f.read()
    with open(proyecto, 'w', encoding='utf-8-sig', newline='') as f:
        f.write(xml.replace('</Project>', '<Import Project="sub\\mid.targets"/></Project>'))
    r = srv.call('delphi_build', {'project': proyecto, 'platform': 'Win64'}, 600)
    mc.check('a39: el <Exec> del fichero que msbuild importa via $(MSBuildProjectDirectory) se escanea y se niega (rojo sin el fix)',
             mc.rechazado(r) and mc.es(r, 'SR_BUILD_HAZARD_FMT') and 'a <exec> task' in r, r[:400])
finally:
    srv.cierra()
    mc.borra(BASE)
    mc.borra(FUERA)
mc.fin('contrato de imports de build')
