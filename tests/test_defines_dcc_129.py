# -*- coding: utf-8 -*-
"""1.29 (EH10 del revisor del paisaje): los simbolos que el compilador define siempre, en la tabla del
evaluador de ramas (Lsp.Preproceso.SimbolosDeDelphi, la que usa el generador de las tablas de clases para los
IFDEF de los fuentes instalados), son una LISTA que imita a dcc: aqui se le pregunta a dcc. Un programa con un
{$IFDEF X}{$MESSAGE WARN 'DEF=X'}{$ENDIF} por simbolo, compilado en Win32 y en Win64, dice cuales define; la
tabla del fuente tiene que decir lo mismo (sin lo que pone el PROYECTO: CONSOLE de una consola, DEBUG de su
DCC_Define). Medido el 7-nov-2026 con dcc 37.0: faltaban CPU386 (Win32), WEAKREF y WEAKINTFREF.

  D1 Win32: lo que define dcc = la tabla (siempre + Win32). ROJO contra 166bea8b (CPU386, WEAKREF, WEAKINTFREF)
  D2 Win64: lo que define dcc = la tabla (siempre + Win64). ROJO contra 166bea8b (WEAKREF, WEAKINTFREF)
  D3 el VER<n> que define dcc es el que la tabla deriva de CompilerVersion (37.0 -> VER370)

Uso:  python tests/test_defines_dcc_129.py [ruta-a-DelphiLspMcp.exe] [ruta-a-Lsp.Preproceso.pas]
"""
import os
import re
import sys
import mcp_cliente as mc
from mcp_cliente import check

exe_src = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else None
FUENTE = sys.argv[2] if len(sys.argv) > 2 else os.path.join(mc.REPO, 'src', 'Server', 'Lsp.Preproceso.pas')

# los que dcc PODRIA definir (los predefinidos de la documentacion de Delphi y los de otras plataformas), mas
# los de la tabla: lo que dcc defina de aqui y la tabla no tenga sale como diferencia
CANDIDATOS = ['DCC', 'CONDITIONALEXPRESSIONS', 'NATIVECODE', 'UNICODE', 'MSWINDOWS', 'ASSEMBLER', 'WIN32', 'WIN64',
              'CPUX86', 'CPUX64', 'CPU386', 'CPU32BITS', 'CPU64BITS', 'UNDERSCOREIMPORTNAME', 'ALIGN_STACK', 'PIC',
              'POSIX', 'POSIX32', 'POSIX64', 'LINUX', 'LINUX32', 'LINUX64', 'MACOS', 'MACOS32', 'MACOS64', 'OSX',
              'OSX32', 'OSX64', 'ANDROID', 'ANDROID32', 'ANDROID64', 'IOS', 'IOS32', 'IOS64', 'CPUARM', 'CPUARM32',
              'CPUARM64', 'EXTERNALLINKER', 'ELF', 'WEAKREF', 'WEAKINSTREF', 'WEAKINTFREF', 'AUTOREFCOUNT', 'NEXTGEN',
              'PC_MAPPED_EXCEPTIONS', 'BCB', 'ARM_NO_VFP_USE', 'LLVM', 'WINDOWS', 'UNIX', 'CPU64', 'CPU32',
              'FRAMEWORK_VCL', 'FRAMEWORK_FMX', 'GENERICS', 'INLINE', 'WIN32ORWIN64', 'CPUX64_WIN64']
DEL_PROYECTO = {'CONSOLE', 'DEBUG', 'RELEASE'}


def lista(texto, ancla):
    m = re.search(re.escape(ancla) + r"\s*(\[[^\]]*\])", texto, re.S)
    return set(re.findall(r"'(\w+)'", m.group(1))) if m else set()


tabla = open(FUENTE, encoding='utf-8-sig').read()
cuerpo = tabla[tabla.index('function SimbolosDeDelphi', tabla.index('\nimplementation')):]
SIEMPRE = lista(cuerpo, "for var S in")
m64 = re.search(r"SameText\(APlataforma, 'Win64'\).*?for var S in\s*(\[[^\]]*\])", cuerpo, re.S)
W64 = set(re.findall(r"'(\w+)'", m64.group(1))) if m64 else set()
m32 = re.search(r"else\s*begin\s*for var S in\s*(\[[^\]]*\])", cuerpo, re.S)
W32 = set(re.findall(r"'(\w+)'", m32.group(1))) if m32 else set()
check('preparacion: la tabla se lee del fuente (siempre, Win64, Win32)', SIEMPRE and W64 and W32,
      (SIEMPRE, W64, W32))

BASE = mc.carpeta('defines_dcc_129')
EXE = mc.copia_exe(os.path.join(BASE, 'srv'), src=exe_src)
JAIL = os.path.join(BASE, 'jail')
os.makedirs(JAIL)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': JAIL}), nombre='defines', t=300)
try:
    P = os.path.join(JAIL, 'Defs')
    srv.call('delphi_create', {'kind': 'project-console', 'name': 'Defs', 'dir': P})
    todos = sorted(set(CANDIDATOS) | SIEMPRE | W64 | W32 | {'VER370', 'VER360', 'VER380'})
    with open(os.path.join(P, 'Defs.dpr'), 'w', encoding='utf-8-sig', newline='\r\n') as f:
        f.write('program Defs;\n\n{$APPTYPE CONSOLE}\n\n' +
                ''.join("{$IFDEF %s}{$MESSAGE WARN 'DEF=%s'}{$ENDIF}\n" % (s, s) for s in todos) +
                '\nbegin\nend.\n')

    def define(plat):
        r = srv.call('delphi_build', {'project': os.path.join(P, 'Defs.dproj'), 'platform': plat,
                                      'verbosity': 'normal'}, 300)
        j = mc.como_json(r) or {}
        return {m.group(1) for w in j.get('warnings') or [] for m in [re.search(r'DEF=(\w+)', w)] if m}, r

    for clave, plat, propios in (('D1', 'Win32', W32), ('D2', 'Win64', W64)):
        dcc, r = define(plat)
        dcc_sin = {s for s in dcc if s not in DEL_PROYECTO and not s.startswith('VER')}
        tabla_p = SIEMPRE | propios
        check('%s %s: lo que define dcc = la tabla de SimbolosDeDelphi' % (clave, plat), dcc_sin == tabla_p,
              'dcc y no la tabla: %s | la tabla y no dcc: %s | %s' % (sorted(dcc_sin - tabla_p),
                                                                       sorted(tabla_p - dcc_sin), r[:160]))
        if plat == 'Win64':
            check('D3 el VER que define dcc es VER370, el que la tabla deriva de CompilerVersion 37.0',
                  {s for s in dcc if s.startswith('VER')} == {'VER370'}, sorted(dcc))
finally:
    srv.cierra()
    mc.borra(BASE)
mc.fin('los simbolos predefinidos de dcc frente a la tabla (1.29)')
