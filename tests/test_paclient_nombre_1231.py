# -*- coding: utf-8 -*-
"""V217 (1.23.1): el nombre del proyecto que viaja a paclient, juzgado en UNA puerta.

paclient separa los campos de --put/--get por ',' y las entradas de --Remove por ';', y la orden
viaja como UN argumento entre comillas. El nombre del .dproj lo elige el agente y entraba SIN
juzgar en esos campos (TPath.GetFileNameWithoutExtension -> ProjName/DeployRel), compuesto a mano
en ~11 sitios. Un ';' en el nombre parte la entrada y el trozo que sobra se lee como fichero
LOCAL, relativo a la carpeta de trabajo de paclient (la CASA del servidor): una FUGA (medido el
30-oct contra el PAServer local con un exe inofensivo; aqui con el stub de paclient, que imita su
reparto por ',' y ';').

El arreglo: UN juez en Lsp.Guard (NombreDeProyectoParaPaclientDenegado, PAS-071) que las puertas
llaman -remote-run, kill y output por la de Mcp.Tools.PAServer (EjecucionRemotaDenegada), y el
segundo cerrojo dentro de Lsp.RemoteRun-. Un nombre con ',' ';' '"' o separador de ruta: PAS-071,
y nada viaja a paclient.

  P1 remote-run, nombre "Fuga;<marcador>": NO sube el fichero local de la casa y lo niega
     (PAS-071).  ROJO contra produccion: el stub recibe el --put partido y el marcador aparece
     en la scratch (la fuga).
  P2 remote-run, nombre "Coma,<marcador>": PAS-071 (el ',' parte igual el campo).  ROJO: pasa.
  P3 output, nombre con ';': PAS-071 en la MISMA puerta (su --get/--Remove llevan el nombre).
     ROJO: pasa la puerta y llega a "job ajeno".
  P4 kill, nombre con ';': PAS-071 en la misma puerta.  ROJO: pasa a "job ajeno".
  P5 control: un nombre limpio ("Limpio") SIGUE llegando a paclient (no se sobre-niega).
  P6 la regla es una lista blanca: un punto y coma de ancho completo tambien se niega.
  P7 control: acentos, espacios, puntos y guiones son un nombre normal y no se niegan.
  D1-D9 los campos de un DeployFile de un .deployproj a mano (BUILD-066): el ';' abre otra entrada
     del --put de msbuild (medido contra el PAServer local con un nombre que no existe).

Sin PAServer: paclient = tests/paclient_stub.py (DELPHI_MCP_PACLIENT), que imita el reparto por
',' y ';'. El servidor corre con cwd=CASA, como en produccion, para que el trozo que sobra se
resuelva ahi; en CASA se planta un fichero INOFENSIVO, nunca settings.ini.

Uso:  python tests/test_paclient_nombre_1231.py [ruta-a-DelphiLspMcp.exe]
"""
import os
import shutil
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 else None
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
BASE = mc.carpeta('paclient_nombre_1231')
SRVDIR = os.path.join(BASE, 'server')
os.makedirs(os.path.join(SRVDIR, 'node'))
EXE = mc.copia_exe(SRVDIR, src=exe_src)
# remote-run sube el lanzador que el servidor lleva en node\ junto a su exe (como test_remoterun):
# sin el, RemoteRun para en RUN-011 antes de llamar a paclient y no se mide nada
for f in ('McpRunJob', 'McpRunJob.exe'):
    shutil.copy(os.path.join(REPO, 'node', f), os.path.join(SRVDIR, 'node', f))
RUNJOB_EXE = os.path.join(SRVDIR, 'node', 'McpRunJob.exe')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
SCRATCH = os.path.join(BASE, 'scratch')
os.makedirs(SCRATCH)
# La CASA del servidor: FUERA de la jaula, como en produccion (donde vive settings.ini). El
# servidor corre con cwd=CASA, asi que paclient -su hijo- resuelve ahi un nombre de fichero
# relativo. Se planta un fichero INOFENSIVO (jamas settings.ini): si una llamada lo sube a la
# scratch, es la fuga.
CASA = os.path.join(BASE, 'casa')
os.makedirs(CASA)
MARCADOR = 'FUGA_INOCUA.txt'
open(os.path.join(CASA, MARCADOR), 'w', encoding='utf-8').write('fichero inofensivo de la casa del servidor')

# paclient = el stub, que imita el reparto por ',' y ';'
STUB = os.path.join(BASE, 'paclient.cmd')
open(STUB, 'w').write('@echo off\r\npython "%s" %%*\r\n' % os.path.join(HERE, 'paclient_stub.py'))
open(os.path.join(SCRATCH, '_espera'), 'w').write('3')  # el stub no espera a que remate un trabajo

PROF = 'perfil'
_ad, _host = mc.appdata_perfil(BASE, PROF, '127.0.0.1')  # perfil FALSO Win64 en 127.0.0.1
env = mc.entorno()
env['DELPHI_MCP_ROOTS'] = JAIL
env['DELPHI_MCP_PACLIENT'] = STUB
env['MCP_STUB_SCRATCH'] = SCRATCH
env['MCP_STUB_RUNJOB_EXE'] = RUNJOB_EXE
env['DELPHI_MCP_ALLOW_REMOTE_RUN'] = '1'
env['DELPHI_MCP_REMOTE_RUN_PROJECTS'] = 'all'   # el comodin: la lista no decide este punto
env['APPDATA'] = _ad
env['DELPHI_MCP_REMOTE_HOSTS'] = _host

srv = mc.Stdio(EXE, env, nombre='v217', cwd=CASA, t=120)
call = srv.call


def dproj(nombre):
    p = os.path.join(JAIL, nombre + '.dproj')
    open(p, 'w', encoding='utf-8').write('<Project/>')
    return p


def marcador_en_scratch():
    for raiz, _dirs, fichs in os.walk(SCRATCH):
        if MARCADOR in fichs:
            return True
    return False


def limpia_scratch():
    for n in os.listdir(SCRATCH):
        if n == '_espera':
            continue
        p = os.path.join(SCRATCH, n)
        if os.path.isdir(p):
            shutil.rmtree(p, ignore_errors=True)
        else:
            os.remove(p)


JOB = '20991231-235959999-deadbeef'  # id con la forma buena pero que este servidor no emitio
SIN_CAMPO = 'NOEXISTE_INOCUO.bin'  # lo que sobraria: un nombre que no existe


def manifiesto(d, nombre, remotedir=None, remotename=None, include=None):
    # un .deployproj como el que genera el servidor, con un campo cambiado
    open(os.path.join(d, nombre + '.deployproj'), 'w', encoding='utf-8').write(
        '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\n'
        '  <Import Condition="Exists(\'$(BDS)\\bin\\CodeGear.Deployment.targets\')" Project="$(BDS)\\bin\\CodeGear.Deployment.targets"/>\n'
        '  <ItemGroup>\n'
        '    <DeployFile Include="%s">\n'
        '      <RemoteDir>%s</RemoteDir>\n'
        '      <RemoteName>%s</RemoteName>\n'
        '      <Operation>1</Operation>\n'
        '      <Overwrite>True</Overwrite>\n'
        '    </DeployFile>\n'
        '  </ItemGroup>\n'
        '</Project>\n' % (include or 'x.txt', remotedir or (nombre + '\\'), remotename or 'x.txt'))

try:
    # P1: ';' en el nombre -> el trozo que sobra sube un fichero local de la casa; el arreglo lo niega
    limpia_scratch()
    djo = dproj('Fuga;' + MARCADOR)                      # ProjName = "Fuga;FUGA_INOCUA.txt"
    r = call('delphi_paserver', {'command': 'remote-run', 'name': PROF, 'project': djo, 'timeoutms': 3000}, t=60)
    check('P1 nombre con ";": NO sube un fichero local de la casa del servidor y lo niega (PAS-071). '
          'ROJO contra produccion: el marcador aparece en la scratch (fuga)',
          mc.es(r, 'SR_PACLIENT_NOMBRE_FMT') and not marcador_en_scratch(),
          '%s | fuga=%s' % (r[:200], marcador_en_scratch()))

    # P2: la coma parte el campo de --put/--get igual que el punto y coma
    limpia_scratch()
    djc = dproj('Coma,' + MARCADOR)
    r = call('delphi_paserver', {'command': 'remote-run', 'name': PROF, 'project': djc, 'timeoutms': 3000}, t=60)
    check('P2 nombre con ",": PAS-071 (paclient separa los campos de --put/--get por ","). ROJO: pasa',
          mc.es(r, 'SR_PACLIENT_NOMBRE_FMT'), r[:200])

    # P3: output pasa por la MISMA puerta; su --get y su --Remove tambien llevan el nombre
    r = call('delphi_paserver', {'command': 'output', 'name': PROF, 'project': djo, 'job': JOB}, t=60)
    check('P3 output con un nombre con ";": PAS-071 en la misma puerta (su --get/--Remove lo llevan). '
          'ROJO: pasa la puerta y llega a "job ajeno"', mc.es(r, 'SR_PACLIENT_NOMBRE_FMT'), r[:200])

    # P4: kill, la misma puerta
    r = call('delphi_paserver', {'command': 'kill', 'name': PROF, 'project': djo, 'job': JOB}, t=60)
    check('P4 kill con un nombre con ";": PAS-071 en la misma puerta. ROJO: pasa a "job ajeno"',
          mc.es(r, 'SR_PACLIENT_NOMBRE_FMT'), r[:200])

    # P5 control: un nombre limpio SIGUE llegando a paclient (el juez no sobre-niega)
    limpia_scratch()
    djl = dproj('Limpio')
    r = call('delphi_paserver', {'command': 'remote-run', 'name': PROF, 'project': djl, 'timeoutms': 5000}, t=60)
    check('P5 control: un nombre limpio no se niega y llega a paclient (hay jobId o se compuso el --put)',
          not mc.es(r, 'SR_PACLIENT_NOMBRE_FMT') and ('jobId' in r or os.path.isdir(os.path.join(SCRATCH, 'Limpio'))),
          r[:200])

    # P6: una variante del separador no pasa por no estar en una lista
    r = call('delphi_paserver', {'command': 'remote-run', 'name': PROF, 'timeoutms': 3000,
                                 'project': dproj('Ancho' + chr(0xff1b) + 'x')}, t=60)
    check('P6 un punto y coma de ancho completo: PAS-071 (lista blanca)', mc.es(r, 'SR_PACLIENT_NOMBRE_FMT'), r[:200])

    # P7 control: un nombre corriente, con acento, espacio, punto y guion
    r = call('delphi_paserver', {'command': 'remote-run', 'name': PROF, 'timeoutms': 5000,
                                 'project': dproj('Mi Gesti' + chr(0xf3) + 'n-2.1 (v2)')}, t=60)
    check('P7 control: acento, espacio, punto, guion y parentesis no se niegan',
          not mc.es(r, 'SR_PACLIENT_NOMBRE_FMT'), r[:200])

    # Los campos de un .deployproj escrito a mano (BUILD-066). ROJOS contra 4f07b8e: nadie los juzga
    dep = os.path.join(JAIL, 'Dep')
    call('delphi_create', {'kind': 'project-console', 'name': 'Dep', 'dir': dep})
    dep_proj = os.path.join(dep, 'Dep.dproj')
    open(os.path.join(dep, 'x.txt'), 'w').write('x')
    for etiqueta, campos in [
            ('D1 ";" en RemoteDir, sin desplegar antes (el manifiesto a mano aun no esta importado)',
             {'remotedir': 'Dep\\;' + SIN_CAMPO}),
            ('D2 ";" en RemoteName', {'remotename': 'x.txt;' + SIN_CAMPO}),
            ('D3 "," en RemoteDir', {'remotedir': 'Dep\\,' + SIN_CAMPO}),
            ('D4 ";" escapado para msbuild', {'remotedir': 'Dep\\%3B' + SIN_CAMPO}),
            ('D5 ";" como entidad XML', {'remotedir': 'Dep\\&#59;' + SIN_CAMPO}),
            ('D6 una macro que no se expande aqui', {'remotedir': '$(MiProp)\\'}),
            ('D7 "," en el Include', {'include': 'x,y.txt'})]:
        manifiesto(dep, 'Dep', **campos)
        r = call('delphi_build', {'project': dep_proj, 'platform': 'Win64', 'target': 'Deploy', 'profile': PROF}, t=300)
        check(etiqueta + ': BUILD-066', mc.es(r, 'SR_BUILD_CAMPO_DE_DESPLIEGUE_FMT'), r[:240])
    # lo mismo en un build que no despliega: el manifiesto ya esta importado
    manifiesto(dep, 'Dep', remotedir='Dep\\;' + SIN_CAMPO)
    r = call('delphi_build', {'project': dep_proj, 'platform': 'Win64'}, t=300)
    check('D8 ...y tambien en un build sin Deploy', mc.es(r, 'SR_BUILD_CAMPO_DE_DESPLIEGUE_FMT'), r[:240])
    # control: lo que escribe el IDE de verdad (medido en 62 manifiestos)
    manifiesto(dep, 'Dep', remotedir='$(PROJECTNAME).app\\..\\Contents\\', remotename='Default~ipad@2x.png')
    r = call('delphi_build', {'project': dep_proj, 'platform': 'Win64'}, t=300)
    check('D9 control: $(PROJECTNAME), .., ~ y @ no se niegan', not mc.es(r, 'SR_BUILD_CAMPO_DE_DESPLIEGUE_FMT'), r[:240])
    # ...pero $(PROJECTNAME) con un valor que el proyecto redefine mal, si
    texto = open(dep_proj, encoding='utf-8-sig').read()
    i = texto.index('<PropertyGroup')
    open(dep_proj, 'w', encoding='utf-8').write(
        texto[:i] + '<PropertyGroup><ProjectName>Dep;' + SIN_CAMPO + '</ProjectName></PropertyGroup>' + texto[i:])
    r = call('delphi_build', {'project': dep_proj, 'platform': 'Win64'}, t=300)
    check('D10 $(PROJECTNAME) con un ";" puesto por el proyecto: BUILD-066', mc.es(r, 'SR_BUILD_CAMPO_DE_DESPLIEGUE_FMT'), r[:240])
finally:
    srv.mata()

mc.borra(BASE)
mc.fin('V217 nombre de proyecto a paclient (PAS-071)')
