# -*- coding: utf-8 -*-
"""La teoria del revisor del 2s, MEDIDA el 14-oct (1.18.3): la puerta de
delphi_build juzgaba cada carpeta de salida ENTERA (EscrituraDenegada) y nada
mas.

  B1 un P.exe que ReadOnlyPaths nombra DENTRO de la carpeta de salida: el
     build lo reescribia (el nombre lo pone el proyecto, que escribe el
     agente) -> BUILD-029 y el P.exe intacto (ROJO en produccion)
  B2 un .dproj con BRCC_OutputDir FUERA de las raices y la version puesta: el
     build escribia alli su P.res, FUERA DEL WORKSPACE -> BUILD-029 y nada
     fuera (ROJO en produccion)
  B3 el .res de version junto al .dproj, en ReadOnlyPaths, con la version
     puesta: se reescribia -> BUILD-029 y el .res intacto (ROJO en produccion)
  B4 control: el mismo proyecto sin nada protegido compila

Uso:  python tests/test_build_salida_protegida_1183.py [ruta-a-DelphiLspMcp.exe]
"""
import hashlib, os, re
import mcp_cliente as mc
from mcp_cliente import check

BASE = mc.carpeta('build_salida_protegida_1183')
JAIL = os.path.join(BASE, 'jail')
FUERA = os.path.join(BASE, 'fuera')
os.makedirs(JAIL)
os.makedirs(FUERA)
EXE = mc.copia_exe(os.path.join(BASE, 'srv'))


def h(p):
    return hashlib.sha256(open(p, 'rb').read()).hexdigest() if os.path.isfile(p) else None


def lanza(solo=''):
    env = {'DELPHI_MCP_ROOTS': JAIL}
    if solo:
        env['DELPHI_MCP_READONLY_PATHS'] = solo
    return mc.Stdio(EXE, mc.entorno(env), nombre='build-protegida', t=600)


def con_version(dproj, extra=''):
    """La informacion de version en el grupo Base del .dproj (como la escribe
    el IDE al marcar "Include version information"), y lo que se anada."""
    x = open(dproj, encoding='utf-8-sig').read()
    m = re.search(r"<PropertyGroup Condition=\"'\$\(Base\)'!=''\">", x)
    x = x[:m.end()] + ('<VerInfo_IncludeVerInfo>true</VerInfo_IncludeVerInfo>'
                       '<VerInfo_Keys>FileVersion=1.0.0.0;ProductVersion=1.0.0.0</VerInfo_Keys>') + extra + x[m.end():]
    open(dproj, 'w', encoding='utf-8', newline='\r\n').write(x)


def proyecto(s, nombre):
    d = os.path.join(JAIL, nombre)
    s.call('delphi_create', {'kind': 'project-console', 'name': nombre, 'dir': d}, t=120)
    return d, os.path.join(d, nombre + '.dpr'), os.path.join(d, nombre + '.dproj')


s = lanza()
try:
    dA, dprA, dprojA = proyecto(s, 'PA')
    r = s.call('delphi_build', {'project': dprA}, t=600)
    exeA = os.path.join(dA, 'Win64', 'Debug', 'PA.exe')
    check('B4 control: el proyecto sin nada protegido compila', '"success":true' in r and os.path.isfile(exeA),
          r[:300])
    dB, dprB, dprojB = proyecto(s, 'PB')
    con_version(dprojB, '<BRCC_OutputDir>%s\\</BRCC_OutputDir>' % FUERA)
    r = s.call('delphi_build', {'project': dprB}, t=600)
    check('B2 BRCC_OutputDir FUERA de las raices: BUILD-029 y nada escrito fuera',
          'BUILD-029' in r and 'BRCC_OutputDir' in r and os.listdir(FUERA) == [],
          (r[:300], os.listdir(FUERA)))
    dC, dprC, dprojC = proyecto(s, 'PC')
    con_version(dprojC)
    s.call('delphi_build', {'project': dprC}, t=600)
    resC = os.path.join(dC, 'PC.res')
finally:
    s.cierra()

# B1 y B3: con lo que el primer build dejo, protegido
antes = {p: h(p) for p in (exeA, resC)}
for d, n in ((dA, 'PA'), (dC, 'PC')):
    dpr = os.path.join(d, n + '.dpr')
    t = open(dpr, encoding='utf-8-sig').read().replace("Writeln('%s running');" % n, "Writeln('%s running 2');" % n)
    open(dpr, 'w', encoding='utf-8-sig', newline='').write(t)
# (la version cambia: el .res de version se rehace)
x = open(dprojC, encoding='utf-8-sig').read().replace('FileVersion=1.0.0.0', 'FileVersion=2.0.0.0')
open(dprojC, 'w', encoding='utf-8', newline='\r\n').write(x)
s = lanza(';'.join([exeA, resC]))
try:
    r = s.call('delphi_build', {'project': dprA}, t=600)
    check('B1 un P.exe de ReadOnlyPaths dentro de la carpeta de salida: BUILD-029 y el exe intacto',
          'BUILD-029' in r and h(exeA) == antes[exeA], (r[:300], h(exeA) == antes[exeA]))
    r = s.call('delphi_build', {'project': dprC}, t=600)
    check('B3 el .res de version junto al .dproj, de solo lectura: BUILD-029 y el .res intacto',
          'BUILD-029' in r and h(resC) == antes[resC] and antes[resC] is not None,
          (r[:300], antes[resC] is not None, h(resC) == antes[resC]))
finally:
    s.cierra()

mc.borra(BASE)
mc.fin('salida protegida del build 1183')
