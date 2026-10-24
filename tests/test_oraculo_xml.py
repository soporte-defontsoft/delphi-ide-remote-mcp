# -*- coding: utf-8 -*-
"""E2E battery for 1.20.1 - the project XML reader against the judge the IDE
loads. The IDE reads a .dproj with Xml.XMLDoc (xmlrtl370) over MSXML6
(measured on bds.exe on 17-oct-2026); the server keeps its own scanner, which
writes in place (no DOM rewrites a project file byte for byte), and MSXML is
its oracle. tests/oraculo-xml is a console program that compiles the
server's OWN reader (Lsp.Dproj and its decoder, by a relative search path,
no copy) next to MSXML and compares, for every project file of a corpus,
every element in document order: its attributes and, for a leaf, its value.

  X1  the oracle builds (delphi_build: the server's own tool)
  X2  the planted file - nesting of the same name, a CDATA with a '<', an
      element inside a comment, entities, an attribute with a line break and
      a tab, single quotes, an empty element, mixed content with a comment and
      a processing instruction - is read the same by both
  X3  MUTANT: with --crudo (the reader of before 17-oct: the text as written,
      not decoded) the same file DISAGREES - otherwise the oracle measures
      nothing
  X4  the corpus: the installation's Samples, ObjRepos, source and bin (the
      .defaultsdkpaths), the IDE's .sdk files, the repo, plus ORACULO_EXTRA
      (folders separated by ;) - every file read by the judge
  X5  0 discrepancies over the corpus

Measured on 17-oct-2026: the reader of 7a3733d disagreed with MSXML in 3.537
of 4.084 files (an element closed at the first closing of its name, a CDATA
read with its <![CDATA[ in front); the core of 1.20.1, in none. And the
planted file found what no file of the corpus had: MSXML6 keeps a tab or a
line break written inside an attribute (only CRLF becomes LF), with
preserveWhiteSpace and without it, though XML says they become blanks - the
reader did what XML says, and now does what the judge does.

Usage:  python tests/test_oraculo_xml.py [path-to-DelphiLspMcp.exe]
"""
import os, re, json, subprocess
import mcp_cliente as mc
from mcp_cliente import check

REPO = mc.REPO
ORACULO = os.path.join(REPO, 'tests', 'oraculo-xml', 'OraculoXml.dproj')
BASE = mc.carpeta('oraculo-xml')
EXE = mc.copia_exe(BASE)
srv = mc.Stdio(EXE, mc.entorno({'DELPHI_MCP_ROOTS': REPO}), nombre='oraculo', t=600)
call = srv.call

ok, errores = mc.build_ok(call, ORACULO)
check('X1 el oraculo compila (delphi_build)', ok, errores)
BIN = os.path.join(os.path.dirname(ORACULO), 'Win64', 'Debug', 'OraculoXml.exe')

# donde esta la instalacion: lo dice el servidor, no se supone
activa = mc.instalacion_activa(call)
RAIZ = mc.raiz_de_instalacion(activa)
VERSION = activa.get('version', '')
SAMPLES = os.path.join(mc.variable_de_rsvars(call, 'BDSCOMMONDIR'), 'Samples')
srv.cierra()


def corre(carpetas, crudo=False):
    """La salida del oraculo y su RESUMEN (ficheros, leidos, discrepancias)."""
    args = [BIN] + (['--crudo'] if crudo else []) + carpetas
    out = subprocess.run(args, capture_output=True, text=True, encoding='utf-8', errors='replace',
                         timeout=1800).stdout
    m = re.search(r'RESUMEN ficheros=(\d+) leidos=(\d+) discrepancias=(\d+)', out)
    return out, (tuple(int(x) for x in m.groups()) if m else None)


PLANTADO = os.path.join(BASE, 'plantado')
os.makedirs(PLANTADO, exist_ok=True)
with open(os.path.join(PLANTADO, 'Plantado.dproj'), 'w', encoding='utf-8', newline='') as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\r\n'
            '<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\r\n'
            '    <!-- <PropertyGroup><DCC_ExeOutput>oculto</DCC_ExeOutput></PropertyGroup> -->\r\n'
            '    <PropertyGroup\r\n'
            '        Condition="\'$(Base)\'!=\'\'">\r\n'
            '        <DCC_ExeOutput>.\\R&amp;D&#59;x</DCC_ExeOutput>\r\n'
            '        <PostBuildEvent><![CDATA[copy "a" "b"\r\necho <hecho>]]></PostBuildEvent>\r\n'
            '        <Vacia/>\r\n'
            '        <Mixta>uno<!-- dos -->tres<?pi algo?></Mixta>\r\n'
            '    </PropertyGroup>\r\n'
            '    <ItemGroup Condition=\'"$(Platform)"=="Win64"\'>\r\n'
            '        <DeployFile Include=\'lib&amp;uno.so\' Condition="a\r\n\tb"><RemoteDir>x\\</RemoteDir></DeployFile>\r\n'
            '    </ItemGroup>\r\n'
            '    <ProjectExtensions>\r\n'
            '        <BorlandProject>\r\n'
            '            <VersionInfo>\r\n'
            '                <VersionInfo Name="MajorVer">1</VersionInfo>\r\n'
            '            </VersionInfo>\r\n'
            '        </BorlandProject>\r\n'
            '    </ProjectExtensions>\r\n'
            '</Project>\r\n')

if ok:
    out, r = corre([PLANTADO])
    check('X2 el fichero plantado: el juez y el lector dicen lo mismo', r == (1, 1, 0), out[-1500:])
    out, r = corre([PLANTADO], crudo=True)
    check('X3 mutante --crudo (el lector sin decodificar): el plantado discrepa', r == (1, 1, 1), out[-1500:])

    carpetas = [SAMPLES] + \
        [os.path.join(RAIZ, x) for x in ('ObjRepos', 'source', 'bin')] + \
        [os.path.join(os.environ.get('APPDATA', ''), 'Embarcadero', 'BDS', VERSION), REPO] + \
        [x for x in os.environ.get('ORACULO_EXTRA', '').split(';') if x.strip()]
    carpetas = [c for c in carpetas if os.path.isdir(c)]
    out, r = corre(carpetas)
    no_lee = [l for l in out.splitlines() if l.startswith('NO LEE')]
    discrepa = [l for l in out.splitlines() if l.startswith('DISCREPA')]
    print('corpus: %s -> %s' % ('; '.join(carpetas), r))
    # 296 .dproj trae solo la carpeta Samples de la 37.0
    check('X4 el corpus se lee entero por el juez (al menos 300 ficheros, ninguno sin leer)',
          r is not None and r[0] >= 300 and r[0] == r[1] and not no_lee, (r, no_lee[:5]))
    check('X5 0 discrepancias entre el lector y MSXML en el corpus', r is not None and r[2] == 0,
          discrepa[:10])
mc.borra(BASE)
mc.fin('oraculo-xml battery')
