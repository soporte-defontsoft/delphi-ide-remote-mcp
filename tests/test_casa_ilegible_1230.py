# -*- coding: utf-8 -*-
r"""V9 (1.23): una carpeta que un test deja NACIDA CERRADA -la DACL vacia
protegida va en el propio CreateDirectory (lpSecurityAttributes), que no
necesita WRITE_DAC- se quedaba imborrable en la casa del servidor: ni el barrido
de delphi_test ni la purga del arranque la quitaban, porque el recorredor da
GUARD-040 al no poder listarla. Ahora el barrido de la CASA (ReclamaArbol, en
TestRunner y en la purga de ServerTempDir) la reclama como dueno -DACL vacia NO
protegida, hereda de la casa- y la borra. Solo en la casa del servidor, nunca
cruzando un enlace, y NO en BorraArbol general (la jaula del agente sigue
negando GUARD-040). ROJO contra r1222ce (la carpeta se planta). argv[1] = exe."""
import json
import os
import mcp_cliente as mc

BASE = mc.carpeta('casa-ilegible')
SRV = os.path.join(BASE, 'srv')
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
EXE = mc.copia_exe(SRV)
TEMP_SRV = os.path.join(SRV, mc.TEMPORALES)
# un test que crea 'cerrada' con una DACL vacia protegida en la propia creacion
PROG = r'''program CerradaTest;
{$APPTYPE CONSOLE}
uses Winapi.Windows, System.SysUtils;
var
  SD: TSecurityDescriptor;
  Acl: array[0 .. 63] of Byte;
  SA: TSecurityAttributes;
begin
  InitializeSecurityDescriptor(@SD, SECURITY_DESCRIPTOR_REVISION);
  InitializeAcl(PACL(@Acl)^, SizeOf(Acl), 2); // ACL_REVISION, 0 ACEs = niega a todos
  SetSecurityDescriptorDacl(@SD, True, PACL(@Acl), False);
  SetSecurityDescriptorControl(@SD, SE_DACL_PROTECTED, SE_DACL_PROTECTED);
  SA.nLength := SizeOf(SA);
  SA.lpSecurityDescriptor := @SD;
  SA.bInheritHandle := False;
  if CreateDirectory('cerrada', @SA) then
    Writeln('CERRADA ok')
  else
    Writeln('CERRADA error ', GetLastError);
  Writeln('PASS cerrada');
end.'''

ENT = mc.entorno({'DELPHI_MCP_ROOTS': JAIL, 'DELPHI_MCP_ALLOW_TESTS': '1'})


def copias():
    return [d for d in os.listdir(TEMP_SRV) if d.startswith('test-')] if os.path.isdir(TEMP_SRV) else []


try:
    s = mc.Stdio(EXE, ENT, nombre='casa-ilegible', t=600)
    try:
        P = os.path.join(JAIL, 'CerradaTest')
        r = s.call('delphi_create', {'kind': 'project-console', 'name': 'CerradaTest', 'dir': P})
        mc.check('fixture de test creada', mc.abre(r, 'SK_CREATE_CREADO_PROYECTO_FMT'), r[:200])
        open(os.path.join(P, 'CerradaTest.dpr'), 'w', encoding='utf-8-sig', newline='\r\n').write(PROG)
        r = s.call('delphi_test', {'command': 'run', 'project': os.path.join(P, 'CerradaTest.dproj')}, 600)
        mc.check('el test corre (crea la carpeta nacida cerrada)',
                 mc.como_json(r).get('result') == 'pass', (mc.como_json(r).get('outputTail') or r)[:300])
        # el barrido de delphi_test (ReclamaArbol + BorraArbol) la quito: casa limpia
        mc.check('la carpeta nacida cerrada NO se queda en la casa tras el run (rojo contra r1222ce)',
                 copias() == [], 'copias: %r' % copias())
    finally:
        s.cierra()
    # ...y la purga del arranque tampoco la dejaria (segundo barrido de la casa)
    s2 = mc.Stdio(EXE, ENT, nombre='casa-ilegible-2', t=600)
    try:
        s2.call('delphi_workspace', {})
    finally:
        s2.cierra()
    mc.check('tras reiniciar (la purga de ServerTempDir) la casa sigue limpia',
             copias() == [], 'copias: %r' % copias())
finally:
    # por si una version SIN el arreglo dejo la carpeta cerrada: recuperarla por
    # el dueno antes de borrar, para no dejar basura imborrable en la maquina
    import subprocess
    for c in copias():
        subprocess.run(['icacls', os.path.join(TEMP_SRV, c, 'cerrada'), '/reset'],
                       capture_output=True, text=True)
    mc.borra(BASE)
mc.fin('la casa del servidor recupera y borra una carpeta nacida cerrada (V9)')
