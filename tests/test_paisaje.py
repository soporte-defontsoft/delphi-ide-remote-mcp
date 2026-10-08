# -*- coding: utf-8 -*-
"""El paisaje, vigilado: cada FORMATO vive en UN sitio (su nombrador, su
lanzador) y no se compone a mano en otro (CLAUDE.md, "un solo nombrador" y
"buscar por formato, no por nombre de funcion").

Por que existe (David, 6-oct-2026): los revisores miran el DIFF, y las cinco
llamadas a paclient que test-connection, get-sdk y add-profile construian a
mano entraron en releases distintas, cada una sola y correcta: ninguna
revision las vio juntas, y vivieron muchas versiones. "Lo que nos falto fue
un revisor inicial del codigo previo al revisor": esta bateria es ese
revisor, y su primera pasada fue la auditoria. Corre en cada run_all: una
copia nueva cae el dia que entra.

Recorre las fuentes del grupo (src/, sin UnitTests: una prueba del nombrador
calcula lo esperado POR SU CUENTA, a proposito) sin comentarios, y para cada
regla busca su formato FUERA de su casa (fichero y funcion). Cada regla lleva
su MUTANTE dentro: una copia plantada en un fragmento de Pascal que el
mismo buscador tiene que cazar (si no la caza, la regla no mide nada).

Deuda declarada (listas negras): GitArgDenied (opciones libres),
ShellArgDenied (metacaracteres), HazardScan (DANGER_TASKS de MSBuild) y
BorradoDenegado (lugares protegidos tras su lista blanca de desechables).
La config local/worktree de Git y los hosts de todos sus remotos son listas blancas.

Uso:  python tests/test_paisaje.py
"""
import os, re, glob
import mcp_cliente as mc
from mcp_cliente import check

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(REPO, 'src')
# UnitTests y Pruebas (la bateria manual de src/Render): una prueba calcula lo
# esperado POR SU CUENTA, y la de los renderizadores compone su orden a mano
FUERA = ('__delphi-patch', '__history', '__recovery', 'Compiled', 'UnitTests', 'Pruebas')
LANZA = r'\b(?:RunCaptured(?:In|EnContenedor)?|RunDetached|CreateProcess[AW]?|ShellExecute\w*)\s*\('

# (nombre, formato, casas: [(fichero, funcion o '*' = todo el fichero)], por que)
REGLAS = [
    ('lanzar paclient', LANZA + r'.*(?i:pa_?client|\bA?Pc\b)',
     [('Lsp.RemoteRun.pas', 'Paclient')],
     'UN helper para todo lo que habla con un PAServer (1.16.0: cinco a mano)'),
    ('lanzar un programa', LANZA,
     [('Lsp.BuildRunner.pas', 'RunCapturedIn'), ('Lsp.BuildRunner.pas', 'RunCaptured'),
      ('Lsp.BuildRunner.pas', 'RunMsBuild'), ('Lsp.BuildRunner.pas', 'RunDetached'),
      ('Lsp.ProcessLaunch.pas', '*'), ('Lsp.RemoteRun.pas', 'Paclient'),
      ('Lsp.Styles.pas', 'CorreStyleConvert'), ('Mcp.Tools.Styles.pas', 'BuildStyles'),
      ('Lsp.TestRunner.pas', 'CorreEnContenedor'), ('Mcp.Tools.Adb.pas', 'RunAdb'),
      ('Mcp.Tools.Workspace.pas', 'GitCorre'), ('Lsp.FormRender.pas', 'CorreRender')],
     'cada programa externo se lanza desde UN sitio conocido; uno nuevo se revisa aqui'),
    ('lanzar el conversor de estilos', LANZA + r""".*'"' \+ A?Exe \+""",
     [('Lsp.Styles.pas', 'CorreStyleConvert')],
     'CorreStyleConvert (1.16.0: defaults y tobin componian la orden a mano)'),
    ('nombre de un .profile', r"\+\s*'\.profile'",
     [('Lsp.Discovery.pas', 'RutaDePerfil')], 'RutaDePerfil, y NombreDePerfil su inversa (1.16.0)'),
    ('nombre de un .sdk', r"\+\s*'\.sdk'",
     [('Lsp.Discovery.pas', 'NombreDeSdk')],
     'NombreDeSdk (fichero, clave del IDE, SDKName, sysroot: el mismo nombre; 1.16.0: 16 a mano)'),
    ('.sdk leido a mano', r"EndsWith\('\.sdk'\)",
     [('Lsp.Discovery.pas', 'NombreDeSdk'), ('Lsp.Discovery.pas', 'NombreSinSdk')],
     'NombreSinSdk es la inversa; "es un .sdk" se pregunta al nombrador'),
    ('__delphi-temp', r"'__delphi-temp",
     [('Lsp.Guard.pas', 'TempFolderName')], 'la casa del servidor tiene UN nombrador'),
    ('__delphi-patch', r"'__delphi-patch",
     [('Lsp.Patch.pas', '*')], 'BACKUP_SUB / TrashFolderName'),
    ("la forma 'srvX:'", r"'srv'",
     [('Lsp.Guard.pas', 'VirtualUnitOf'), ('Lsp.Guard.pas', 'EmpiezaPorUnidadVirtual')],
     'VirtualUnitOf la escribe y EmpiezaPorUnidadVirtual la prueba: nadie la compone ni la prueba a mano'),
    ('GetTempPath suelto', r'\bGetTempPath\w*\s*\(', [],
     'lo temporal del servidor va en su casa (ServerTempDir), nunca en el %TEMP% del sistema'),
    ('el .dproj de un .dpr', r"(?:ChangeExtension|ChangeFileExt)\s*\([^;]*'\.dproj'\)",
     [('Lsp.Dproj.pas', 'DprojDe')],
     'DprojDe (1.17.0: diez a mano, y delphi_build rechazaba el .dpr que delphi_config resolvia)'),
    ('el .dproj compuesto a mano', r"\+\s*'\.dproj'", [],
     'DprojDe tambien para el que se crea (revision de la 1.17.0: Scaffold y ResolveProjectPair lo '
     'componian con + \'.dproj\')'),
    ('la unidad de un form', r"(?:ChangeExtension|ChangeFileExt)\s*\([^;]*'\.pas'\)",
     [('Lsp.DesignerForma.pas', 'UnidadDeDesigner')],
     'UnidadDeDesigner (revision de la 1.17.0: cuatro a mano, uno en el renderizador)'),
    ('la forma de un designer', r'\bTestStreamFormat\s*\(', [],
     'DesignerShapeOf / DesignerAFlujo (Lsp.DesignerForma): TestStreamFormat llama binario al texto '
     'UTF-16 y no salta la cabecera del recurso (preview de un .dfm binario, revision de la 1.17.0)'),
    ('leer la linea de objeto de un form', r'object\|inherited\|inline',
     [('Lsp.DesignerForma.pas', 'LineaDeObjeto')],
     'LineaDeObjeto (1.12.0: seis regex; la septima, la del renderizador, en la revision de la 1.17.0)'),
    ('el literal de cadena de un form a mano', r"\w = '''\s*\+|SetProp\([^;]*'''", [],
     'TrozosDeLiteral / LineasDePropiedad (revision de la 1.17.0: el StyleName de delphi_styles se '
     'escribia entre comillas a mano, sin #N ni trozos)'),
    ('el exe de un renderizador de forms', r"'DelphiFormRender",
     [('Lsp.FormRender.pas', 'FormRenderExe')],
     'FormRenderExe (1.17.0, delphi_designer preview): el nombre del ayudante se compone en UN sitio'),
    ('la orden del renderizador de forms', r"'[^']*--(?:path|state|component|nonvisual|root|style|bds)\b",
     [('Lsp.FormRender.pas', 'ComponeOrdenDeRender'), ('FormRender.Comun.pas', 'ParseaArgumentos'),
      ('FormRender.Textos.pas', '*')],
     'ComponeOrdenDeRender la escribe y ParseaArgumentos del ayudante la lee (1.17.0)'),
    ('la linea de objeto de un form', r"'(?:object|inherited|inline) '\s*\+",
     [('Lsp.DesignerForma.pas', 'ComponeLineaDeObjeto')],
     'ComponeLineaDeObjeto la escribe y LineaDeObjeto la lee (1.17.0: el insert de delphi_designer; '
     'las plantillas de Lsp.Scaffold la componian a mano)'),
    ('un componente por su ruta en el renderizador', r'\bFindNestedComponent\s*\(',
     [('FormRender.Comun.pas', 'ComponenteDeRuta')],
     'ComponenteDeRuta: UN lector de Marco1.LblAviso, y de la raiz delante, para component= y state= '
     '(segunda revision de la 1.17.0: el estado de un frame suelto con su nombre delante no llegaba)'),
    ('un flotante de un form', r"\.0{18}'|ffFixed\s*,\s*16\s*,\s*18",
     [('Lsp.DesignerBin.pas', 'FlotanteDeForm')],
     'FlotanteDeForm: el numero de coma flotante como lo escribe el IDE en UN sitio (1.17.0: insert, '
     'set y las plantillas FMX)'),
]


def fuentes():
    for f in glob.glob(os.path.join(SRC, '**', '*.pas'), recursive=True) + \
            glob.glob(os.path.join(SRC, '**', '*.dpr'), recursive=True):
        if not any(('\\%s\\' % x) in f or ('/%s/' % x) in f for x in FUERA):
            yield f


def codigo(texto):
    """Las lineas sin comentarios (// { } (* *)) y sin Lsp.Texts aparte; los
    literales se quedan: los formatos SON literales."""
    out, en_llave, en_paren = [], False, False
    for linea in texto.split('\n'):
        res, i, en_cad = [], 0, False
        while i < len(linea):
            c = linea[i]
            if en_llave:
                if c == '}': en_llave = False
                i += 1; continue
            if en_paren:
                if linea.startswith('*)', i): en_paren = False; i += 2; continue
                i += 1; continue
            if c == "'":
                en_cad = not en_cad; res.append(c); i += 1; continue
            if not en_cad:
                if linea.startswith('//', i): break
                if c == '{': en_llave = True; i += 1; continue
                if linea.startswith('(*', i): en_paren = True; i += 2; continue
            res.append(c); i += 1
        out.append(''.join(res))
    return out


CABECERA = re.compile(r'^(?:class\s+)?(?:function|procedure|constructor|destructor)\s+([\w.]+)', re.I)


def funcion_de(lineas, n):
    """La rutina que contiene la linea n: la ultima cabecera de la columna 0."""
    for k in range(n, -1, -1):
        m = CABECERA.match(lineas[k])
        if m:
            return m.group(1).split('.')[-1]
    return ''


def fuera_de_casa(regla, ficheros_texto):
    nombre, formato, casas, _ = regla
    rx = re.compile(formato)
    malos = []
    for f, texto in ficheros_texto:
        if os.path.basename(f) == 'Lsp.Texts.pas':
            continue
        lineas = codigo(texto)
        for n, l in enumerate(lineas):
            # una cabecera (la declaracion de un lanzador) no es una llamada
            if rx.search(l) and not CABECERA.match(l.strip()):
                fn = funcion_de(lineas, n)
                base = os.path.basename(f)
                if not any(base == cf and (cfn == '*' or cfn.lower() == fn.lower()) for cf, cfn in casas):
                    malos.append('%s:%d (%s) %s' % (os.path.relpath(f, REPO), n + 1, fn or '-', l.strip()[:90]))
    return malos


TEXTOS = [(f, open(f, encoding='utf-8-sig', errors='replace').read()) for f in fuentes()]
check('las fuentes del grupo se leen (83 unidades el 6-oct-2026: al menos 70)', len(TEXTOS) >= 70, len(TEXTOS))

# el MUTANTE de cada regla: una copia plantada, fuera de su casa, que la
# regla tiene que cazar (y un comentario con el formato, que NO)
PLANTADO = {
    'lanzar paclient': "  Output := RunCaptured('\"' + PaClient + '\" --timeout=20 \"' + P + '\"', 45000, E);",
    'lanzar un programa': "  Out := RunCapturedIn('\"' + Exe + '\" algo', Dir, 1000, C);",
    'lanzar el conversor de estilos': "  Out := RunCapturedIn('\"' + Exe + '\" tobin', Dir, 1000, C);",
    'nombre de un .profile': "  F := TPath.Combine(Dir, Nombre + '.profile');",
    'nombre de un .sdk': "  F := TPath.Combine(Dir, Nombre + '.sdk');",
    '.sdk leido a mano': "  if not S.ToLower.EndsWith('.sdk') then S := S;",
    '__delphi-temp': "  D := TPath.Combine(Raiz, '__delphi-temp');",
    '__delphi-patch': "  D := TPath.Combine(Raiz, '__delphi-patch');",
    "la forma 'srvX:'": "  U := 'srv' + LowerCase(Letra) + ':';",
    'GetTempPath suelto': "  T := TPath.GetTempPath();",
    'el .dproj de un .dpr': "  D := ChangeFileExt(P, '.dproj');",
    'el .dproj compuesto a mano': "  D := Stem + '.dproj';",
    'la unidad de un form': "  P := ChangeFileExt(Dfm, '.pas');",
    'la forma de un designer': "  if TestStreamFormat(S) = sofBinary then",
    'leer la linea de objeto de un form': r"  M := TRegEx.Match(L, '^\s*(object|inherited|inline)\s+(\w+)');",
    'el literal de cadena de un form a mano': "  T := Ind + 'Caption = ''' + Nombre + '''';",
    'el exe de un renderizador de forms': "  E := ServerDir('DelphiFormRenderVcl.exe');",
    'la orden del renderizador de forms': "  O := '\"' + Exe + '\" --path \"' + P + '\"';",
    'la linea de objeto de un form': "  L := 'object ' + Nombre + ': ' + Clase;",
    'un componente por su ruta en el renderizador': "  C := FindNestedComponent(ARaiz, ANombre);",
    'un flotante de un form': "  V := IntToStr(N) + '.000000000000000000';",
}
for regla in REGLAS:
    nombre = regla[0]
    planta = ('unit Plantado;\nimplementation\nprocedure CopiaAMano;\nbegin\n  // ' + PLANTADO[nombre] +
              '\n' + PLANTADO[nombre] + '\nend;\nend.\n')
    cazados = fuera_de_casa(regla, [('Plantado.pas', planta)])
    check('mutante "%s": la copia plantada se caza (y el comentario no)' % nombre,
          len(cazados) == 1 and ':6 ' in cazados[0], cazados)

for regla in REGLAS:
    malos = fuera_de_casa(regla, TEXTOS)
    check('"%s" solo en su casa - %s' % (regla[0], regla[3]), not malos, '\n      ' + '\n      '.join(malos))

# Toda puerta de este censo dice LISTA NEGRA en su cabecera. Este control
# mide la declaracion, NO que una lista negra sea completa.
LISTAS_NEGRAS = [
    ('Lsp.Guard.pas','GitArgDenied'),
    ('Lsp.Guard.pas','ShellArgDenied'),
    ('Lsp.Guard.pas','BorradoDenegado'),
    ('Lsp.Dproj.pas','HazardScan'),
]
def negra_declarada(texto,funcion):
    for m in re.finditer(r'(?m)^function '+re.escape(funcion)+r'\b',texto):
        antes=texto[:m.start()].rstrip()
        inicio=antes.rfind('{')
        if inicio>=0 and antes.endswith('}') and 'LISTA NEGRA' in antes[inicio:]:
            return True
    return False
for fichero,funcion in LISTAS_NEGRAS:
    texto=next(t for f,t in TEXTOS if os.path.basename(f)==fichero)
    check('deuda declarada '+fichero+' '+funcion,negra_declarada(texto,funcion))
    check('mutante cabecera sin declarar '+funcion,
          not negra_declarada(texto.replace('LISTA NEGRA','sin declarar'),funcion))
mc.fin('paisaje battery')
