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
      ('Mcp.Tools.Git.pas', 'GitCorre'), ('Lsp.FormRender.pas', 'CorreRender')],
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
     [('Lsp.Casa.pas', 'TempFolderName')], 'la casa del servidor tiene UN nombrador'),
    ('__delphi-patch', r"'__delphi-patch",
     [('Lsp.Casa.pas', '*')], 'BACKUP_SUB / TrashFolderName (Lsp.Casa desde el 8-oct-2026)'),
    ('la extension de la marca de dueno', r"'\.by'",
     [('Lsp.Casa.pas', '*')],
     'MARCA_DUENO_EXT: MarcaDeDueno la escribe, CopiaDeLaMarca la deshace y EsMarcaDeDueno la '
     'reconoce, los tres en Lsp.Casa con su formato (David, 8-oct-2026: viajan juntos o ninguno)'),
    ("la forma 'srvX:'", r"'srv'",
     [('Lsp.Mascara.pas', 'VirtualUnitOf'), ('Lsp.Mascara.pas', 'EmpiezaPorUnidadVirtual')],
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
    ('decidir la codificacion de unos bytes',
     r'\bGetBufferEncoding\b|\$FF\b[^;]*\$FE\b|\$FE\b[^;]*\$FF\b|\$EF\b[^;]*\$BB\b|\$BB\b[^;]*\$BF\b',
     [('Lsp.Patch.pas', 'DetectEnc'), ('Lsp.Codificacion.pas', 'BomUtf8En'),
      ('Lsp.Codificacion.pas', 'EncodeText'),
      # deuda declarada (2.1g de la 1.18.0): dos detectores sueltos; solo puede encoger
      ('Lsp.DesignerForma.pas', 'DesignerAFlujo'), ('Lsp.Docs.pas', 'KindDeAyuda')],
     'EL detector (DetectEnc, en Lsp.Patch) y el BOM de los codecs (BomUtf8En lo lee, EncodeText lo '
     'escribe): nadie mas mira unos bytes para decidir que son (24-sep-2026: dos detectores; 1.18.0: '
     'los codecs salen a Lsp.Codificacion y la decision se queda en Patch)'),
    ('UTF-8 estricto preguntado a mano', r'\bValidUtf8\s*\(',
     [('Lsp.Patch.pas', 'DetectEnc'), ('Lsp.Patch.pas', 'ExecutePatch')],
     'ValidUtf8 lo preguntan el detector y la auditoria del cuerpo de un utf8-bom: otro que lo '
     'pregunte esta decidiendo una codificacion por su cuenta'),
    ('el codec CP1252', r'GetEncoding\s*\(\s*1252\s*\)',
     [('Lsp.Codificacion.pas', '*'),
      # deuda declarada (2.1g de la 1.18.0): Docs crea el suyo en cada llamada para medir
      # bytes; se va con un parametro de EncodeText (sustitucion), no con un hermano
      ('Lsp.Docs.pas', 'BytesMin')],
     'GCp1252: UN codec compartido (revision de la 1.10.0: crear uno por bloque del indice caia en '
     'el bucle de la busqueda)'),
    ('las listas crudas de los sitios',
     r'\b(?:WorkspaceRoots|WorkspaceReadOnlyRoots|WorkspaceReadOnlyPaths|LugaresDeclarados|LibraryRoots|'
     r'TodosLosVaults)\b',
     [('Lsp.Settings.pas', '*'), ('Lsp.Lugares.pas', '*'),
      # deuda declarada (2.1c de la 1.18.0): quien recorre los sitios por su cuenta
      # recalcula sus formas en cada llamada; se va con el cache de formas y el
      # comparador unico de Lsp.Lugares. Por (fichero, funcion): solo puede encoger
      ('Lsp.Guard.pas', 'ArgPathOutsideDenied'), ('Lsp.Guard.pas', 'CasasDeEntregables'),
      ('Lsp.Guard.pas', 'InVault'), ('Lsp.Guard.pas', 'JaulaDecide'), ('Lsp.Guard.pas', 'NegativaDeUnc'),
      ('Lsp.Guard.pas', 'PathDenied'), ('Lsp.Guard.pas', 'RaicesDisponibles'),
      ('Lsp.Guard.pas', 'RaizEnLetraNoConectada'), ('Lsp.Guard.pas', 'ReadOnlyRootOf'),
      ('Lsp.Guard.pas', 'RootItselfDenied'), ('Lsp.Guard.pas', 'RutaRelativaDenegada'),
      ('Lsp.Mascara.pas', 'ServedDriveLetters'), ('Lsp.Guard.pas', 'UncFueraDeLugares'),
      ('Lsp.BuildRunner.pas', 'UnitSourceFolders'), ('Lsp.ProjectUnits.pas', 'BordeDeMudanza'),
      ('Lsp.References.pas', 'ProjectsSearching'), ('Lsp.Session.pas', 'TLspSession.ResolveSettings'),
      ('Mcp.Tools.Workspace.pas', 'TDelphiWorkspaceTool.ExecuteWithParams'),
      ('Mcp.Tools.Workspace.pas', 'TDelphiProjectsTool.ExecuteWithParams')],
     'Lsp.Settings lee las listas de los sitios y Lsp.Lugares las recorre: quien las recorre por su '
     'cuenta recalcula la forma de un sitio en cada llamada (68 llamadas a las formas medidas el '
     '8-oct-2026, ~30 de un sitio), y dos formas de un mismo sitio fueron el workspace borrable del '
     '20-sep-2026'),
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
    """La rutina que contiene la linea n: la ultima cabecera de la columna 0,
    con su clase delante si es un metodo (TClase.Metodo)."""
    for k in range(n, -1, -1):
        m = CABECERA.match(lineas[k])
        if m:
            return m.group(1)
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
                # una casa con su clase delante (TClase.Metodo) es ESE metodo; sin
                # ella, la rutina o el metodo de ese nombre en cualquier clase
                if not any(base == cf and (cfn == '*' or cfn.lower() in (fn.lower(), fn.split('.')[-1].lower()))
                           for cf, cfn in casas):
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
    'la extension de la marca de dueno': "  M := Copia + '.by';",
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
    'decidir la codificacion de unos bytes': "  if (B[0] = $FF) and (B[1] = $FE) then K := ekUtf16LE;",
    'UTF-8 estricto preguntado a mano': "  if ValidUtf8(B, 0) then K := ekUtf8;",
    'el codec CP1252': "  E := TEncoding.GetEncoding(1252);",
    'las listas crudas de los sitios': "  for R in WorkspaceRoots do",
}
for regla in REGLAS:
    nombre = regla[0]
    planta = ('unit Plantado;\nimplementation\nprocedure CopiaAMano;\nbegin\n  // ' + PLANTADO[nombre] +
              '\n' + PLANTADO[nombre] + '\nend;\nend.\n')
    cazados = fuera_de_casa(regla, [('Plantado.pas', planta)])
    check('mutante "%s": la copia plantada se caza (y el comentario no)' % nombre,
          len(cazados) == 1 and ':6 ' in cazados[0], cazados)

# una casa con su clase delante es ESE metodo y no otro del mismo nombre: la
# excepcion de una tool no tapa a sus hermanas de la unidad
REGLA_SITIOS = next(r for r in REGLAS if r[0] == 'las listas crudas de los sitios')
def metodo_plantado(clase):
    return ('unit Plantado;\nimplementation\nfunction %s.ExecuteWithParams: string;\nbegin\n'
            '  for R in WorkspaceRoots do\nend;\nend.\n' % clase)
OTRA = fuera_de_casa(REGLA_SITIOS, [('Mcp.Tools.Workspace.pas', metodo_plantado('TDelphiListTool'))])
check('mutante de la casa con clase: el mismo metodo de OTRA clase se caza', len(OTRA) == 1, OTRA)
SUYA = fuera_de_casa(REGLA_SITIOS, [('Mcp.Tools.Workspace.pas', metodo_plantado('TDelphiWorkspaceTool'))])
check('...y el de la clase declarada no', not SUYA, SUYA)

for regla in REGLAS:
    malos = fuera_de_casa(regla, TEXTOS)
    check('"%s" solo en su casa - %s' % (regla[0], regla[3]), not malos, '\n      ' + '\n      '.join(malos))

# Toda puerta de este censo dice LISTA NEGRA en su cabecera. Este control
# mide la declaracion, NO que una lista negra sea completa.
LISTAS_NEGRAS = [
    ('Lsp.Args.pas','GitArgDenied'),
    ('Lsp.Args.pas','ShellArgDenied'),
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
