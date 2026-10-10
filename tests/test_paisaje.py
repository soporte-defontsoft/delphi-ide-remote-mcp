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
     # (RunCapturedIn no es casa: delega en RunCore y no lanza nada por su cuenta)
     [('Lsp.BuildRunner.pas', 'RunCaptured'),
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
    ('un campo de conexion de un perfil',
     r"TagValue\s*\(.*'Profile_(?:host|port|platform|password)'",
     [('Lsp.Discovery.pas', 'CamposDePerfil')],
     'CamposDePerfil: UN lector del host, el puerto, la plataforma y la contrasena de un perfil '
     '(2.4 de la 1.18.0: doce a mano en tres unidades)'),
    ('.sdk leido a mano', r"EndsWith\('\.sdk'\)",
     [('Lsp.Discovery.pas', 'NombreDeSdk'), ('Lsp.Discovery.pas', 'NombreSinSdk')],
     'NombreSinSdk es la inversa; "es un .sdk" se pregunta al nombrador'),
    ('__delphi-temp', r"'__delphi-temp",
     [('Lsp.Casa.pas', 'TempFolderName')], 'la casa del servidor tiene UN nombrador'),
    ('__delphi-patch', r"'__delphi-patch",
     [('Lsp.Casa.pas', '*')], 'BACKUP_SUB / TrashFolderName (Lsp.Casa desde el 8-oct-2026)'),
    ('StyleName o StyleLookup leidos con una regex', r"'Style(?:Name|Lookup)\\s",
     # la asignacion de un .pas (StyleLookup := ...;), que no es una linea de form
     [('Mcp.Tools.Styles.pas', 'LintStyles')],
     'LineaDePropiedad + LeeLiteralDeForm (2.2 de la 1.18.0: con una regex propia un '
     '\'card\'#115\'tyle\' se leia \'card\', el lint lo daba por estilo que falta)'),
    # (FormatDateTime no distingue mayusculas: 'YYYYMMDD' es el mismo formato)
    ('el nombre de la carpeta de un dia', r"(?i)'yyyymmdd'",
     [('Lsp.Casa.pas', 'NombreDeDia')],
     'NombreDeDia: la carpeta del dia de la papelera y el limite de su purga (2.1f de la 1.18.0: a mano '
     'en TrashDayDir y en PurgeOldBackups)'),
    ('reconocer la carpeta de un dia', r'\\d\{8\}',
     [('Lsp.Casa.pas', 'EsCarpetaDeDia')],
     'EsCarpetaDeDia, el lector de NombreDeDia (2.1f de la 1.18.0: la purga y el restore la '
     'reconocian cada uno con su regex)'),
    ('la carpeta del servidor',
     r'\b(?:ExtractFileDir|ExtractFilePath|TPath\.GetDirectoryName)\s*\(\s*ParamStr\s*\(\s*0\s*\)',
     [('Lsp.Casa.pas', 'ServerDir'),
      # otro programa: la carpeta del NODO, no la del servidor
      ('McpDesktopNode.dpr', '*')],
     'ServerDir: la casa tiene UN compositor (2.7 de la 1.18.0: LugaresProtegidos la escribia a mano)'),
    # (tambien como mascara, '*.by': MascaraDeMarcas; revisor de 9a9c4cc)
    ('la extension de la marca de dueno', r"'\*?\.by'",
     [('Lsp.Casa.pas', '*')],
     'MARCA_DUENO_EXT: MarcaDeDueno la escribe, CopiaDeLaMarca la deshace y EsMarcaDeDueno la '
     'reconoce, los tres en Lsp.Casa con su formato (David, 8-oct-2026: viajan juntos o ninguno)'),
    ("la forma 'srvX:'", r"'srv'",
     [('Lsp.Mascara.pas', 'VirtualUnitOf'), ('Lsp.Mascara.pas', 'EmpiezaPorUnidadVirtual')],
     'VirtualUnitOf la escribe y EmpiezaPorUnidadVirtual la prueba: nadie la compone ni la prueba a mano'),
    ('el host virtual srvhost', r"'(?:\\\\)?srvhost",
     [('Lsp.Mascara.pas', '*')],
     'HOST_VIRTUAL: MaskDriveText lo escribe y ExpandDriveValue lo lee de vuelta, con la misma '
     'constante (2.10 de la 1.18.0: un literal suelto a cada lado)'),
    ('GetTempPath suelto', r'\bGetTempPath\w*\s*\(', [],
     'lo temporal del servidor va en su casa (ServerTempDir), nunca en el %TEMP% del sistema'),
    ('el .dproj de un .dpr', r"(?:ChangeExtension|ChangeFileExt)\s*\([^;]*'\.dproj'\)",
     [('Lsp.Dproj.pas', 'DprojDe')],
     'DprojDe (1.17.0: diez a mano, y delphi_build rechazaba el .dpr que delphi_config resolvia)'),
    ('de que marco es un designer',
     r"(?i)(?:EndsWith\s*\(\s*'\.fmx'|(?:GetExtension|ExtractFileExt)\s*\([^)]*\)\s*,\s*'\.fmx')",
     [('Lsp.DesignerForma.pas', 'EsDesignerFmx'),
      # el filtro de ficheros del lint (un .fmx o un .pas), no el marco de un form
      ('Mcp.Tools.Styles.pas', 'LintStyles')],
     'EsDesignerFmx (2.3 de la 1.18.0: siete a mano, de tres formas)'),
    ('la sangria de un nivel de un designer', r"StringOfChar\s*\(\s*' '\s*,.*\*\s*2\s*\)",
     [('Lsp.DesignerBin.pas', 'SangriaDeNivel')],
     'SangriaDeNivel: dos espacios por nivel, como el IDE (2.3 de la 1.18.0: cuatro a mano)'),
    ('el .dpr de un .dproj', r"(?:ChangeExtension|ChangeFileExt)\s*\([^;]*'\.dp[rk]'\)",
     [('Lsp.Dproj.pas', 'DprDe')],
     'DprDe, la inversa de DprojDe (2.2 de la 1.18.0: a mano en el build, delphi_test y el scaffold; '
     'y el .dpk de un paquete, que solo sabia ResolveProjectPair: P9)'),
    ('el juez del nombre de un perfil', r"(?i)(?:IsMatch|CharInSet)\s*\(\s*\w*(?:prof|perfil)\w*\s*,", [],
     'Lsp.Guard.BadProfileName, la regla de la puerta (2.3 de la 1.18.0: set-profile y remove-profile '
     'tenian una regex propia que dejaba pasar el punto)'),
    # las casas del lector de forms de la revision de la 1.17.0 que no tenian
    # regla (punto 10 del revisor de las pruebas; 2.3 de la 1.18.0)
    ('la gramatica de las lineas de un form', r"EndsWith\(\s*'= <'|Contains\(\s*'= \{'|'\(\?i\)\^end\\b", [],
     'LineasDeForm (Lsp.DesignerBin): la leian cuatro lectores, cada uno con su parte de la gramatica '
     '(revision de la 1.17.0)'),
    ('un literal de form leido a mano',
     r"Trim\(\s*\[\s*''''\s*\]\s*\)|StartsWith\(\s*''''\s*\)\s*and\s*[\w.]+\.EndsWith\(\s*''''\s*\)", [],
     'LeeLiteralDeForm / NombreDeValor (Lsp.DesignerBin): .Trim([\'\'\'\']) en los estilos y las comillas '
     'quitadas a mano en el renombrado no leian ni #N ni trozos (revision de la 1.17.0; P5)'),
    ('la gramatica de un numero de un form', r"\\d\+\(\?:\\\.\\d\+\)\?|\\\$\[0-9A-Fa-f\]\+",
     [('Lsp.DesignerBin.pas', 'EsNumeroDeForm'), ('Lsp.DesignerBin.pas', 'EsEnteroDeForm')],
     'EsNumeroDeForm / EsEnteroDeForm: la de ValidStyleValue y la del entero del juez eran copias, y '
     'las dos aceptaron -$FF, que TParser no lee (segunda revision de la 1.17.0)'),
    ('una linea de propiedad de un form compuesta a mano',
     r"'\s+[A-Za-z_][\w.]*\s+=\s+'\s*\+|\b\w*Prop\w*\s*\+\s*' = '\s*\+", [],
     'LineasDePropiedad (Lsp.DesignerBin): Prop = valor, y sus trozos en las lineas de debajo como el IDE '
     '(revision de la 1.17.0; la plantilla del frame FMX, 2.3 de la 1.18.0)'),
    ('un valor de bloque preguntado a mano', r"CharInSet\(\s*\w+\[1\]\s*,\s*\['[(<{]'",
     [('Lsp.DesignerBin.pas', 'EsValorDeBloque')],
     'EsValorDeBloque: una lista, un bloque binario o una coleccion (2.3 de la 1.18.0: tres a mano)'),
    ('la regex de una linea de propiedad', r"PATRON_IDENT_PUNTOS\s*\+\s*'\)\\s\*=",
     [('Lsp.DesignerBin.pas', 'LineaDePropiedad')],
     'LineaDePropiedad: PropRaw de layout tenia su copia literal y tomaba un item de una coleccion por '
     'una propiedad del objeto (P2 de la segunda revision de la 1.17.0)'),
    ('binario por el primer byte', r"\[\s*0\s*\]\s*=\s*\$FF\b",
     [('Lsp.DesignerForma.pas', 'DesignerShapeOf'),
      # el BOM de UTF-16 LE (FF FE): la otra pregunta, la de la codificacion
      ('Lsp.Codificacion.pas', 'KindDeBom')],
     'DesignerShapeOf: solo $FF tambien es el BOM de un texto UTF-16 LE; IsBinaryStyle era la quinta copia '
     'del fallo del 24-sep (P3 de la segunda revision de la 1.17.0)'),
    ('la distancia de edicion', r"Min\s*\(\s*Min\s*\(", [('Lsp.Pascal.pas', 'EditDistance')],
     'EditDistance (Lsp.Pascal): vivia dentro de delphi_help (1.17.0)'),
    ('el mas parecido', r"\bEditDistance\s*\(",
     [('Lsp.Pascal.pas', 'ElMasParecido'),
      # OTRA pregunta: la lista de los nombres a dos letras o menos
      ('Mcp.Tools.Help.pas', 'OneTool')],
     'ElMasParecido (Lsp.Pascal): el UNICO a la menor distancia; delphi_help tenia su copia (revision de '
     'la 1.17.0)'),
    ('convertir un designer con la RTL',
     r"\b(?:Object(?:Resource|Binary)ToText|ObjectTextTo(?:Resource|Binary))\s*\(|\.ReadResHeader\b",
     [('Lsp.DesignerForma.pas', 'DesignerAFlujo'), ('Lsp.DesignerForma.pas', 'DesignerBinarioATexto'),
      ('Lsp.DesignerBin.pas', 'DesignerTextToBinary')],
     'DesignerAFlujo / DesignerBinarioATexto (Lsp.DesignerForma) y DesignerTextToBinary: el servidor y el '
     'renderizador convertian cada uno con su llamada a la RTL (P10 de la segunda revision de la 1.17.0)'),
    ('la clave del nombre de un estilo', r"\.StyleName\.ToLower|SameText\(\s*[\w.\[\]]*\.StyleName\b", [],
     'ClaveDeEstilo (Lsp.Styles), la de FMX: ToLowerInvariant (P7 de la segunda revision de la 1.17.0: '
     'SameText en FindStyle y Child, ToLower en el lint)'),
    ('la cadena de clases de la tabla', r"\bPadres\.TryGetValue\s*\(",
     [('Lsp.DesignerMeta.pas', 'TMetaTable.CadenaDe'),
      # OTRO Padres: los hijos de cada clase, en el generador
      ('Lsp.DesignerMetaGen.pas', 'TGenerador.ResuelveAyudantes')],
     'TMetaTable.CadenaDe: la cadena de una clase hasta su raiz, con su tope (revision de la 1.17.0: '
     'cada pregunta de la tabla la recorria a mano)'),
    ('el designer de una unidad', r"(?:ChangeExtension|ChangeFileExt)\s*\([^;]*'\.(?:dfm|fmx)'\)", [],
     'DesignersDeUnidad (Lsp.Patch), la inversa de UnidadDeDesigner (2.2 de la 1.18.0: cinco a mano)'),
    ('el .dproj compuesto a mano', r"\+\s*'\.dproj'", [],
     'DprojDe tambien para el que se crea (revision de la 1.17.0: Scaffold y ResolveProjectPair lo '
     'componian con + \'.dproj\')'),
    ('la unidad de un form', r"(?:ChangeExtension|ChangeFileExt)\s*\([^;]*'\.?pas'\s*\)",
     [('Lsp.DesignerForma.pas', 'UnidadDeDesigner')],
     'UnidadDeDesigner (revision de la 1.17.0: cuatro a mano, uno en el renderizador)'),
    ('la forma de un designer', r'\bTestStreamFormat\s*\(', [],
     'DesignerShapeOf / DesignerAFlujo (Lsp.DesignerForma): TestStreamFormat llama binario al texto '
     'UTF-16 y no salta la cabecera del recurso (preview de un .dfm binario, revision de la 1.17.0)'),
    ('leer la linea de objeto de un form',
     r"object\|inherited\|inline|'[^']*\^(?:\\s\*)?\(?(?:\?i\))?(?:object|inherited|inline)\b"
     r"|StartsWith\(\s*'(?:object|inherited|inline)\b",
     [('Lsp.DesignerForma.pas', 'LineaDeObjeto')],
     'LineaDeObjeto (1.12.0: seis regex; la septima, la del renderizador, en la revision de la 1.17.0; '
     'la octava, una sola palabra, en layout: 2.3 de la 1.18.0)'),
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
     # sin casa: ComponeLineaDeObjeto recibe la palabra (AClave) y no la escribe asi
     [],
     'ComponeLineaDeObjeto la escribe y LineaDeObjeto la lee (1.17.0: el insert de delphi_designer; '
     'las plantillas de Lsp.Scaffold la componian a mano)'),
    ('un componente por su ruta en el renderizador', r'\bFindNestedComponent\s*\(',
     [('FormRender.Comun.pas', 'ComponenteDeRuta')],
     'ComponenteDeRuta: UN lector de Marco1.LblAviso, y de la raiz delante, para component= y state= '
     '(segunda revision de la 1.17.0: el estado de un frame suelto con su nombre delante no llegaba)'),
    ('un flotante de un form', r"\.0{18}'|ffFixed\s*,\s*16\s*,\s*18|StringOfChar\s*\(\s*'0'\s*,\s*18\s*\)",
     [('Lsp.DesignerBin.pas', 'FlotanteDeForm')],
     'FlotanteDeForm: el numero de coma flotante como lo escribe el IDE en UN sitio (1.17.0: insert, '
     'set y las plantillas FMX)'),
    # la gramatica PASCAL que se lee a mano (punto D/E de adivinar-vs-medir; inventario del
    # 10-oct-2026, medida-pascal-copias): las copias de hoy, declaradas; los lectores son
    # Lsp.Pascal (el end. y la cabecera, sobre la vista del codigo) y Lsp.PascalDecl
    # (TLectorPas), y cada copia que pase a ellos sale de la lista
    ('el end. de una unidad leido a mano', r"end(?:\\s\*)?\\\.",
     [('Lsp.Pascal.pas', 'EndsConPunto')],
     'EndsConPunto (Lsp.Pascal): eran siete sitios con dos ortografias (laxa "end\\s*\\." y '
     'estricta "end\\." sola en su linea); la estricta daba BROKEN STRUCTURE sobre un '
     '"program P; begin end." que compila (inventario y sonda del 10-oct-2026)'),
    ('la cabecera de una unidad leida a mano',
     r"\((?:\?:)?(?:unit\|)?program\|library|\^\\s\*unit\\s\+|StartsWith\(\s*'unit '",
     [('Lsp.Pascal.pas', 'CabeceraDeFuente')],
     'CabeceraDeFuente (Lsp.Pascal): eran cinco lectores de unit/program/library/package - solo '
     'FindUses veia package, solo CabeceraDeUnit daba posicion, ExecutePatch la queria en una linea '
     '(inventario del 10-oct-2026; una casa desde el mismo dia)'),
    ('la seccion interface/implementation buscada a mano',
     r"'\^(?:\[ \\t\]\*|\\s\*)'\s*\+\s*\w+\s*\+\s*'\\b'|\^(?:interface|implementation)\[ \]\*\$|"
     r"\.Trim\.ToLower\s*=\s*'(?:interface|implementation)'",
     [('Lsp.ProjectUnits.pas', 'FinDeSeccion'), ('Mcp.Tools.DelphiLsp.pas', 'InterfaceDigest'),
      ('Lsp.Patch.pas', 'ExecutePatch')],
     'la primera linea que empieza por la palabra (FinDeSeccion: estaba cinco veces en tres funciones '
     'de ProjectUnits), la linea exacta (InterfaceDigest) o la linea que es la palabra (ExecutePatch, '
     'la frontera del insert; la vio el revisor 7): tres reglas para lo que TLectorPas ya sabe '
     '(inventario del 10-oct-2026)'),
    ('decidir la codificacion de unos bytes',
     r'\bGetBufferEncoding\b|\$FF\b[^;]*\$FE\b|\$FE\b[^;]*\$FF\b|\$EF\b[^;]*\$BB\b|\$BB\b[^;]*\$BF\b',
     # (EncodeText escribe el BOM byte a byte, una forma que esta regla no ve: 2.1g)
     # (EL lector del BOM del principio, KindDeBom, lo preguntan DetectEnc y el
     # lector de settings.ini, que no puede usar Patch: 9.2 de la 1.18.0)
     [('Lsp.Codificacion.pas', 'KindDeBom'), ('Lsp.Codificacion.pas', 'BomUtf8En'),
      # deuda declarada (2.1g de la 1.18.0): un detector suelto, el de los renderizadores,
      # que no enlazan la casa (Lsp.Codificacion arrastra Lsp.Texts); solo puede encoger.
      # (el de la ayuda se fue en r5: pregunta BomUtf8En y CodecDeCharset)
      ('Lsp.DesignerForma.pas', 'DesignerAFlujo')],
     'EL detector (DetectEnc, en Lsp.Patch) y el BOM de los codecs (BomUtf8En lo lee, EncodeText lo '
     'escribe): nadie mas mira unos bytes para decidir que son (24-sep-2026: dos detectores; 1.18.0: '
     'los codecs salen a Lsp.Codificacion y la decision se queda en Patch). KindDeBom es GRAMATICA '
     'PROPIA declarada (norma 6 del paisaje): el juez de la RTL, TEncoding.GetBufferEncoding, no '
     'conoce UTF-32, y su BOM de LE empieza como el de UTF-16 LE'),
    ('UTF-8 estricto preguntado a mano', r'\b(?:ValidUtf8|IsBufferValid)\s*\(',
     [('Lsp.Patch.pas', 'DetectEnc'),
      # el juez de la RTL (TEncoding.UTF8.IsBufferValid) en UN sitio
      ('Lsp.Codificacion.pas', 'ValidUtf8')],
     'si unos bytes son UTF-8 lo contesta el juez de la RTL, TEncoding.UTF8.IsBufferValid (norma 6: '
     'habia una copia a mano, la de la 1.17 aceptaba formas largas), y lo pregunta el detector: '
     'otro que lo pregunte esta decidiendo una codificacion por su cuenta'),
    ('codificar el texto de un fichero para escribirlo', r'\bEncodeText\s*\(',
     [('Lsp.Codificacion.pas', '*'),
      # los DOS escritores (con la regla de ida y vuelta y la del primer caracter no
      # ASCII), la creacion de una unit nueva y la medida de un cuerpo de varios bytes
      ('Lsp.Patch.pas', 'DoEdit'), ('Lsp.Patch.pas', 'PatchSaveText'),
      ('Lsp.Patch.pas', 'ExecutePatch'), ('Lsp.Patch.pas', 'Measure'),
      # la puerta de escribir: el texto que COMPONE el servidor, en la codificacion
      # de su formato (un .job, una nota del vault, un .sdk), con la de ida y vuelta
      ('Lsp.Patch.pas', 'EscribeTexto'),
      # la decision del escritor: como se LEERIAN los bytes ANSI de un fuente
      # sin codificacion (LecturaCambiada); no escribe nada
      ('Lsp.Patch.pas', 'EncAlEscribir'),
      # el texto de un form, en ANSI, para el parser de forms de la RTL EN MEMORIA:
      # lo que se escribe es el binario (to-binary, por AtomicWrite), no un texto
      ('Lsp.DesignerBin.pas', 'DesignerTextToBinary'),
      # las lineas de un form en los bytes que harian en SU codificacion, para
      # PREGUNTAR al parser del IDE si las lee (9.B de la 1.18.0); no escribe nada
      ('Lsp.DesignerBin.pas', 'ParserDeForm')],
     'quien codifica el texto de un fichero por su cuenta se salta la regla de ida y vuelta y la '
     'del primer caracter no ASCII (David, 9-oct-2026): se escribe por PatchSaveText o DoEdit'),
    ('la regla de ida y vuelta preguntada a mano',
     r'\bBytesVuelvenIgual\s*\(|\bSR_EDIT_BYTES_NO_VUELVEN_FMT\b|\bSR_EDIT_SE_LEERIA_DISTINTO_FMT\b',
     [('Lsp.Patch.pas', 'ReescrituraDenegada'),
      # su lado de la escritura: lo que se escribe se lee igual (EDIT-122)
      ('Lsp.Patch.pas', 'LecturaCambiada'),
      # delphi_read la pregunta para AVISAR (READ-007), no para escribir
      ('Lsp.Patch.pas', 'NotaDeIdaYVuelta')],
     'si unos bytes se pueden reescribir lo dice ReescrituraDenegada, con EL detector, y la '
     'preguntan los escritores (DoEdit, PatchSaveText, el del vault): esta regla evita una SEGUNDA '
     'copia de la pregunta; que un escritor se OLVIDE de hacerla (el del vault, revisor propio de la '
     '4.1) lo caza su bateria, y lo cazara la regla de la puerta de escribir'),
    ('las extensiones de un fuente a mano',
     # la lista de los fuentes (lleva .pas y .inc) salvo la declaracion de SOURCE_EXTS, o
     # el predicado o el recorrido reescritos con ella (4.1 de la 1.18.0)
     # (una LISTA, con comas: comparar una extension con .pas y con .inc es otra familia,
     # la de HuellaDeCarpetas del generador de tablas)
     r"^(?!\s*SOURCE_EXTS\s*:).*(?:'\*?\.pas'\s*,[^;]*'\*?\.inc'|'\*?\.inc'\s*,[^;]*'\*?\.pas')|"
     r"MatchText\s*\([^;]*\bSOURCE_EXTS\s*\)|\bin\s+SOURCE_EXTS\b",
     [('Lsp.Patch.pas', 'EsRutaDeFuente'),
      # deuda declarada (9-oct-2026): delphi_references busca *.pas, *.dpr e *.inc SIN
      # .dpk; anadirlo cambia lo que encuentra, y eso se decide aparte
      ('Lsp.References.pas', 'FindDelphiReferences')],
     'EsRutaDeFuente (Lsp.Patch): la lista estaba escrita a mano en cinco sitios, y el escritor '
     'necesita saber si un fichero lo lee dcc (4.1 de la 1.18.0)'),
    ('las extensiones de un designer a mano',
     # la lista, como extensiones o como mascaras y en cualquier orden - salvo
     # la declaracion de DESIGNER_EXTS, la UNICA, este donde este -, o el
     # predicado o el recorrido reescritos con ella (revisor propio de la 4.1,
     # 9-oct-2026: una excepcion por posicion tapaba tambien una copia dentro
     # de la funcion bajo la que cae la constante)
     r"^(?!\s*DESIGNER_EXTS\s*:).*'\*?\.(?:dfm|fmx)'\s*,\s*'\*?\.(?:dfm|fmx)'|"
     r"MatchText\s*\([^;]*\bDESIGNER_EXTS\s*\)|\bin\s+DESIGNER_EXTS\b",
     [('Lsp.Patch.pas', 'EsRutaDeDesigner'), ('Lsp.Patch.pas', 'DesignersDeUnidad')],
     'DESIGNER_EXTS, EsRutaDeDesigner y DesignersDeUnidad (Lsp.Patch): la lista estaba escrita a mano en '
     'nueve sitios, y el detector necesita saber si un fichero es un form (4.1 de la 1.18.0)'),
    ('una cadena ASCII preguntada a mano', r'\bOrd\s*\(\s*\w+\s*\)\s*>\s*127\b',
     [('Lsp.Codificacion.pas', 'IsAscii')],
     'IsAscii (Lsp.Codificacion): estaba en Lsp.TextEdit y en linea en NombreQueElFicheroNoLee, y '
     'to-binary iba a por la tercera (4.1 de la 1.18.0)'),
    ('una pagina de codigos a mano',
     r'GetEncoding\s*\(|TEncoding\.(?:ANSI|Default)\b|\bGetACP\b|TMBCSEncoding\.Create\s*\(',
     [('Lsp.Codificacion.pas', '*'),
      # la pagina OEM de la CONSOLA (GetConsoleOutputCP, o GetOEMCP sin consola) con
      # la que escribe un hijo en su tuberia: otro juez y otra pagina, no la ANSI
      ('Lsp.BuildRunner.pas', 'RunCore')],
     'LA pagina ANSI es la de la maquina, medida en UN lector (PaginaAnsi: GetACP, la de '
     'TEncoding.ANSI), y los codecs se crean en la casa (CodecDeCharset para la pagina que declara '
     'un formato): r5 de la 1.18.0, norma 6 del paisaje - el servidor tenia la 1252 clavada en el '
     'detector, TEncoding.ANSI en to-binary y en los estilos y TEncoding.Default en el renderizador, '
     'tres definiciones de ANSI; y la ayuda creaba su 1252 en cada busqueda'),
    ('fijar la pagina ANSI', r'\bUsaPaginaAnsi\s*\(',
     [('Lsp.Codificacion.pas', '*')],
     'la pagina ANSI la fija la initialization de Lsp.Codificacion con la de la maquina; otra la '
     'piden SOLO las pruebas (DUnitX, para medir 1251, 1253 o 932 en una maquina 1252). Un sitio '
     'del servidor que la cambie lee y escribe en otra pagina que el IDE y dcc'),
    ('las listas crudas de los sitios',
     r'\b(?:WorkspaceRoots|WorkspaceReadOnlyRoots|WorkspaceReadOnlyPaths|LugaresDeclarados|LibraryRoots|LibraryReadRoots|'
     r'TodosLosVaults|RaicesDeLosWorkspaces|RaicesDelModoLocal|SitiosQueNoSeTocan)\b',
     [('Lsp.Settings.pas', '*'), ('Lsp.Lugares.pas', '*'),
      # deuda declarada (2.1c de la 1.18.0): quien recorre los sitios por su cuenta
      # recalcula sus formas en cada llamada; se va con el cache de formas y el
      # comparador unico de Lsp.Lugares. Por (fichero, funcion): solo puede encoger
      ('Lsp.Guard.pas', 'ArgPathOutsideDenied'), ('Lsp.Guard.pas', 'CasasDeEntregables'),
      ('Lsp.Guard.pas', 'InVault'), ('Lsp.Guard.pas', 'JaulaDecide'), ('Lsp.Guard.pas', 'NegativaDeUnc'),
      ('Lsp.Guard.pas', 'LugaresProtegidos'), ('Lsp.Guard.pas', 'PurgeServerTemp'),
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
    ('la zona de biblioteca cruda', r'\bLibraryRoots\b',
     [('Lsp.Lugares.pas', '*'), ('Lsp.Mascara.pas', 'ServedDriveLetters')],
     'la zona de biblioteca se juzga con LugaresDeLaBiblioteca (en la forma larga) y por la ruta '
     'real (Lsp.Rutas.EnAlgunLugar): JaulaDecide la juzgaba por el TEXTO de LibraryRoots, y un '
     'enlace plantado en una carpeta de la Library Path que apuntase fuera se leia, y una raiz en 8.3 '
     'negaba hasta lo suyo (M1 de la 1.18.0, medido con la HKCU virtual). La lista cruda queda para '
     'Lsp.Lugares y para las letras que se sirven'),
    ('leer sin la puerta',
     # (un TMemIniFile vacio que se llena con SetStrings no lee nada)
     r"TFile\.(?:ReadAllText|ReadAllLines|OpenText)\b|\.LoadFromFile\s*\(|TMemIniFile\.Create\s*\((?!\s*'')|"
    r"TIniFile\.Create\s*\(|TStreamReader\.Create\s*\(|"
    # y los BYTES (P2 de la 1.18.0): un flujo que no se abre para escribir es para leer
    r"TFile\.(?:ReadAllBytes|OpenRead|Open)\b|\bTFileStream\.Create\s*\((?![^;]*\bfm(?:Create|OpenWrite|OpenReadWrite)\b)|"
    r"\bFileOpen\s*\(|\bCreateFile\w*\s*\([^;]*GENERIC_READ",
     # excepciones DECLARADAS, cada una con su motivo; solo pueden encoger
     [# settings.ini: su lector es Lsp.Settings y no es lugar de ninguna puerta (C1)
      ('Lsp.Settings.pas', 'ComprobarDuplicadosIni'), ('Lsp.Settings.pas', 'LoadSecurity'),
      ('Lsp.Settings.pas', 'FijaDelphiVersionEnElIni'), ('Lsp.Settings.pas', 'BytesDelIni'),
      # LA puerta (LeeBytes) y el decodificador que usan ella y LeeTexto, tras la puerta
      ('Lsp.Patch.pas', 'LeeBytes'), ('Lsp.Patch.pas', 'TextoDeFichero'),
      # .git\HEAD: la puerta niega .git y esta lectura lo admite (el juez es git, 9.5)
      ('Mcp.Tools.Workspace.pas', 'RepoOf'),
     # BYTES de la jaula que la tool ya comprobo (delphi_fetch, el zip de delphi_package;
     # el PNG que se recorta, P4) y la captura que la propia tool acaba de dejar
     ('Mcp.Tools.Workspace.pas', 'TDelphiFetchTool.ExecuteWithParams'),
     ('Mcp.Tools.Workspace.pas', 'TDelphiPackageTool.ExecuteWithParams'),
     ('Lsp.InlineImages.pas', 'DeliverCapture'),
      ('Lsp.Files.pas', 'ServeFile'), ('Lsp.Imagen.pas', 'RecortaPng'),
      # programas que NO son el servidor: los renderizadores y el conversor leen lo que
      # el servidor ya paso por su puerta; el nodo y el lanzador corren en el destino
      ('FormRender.Comun.pas', 'Cabecera'), ('FormRender.Comun.pas', 'AncestroDeClase'),
      ('FormRender.Comun.pas', 'TCargador.LeeUno'), ('FormRender.Fmx.pas', 'AplicaEstilo'),
      ('FormRender.Vcl.pas', 'Main'), ('DelphiStyleConvert.dpr', 'Convert'),
     # los OLFATEADORES: la cabecera de lo que la tool ya juzgo (4 bytes de un designer o
     # de un estilo, el BOM de un form, el tamano de un PNG)
     ('Lsp.DesignerBin.pas', 'IsBinaryDesignerFile'), ('Lsp.Styles.pas', 'IsBinaryStyle'),
     ('Mcp.Tools.Designer.pas', 'FormAncho'), ('Lsp.Imagen.pas', 'TamanoPng'),
     # el MOTOR de edicion de la jaula: lo que la tool ya paso por la puerta de la jaula
     # (delphi_read, delphi_edit, delphi_textedit, delphi_changeset, el disenador)
     ('Lsp.Patch.pas', 'RelecturaDe'), ('Lsp.Patch.pas', 'PatchSaveText'),
     ('Lsp.Patch.pas', 'ReadNumbered'), ('Lsp.Patch.pas', 'ExecutePatch'), ('Lsp.Patch.pas', 'DoEdit'),
     ('Lsp.TextEdit.pas', 'DoCreate'), ('Lsp.TextEdit.pas', 'DoEditLine'),
     ('Lsp.Changeset.pas', 'FingerprintBytes'), ('Lsp.DesignerEdit.pas', 'NombreQueLaCodificacionNoLleva'),
     ('Mcp.Tools.Designer.pas', 'ConvertDesigner'), ('Lsp.DesignerBin.pas', 'DesignerFileToText'),
     # la foto del todo o nada: los bytes de lo que la operacion va a tocar, ya juzgado
     ('Lsp.TodoONada.pas', 'TFotoDeFicheros.Toma'), ('Lsp.TodoONada.pas', 'TFotoDeFicheros.Anota'),
     ('Lsp.TodoONada.pas', 'TFotoDeFicheros.Vigila'), ('Lsp.TodoONada.pas', 'TFotoDeFicheros.Restaura'),
     ('Lsp.TodoONada.pas', 'TFotoDeFicheros.Cambiados'),
     # su propio log (C5) y los binarios del propio servidor (el hash de lo que sube remote-run)
     ('Lsp.LogSink.pas', 'LineasDe'), ('Lsp.RemoteRun.pas', 'Sha256DeFichero'),
     ('Mld.Sesion.pas', 'SesionGrafica'), ('McpDesktopNode.dpr', 'EjecutarLinux'),
     ('McpRunJob.dpr', 'LanzarYVigilar'), ('McpDesktopNode.dpr', 'TamanoPng'),
     ('McpRunJob.dpr', 'EsBinarioNativo'), ('McpRunJob.dpr', 'Arrancar')],
    'LeeTexto y LeeBytes (Lsp.Patch): LA puerta de leer, con el LUGAR por parametro (jaula, IDE, '
     'casa, temporal, vault), por la ruta REAL y con EL detector. 41 lecturas iban por su cuenta '
     '(inventario del 9-oct-2026, bloque de las puertas de la 1.18.0): el escaner de peligros leia un '
     'Import de fuera de las raices y, limpio, el build lo cargaba de alli; un buzon que era una union '
    'entregaba y BORRABA lo de detras. Y los de BYTES (P2): 36 medidos; el vault y la inspeccion '
    'de una unidad (la cabecera de su designer) los leian sin la puerta'),
    ('escribir sin la puerta',
     # (revisor de P3: la primera forma solo veia la mitad - ni CreateFile para escribir,
     # ni fmOpenWrite, ni un fmCreate en la linea de abajo, ni un ini, un zip, un
     # RenameFile o el CopiaNuestra publico que copia sin puerta)
     r"TFile\.(?:WriteAllText|WriteAllBytes|WriteAllLines|AppendAllText|AppendAllLines|Copy|Move|"
     r"Create|OpenWrite|CreateText|AppendText|Replace)\s*\(|"
     r"\.SaveToFile\s*\(|TStreamWriter\.Create\s*\(|\bfm(?:Create|OpenWrite|OpenReadWrite)\b|"
     r"WritePrivateProfileString\w*\s*\(|\bCopyFile\w*\s*\(|\bMoveFile\w*\s*\(|"
     r"\bCreateFile\w*\s*\([^;]*(?:GENERIC_WRITE|GENERIC_ALL|FILE_WRITE_DATA|FILE_APPEND_DATA|"
     r"FILE_WRITE_ATTRIBUTES|CREATE_ALWAYS|CREATE_NEW|TRUNCATE_EXISTING|OPEN_ALWAYS)|"
     r"\bzm(?:Write|ReadWrite)\b|\.ExtractAll\s*\(|\bFileCreate\s*\(|\bRenameFile\s*\(|"
    r"TIniFile\.Create\s*\(|TMemIniFile\.Create\s*\((?!\s*'')|\.UpdateFile\b|\bCopiaNuestra\s*\(|"
    r"TFile\.Open\s*\([^;]*\b(?:faWrite|faReadWrite|fmCreateNew|fmOpenOrCreate|fmTruncate|fmAppend)\b",
     [# LA puerta (EscribeBytes) y los escritores de la jaula que ya preguntan la suya:
      # el atomico, el de productos, la copia diaria y la sellada de la papelera
      ('Lsp.Patch.pas', 'EscribeBytes'), ('Lsp.Patch.pas', 'CopiaAntesDePisar'),
      ('Lsp.Patch.pas', 'AtomicWrite'),
      ('Lsp.Patch.pas', 'SustituyePorRenombre'), ('Lsp.Patch.pas', 'Coloca'),
      # la fecha de creacion de lo que el escritor ACABA de sustituir
      ('Lsp.Patch.pas', 'PonFechaDeCreacion'),
      # la reserva del nombre de un informe, tras la puerta sobre su carpeta con el
      # nombre mas largo (CREATE_NEW: no pisa nada)
      ('Mcp.Tools.Report.pas', 'ReservarNombre'),
      # settings.ini: su lector y escritor es Lsp.Settings (C1), ninguna puerta
      ('Lsp.Settings.pas', 'LoadSecurity'), ('Lsp.Settings.pas', 'FijaDelphiVersionEnElIni'),
      # NUL como salida de error de un hijo: no es un fichero
      ('Lsp.Transport.Process.pas', 'TLspProcessTransport.Start'),
      # el zip de delphi_package se arma en su temporal de sustitucion junto al
      # destino, ya comprobado por la jaula, y se pone de un golpe
      ('Mcp.Tools.Workspace.pas', 'TDelphiPackageTool.ExecuteWithParams'),
      ('Lsp.Patch.pas', 'BackupFile'), ('Lsp.Patch.pas', 'GuardaContenidoActual'),
      # los recorredores y movimientos de la jaula (no cruzan enlaces; la puerta antes)
      ('Lsp.Guard.pas', 'CopiaNuestra'), ('Lsp.Guard.pas', 'CopiaArbol'),
      ('Lsp.Guard.pas', 'MueveArbol'), ('Lsp.Changeset.pas', 'ApplyOneConAvisos'),
      ('Mcp.Tools.FileOps.pas', 'MoveToTrash'), ('Mcp.Tools.FileOps.pas', 'MoverNucleo'),
      # la copia de la regla 11 dentro del vault (DentroDelVault antes) y la subida por
      # trozos de delphi_upload (la puerta de la jaula a la entrada; no atomica)
      ('Mcp.Tools.Vault.pas', 'VaultBackup'), ('Mcp.Tools.Workspace.pas', 'SubirNucleo'),
      # el log rota sus bloques y anade al vivo (C5: su propio fichero, append)
      ('Lsp.LogSink.pas', 'CierraBloque'), ('Lsp.LogSink.pas', 'Anade'),
      # el PNG se recorta en SU temporal - la descarga de esa llamada o el temporal del
      # designer - ANTES de colocarlo (P4 de la 1.18.0: recortaba en sitio el out= ya
      # colocado); la restauracion de la foto va por la puerta (EscribeBytes) salvo
      # una ruta que no cabe con el temporal del escritor (GUARD-028): directa, ya
      # aprobada por EscrituraDenegada, porque no devolverla perdia el fichero
      # (revisor de la noche del 10-oct, A-1)
      ('Lsp.Imagen.pas', 'RecortaPng'), ('Lsp.TodoONada.pas', 'TFotoDeFicheros.Restaura'),
      # programas que NO son el servidor: escriben donde el servidor les dijo, ya
      # comprobado, o en el destino
      ('Mld.Captura.pas', 'GuardarPNG'), ('McpDesktopNode.dpr', 'RecogerCaptura'),
      ('FormRender.Fmx.pas', 'Main'), ('FormRender.Vcl.pas', 'GuardaPng'),
      ('McpRunJob.dpr', 'EscribePid'), ('McpRunJob.dpr', 'LanzarYVigilar'),
      ('McpRunJob.dpr', 'Anade'), ('McpRunJob.dpr', 'Arrancar'),
      ('DelphiStyleConvert.dpr', 'Convert'), ('DelphiStyleConvert.dpr', 'Defaults')],
     'EscribeTexto y EscribeBytes (Lsp.Patch): LA puerta de escribir, con el LUGAR por parametro '
     '(jaula, IDE, casa, temporal, vault), entero o nada y con la copia que pida el lugar. 18 '
     'escritores iban por su cuenta (inventario del 9-oct-2026): el vault escribia encima, sin '
     'temporal; la semilla del vault, los informes, los mensajes de git y los .job sin puerta; '
     'get-sdk pisaba un .sdk del IDE sin copia y las libX.so se copiaban al sysroot sin preguntar'),
    ('borrar sin la puerta',
     r"TFile\.Delete\s*\(|\bDeleteFile\w*\s*\(|\bRemoveDir\w*\s*\(|TDirectory\.Delete\s*\(|"
     r"\bRemoveDirectory\w*\s*\(|\bBorraLoNuestro\s*\(",
     [# LA puerta de borrar fuera de la jaula (BorraFichero) y los temporales que los
      # escritores acaban de dejar (el suyo, la copia que no se llego a usar)
      ('Lsp.Patch.pas', 'BorraFichero'), ('Lsp.Patch.pas', 'EscribeBytes'),
      ('Lsp.Patch.pas', 'SustituyePorRenombre'), ('Lsp.Patch.pas', 'Coloca'),
      # la jaula: su borrado de lo que la operacion acaba de dejar, sus recorredores
      # (no cruzan enlaces; la puerta antes), la papelera y el deshacer
      ('Lsp.Guard.pas', 'BorraLoNuestro'), ('Lsp.Guard.pas', 'ConsumeAgentCapture'),
      ('Lsp.Guard.pas', 'BorraArbolDentro'), ('Lsp.Guard.pas', 'VaciaDesechable'),
      ('Lsp.Guard.pas', 'QuitaCarpetasCreadas'), ('Lsp.Changeset.pas', 'ApplyOneConAvisos'),
      ('Lsp.TodoONada.pas', 'TFotoDeFicheros.Restaura'),
      ('Mcp.Tools.FileOps.pas', 'QuitaMarcaDeDueno'), ('Mcp.Tools.FileOps.pas', 'QuitaCopiaDeSeguridad'),
      ('Mcp.Tools.FileOps.pas', 'BorraDeVerdad'), ('Mcp.Tools.FileOps.pas', 'RecogeVacias'),
      ('Mcp.Tools.FileOps.pas', 'BorrarNucleo'), ('Mcp.Tools.FileOps.pas', 'MoverNucleo'),
      # la cuarentena de una subida y el zip a medias de delphi_package: de la jaula,
      # lo que esa misma operacion dejo
      ('Mcp.Tools.Workspace.pas', 'SubirNucleo'),
      ('Mcp.Tools.Workspace.pas', 'TDelphiPackageTool.ExecuteWithParams'),
      # el log poda sus bloques viejos (C5)
      ('Lsp.LogSink.pas', 'Poda'),
      # la carpeta VACIA que paclient deja en la de SDKs del IDE: RemoveDir solo se lleva
      # una vacia (o un enlace, como enlace), nunca lo de dentro
      ('Mcp.Tools.PAServer.pas', 'RemoveProfile'),
      # programas que NO son el servidor: lo suyo, en el destino o en el temporal
      ('McpDesktopNode.dpr', 'RecogerCaptura'), ('McpRunJob.dpr', 'BorraPid'),
      ('McpRunJob.dpr', 'LanzarYVigilar')],
     'BorraFichero (Lsp.Patch): LA puerta de borrar fuera de la jaula, con el LUGAR (casa, temporal, '
     'vault, IDE con copia); en la jaula, la papelera. Los temporales de remote-run y de git, el buzon y '
     'las purgas de la cache del disenador borraban con TFile.Delete o DeleteFile por su cuenta: detras '
     'de una union, fuera (revisor de P3, 9-oct-2026)'),
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


def aciertos(regla, ficheros_texto):
    """Cada linea de codigo con el formato de la regla: (fichero, n, rutina, linea)."""
    nombre, formato, casas, _ = regla
    rx = re.compile(formato)
    for f, texto in ficheros_texto:
        if os.path.basename(f) == 'Lsp.Texts.pas':
            continue
        lineas = codigo(texto)
        for n, l in enumerate(lineas):
            # una cabecera (la declaracion de un lanzador) no es una llamada
            if rx.search(l) and not CABECERA.match(l.strip()):
                yield f, n, funcion_de(lineas, n), l


def casas_de(base, fn, casas):
    """Las casas en las que cae la rutina fn del fichero base: una casa con su
    clase delante (TClase.Metodo) es ESE metodo; sin ella, la rutina o el metodo
    de ese nombre en cualquier clase; '*' es el fichero entero."""
    return [(cf, cfn) for cf, cfn in casas
            if base == cf and (cfn == '*' or cfn.lower() in (fn.lower(), fn.split('.')[-1].lower()))]


def fuera_de_casa(regla, ficheros_texto):
    malos = []
    for f, n, fn, l in aciertos(regla, ficheros_texto):
        if not casas_de(os.path.basename(f), fn, regla[2]):
            malos.append('%s:%d (%s) %s' % (os.path.relpath(f, REPO), n + 1, fn or '-', l.strip()[:90]))
    return malos


def casas_sin_uso(regla, ficheros_texto):
    """Las casas declaradas en las que el formato ya no aparece."""
    usadas = set()
    for f, n, fn, l in aciertos(regla, ficheros_texto):
        usadas.update(casas_de(os.path.basename(f), fn, regla[2]))
    return [c for c in regla[2] if c not in usadas]


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
    'un campo de conexion de un perfil': "  H := TagValue(Xml, 'Profile_host');",
    '.sdk leido a mano': "  if not S.ToLower.EndsWith('.sdk') then S := S;",
    '__delphi-temp': "  D := TPath.Combine(Raiz, '__delphi-temp');",
    '__delphi-patch': "  D := TPath.Combine(Raiz, '__delphi-patch');",
    'StyleName o StyleLookup leidos con una regex': r"  M := TRegEx.Match(L, 'StyleName\s*=\s*''([^'']+)''');",
    'el nombre de la carpeta de un dia': "  D := FormatDateTime('yyyymmdd', Now);",
    'reconocer la carpeta de un dia': "  if TRegEx.IsMatch(N, '^\\d{8}$') then",
    'la carpeta del servidor': "  D := ExtractFileDir(ParamStr(0));",
    'la extension de la marca de dueno': "  M := Copia + '.by';",
    "la forma 'srvX:'": "  U := 'srv' + LowerCase(Letra) + ':';",
    'el host virtual srvhost': "  H := '\\\\srvhost\\' + Resto;",
    'GetTempPath suelto': "  T := TPath.GetTempPath();",
    'el .dproj de un .dpr': "  D := ChangeFileExt(P, '.dproj');",
    'el .dproj compuesto a mano': "  D := Stem + '.dproj';",
    'el .dpr de un .dproj': "  D := TPath.ChangeExtension(P, '.dpr');",
    'el juez del nombre de un perfil': "  if not TRegEx.IsMatch(Perfil, '^[A-Za-z0-9_.-]+$') then",
    'la gramatica de las lineas de un form': "  if L.Trim.EndsWith('= <') then",
    'un literal de form leido a mano': "  N := V.Trim(['''']);",
    'la gramatica de un numero de un form': r"  if TRegEx.IsMatch(V, '^-?\d+(?:\.\d+)?$') then",
    'una linea de propiedad de un form compuesta a mano': "  T := '  Size.Width = ' + FlotanteFmx(320);",
    'un valor de bloque preguntado a mano': "  if CharInSet(V[1], ['(', '<', '{']) then",
    'la regex de una linea de propiedad': r"  M := TRegEx.Match(L, '^(' + PATRON_IDENT_PUNTOS + ')\s*=\s*(.*)$');",
    'binario por el primer byte': "  if (B[0] = $FF) or EsFirmaFmx(B) then",
    'la distancia de edicion': "  D[J] := Min(Min(D[J] + 1, D[J - 1] + 1), P + C);",
    'el mas parecido': "  if EditDistance(A, C) < Mejor then",
    'la cadena de clases de la tabla': "  while Padres.TryGetValue(C, P) do",
    'la clave del nombre de un estilo': "  if SameText(O.StyleName, AStyleName) then",
    'convertir un designer con la RTL': "  ObjectBinaryToText(Bin, Texto);",
    'la sangria de un nivel de un designer': "  I := StringOfChar(' ', (Obj.Depth + 1) * 2);",
    'de que marco es un designer': "  if APath.EndsWith('.fmx', True) then",
    'el designer de una unidad': "  F := ChangeFileExt(Pas, '.dfm');",
    'la unidad de un form': "  P := ChangeFileExt(Dfm, '.pas');",
    'la forma de un designer': "  if TestStreamFormat(S) = sofBinary then",
    'leer la linea de objeto de un form': r"  I := TRegEx.IsMatch(Doc.Lines[N].Trim, '(?i)^inherited\b');",
    'el literal de cadena de un form a mano': "  T := Ind + 'Caption = ''' + Nombre + '''';",
    'el exe de un renderizador de forms': "  E := ServerDir('DelphiFormRenderVcl.exe');",
    'la orden del renderizador de forms': "  O := '\"' + Exe + '\" --path \"' + P + '\"';",
    'la linea de objeto de un form': "  L := 'object ' + Nombre + ': ' + Clase;",
    'un componente por su ruta en el renderizador': "  C := FindNestedComponent(ARaiz, ANombre);",
    'un flotante de un form': "  V := IntToStr(N) + '.000000000000000000';",
    'el end. de una unidad leido a mano': r"  if TRegEx.IsMatch(T, '(?im)^\s*end\s*\.') then",
    'la cabecera de una unidad leida a mano': r"  M := TRegEx.Match(T, '^\s*(program|library)\b');",
    'la seccion interface/implementation buscada a mano': r"  M := TRegEx.Match(T, '^[ \t]*' + ASec + '\b');",
    'decidir la codificacion de unos bytes': "  if (B[0] = $FF) and (B[1] = $FE) then K := ekUtf16LE;",
    'UTF-8 estricto preguntado a mano': "  if ValidUtf8(B, 0) then K := ekUtf8;",
    'una cadena ASCII preguntada a mano': "  for C in S do if Ord(C) > 127 then Exit(False);",
    'codificar el texto de un fichero para escribirlo': "  B := EncodeText(Texto, K);",
    'la regla de ida y vuelta preguntada a mano': "  if not BytesVuelvenIgual(B, K) then Exit;",
    'las extensiones de un fuente a mano': "  if MatchText(Ext, ['.pas', '.dpr', '.dpk', '.inc']) then X := 1;",
    'las extensiones de un designer a mano': "  if MatchText(TPath.GetExtension(P), ['.dfm', '.fmx']) then X := 1;",
    'una pagina de codigos a mano': "  E := TEncoding.GetEncoding(1252);",
    'fijar la pagina ANSI': "  UsaPaginaAnsi(1251);",
    'las listas crudas de los sitios': "  for R in WorkspaceRoots do",
    'la zona de biblioteca cruda': "  for R in LibraryRoots do",
    'leer sin la puerta': "  Xml := TFile.ReadAllText(Dproj);",
    'escribir sin la puerta': "  TFile.WriteAllText(Ruta, Texto, TEncoding.UTF8);",
    'borrar sin la puerta': "  TFile.Delete(Ruta);",
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

# las otras formas de la lista de designers: las mascaras de Lsp.Rename y de
# delphi_search, el orden inverso y el predicado reescrito (revisor propio
# de la 4.1, 9-oct-2026)
REGLA_DSG = next(r for r in REGLAS if r[0] == 'las extensiones de un designer a mano')
for forma in ("  for E in TArray<string>.Create('*.dfm', '*.fmx') do X := 1;",
              "  M := ['*.pas', '*.fmx', '*.dfm'];",
              "  if MatchText(Ext, DESIGNER_EXTS) then X := 1;",
              "  for var E in DESIGNER_EXTS do if SameText(E, Ext) then X := 1;",
              "  OTRA: array [0 .. 1] of string = ('.dfm', '.fmx');"):
    cazados = fuera_de_casa(REGLA_DSG, [('Plantado.pas', 'unit Plantado;\nimplementation\nprocedure '
                                         'CopiaAMano;\nbegin\n' + forma + '\nend;\nend.\n')])
    check('mutante "%s": tambien %s' % (REGLA_DSG[0], forma.strip()), len(cazados) == 1, cazados)

# las otras formas de leer texto por su cuenta, y la que NO lo es (un
# TMemIniFile vacio que se llena con SetStrings desde la puerta)
REGLA_LEER = next(r for r in REGLAS if r[0] == 'leer sin la puerta')
def leer_plantado(forma):
    return fuera_de_casa(REGLA_LEER, [('Plantado.pas', 'unit Plantado;\nimplementation\nprocedure '
                                       'LeeAMano;\nbegin\n' + forma + '\nend;\nend.\n')])
for forma in ("  L := TFile.ReadAllLines(F);", "  Ini := TMemIniFile.Create(F, TEncoding.UTF8);",
              "  Ini := TIniFile.Create(F);", "  Lista.LoadFromFile(F);", "  R := TStreamReader.Create(F);",
              "  T := DecodeSourceBytes(TFile.ReadAllBytes(F));", "  B := TFile.ReadAllBytes(F);",
              "  S := TFileStream.Create(F, fmOpenRead or fmShareDenyNone);",
              "  S := TFileStream.Create(F, fmShareDenyWrite);", "  S := TFile.OpenRead(F);",
              "  S := TFile.Open(F, TFileMode.fmOpen, TFileAccess.faRead);", "  H := FileOpen(F, fmOpenRead);",
              "  H := CreateFile(PChar(F), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0);"):
    cazados = leer_plantado(forma)
    check('mutante "%s": tambien %s' % (REGLA_LEER[0], forma.strip()), len(cazados) == 1, cazados)
NO_CAZADO = leer_plantado("  Ini := TMemIniFile.Create('');")
check('...y un TMemIniFile vacio (lo llena SetStrings) no es una lectura', not NO_CAZADO, NO_CAZADO)
for forma in ("  S := TFileStream.Create(F, fmCreate);", "  S := TFileStream.Create(F, fmOpenReadWrite);"):
    NO_CAZADO = leer_plantado(forma)
    check('...y un TFileStream para ESCRIBIR no es una lectura (lo caza la regla de escribir): %s'
          % forma.strip(), not NO_CAZADO, NO_CAZADO)

# las otras formas de escribir por su cuenta (y una apertura para LEER, que no)
REGLA_ESCRIBIR = next(r for r in REGLAS if r[0] == 'escribir sin la puerta')
def escribir_plantado(forma):
    return fuera_de_casa(REGLA_ESCRIBIR, [('Plantado.pas', 'unit Plantado;\nimplementation\nprocedure '
                                           'EscribeAMano;\nbegin\n' + forma + '\nend;\nend.\n')])
for forma in ("  TFile.WriteAllBytes(Ruta, B);", "  TFile.Copy(A, B, True);", "  TFile.Move(A, B);",
              "  L.SaveToFile(Ruta);", "  W := TStreamWriter.Create(Ruta);",
              "  S := TFileStream.Create(Ruta, fmCreate);", "  MoveFileEx(PChar(A), PChar(B), 0);",
              "  CopyFile(PChar(A), PChar(B), False);", "  TFile.AppendAllText(Ruta, T);"):
    cazados = escribir_plantado(forma)
    check('mutante "%s": tambien %s' % (REGLA_ESCRIBIR[0], forma.strip()), len(cazados) == 1, cazados)
NO_CAZADO = escribir_plantado("  S := TFileStream.Create(Ruta, fmOpenRead or fmShareDenyNone);")
check('...y un TFileStream para LEER no es una escritura', not NO_CAZADO, NO_CAZADO)
# las que la primera forma no veia (revisor de P3: de 16 plantadas no cazaba ninguna)
for forma in ("  H := CreateFile(PChar(R), GENERIC_WRITE, 0, nil, CREATE_ALWAYS, 0, 0);",
              "  S := TFileStream.Create(Ruta, fmOpenWrite);",
              "  S := TFileStream.Create(Ruta, fmOpenReadWrite or fmShareDenyWrite);",
              "  S := TFileStream.Create(Ruta,\n    fmCreate);",
              "  S := TFile.Create(Ruta);", "  S := TFile.OpenWrite(Ruta);",
              "  W := TFile.CreateText(Ruta);", "  TFile.Replace(A, B, C);",
              "  Ini := TIniFile.Create(Ruta); Ini.WriteString('a', 'b', 'c');",
              "  Ini.UpdateFile;", "  Zip.Open(Ruta, zmWrite);", "  Zip.ExtractAll(Dir);",
              "  H := FileCreate(Ruta);", "  RenameFile(A, B);", "  CopiaNuestra(A, B);",
              "  S := TFile.Open(Ruta, TFileMode.fmOpenOrCreate, TFileAccess.faWrite);"):
    cazados = escribir_plantado(forma)
    check('mutante "%s": tambien %s' % (REGLA_ESCRIBIR[0], ' '.join(forma.split())), len(cazados) == 1, cazados)
NO_CAZADO = escribir_plantado("  H := CreateFile(PChar(R), GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0);")
check('...y un CreateFile para LEER no es una escritura', not NO_CAZADO, NO_CAZADO)

# las otras formas de borrar por su cuenta
REGLA_BORRAR = next(r for r in REGLAS if r[0] == 'borrar sin la puerta')
for forma in ("  System.SysUtils.DeleteFile(Ruta);", "  DeleteFileW(PChar(Ruta));", "  RemoveDir(Dir);",
              "  TDirectory.Delete(Dir, False);", "  RemoveDirectory(PChar(Dir));", "  BorraLoNuestro(Ruta);"):
    cazados = fuera_de_casa(REGLA_BORRAR, [('Plantado.pas', 'unit Plantado;\nimplementation\nprocedure '
                                            'BorraAMano;\nbegin\n' + forma + '\nend;\nend.\n')])
    check('mutante "%s": tambien %s' % (REGLA_BORRAR[0], forma.strip()), len(cazados) == 1, cazados)

for regla in REGLAS:
    malos = fuera_de_casa(regla, TEXTOS)
    check('"%s" solo en su casa - %s' % (regla[0], regla[3]), not malos, '\n      ' + '\n      '.join(malos))

# "Solo puede encoger" (David, 8-oct-2026): una casa declarada en la que el
# formato ya no aparece es una puerta abierta para la proxima copia. La que
# pierde su uso se quita de la lista (y su porque se resuelve), no se excluye.
REGLA_DE_PRUEBA = ('de prueba', r"'zz'", [('Plantado.pas', 'ConUso'), ('Plantado.pas', 'SinUso'),
                                          ('Plantado.pas', 'TCon.Uso'), ('Otro.pas', '*')], '')
PLANTA_CASAS = ("unit Plantado;\nimplementation\nprocedure ConUso;\nbegin\n  X := 'zz';\nend;\n"
                "procedure SinUso;\nbegin\n  X := 'yy';\nend;\nprocedure TCon.Uso;\nbegin\n  X := 'zz';\nend;\nend.\n")
VACIAS = casas_sin_uso(REGLA_DE_PRUEBA, [('Plantado.pas', PLANTA_CASAS), ('Otro.pas', 'unit Otro;\nend.\n')])
check('mutante de la casa sin uso: se cazan la rutina y el fichero sin el formato, y solo esos',
      VACIAS == [('Plantado.pas', 'SinUso'), ('Otro.pas', '*')], VACIAS)
for regla in REGLAS:
    vacias = casas_sin_uso(regla, TEXTOS)
    check('"%s": cada casa declarada tiene uso (la deuda solo puede encoger)' % regla[0], not vacias, vacias)

# Dos sobrecargas de igual aridad que solo difieren en TArray<T> frente a T:
# DelphiLSP fuera de un proyecto no resuelve TArray<string> y revienta con la
# unidad entera (-32603; medido el 8-oct-2026, vault, decisions/delphilsp-
# sobrecargas-sin-proyecto: lo hizo WalkFiles de la 1.13.1 a la 1.17.0). Los
# agentes leen copias sueltas con delphi_symbols: en nuestras unidades no entra
# ninguna pareja asi (regla de la casa, punto 4 del rojo de S1, 1.18.0).
RX_RUTINA = re.compile(r'(?is)\b(?:function|procedure)\s+([\w.]+)\s*\(([^()]*)\)\s*(?::\s*[^;]+)?;'
                       r'((?:\s*(?:overload|virtual|override|static|inline|stdcall|cdecl|reintroduce|'
                       r'abstract|dynamic|register|safecall|deprecated|platform|experimental)\s*;)*)')
def tipos_de(params):
    tipos = []
    for grupo in params.split(';'):
        if ':' not in grupo:
            continue
        nombres, tipo = grupo.split(':', 1)
        tipo = re.sub(r'\s+', '', tipo.split('=')[0]).lower()
        nombres = re.sub(r'(?i)^\s*(?:const|var|out|constref)\s+', '', nombres)
        tipos += [tipo] * len([n for n in nombres.split(',') if n.strip()])
    return tuple(tipos)
def parejas_tarray(ficheros_texto):
    malas = []
    for f, t in ficheros_texto:
        firmas = {}
        for m in RX_RUTINA.finditer('\n'.join(codigo(t))):
            if 'overload' not in m.group(3).lower():
                continue
            firmas.setdefault(m.group(1).split('.')[-1].lower(), set()).add(tipos_de(m.group(2)))
        for nombre, fs in firmas.items():
            fs = sorted(fs)
            for i, a in enumerate(fs):
                for b in fs[i + 1:]:
                    if len(a) != len(b):
                        continue
                    distintas = [(x, y) for x, y in zip(a, b) if x != y]
                    if distintas and all(x == 'tarray<%s>' % y or y == 'tarray<%s>' % x for x, y in distintas):
                        malas.append('%s %s: %s / %s' % (os.path.basename(f), nombre, a, b))
    return malas
PLANTA_TARRAY = ('unit Plantado;\ninterface\n'
                 'function WalkFiles(const ADir: string; const AMasks: TArray<string>;\n'
                 '  AConPapelera: Boolean = False): TArray<string>; overload;\n'
                 'function WalkFiles(const ADir, AMask: string;\n'
                 '  AConPapelera: Boolean = False): TArray<string>; overload;\n'
                 'function Otra(const A: string; B: Integer): string; overload;\n'
                 'function Otra(const A: TArray<string>): string; overload;\n'
                 'implementation\nend.\n')
PLANTADAS = parejas_tarray([('Plantado.pas', PLANTA_TARRAY)])
check('mutante de las sobrecargas TArray<T>/T: la pareja de WalkFiles se caza, la de distinta aridad no',
      len(PLANTADAS) == 1 and 'walkfiles' in PLANTADAS[0], PLANTADAS)
MALAS = parejas_tarray(TEXTOS)
check('ninguna unidad tiene dos sobrecargas de igual aridad que solo difieran en TArray<T> frente a T '
      '(DelphiLSP revienta con ellas fuera de un proyecto)', not MALAS, MALAS)

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

# ---- LAS BATERIAS TAMBIEN (2.3 de la 1.18.0): los formatos que tests/*.py
# escribia a mano (63 nombres de la papelera, el dia en 6 sitios, el cajon de
# lo borrado en 7). Una comprobacion de AUSENCIA con el formato a mano pasa en
# verde si el servidor lo cambia. Casas: (fichero, marca) - la linea que la
# lleva, o la funcion (def) cuya cabecera la lleva. Fuera: esta bateria (sus
# reglas y mutantes SON los formatos) y release_check (el arnes del ritual,
# que no importa mcp_cliente: anotado para David).
FUERA_PY = ('test_paisaje.py', 'release_check.py')
REGLAS_PY = [
    ('el nombre de la papelera a mano', r"""(['"])__delphi-patch\1""",
     # fija a proposito la constante del fuente del servidor
     [('test_round44.py', 'BACKUP_SUB =')],
     'mc.PAPELERA, leido de BACKUP_SUB (Lsp.Casa)'),
    ('el dia de la papelera a mano', r"""strftime\(\s*['"]%Y%m%d['"]""",
     [('mcp_cliente.py', 'def dia_de_papelera')],
     'mc.dia_de_papelera, como NombreDeDia del servidor'),
    ('el cajon de lo borrado a mano', r"""os\.path\.join\([^)]*['"]deleted['"]""", [],
     'mc.CAJON_BORRADOS, leido de Lsp.Patch'),
]


def codigo_py(texto):
    """Las lineas de un .py sin comentarios ni docstrings (numeracion intacta)."""
    out, en_doc = [], False
    for l in texto.split('\n'):
        cuenta = l.count('"""') + l.count("'''")
        if en_doc or cuenta:
            if cuenta % 2 == 1:
                en_doc = not en_doc
            out.append('')
            continue
        out.append('' if l.lstrip().startswith('#') else l)
    return out


def fuera_de_casa_py(regla, ficheros_texto):
    _, formato, casas, _ = regla
    rx = re.compile(formato)
    malos = []
    for f, texto in ficheros_texto:
        base = os.path.basename(f)
        lineas = codigo_py(texto)
        crudas = texto.split('\n')
        for n, l in enumerate(lineas):
            if not rx.search(l):
                continue
            cabecera = next((crudas[k] for k in range(n, -1, -1) if crudas[k].startswith('def ')), '')
            if not any(base == cf and (marca in crudas[n] or marca in cabecera) for cf, marca in casas):
                malos.append('%s:%d %s' % (base, n + 1, l.strip()[:90]))
    return malos


TEXTOS_PY = [(f, open(f, encoding='utf-8', errors='replace').read())
             for f in glob.glob(os.path.join(REPO, 'tests', '*.py')) if os.path.basename(f) not in FUERA_PY]
check('las baterias se leen (al menos 100 .py)', len(TEXTOS_PY) >= 100, len(TEXTOS_PY))
PLANTADO_PY = {
    'el nombre de la papelera a mano': "    d = os.path.join(base, '__delphi-patch')",
    'el dia de la papelera a mano': "    hoy = time.strftime('%Y%m%d')",
    'el cajon de lo borrado a mano': "    c = os.path.join(pap, dia, 'deleted', 'x')",
}
for regla in REGLAS_PY:
    nombre = regla[0]
    planta = ('def copia_a_mano():\n    # ' + PLANTADO_PY[nombre] + '\n' + PLANTADO_PY[nombre] + '\n')
    cazados = fuera_de_casa_py(regla, [('plantado.py', planta)])
    check('mutante py "%s": la copia plantada se caza (y el comentario no)' % nombre,
          len(cazados) == 1 and ':3 ' in cazados[0], cazados)
    malos = fuera_de_casa_py(regla, TEXTOS_PY)
    check('"%s" en ninguna bateria - %s' % (nombre, regla[3]), not malos, malos)
mc.fin('paisaje battery')
