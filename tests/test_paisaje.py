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

Deuda declarada (listas negras): ShellArgDenied (metacaracteres) y BorradoDenegado (lugares
protegidos tras su lista blanca de desechables). HazardScan dejo de serlo en la 1.21.2: la puerta
del build es una LISTA BLANCA de elementos (ElementoNoAdmitido) y DANGER_TASKS queda de segunda
barrera y para nombrar el porque de una tarea conocida.
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
# CreateProcess\w*: tambien los lanzadores con nombre propio (CreateProcessConHandles,
# CreateProcessEnContenedor), que desde la 1.11.3 la regla no veia (revisor de
# baterias, 18-oct-2026: cuatro llamadas sin casa)
LANZA = r'\b(?:RunCaptured(?:In|EnContenedor)?|RunDetached|CreateProcess\w*|ShellExecute\w*)\s*\('

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
      ('Lsp.Styles.pas', 'CorreStyleConvert'),
      # brcc32 del build de estilos, DENTRO del AppContainer (2al de la 1.18.2):
      # el lanzado se movio aqui desde BuildStyles (antes compilaba el .rc directo)
      ('Mcp.Tools.Styles.pas', 'CompilaRcEnContenedor'),
      ('Lsp.TestRunner.pas', 'CorreEnContenedor'), ('Mcp.Tools.Adb.pas', 'RunAdb'),
      ('Mcp.Tools.Git.pas', 'GitCorre'), ('Lsp.FormRender.pas', 'CorreRender'),
      # los que la regla no veia hasta el 18-oct-2026: el nucleo de RunCaptured*
      # (con y sin contenedor), el lanzador del AppContainer, el del motor LSP
      # (DelphiLSP.exe) y el ayudante de remote-run que arranca lo pedido
      ('Lsp.BuildRunner.pas', 'RunCore'), ('Lsp.Sandbox.pas', 'CreateProcessEnContenedor'),
      ('Lsp.Transport.Process.pas', 'TLspProcessTransport.Start'), ('McpRunJob.dpr', 'Arrancar')],
     'cada programa externo se lanza desde UN sitio conocido; uno nuevo se revisa aqui'),
    ('lanzar el conversor de estilos', LANZA + r""".*'"' \+ A?Exe \+""",
     [('Lsp.Styles.pas', 'CorreStyleConvert')],
     'CorreStyleConvert (1.16.0: defaults y tobin componian la orden a mano)'),
    ('nombre de un .profile', r"\+\s*'\.profile'",
     [('Lsp.Discovery.pas', 'RutaDePerfil')], 'RutaDePerfil, y NombreDePerfil su inversa (1.16.0)'),
    ('listar los perfiles a mano', r"GetFiles\s*\([^)]*'\*\.profile'",
     [('Lsp.Discovery.pas', 'PerfilesDelIde')],
     'PerfilesDelIde: LA lista de perfiles del IDE, y PerfilDelIde elige de ella (2an de la 1.18.2: '
     'cuatro listados a mano en set-profile, profiles, add-profile y reseat; el build pasaba a msbuild '
     'el perfil del .dproj sin juez)'),
    ('listar los SDK a mano', r"GetFiles\s*\([^)]*'\*\.sdk'",
     [('Lsp.Discovery.pas', 'SdksDelIde')],
     'SdksDelIde: LA lista de los .sdk del IDE (punto 4 de la 1.18.2: seis GetFiles a mano en el '
     'build, adb, profiles, seat-sdk, HasProfileFor y los sysroots de la puerta; HasProfileFor '
     'buscaba el nombre de la plataforma en todo el texto en vez de su Profile_platform)'),
    ('leer un designer binario a mano', r"(?<!function )DesignerFileToText\s*\(",
     [('Lsp.Patch.pas', 'TextoDeDesigner')],
     'TextoDeDesigner: EL texto de un designer, binario o de texto, por la puerta de leer (W4 del '
     'revisor de cierre de la 1.18.2: cinco sitios lo hacian a mano y el juicio de lo escrito leia un '
     'binario como texto y no juzgaba nada)'),
    ('la nota de codificacion de un form a mano', r"(?<!function )\b(?:NotaDeFormAncho|NotaDeUtf8SinBomDe)\s*\(",
     [('Lsp.Patch.pas', 'NotaDeCodificacionDeForm')],
     'NotaDeCodificacionDeForm: LA nota de codificacion de un form (ancho, DSGN-121, o UTF-8 sin BOM, '
     'READ-009) para lint, los escritores del disenador, preview y el lint de delphi_edit/tanda/changeset '
     '(W9 del revisor de cierre de la 1.18.2: tres emisores, dos sin READ-009)'),
    ('listar una carpeta sin saber si se dejo', r"TDirectory\.GetFileSystemEntries\s*\(",
     [('Lsp.Guard.pas', 'EntradasDeCarpeta'),
      ('Mld.Sesion.pas', 'PrimerSocketPropio'), ('Mld.X11.pas', 'TOjos.Diagnostico')],
     'EntradasDeCarpeta: la RTL da por VACIA una carpeta que Windows no deja listar (FindFirst falla y '
     'WalkThroughDirectory no dice nada): la puerta de los metadatos la pasaba, la copia la copiaba vacia '
     'contestando COPIED y la purga borraba a medias (2g de la 1.18.x). El nodo de Linux, aparte: alli no '
     'hay FindFirstFile y sus dos usos toleran el vacio'),
    ('listar ficheros o carpetas sin saber si se dejo', r"TDirectory\.(?:GetFiles|GetDirectories)\s*\(",
     [(u, '*') for u in ('Lsp.BuildRunner.pas', 'Lsp.Casa.pas', 'Lsp.DesignerMetaGen.pas',
                         'Lsp.Discovery.pas', 'Lsp.Guard.pas', 'Lsp.LogSink.pas', 'Lsp.PackageMap.pas',
                         'Lsp.Patch.pas', 'Lsp.ProjectUnits.pas', 'Lsp.Session.pas', 'Lsp.Styles.pas',
                         'Mcp.Tools.FileOps.pas', 'Mcp.Tools.Messages.pas', 'Mcp.Tools.PAServer.pas',
                         'Mcp.Tools.Report.pas', 'Mcp.Tools.Styles.pas', 'Mcp.Tools.Vault.pas',
                         'Mcp.Tools.Workspace.pas', 'Mcp.Vault.Seed.pas', 'Mld.Sesion.pas', 'Mld.X11.pas',
                         'FormRender.Comun.pas', 'McpRunJob.dpr')],
     'GetFiles y GetDirectories pasan por el MISMO WalkThroughDirectory que GetFileSystemEntries (VACIO si '
     'Windows no deja listar): unos 50 sitios en 24 unidades el 14-oct-2026, todos detras del recorrido '
     'cerrado de la puerta o fuera de la jaula (B2 del cierre de la 1.19.0, medido por el revisor). La lista '
     'SOLO ENCOGE: un sitio nuevo lista por EntradasDeCarpeta o recorre con el guard (RecorreSinEnlaces, '
     'WalkFiles)'),
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
    ('el manifiesto de despliegue a mano', r"'\.deployproj'",
     [('Lsp.Patch.pas', '*')],
     'EXT_MANIFIESTO, EsManifiesto y ManifiestoDe (Lsp.Patch, 1.22.2): tres compositores y tres '
     'reconocedores lo escribian a mano en el build, la mudanza y config'),
    # tambien con la barra delante ('\__delphi-temp\', la forma de los saltos de Lsp.References): esa no la
    # veia y una tercera copia asi entraba sin que nadie la viera (P10 de la revision de Opus 5.5). Las dos
    # lineas declaradas de Lsp.References (un array const no puede llamar a una funcion; las vigila
    # test_round44 T6c/T6f) quedan fuera por su forma, como DESIGNER_EXTS
    ('__delphi-temp', r"^(?!\s*CARPETA_TEMPORAL\s*=).*'\\?__delphi-temp",
     [('Lsp.Casa.pas', 'TempFolderName')], 'la casa del servidor tiene UN nombrador'),
    ('__delphi-patch', r"^(?!\s*'\\__pascal-patch\\',).*'\\?__delphi-patch",
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
    ('la carpeta de los informes o del correo sin el workspace', r'\bCarpetaDe(?:Informes|Mensajes)\b',
     [('Lsp.Casa.pas', '*')],
     'BuzonDeInformes / BuzonDeMensajes: la carpeta del workspace la pone el token (8.5 de la 1.18.0, '
     'David: "la misma estructura separada por workspace"); quien usa la raiz ve lo de todos'),
    ('la raiz de los informes o del correo compuesta a mano', r"ServerDir\(\s*'(?:reports|messages)'",
     [('Lsp.Casa.pas', 'CarpetaDeMensajes'), ('Lsp.Casa.pas', 'CarpetaDeInformes')],
     'CarpetaDeInformes / CarpetaDeMensajes, y por encima el buzon del workspace'),
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
    # LA REGLA de la expansion de ida (B-9, 10-oct-2026; escrita una vez en
    # Lsp.Attributes, ContenidoAttribute): lo que se escribe dentro de un fichero es
    # contenido y no se expande; value, props y state del disenador son la excepcion
    # declarada; lo que no es ruta ni contenido se expande y da igual. Sus casas:
    ('la expansion de ida de una unidad virtual', r'\bExpandDriveValue\s*\(',
     [('Lsp.Mascara.pas', 'ExpandVirtualDrives'),  # la puerta: todo menos [Contenido]
      ('Lsp.Files.pas', 'ServeFile'),              # la ruta de /files, que no es un tools/call
      ('Lsp.DesignerEdit.pas', 'PonEnMemoria'),    # LA EXCEPCION: value y props, valor a valor
      ('Mcp.Tools.Designer.pas', 'PreviewDeForm')],  # ...y el state de preview
     'la puerta expande lo que no lleva [Contenido] y el disenador el TEXTO de cada valor: una '
     'expansion en otro sitio es una excepcion sin declarar (era una lista de nombres, '
     'PARAMS_CON_CONTENIDO, y un value entre comillas llegaba como srvX: al .dfm)'),
    ('la expansion de ida de una llamada con otro predicado', r'\bExpandVirtualDrives\s*\(',
     [('Lsp.Guard.pas', 'ExpandeUnidadesVirtuales')],
     'la puerta expande cada llamada UNA vez, preguntando a las marcas [Contenido]: otra llamada con '
     'otro predicado seria una excepcion sin declarar (revisor de B-9, 10-oct-2026)'),
    ('un paseo del arbol por cada mascara',
     r"for\s+(?:var\s+)?\w+\s+in\s+(?:MascarasDe\(|TArray<string>\.Create\(\s*'\*\.|\[\s*'\*\.)", [],
     'WalkFiles toma VARIAS mascaras y recorre una vez (cada fichero una vez, una purga de la '
     'papelera al pasar): references paseaba tres veces, rename dos y delphi_projects dos (8.3 de la '
     '1.18.0, 10-oct-2026)'),
    # (y la tool en minusculas delante del '|', con la normalizacion que sea: la
    # deriva probable es otra normalizacion, no la misma; revisor de B-9)
    ('la clave tool|parametro de las marcas',
     r"'\|'\s*\+\s*TMCPSerializer\.NormalizeKey|\bLowerCase\([^)]*\)\s*\+\s*'\|'",
     [('Lsp.Guard.pas', 'ClaveDeParam')],
     'ClaveDeParam: la clave de las marcas [RutaDelServidor] y [Contenido], con la normalizacion del '
     'binder; estaba a mano en cuatro sitios de Lsp.Guard (B-9, 10-oct-2026)'),
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
    # quien lee o escribe un form o un estilo POR SUS LINEAS (LineasDeForm) pregunta
    # antes al parser del IDE si las lee igual: un form que el IDE carga, con el '>'
    # de una coleccion en su propia linea, y set escribia un Left nuevo encima (3b
    # del censo de jueces, 18-oct-2026). Las casas que abren sin Lee lo juzgan aparte
    ('un documento de lineas abierto sin su juez', r'\bTStyleDoc\.Create\s*\(',
     [('Lsp.Styles.pas', 'TStyleDoc.Lee'),                    # EL abridor: lee y juzga
      ('Lsp.FormRender.pas', 'LiteralesDeRenderDenegados'),   # la puerta del preview, con su fichero
      ('Lsp.FormRender.pas', 'CorreRender'),                  # lo que dijo el lector de uno que no cargo
      ('Mcp.Tools.Styles.pas', 'LintStyles')],                # el lint dice cual no tiene la forma
     'TStyleDoc.Lee (y FormaDistinta): el parser del IDE, con su SourceLine, dice si las lineas se leen '
     'como las lee LineasDeForm (Lsp.DesignerBin.LineaQueElParserLeeDistinta, DSGN-160)'),
    # el .rc lo leian dos regex de linea (RcPathsDenied y el lint de estilos), cada una
    # con su parte: 'X RCDATA DISCARDABLE "f"' no lo veia ninguna (3c del censo, 18-oct-2026)
    # las listas de Register* (la paleta y, desde el hecho R, el registro al ejecutar)
    # las leia cada lector con su regex: dos gemelas (18-oct-2026, David: "no dupliques reglas")
    # la propiedad que elige las PARTES de un componente ('...ClassName') es gramatica nuestra
    # sin juez (lo decide el setter con GetClass): UNA, declarada (revisor de la 1.20.2)
    # la forma de los atomos del RTL (Vcl.Controls, Vcl.Dialogs, FMX.Platform.Win) que un proceso
    # muerto sin finalizar deja en la tabla global de la sesion: Windows no sabe de quien es un
    # atomo, asi que es gramatica nuestra con UNA casa (la maquina se cayo el 18-oct-2026)
    # la notificacion de cambio de una clave del registro (RegNotifyChangeKeyValue): EL juez de
    # "cambio la configuracion del IDE" para lo que se cachea de ella (la zona de biblioteca,
    # 1.21.4); otra llamada seria otro vigia con otro rearme
    # la clave del IDE en el registro (SOFTWARE\Embarcadero\BDS\<ver>\...) se componia a mano
    # unas 18 veces en cuatro unidades con dos grafias, y dio un bug medido el 9-oct-2026
    # (SysrootsRegistrados); D9 de la auditoria de duplicados, cerrado en la 1.21.4
    ('la clave del IDE en el registro', r'Embarcadero\\+BDS',
     [('Lsp.Discovery.pas', 'ClaveDelIde'),
      # otro programa: el renderizador de forms no lleva Lsp.Discovery (sus dos lecturas)
      ('FormRender.Comun.pas', 'RaizDelIde'), ('FormRender.Comun.pas', 'LeeConocidos'),
      # ...y sus textos (el Lsp.Texts del renderizador): un mensaje la nombra, no la compone
      ('FormRender.Textos.pas', '*')],
     'ClaveDelIde (Lsp.Discovery): la raiz, la de una version o una subclave; quien la quiera '
     'absoluta le pone la barra delante'),
    # la rama ABSOLUTA de una entrada de sitio (la unidad a secas o la ruta -> GetFullPath, letra,
    # barra final, o rechazada) la tenian ParseRootsList y ParseReadOnlyList cada una (D5 de la
    # auditoria de duplicados, 1.21.4): configuracion + jaula = UN lector. Lsp.Rutas canonicaliza
    # rutas con la misma forma (otra pregunta: no una entrada declarada), y VaultNormalizado es la
    # del VaultPath, que no es un sitio de la jaula
    ('la rama absoluta de una entrada de sitio', r'GetFullPath\(\s*RaizSiUnidad\(',
     [('Lsp.Settings.pas', 'EntradaAbsolutaDeSitio'), ('Lsp.Settings.pas', 'VaultNormalizado'),
      ('Lsp.Rutas.pas', '*')],
     'EntradaAbsolutaDeSitio (Lsp.Settings): la forma con la que la jaula compara se mantiene en UN '
     'sitio, no a mano en cada lista'),
    # el significado de old/new (old dado = ancla; con new vacio = linea en blanco) estaba en los dos
    # gemelos y en sus dos tandas, donde ya vivio el bug de occurrence (D7 de la auditoria, 1.21.4)
    ('el significado de old/new', r'HasNew\s*:=\s*\(',
     [('Lsp.Patch.pas', 'SignificadoDeOldNew')],
     'SignificadoDeOldNew (Lsp.Patch): UNA regla para delphi_edit, delphi_textedit y sus tandas'),
    # ...y la escalera de lo que choca con fragment (old, delete, toline, los modos propios), que
    # estaba en ExecutePatch, en TextEditNucleo y en la tanda (D7)
    ('lo que choca con fragment', r"then\s+\w+\s*:=\s*'old'",
     [('Lsp.Patch.pas', 'OtroModoConFragmento')],
     'OtroModoConFragmento (Lsp.Patch): la escalera, con los modos propios de quien llama ya decididos'),
    # la cadena de ancestros por el motor la recorrian tres bucles con su cuenta y su tope (8 o 20):
    # el disenador (NombresHeredados, ClaseDeJuezDeRaiz) y references (D2 de la auditoria, 1.21.4)
    ('la cadena de ancestros por el motor', r'\bAncestroDe\s*\(',
     [('Lsp.Herencia.pas', 'TCadenaPorElMotor.Siguiente')],
     'TCadenaPorElMotor.Siguiente (Lsp.Herencia): EL recorredor, con TOPE_SALTOS; quien recorre decide '
     'que hacer en cada salto, no cuantos dar'),
    # la puerta de escritura del vault (hay vault, se deja escribir, resuelve dentro, no es de
    # gobierno) estaba a mano en append, create y patch (D6 de la auditoria de duplicados, 1.21.4)
    ('la puerta de escritura del vault', r'\bVaultGovernance\s*\(',
     [('Mcp.Tools.Vault.pas', 'VaultEscrituraDenegada')],
     'VaultEscrituraDenegada (Mcp.Tools.Vault): la EscrituraDenegada del vault; la cuarta tool que '
     'escriba la llama, no copia los cuatro pasos'),
    ('vigilar una clave del registro', r'\bRegNotifyChangeKeyValue\s*\(',
     [('Lsp.Discovery.pas', 'ArmaVigia')],
     'ArmaVigia (Lsp.Discovery): VigilaClave abre y arma, CambioLaClave pregunta y rearma; quien cachea '
     'algo del registro del IDE pregunta a su vigia, ni relee por llamada ni cachea para siempre'),
    ('la forma de los atomos del RTL', r"'(?:ControlOfs|WndProcPtr|FIREMONKEY%|Delphi%\.8X)'",
     [('Lsp.AtomosRtl.pas', '*')],
     'Lsp.AtomosRtl: los atomos globales que deja un proceso VCL/FMX muerto sin finalizar (llena la tabla, '
     'Windows no arranca ningun proceso: 0xC0000142); lo que matamos, lo limpiamos ahi'),
    ('la propiedad que elige las partes de un componente', r"EndsWith\('ClassName'",
     [('Lsp.FormRender.pas', 'PartesDeClaseNoInstalada')],
     'PartesDeClaseNoInstalada (Lsp.FormRender): lo saltado bajo las partes de una clase que la tabla '
     'no tiene no se confirma (DSGN-154/163)'),
    ('el argumento de una llamada a Register* leido a mano', r"\\s\*\\\(\(\.\*\?\)\\\)\\s\*;",
     [('Lsp.DesignerMetaGen.pas', 'NombresRegistrados')],
     'NombresRegistrados (Lsp.DesignerMetaGen): EL lector del argumento de una llamada Register* '
     '(RegistradosEnPaleta y RegistradasAlEjecutar solo le dan el nombre de la rutina)'),
    ('un .rc leido a mano', r"'[^']*(?i:rcdata|rcinclude|#include)[^']*'",
     [('Lsp.Styles.pas', 'LeeRc')],
     'LeeRc (Lsp.Styles): EL lector del .rc, por tokens como brcc32; la segunda barrera y el lint le '
     'preguntan (la puerta es brcc32 en su contenedor)'),
    ('el recorrido del parser con sus lineas', r'\.SourceLine\b',
     [('Lsp.DesignerBin.pas', 'LineaQueElParserLeeDistinta')],
     'LineaQueElParserLeeDistinta: EL juez de la forma de las lineas de un form, el recorrido de '
     'ObjectTextToBinary con el TParser del IDE; otro recorrido seria otro juez'),
    ('un literal de form leido a mano',
     r"Trim\(\s*\[\s*''''\s*\]\s*\)|StartsWith\(\s*''''\s*\)\s*and\s*[\w.]+\.EndsWith\(\s*''''\s*\)", [],
     'LeeLiteralDeForm / NombreDeValor (Lsp.DesignerBin): .Trim([\'\'\'\']) en los estilos y las comillas '
     'quitadas a mano en el renombrado no leian ni #N ni trozos (revision de la 1.17.0; P5)'),
    # sin casa desde el 18-oct-2026: la regex de EsNumeroDeForm / EsEnteroDeForm (la de
    # ValidStyleValue y la del entero del juez eran copias, y aceptaron -$FF; segunda
    # revision de la 1.17.0) no veia los sufijos con que el IDE escribe un TDate, un Single o
    # un Currency (DSGN-092 en un 41500.5d que se escribe por codigo; lote 3 del censo)
    ('la gramatica de un numero de un form', r"\\d\+\(\?:\\\.\\d\+\)\?|\\\$\[0-9A-Fa-f\]\+", [],
     'TipoDeValorDeForm (Lsp.DesignerBin): el parser del IDE y el tipo con que deja el valor; '
     'EsNumeroDeForm, EsEnteroDeForm y EsNumeroDeFloat le preguntan'),
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
    ('el end. de una unidad leido a mano', r"end(?:\\s\*|\[ \\t\]\*)?\\\.|(?:=|SameText\([^)]*,)\s*'end\.'",
     [('Lsp.Pascal.pas', 'EndsConPunto')],
     'EndsConPunto (Lsp.Pascal): eran siete sitios con dos ortografias (laxa "end\\s*\\." y '
     'estricta "end\\." sola en su linea); la estricta daba BROKEN STRUCTURE sobre un '
     '"program P; begin end." que compila (inventario y sonda del 10-oct-2026)'),
    ('la cabecera de una unidad leida a mano',
     r"\((?:\?:)?(?:unit\|)?(?:program|library)\||\^\\s\*\(?(?:unit|program|library|package)\b|"
     r"StartsWith\(\s*'(?:unit|program|library|package) '|(?<!Palabra )(?<!Kind )=\s*'(?:program|library|package)'",
     # (Palabra = '...' es quien consume la respuesta de CabeceraDeFuente; Kind, el tipo de proyecto)
     [('Lsp.Pascal.pas', 'CabeceraDeFuente'),
      # el PARSER de declaraciones (la gramatica de la casa, una) lee sus tokens; las
      # posiciones para escribir son de CabeceraDeFuente (revisor 8, 10-oct-2026)
      ('Lsp.PascalDecl.pas', 'TLectorPas.Lee')],
     'CabeceraDeFuente (Lsp.Pascal): eran cinco lectores de unit/program/library/package - solo '
     'FindUses veia package, solo CabeceraDeUnit daba posicion, ExecutePatch la queria en una linea '
     '(inventario del 10-oct-2026; una casa desde el mismo dia)'),
    ('la seccion interface/implementation buscada a mano',
     r"'\^(?:\[ \\t\]\*|\\s\*)'\s*\+\s*\w+\s*\+\s*'\\b'|\^(?:interface|implementation)\[ \]\*\$|"
     r"\.Trim\.ToLower\s*=\s*'(?:interface|implementation)'",
     [('Mcp.Tools.DelphiLsp.pas', 'InterfaceDigest'), ('Lsp.Patch.pas', 'ExecutePatch')],
     'FinDeSeccion (Lsp.ProjectUnits): la palabra entera en el codigo, este donde este (estaba cinco '
     'veces en tres funciones de ProjectUnits; a principio de linea hasta el 18-oct-2026, y una unit de '
     'una linea no tenia seccion). DEUDA declarada: la linea exacta (InterfaceDigest) y la linea que es '
     'la palabra (ExecutePatch, la frontera del insert; la vio el revisor 7), dos reglas mas para lo '
     'mismo (inventario del 10-oct-2026)'),
    ('la forma canonica de una ruta preguntada a Windows',
     r'\bGet(?:LongPathName|FinalPathNameByHandle)\w*\s*\(',
     [('Lsp.Rutas.pas', 'LongCanonical'), ('Lsp.Rutas.pas', 'NombreFinal'),
      # el lanzador que viaja al destino compara el binario de un proceso con SU
      # carpeta; solo enlaza Lsp.ProcessLaunch del servidor (Lsp.Rutas traeria el
      # log y el catalogo de mensajes): declarado, y solo puede encoger
      ('McpRunJob.dpr', 'RutaLarga')],
     'Lsp.Rutas: la forma larga (LongCanonical) y la del final de los enlaces (NombreFinal), en UN '
     'sitio; dos formas de la misma raiz a la vez rompieron "es la raiz?" y la raiz del workspace '
     'quedo borrable (20-sep-2026). Regla desde el 10-oct (11.5): el inventario del 8-oct miro solo '
     'src/Server y no vio la del lanzador'),
    ('decidir la codificacion de unos bytes',
     r'\bGetBufferEncoding\b|\$FF\b[^;]*\$FE\b|\$FE\b[^;]*\$FF\b|\$EF\b[^;]*\$BB\b|\$BB\b[^;]*\$BF\b',
     # (EncodeText escribe el BOM byte a byte, una forma que esta regla no ve: 2.1g)
     # (EL lector del BOM del principio, KindDeBom, lo preguntan DetectEnc y el
     # lector de settings.ini, que no puede usar Patch: 9.2 de la 1.18.0)
     [('Lsp.Codificacion.pas', 'KindDeBom'), ('Lsp.Codificacion.pas', 'BomUtf8En'),
      # deuda declarada (2.1g de la 1.18.0): un detector suelto, el de los renderizadores,
      # que no enlazan la casa (Lsp.Codificacion arrastra Lsp.Texts); solo puede encoger.
      # (el de la ayuda se fue en r5: pregunta BomUtf8En y CodecDeCharset)
      # Desde M2 (punto 4 de la 1.18.2) es EL alimentador del parser de forms,
      # FormParaElParser, que usan DesignerAFlujo y to-binary: la misma deuda
      ('Lsp.DesignerForma.pas', 'FormParaElParser')],
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
      # el texto de un form en los bytes que se le dan al parser del IDE, para
      # PREGUNTARLE si lo lee (9.B de la 1.18.0) o para convertir un UTF-32 a
      # binario (R1 del punto 4 de la 1.18.2); no escribe nada. Una casa: lint y
      # to-binary la tenian cada uno (run_all de la 1.18.2 lo cazo)
      ('Lsp.DesignerBin.pas', 'TextoParaElParser'),
      # el volcado de logcat a un out= del agente: texto del DISPOSITIVO, laxo, en
      # UTF-8 con BOM, antes de colocarlo con ColocaContenido (la puerta del
      # producto); lo componia a mano con TEncoding (punto 4 de la 1.18.2)
      ('Mcp.Tools.Adb.pas', 'TDelphiAdbTool.ExecuteWithParams')],
     'quien codifica el texto de un fichero por su cuenta se salta la regla de ida y vuelta y la '
     'del primer caracter no ASCII (David, 9-oct-2026): se escribe por PatchSaveText o DoEdit'),
    ('la regla de ida y vuelta preguntada a mano',
     r'\bBytesVuelvenIgual\s*\(|\bSR_EDIT_BYTES_NO_VUELVEN_FMT\b|\bSR_EDIT_SE_LEERIA_DISTINTO_FMT\b',
     [('Lsp.Patch.pas', 'ReescrituraDenegada'),
      # su lado de la escritura: lo que se escribe se lee igual (EDIT-122)
      ('Lsp.Patch.pas', 'LecturaCambiada'),
      # delphi_read la pregunta para AVISAR (READ-007), no para escribir
      ('Lsp.Patch.pas', 'NotaDeIdaYVuelta'),
      # una URI del motor: si sus bytes se leen SIN perdida; la lectura laxa daria
      # la misma forma a dos uris rotas distintas al compararlas (1.18.2). No escribe
      ('Lsp.Client.pas', 'TLspClient.UriCanonica')],
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
     # (la deuda de delphi_references -*.pas, *.dpr e *.inc SIN .dpk- se pago en el punto 8
     # de la 1.18.2: recorre MascarasDe(SOURCE_EXTS))
     [('Lsp.Patch.pas', 'EsRutaDeFuente')],
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
    ('las extensiones de un proyecto del IDE a mano',
     # la lista de lo que mantiene el IDE (.dproj, .groupproj) salvo la declaracion de
     # PROJECT_EXTS, o el predicado reescrito con ella: el changeset llevaba la suya CON el
     # .dpk, que es un fuente, y negaba apilarlo diciendo que el commit lo negaria
     # (18-oct-2026). Una comparacion con '.groupproj' sola (es un grupo?) es otra pregunta
     r"^(?!\s*PROJECT_EXTS\s*:).*'\*?\.(?:dproj|groupproj)'\s*,\s*'\*?\.(?:dproj|groupproj)'|"
     r"MatchText\s*\([^;]*\bPROJECT_EXTS\s*\)|\bin\s+PROJECT_EXTS\b",
     [('Lsp.Patch.pas', 'EsRutaDeProyecto')],
     'EsRutaDeProyecto (Lsp.Patch): lo que lleva delphi_config y ni delphi_edit, ni delphi_textedit, '
     'ni el changeset escriben'),
    ('una cadena ASCII preguntada a mano', r'\bOrd\s*\(\s*\w+\s*\)\s*>\s*127\b',
     [('Lsp.Codificacion.pas', 'IsAscii')],
     'IsAscii (Lsp.Codificacion): estaba en Lsp.TextEdit y en linea en NombreQueElFicheroNoLee, y '
     'to-binary iba a por la tercera (4.1 de la 1.18.0)'),
    ('una pagina de codigos a mano',
     r'GetEncoding\s*\(|TEncoding\.(?:ANSI|Default)\b|\bGetACP\b|TMBCSEncoding\.Create\s*\(',
     [('Lsp.Codificacion.pas', '*'),
      # el codec de la pagina en que escribe un hijo en su tuberia: la OEM de la
      # CONSOLA (GetConsoleOutputCP, o GetOEMCP sin consola), otro juez y otra pagina,
      # o la ANSI, que pregunta a PaginaAnsi (salio de RunCore en la 1.22.1 para leer
      # git linea a linea)
      ('Lsp.BuildRunner.pas', 'DecodificaHijo')],
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
      ('Lsp.Guard.pas', 'ArgPathOutsideDenied'),
      ('Lsp.Guard.pas', 'InVault'), ('Lsp.Guard.pas', 'JaulaDecide'), ('Lsp.Guard.pas', 'NegativaDeUnc'),
      ('Lsp.Guard.pas', 'LugaresProtegidos'), ('Lsp.Guard.pas', 'PurgeServerTemp'),
      ('Lsp.Guard.pas', 'PathDenied'), ('Lsp.Guard.pas', 'RaicesDisponibles'),
      ('Lsp.Guard.pas', 'RaizEnLetraNoConectada'), ('Lsp.Guard.pas', 'ReadOnlyRootOf'),
      ('Lsp.Guard.pas', 'RootItselfDenied'), ('Lsp.Guard.pas', 'RutaRelativaDenegada'),
      ('Lsp.Mascara.pas', 'ServedDriveLetters'), ('Lsp.Guard.pas', 'UncFueraDeLugares'),
      ('Lsp.BuildRunner.pas', 'UnitSourceFolders'), ('Lsp.ProjectUnits.pas', 'BordeDeMudanza'),
      ('Lsp.References.pas', 'ProjectsSearching'), ('Lsp.Session.pas', 'TLspSession.FindDproj'),
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
     # BYTES de la jaula que la tool ya comprobo (delphi_fetch, el zip de delphi_package,
     # la descarga). La captura y su recorte ya van por la puerta (1.18.2, 2b)
     ('Mcp.Tools.Workspace.pas', 'TDelphiFetchTool.ExecuteWithParams'),
     ('Mcp.Tools.Workspace.pas', 'TDelphiPackageTool.ExecuteWithParams'),
      ('Lsp.Files.pas', 'ServeFile'),
      # el RECLAMO de una captura nuestra antes de entregarla por su enlace: apertura
      # EXCLUSIVA (CreateFile GENERIC_READ, sin compartir, borrado al cerrar) y lectura
      # por el handle de lo que su nombrador ya juzgo (CapturaConsumible); hermano de
      # ConsumeAgentCapture (2am de la 1.18.2: MoveFile daba TRUE a varios GET a la vez)
      ('Lsp.Guard.pas', 'ReclamaCaptura'),
      # programas que NO son el servidor: los renderizadores y el conversor leen lo que
      # el servidor ya paso por su puerta; el nodo y el lanzador corren en el destino
      ('FormRender.Comun.pas', 'Cabecera'), ('FormRender.Comun.pas', 'AncestroDeClase'),
      # (la gemela de AncestroDeClase para una vista FMX: el .pas del maestro, 18-oct-2026)
      ('FormRender.Comun.pas', 'MaestroDeVista'),
      ('FormRender.Comun.pas', 'TCargador.LeeUno'), ('FormRender.Fmx.pas', 'AplicaEstilo'),
      ('FormRender.Vcl.pas', 'Main'), ('DelphiStyleConvert.dpr', 'Entrada'),
     # los OLFATEADORES: la cabecera de lo que la tool ya juzgo (4 bytes de un designer o
     # de un estilo, el BOM de un form; el tamano de un PNG ya sale de sus bytes, 2b)
     ('Lsp.DesignerBin.pas', 'IsBinaryDesignerFile'), ('Lsp.Styles.pas', 'IsBinaryStyle'),
     # (FormAncho bajo a Lsp.DesignerBin en B1 de la 1.18.2: la usan tambien la tanda y
     # el changeset, sobre forms que ya pasaron su puerta; la misma, no una mas)
     ('Lsp.DesignerBin.pas', 'FormAncho'),
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
     ('Lsp.TodoONada.pas', 'TFotoDeFicheros.CambioEn'),  # la de Cambiados, movida (W2 de la 1.18.2)
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
      # la restauracion de la foto va por la puerta (EscribeBytes) salvo
      # una ruta que no cabe con el temporal del escritor (GUARD-028): directa, ya
      # aprobada por EscrituraDenegada, porque no devolverla perdia el fichero
      # (revisor de la noche del 10-oct, A-1)
      ('Lsp.TodoONada.pas', 'TFotoDeFicheros.Restaura'),
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
     r"\bRemoveDirectory\w*\s*\(|\bBorraLoNuestro\s*\(|\bBorraNombre\s*\(",
     [# LA puerta de borrar fuera de la jaula (BorraFichero) y los temporales que los
      # escritores acaban de dejar (el suyo, la copia que no se llego a usar)
      ('Lsp.Patch.pas', 'BorraFichero'), ('Lsp.Patch.pas', 'EscribeBytes'),
      ('Lsp.Patch.pas', 'SustituyePorRenombre'), ('Lsp.Patch.pas', 'Coloca'),
      # la jaula: su borrado de lo que la operacion acaba de dejar, sus recorredores
      # (no cruzan enlaces; la puerta antes), la papelera y el deshacer
      # BorraNombre: borra un NOMBRE sin tocar los atributos del fichero (un enlace
      # duro de fuera los compartia: 11-oct y 20-oct-2026); su TFile.Delete es el
      # respaldo donde el sistema de ficheros no conoce la disposicion Ex
      ('Lsp.Guard.pas', 'BorraNombre'),
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
    # (las tres de abajo, del revisor de version de la 1.18.0: la de escribir no las veia)
    ('mover o copiar un arbol con la RTL', r"TDirectory\.(?:Move|Copy)\s*\(",
     [],
     'TDirectory.Move siguio cada union de dentro, copio lo de detras a la jaula y BORRO los originales '
     '(25-sep-2026): un arbol se mueve renombrando la carpeta (MueveArbol) y se copia sin cruzar enlaces '
     '(CopiaArbol); las funciones de arbol de la RTL no pertenecen al servidor (CLAUDE.md)'),
    ('crear una carpeta sin la puerta',
     r"\bForceDirectories\s*\(|\bCreateDir\s*\(|TDirectory\.CreateDirectory\s*\(|\bCreateDirectory\w*\s*\(",
     [('Lsp.Guard.pas', 'CrearCarpeta')],
     'CrearCarpeta (Lsp.Guard): crear una carpeta tolerando la carrera, detras de la puerta de quien la '
     'pide; otra que la creara por su cuenta seria otra puerta'),
    ('atributos o fechas sin la puerta',
     r"\bSetFileAttributes\w*\s*\(|TFile\.SetAttributes\s*\(|\bSetFileTime\s*\(|"
     r"TFile\.Set(?:CreationTime|LastWriteTime|LastAccessTime)\w*\s*\(",
     [('Lsp.Guard.pas', 'QuitaSoloLectura'), ('Lsp.Guard.pas', 'BorraArbolDentro'),
      ('Lsp.TodoONada.pas', 'TFotoDeFicheros.Restaura'),
      ('Lsp.Patch.pas', 'PonFechaDeCreacion')],
     'Cambiar un atributo o una fecha ESCRIBE: los de hoy van detras de la puerta de su operacion (el +R '
     'de lo propio, restaurar una foto, la fecha de creacion de lo que el escritor acaba de sustituir); '
     'uno nuevo se revisa aqui'),
    # la firma (en literal o byte a byte, entera o sus letras) y el ancho y alto del IHDR
    # leidos de sus bytes 16..23
    ('la cabecera de un PNG',
     r"\$89\s*[,;]|Ord\('P'\)[^;\n]*Ord\('N'\)|\[\s*(?:1[6-9]|2[0-3])\s*\]\s*shl\s*(?:24|16|8)\b",
     [('Lsp.Png.pas', '*')],
     'Lsp.Png: la firma, los datos del IHDR y su lector, uno inverso del otro, para el servidor y el '
     'nodo (David, 11-oct-2026: "leer un png no lo vamos a desperdigar"; eran el escritor del nodo y '
     'dos lectores, uno con la firma entera y otro con sus tres letras)'),
    # 2an de la 1.18.2: el build iba por cmd.exe /c "rsvars.bat && msbuild ..." en la carpeta
    # del proyecto, y cmd busca 'msbuild' PRIMERO ahi: un msbuild.bat del agente corria con la
    # cuenta del servicio (medido el 13-oct contra produccion). No es una prohibicion: el
    # servidor ejecuta lo que necesite (David: "internamente podemos ejecutar lo que nos
    # convenga, es el agente el que no debe poder"), pero un shell nuevo se declara aqui con su
    # porque: que nada del agente decida que corre ni como
    # ...y no solo cmd: los otros interpretes de Windows (revisor de baterias,
    # 18-oct-2026: la regla solo conocia cmd y ComSpec)
    ('lanzar un shell', r"\bcmd(?:\.exe)?\s+/[cCkK]\b|\bcmd\.exe\b|\bComSpec\b|"
                        r"\b(?:powershell|pwsh|wscript|cscript|bash|mshta)(?:\.exe)?\b|\bsh\.exe\b",
     [],
     'Ningun shell en el servidor sin casa declarada: un shell busca en su carpeta actual, expande '
     'variables y lee metacaracteres, y es donde mas cuesta que nada del agente decida que se ejecuta. '
     'msbuild va por su ruta (Lsp.ProcessLaunch.ProgramaEnPath), sin cmd (2an de la 1.18.2)'),
    # git por su RUTA (1.19.0): se lanzaba 'git.exe ...' por su nombre, y a un nombre sin
    # carpeta CreateProcess lo busca PRIMERO en la carpeta del exe y en la ACTUAL del
    # proceso (por stdio, la de quien lanza el servidor: el repo del agente); medido el
    # 14-oct con una sonda inerte (test_git_por_ruta_119). Todo programa, por su ruta
    ('lanzar un programa por su nombre a secas', LANZA + r"\s*'[A-Za-z][\w.-]*(?:\.exe)?[ ']",
     [],
     'Ningun programa por su nombre: su ruta completa, encontrada donde el agente no escribe '
     '(ProgramaEnPath en el PATH del servidor, o la del IDE), y entre comillas (git.exe a secas '
     'hasta la 1.19.0, medido con una sonda inerte el 14-oct)'),
    # ...y tampoco COMPUESTA en una cadena que luego se lanza (GitLinea devolvia 'git.exe -c ...')
    ('una orden que empieza por un programa a secas',
     r"'(?:git|msbuild|cmd|paclient|adb|dcc\w*|brcc\w*|rsvars)(?:\.exe|\.bat)?\s+[-/\w\"]",
     [],
     'Una orden se compone con la RUTA del programa entre comillas (EnComillas(RutaDeGit) + ...), '
     'nunca con su nombre a secas al principio: quien la lance la buscaria en su carpeta actual'),
    # que guarda una propiedad de clase: un objeto suyo (TFont, sus sub-propiedades con
    # punto) o una REFERENCIA a un componente (PopupMenu, un Name). Vivia dentro de
    # TipoQueNoCasa (set); prop no la llamo y decia de un PopupMenu "set writes them
    # dotted" (1.20). Esta regla caza la COPIA; el olvido lo caza test_prop_ruta_120
    ('objeto propio o referencia a mano', r"Desciende\s*\([^)]*ID_COMPONENTE",
     [('Lsp.DesignerMeta.pas', 'TMetaTable.EsObjetoPropio'), ('Lsp.DesignerMeta.pas', 'RaizDeDiseno')],
     'EsObjetoPropio: si una propiedad de clase guarda un objeto suyo o una referencia a un '
     'componente; la piden set, prop y el filtro de info (1.20). RaizDeDiseno pregunta otra '
     'cosa con el mismo juez: si la clase juez de una raiz es un componente (un modulo)'),
    # el recorrido de una clase y sus descendientes: dos copias del mismo BFS sobre Hijas
    # (PublicadaEnDescendiente, PublicadasDeLaFamilia) y el filtro de info iba a ser la
    # tercera (1.20; propuesta de la auditoria de duplicados). La tabla lo llena al leerse
    ('recorrer la familia a mano', r"\bHijas\.TryGetValue\s*\(",
     [('Lsp.DesignerMeta.pas', 'TMetaTable.RecorreFamilia'), ('Lsp.DesignerMeta.pas', 'TMetaTable.Create')],
     'RecorreFamilia: AClase y sus descendientes por generaciones, con un visitante; la '
     'tabla solo llena Hijas al leerse (1.20)'),
    # el XML de proyecto (.dproj, .deployproj, .groupproj, .optset, el .sdk del IDE): UN
    # analisis, el de Lsp.Dproj, contrastado con MSXML -el juez que carga el IDE- por
    # test_oraculo_xml. Habia regex y Pos de etiquetas por todas partes, cada una con su
    # forma: quince en la mudanza, diez en el .groupproj, el ancla del Deploy que no veia el
    # Import con la Condition delante (1.20.1, medido contra los Samples). Tres formas: una
    # TRegEx con una etiqueta en el patron, un Pos/IndexOf/Contains de '<Etiqueta' y un
    # literal de regex sobre una etiqueta (la linea de continuacion de una TRegEx). Componer
    # un elemento nuevo (con XmlAtributo / XmlElemento) no es leerlo y no se caza. Medida
    # contra 7a3733d: 39 copias en 5 unidades; NO ve una aguja guardada en una constante (el
    # ANCHOR del Deploy, el Needle de ReadDproj) ni buscar un texto que no es una etiqueta
    # (Contains('minSdkVersion')): esas las caza el revisor, no esta regla
    ('leer o editar XML de proyecto a mano',
     r"TRegEx\.\w+\s*\([^;]*'[^']*</?[A-Za-z(]"
     r"|\b(?:Pos|PosEx|PosMin|IndexOf|LastIndexOf|Contains|StartsWith|EndsWith)\s*\(\s*'</?[A-Za-z]"
     r"|'[^']*</?[A-Za-z]\w*(?:\\s|\(\?:\\s)|\[\^<\]\*",
     [('Lsp.Docs.pas', '*'), ('Mcp.Tools.DelphiLsp.pas', 'TDelphiCompletionTool.ExecuteWithParams')],
     'Por Lsp.Dproj (TramosDeEtiqueta, AtributosDeTramo, ValorDeTramo y sus escritores), que '
     'ni siquiera tiene estas formas: busca \'<\' + la etiqueta que le piden. Lsp.Docs lee el '
     'HTML de la ayuda, no XML de proyecto; la completion mira el texto <error> de un detalle '
     'del motor'),
    # la Condition de un grupo o de un elemento del .dproj escrita o leida a mano:
    # '$(Base_X)'!='', '$(Cfg_N)'!='', '$(Platform)'=='X', '$(Config)'=='Y'. Los
    # nombradores y sus inversas viven en Lsp.Dproj, y la puerta del build las
    # evalua con EvaluaCondicion (revisor C, 21-oct-2026: nadie lo vigilaba)
    ('la Condition de un grupo del .dproj a mano',
     r"(?i)'\$\((?:base|cfg_)|''\$\((?:platform|config)\)''\s*[!=]=",
     [('Lsp.Dproj.pas', 'DefinerCondition'), ('Lsp.Dproj.pas', 'DeployGroupCondition'),
      ('Lsp.Dproj.pas', 'ConfigCondition')],
     'los nombradores de Lsp.Dproj (GroupCondition y ConfigDefinerCondition componen sin el '
     'literal; DefinerCondition, DeployGroupCondition y ConfigCondition lo llevan) y la inversa '
     'EsGrupoDeClave (sin literal: compone y compara); la puerta del build las evalua con '
     'EvaluaCondicion, no las compara'),
    # el grupo de VALORES de un build elegido o creado a mano - el grupo por su Condition
    # compuesta con un nombrador, o un definidor / grupo de valores escrito con su compositor -
    # fuera de su casa: GrupoDelBuild, AseguraGrupoDelBuild y PonPropiedadDelBuild (Lsp.Dproj),
    # donde el IDE escribe una opcion de una plataforma y una configuracion. Lo elegian cada uno
    # a su manera set-sdk / set-profile, add-searchpath y remove-searchpath (unificacion 1.22.0)
    ('elegir el grupo de un build a mano',
     r"GrupoConCondicion\s*\("
     r"|CondicionNormalizada\s*\([^;=]*\)\s*=\s*CondicionNormalizada\s*\(\s*(?:GroupCondition|DefinerCondition|ConfigDefinerCondition)\s*\("
     r"|PlataformaDeGrupo\s*\(|XmlGrupoDeValores\s*\(|XmlGrupoDefinidor",
     [('Lsp.Dproj.pas', '*'), ('Lsp.Scaffold.pas', '*')],
     'GrupoDelBuild / AseguraGrupoDelBuild / PonPropiedadDelBuild (Lsp.Dproj); delphi_create compone '
     'el .dproj entero con los nombradores (Lsp.Scaffold)'),
    # un <ItemGroup Condition="..."> del .deployproj compuesto a mano: lo componian cinco sitios
    # (el manifiesto de Android y el de las demas plataformas, el hueco y el grupo nuevo de
    # EnsurePlatformOutputEntries, add-deployfile; revisor del 21-oct-2026)
    ('un ItemGroup de despliegue compuesto a mano',
     r"'\s*<ItemGroup\s",
     [('Lsp.Dproj.pas', 'XmlGrupoDeDespliegue')],
     'XmlGrupoDeDespliegue (Lsp.Dproj), con las entradas de XmlDeployFile dentro'),
    # una <DCCReference> compuesta a mano: delphi_create la componia dos veces al lado del
    # escritor de add-unit (revisor del 21-oct-2026)
    ('una DCCReference compuesta a mano',
     r"'\s*<DCCReference\s",
     [('Lsp.ProjectUnits.pas', 'DccRefXml')],
     'DccRefXml (Lsp.ProjectUnits): add-unit, el rename y delphi_create'),
    # el argumento de una directiva de fichero ($I, $R, $L) troceado a mano: el bucle de
    # DirectivasDeFichero y el Split()[0] de la vista FMX del renderizador, que con un {$R}
    # vacio leia fuera del array (EAccessViolation, medido el 18-oct-2026). Dos formas:
    # partir el Argumento de una directiva, o mirar si un caracter abre una ruta entre comillas
    ('trocear el argumento de una directiva a mano',
     r"\.Argumento\b[^;]*\.Split\s*\(|CharInSet\(\s*\w+\[\w+\]\s*,\s*\[''''\s*,\s*'\"'\]\s*\)",
     [('Lsp.Pascal.pas', 'TrozosDeDirectiva')],
     'TrozosDeDirectiva (Lsp.Pascal), junto a DirectivasPascal: lo usan la mudanza, la puerta '
     'del build y la vista FMX de los renderizadores'),
    # el resultado de un Split indexado a secas: con '' Delphi devuelve un array VACIO y [0]
    # lee fuera (EAccessViolation: 25-ago en delphi_edit, 26-sep en delphi_textedit, 18-oct en
    # la vista FMX; quedaban nueve en el servidor, cambiados por PrimerTrozo ese dia)
    ('indexar un Split a secas', r"\.Split\s*\([^;]*\)\s*\[", [],
     'PrimerTrozo (Lsp.Args), o el array en una variable con su Length mirado antes'),
    # la marca del grupo de clases que el IDE escribe en un modulo de datos: la
    # componia Lsp.Scaffold a mano y nadie la leia - un modulo de datos .dfm de
    # FMX se juzgaba con la VCL (corpus, 18-oct-2026)
    ('la marca CLASSGROUP del IDE a mano', r"'CLASSGROUP|\{%CLASSGROUP", [('Lsp.Pascal.pas', '*')],
     'GrupoDeClasesDe (el lector) y PseudoDirectivaGrupoDeClases (el compositor), en Lsp.Pascal'),
    # lo que es la raiz de un designer (form, frame, modulo) por el NOMBRE de una clase:
    # una lista (TFrame, TCustomFrame, TDataModule, TForm, TCustomForm, TForm3D) y un
    # sufijo en Lsp.ProjectUnits, 'frame' dentro del nombre en el ayudante, otra lista en
    # check-binding y una regex del ancestro (TForm*, TDataModule*, TFrame*): fallaban en
    # las 39 unidades de los Samples cuya cadena sale de la unidad (18-oct-2026). Tres
    # formas: el nombre solo entre comillas, mirar si un nombre contiene o acaba en
    # frame/datamodule (o empieza por TFrame, TForm...), y la alternancia de esos nombres en
    # una regex. Componer el fuente de una clase nueva (' = class(TFrame)') no es juzgar, y
    # el kind de delphi_create ('frame-vcl') no es una clase: no se cazan
    ('la raiz de un designer por el nombre de su clase',
     r"'(?:T(?:Custom)?Frame|T(?:Custom|CommonCustom)?Form(?:3D)?|TDataModule)'"
     r"|\b(?:Contains|EndsWith)\s*\(\s*'(?i:t?frame|t?datamodule)'"
     r"|\bStartsWith\s*\(\s*'(?i:tframe|tdatamodule|tform)'"
     r"|\b(?:Form|Frame|DataModule)\|(?:Form|Frame|DataModule)\b",
     [('Lsp.FormRender.pas', 'ClaseDelSustituto'), ('Lsp.DesignerMetaGen.pas', 'TGenerador.EsRaiz')],
     'RaizDeDiseno (Lsp.DesignerMeta: la cadena por el motor hasta la clase que la tabla conoce '
     'y su categoria por la jerarquia de la tabla) y su escritor y lector del <DesignClass> '
     '(DesignClassDeFrame, RaizDeDesignClass); en el ayudante, la clase CARGADA (EsFrame). '
     'Su casa: el sustituto que crea el ayudante (ClaseDelSustituto) y el generador de la '
     'tabla, que lee las raices del fuente por su identidad (EsRaiz)'),
    # el mensaje del lector de forms (Format(SPropertyException, ...) de TReader) partido
    # con un formato propio: el servidor lo partia con el INGLES y el RTL del ayudante habla
    # el idioma de Windows (rtl370.de/.fr/.ja; medido el 18-oct-2026: en aleman no nombraba
    # nada, set escribia sin juzgar y el lint perdia la linea). Dos formas: una regex sobre
    # el texto ingles, y el formato del RTL usado fuera de su casa. Mirar si una salida
    # CONTIENE ese texto (las baterias, los tests) no es partirlo
    ('el mensaje del lector de forms partido a mano',
     r"TRegEx\.\w+\s*\([^;]*'[^']*Error reading|\bSPropertyException\b",
     [('FormRender.Comun.pas', 'LecturaEnPartes')],
     'LecturaEnPartes (FormRender.Comun): el ayudante lo parte con el formato que lo compuso, en '
     'su idioma, y lo manda en partes (FR_PARTES_SEP); el servidor lo lee con PartesDeLectura '
     '(Lsp.FormRender)'),
    # que una linea de un form es un EVENTO, por el prefijo On: los de un TDataSet (AfterOpen,
    # BeforePost) y los de un TWebModule (BeforeDispatch) no lo llevan, y check-binding los
    # daba por buenos sin manejador o con el suyo en public (medido el 18-oct-2026). Dos
    # formas: el patron 'On' + identificador, y mirar si un nombre empieza por On
    # la clausula requires de un paquete leida con una regex: sobre el codigo con las
    # directivas en blanco, y add-requires la reescribia sin sus {$IFDEF} ni sus
    # comentarios (medido el 18-oct-2026: vcl pasaba a ser de todas las plataformas)
    ('la clausula requires leida con una regex', r"TRegEx\.\w+\s*\([^;]*'[^']*\brequires\b", [],
     'FindUses con la palabra (APalabra=requires): EL lector de las clausulas, con sus comentarios '
     'y sus ramas; y ReplaceUses, su escritor (Lsp.ProjectUnits)'),
    # que una linea es una SENTENCIA, por una lista de palabras clave (el aviso de un
    # metodo partido miraba asi la linea de encima, y dos declaraciones seguidas en un
    # interface avisaban; 18-oct-2026): donde esta cada cuerpo lo sabe el lector
    ('una sentencia por una lista de palabras clave',
     r"'\^\((?:\?:)?if\|while\|for\|case\b", [],
     'TUnidadPas (Lsp.PascalDecl): Cuerpos (entre el begin y el end de cada rutina) y '
     'FinDeclaraciones (donde acaban las declaraciones)'),
    ('un evento por el prefijo On',
     r"'(?:\\A|\^\(?)?On'\s*\+|StartsWith\(\s*'On'",
     [('Lsp.DesignerBinding.pas', 'EsEvento')],
     'EsEvento (Lsp.DesignerBinding): la tabla (Kind m, por la clase del objeto: ClasesDeLasLineas, '
     'y la raiz por JuezDeLaRaiz); el nombre solo donde la tabla no sabe, y ahi, declarado'),
    # lo que es una plataforma (de Windows, de Android, el ABI de su apk) por su nombre:
    # StartsWith('Win'), StartsWith('Android')... en ~20 sitios y SameText(P, 'Android64')
    # para el ABI, dos veces; y tres preguntas con una respuesta ("se compila aqui" por
    # "corre aqui" y por "despliega por PAServer"; censo de jueces, lote 2, 18-oct-2026).
    # Las filas de la tabla (llevan Sistema:) son la casa
    ('la familia de una plataforma por su nombre a mano',
     r"\.StartsWith\(\s*'(?:Win|Android|Linux|OSX|iOS)'|SameText\([^;]*'Android(?:64)?'\s*\)|"
     r"^(?!.*\bSistema\s*:).*'(?:arm64-v8a|armeabi-v7a)'", [],
     'la tabla PLATAFORMAS de Lsp.Dproj y sus preguntas: SistemaDePlataforma, SistemaDelPAServer, '
     'CorreEnEstaMaquina, ExtensionDeEjecutable, CarpetaDeLibreriasDelApk'),
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
    'elegir el grupo de un build a mano': "  if GrupoConCondicion(Xml, GroupCondition(Plat), G) then",
    'un ItemGroup de despliegue compuesto a mano': "  B := '    <ItemGroup ' + XmlAtributo('Condition', C) + '>';",
    'una DCCReference compuesta a mano': "  R := '        <DCCReference ' + XmlAtributo('Include', I) + '/>';",
    'lanzar paclient': "  Output := RunCaptured('\"' + PaClient + '\" --timeout=20 \"' + P + '\"', 45000, E);",
    'lanzar un programa': "  Out := RunCapturedIn('\"' + Exe + '\" algo', Dir, 1000, C);",
    'lanzar un programa por su nombre a secas': "  Out := RunCapturedIn('git.exe status', '', 1000, C);",
    'una orden que empieza por un programa a secas': "  Linea := 'git.exe -c core.fsmonitor=false status';",
    'lanzar el conversor de estilos': "  Out := RunCapturedIn('\"' + Exe + '\" tobin', Dir, 1000, C);",
    'nombre de un .profile': "  F := TPath.Combine(Dir, Nombre + '.profile');",
    'listar los perfiles a mano': "  for F in TDirectory.GetFiles(Dir, '*.profile') do",
    'listar los SDK a mano': "  for F in TDirectory.GetFiles(Dir, '*.sdk') do",
    'listar una carpeta sin saber si se dejo': "  for E in TDirectory.GetFileSystemEntries(Dir) do",
    'listar ficheros o carpetas sin saber si se dejo': "  for F in TDirectory.GetFiles(Dir, '*.pas') do",
    'nombre de un .sdk': "  F := TPath.Combine(Dir, Nombre + '.sdk');",
    'leer un designer binario a mano': "  Err := DesignerFileToText(APath, Texto);",
    'la nota de codificacion de un form a mano': "  N := NotaDeFormAncho(Nombre, Enc);",
    'un campo de conexion de un perfil': "  H := TagValue(Xml, 'Profile_host');",
    '.sdk leido a mano': "  if not S.ToLower.EndsWith('.sdk') then S := S;",
    'el manifiesto de despliegue a mano': "  F := TPath.ChangeExtension(D, '.deployproj');",
    '__delphi-temp': "  if ContainsText(P, '\\__delphi-temp\\') then",
    '__delphi-patch': "  if ContainsText(P, '\\__delphi-patch\\') then",
    'StyleName o StyleLookup leidos con una regex': r"  M := TRegEx.Match(L, 'StyleName\s*=\s*''([^'']+)''');",
    'el nombre de la carpeta de un dia': "  D := FormatDateTime('yyyymmdd', Now);",
    'reconocer la carpeta de un dia': "  if TRegEx.IsMatch(N, '^\\d{8}$') then",
    'la carpeta del servidor': "  D := ExtractFileDir(ParamStr(0));",
    'la carpeta de los informes o del correo sin el workspace': "  D := TPath.Combine(CarpetaDeInformes, Agente);",
    'la raiz de los informes o del correo compuesta a mano': "  D := ServerDir('reports');",
    'la extension de la marca de dueno': "  M := Copia + '.by';",
    "la forma 'srvX:'": "  U := 'srv' + LowerCase(Letra) + ':';",
    'el host virtual srvhost': "  H := '\\\\srvhost\\' + Resto;",
    'la expansion de ida de una unidad virtual': "  V := ExpandDriveValue(V);",
    'la clave tool|parametro de las marcas': "  K := LowerCase(T) + '|' + TMCPSerializer.NormalizeKey(P);",
    'un paseo del arbol por cada mascara': "  for var Ext in MascarasDe(SOURCE_EXTS) do Fs := WalkFiles(D, Ext);",
    'la expansion de ida de una llamada con otro predicado': "  ExpandVirtualDrives(Args, EsNombreDeContenido);",
    'GetTempPath suelto': "  T := TPath.GetTempPath();",
    'el .dproj de un .dpr': "  D := ChangeFileExt(P, '.dproj');",
    'el .dproj compuesto a mano': "  D := Stem + '.dproj';",
    'el .dpr de un .dproj': "  D := TPath.ChangeExtension(P, '.dpr');",
    'el juez del nombre de un perfil': "  if not TRegEx.IsMatch(Perfil, '^[A-Za-z0-9_.-]+$') then",
    'la gramatica de las lineas de un form': "  if L.Trim.EndsWith('= <') then",
    'un documento de lineas abierto sin su juez': "  Doc := TStyleDoc.Create(APath);",
    'el recorrido del parser con sus lineas': "  L := Parser.SourceLine - 1;",
    'un .rc leido a mano': "  for M in TRegEx.Matches(T, '^\\s*(\\w+)\\s+RCDATA\\s+\"([^\"]+)\"') do",
    'el argumento de una llamada a Register* leido a mano':
        "  for var Mt in TRegEx.Matches(T, '(?is)RegisterClass\\s*\\((.*?)\\)\\s*;') do",
    'la propiedad que elige las partes de un componente': "  if P.EndsWith('ClassName', True) then",
    'la clave del IDE en el registro': "  if Reg.OpenKeyReadOnly('SOFTWARE\\Embarcadero\\BDS\\' + Ver) then",
    'la rama absoluta de una entrada de sitio': "  Full := TPath.GetFullPath(RaizSiUnidad(V));",
    'el significado de old/new': "  A.HasNew := (ANew <> '') or A.HasOld;",
    'lo que choca con fragment': "  if A.HasOld then Otros := 'old'",
    'la cadena de ancestros por el motor': "  if not Cadena.AncestroDe(F, L, F2, L2) then",
    'la puerta de escritura del vault': "  if VaultGovernance(Full) then",
    'vigilar una clave del registro': "  RegNotifyChangeKeyValue(H, True, REG_NOTIFY_CHANGE_LAST_SET, Ev, True);",
    'la forma de los atomos del RTL': "  N := Format('Delphi%.8X', [Pid]);",
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
    'la forma canonica de una ruta preguntada a Windows': "  N := GetLongPathName(PChar(P), @B[0], Length(B));",
    'decidir la codificacion de unos bytes': "  if (B[0] = $FF) and (B[1] = $FE) then K := ekUtf16LE;",
    'UTF-8 estricto preguntado a mano': "  if ValidUtf8(B, 0) then K := ekUtf8;",
    'una cadena ASCII preguntada a mano': "  for C in S do if Ord(C) > 127 then Exit(False);",
    'codificar el texto de un fichero para escribirlo': "  B := EncodeText(Texto, K);",
    'la regla de ida y vuelta preguntada a mano': "  if not BytesVuelvenIgual(B, K) then Exit;",
    'las extensiones de un fuente a mano': "  if MatchText(Ext, ['.pas', '.dpr', '.dpk', '.inc']) then X := 1;",
    'las extensiones de un designer a mano': "  if MatchText(TPath.GetExtension(P), ['.dfm', '.fmx']) then X := 1;",
    # la de Lsp.Changeset hasta el 18-oct-2026
    'las extensiones de un proyecto del IDE a mano':
        "  if MatchText(TPath.GetExtension(Op.Path), ['.dproj', '.groupproj', '.dpk']) and",
    'una pagina de codigos a mano': "  E := TEncoding.GetEncoding(1252);",
    'fijar la pagina ANSI': "  UsaPaginaAnsi(1251);",
    'las listas crudas de los sitios': "  for R in WorkspaceRoots do",
    'la zona de biblioteca cruda': "  for R in LibraryRoots do",
    'leer sin la puerta': "  Xml := TFile.ReadAllText(Dproj);",
    'escribir sin la puerta': "  TFile.WriteAllText(Ruta, Texto, TEncoding.UTF8);",
    'borrar sin la puerta': "  TFile.Delete(Ruta);",
    'mover o copiar un arbol con la RTL': "  TDirectory.Move(Origen, Destino);",
    'crear una carpeta sin la puerta': "  ForceDirectories(Dir);",
    'atributos o fechas sin la puerta': "  SetFileAttributes(PChar(Ruta), FILE_ATTRIBUTE_NORMAL);",
    'la cabecera de un PNG': "  W := (B[16] shl 24) or (B[17] shl 16) or (B[18] shl 8) or B[19];",
    # la linea del build de hasta la 1.18.1
    'lanzar un shell': "  Orden := Format('cmd.exe /c \"\"%s\" && msbuild \"%s\"', [Rs, P]);",
    # la de TipoQueNoCasa hasta la 1.19
    'objeto propio o referencia a mano': "  if not F.Tabla.Desciende(AHoja.TypeId, ID_COMPONENTE) then",
    # la de PublicadaEnDescendiente hasta la 1.19
    'recorrer la familia a mano': "  if not Hijas.TryGetValue(Cola.Dequeue, Hs) then",
    # el de set-version hasta la 1.20.1
    'la Condition de un grupo del .dproj a mano': "  if Pos('$(Base_' + P + ')', Cond) > 0 then",
    'leer o editar XML de proyecto a mano':
        "  M := TRegEx.Match(Xml, '(?i)<VerInfo_MajorVer>([^<]*)</VerInfo_MajorVer>');",
    # el de MaestroDeVista hasta el 18-oct-2026
    'trocear el argumento de una directiva a mano': "  V := D.Argumento.Trim.Split([' ', #9])[0];",
    # el de PonFalloDelLanzador hasta el 18-oct-2026
    'indexar un Split a secas': "  AObj.AddPair('error', ASalida.TrimLeft.Split([#10])[0].Trim);",
    # la de Lsp.Scaffold hasta el 18-oct-2026
    'la marca CLASSGROUP del IDE a mano': "  S := '{%CLASSGROUP ''FMX.Controls.TControl''}';",
    # la de Lsp.ProjectUnits.RaizDeLaCadena hasta el 18-oct-2026
    'la raiz de un designer por el nombre de su clase': "    if SameText(AUltimo, 'TFrame') then Exit('TFrame');",
    # la de Lsp.FormRender.IgnoradaDeTexto hasta el 18-oct-2026
    'el mensaje del lector de forms partido a mano':
        r"  M := TRegEx.Match(ATexto, '\AError reading ([^.:\s]+)\.([^:\s]+): (.+)\z');",
    # la del aviso EDIT-101 de Lsp.Patch hasta el 18-oct-2026
    'una sentencia por una lista de palabras clave':
        "  S := TRegEx.IsMatch(E, '^(if|while|for|case|repeat|until|raise|exit|with|begin|try)\\b', [roIgnoreCase]);",
    # la de Lsp.ProjectUnits.ClausulaRequires hasta el 18-oct-2026
    'la clausula requires leida con una regex':
        r"  M := TRegEx.Match(Copy(Codigo, Cab.Fin, MaxInt), '^(\s*)(requires\b\s*(.*?);)', [roIgnoreCase]);",
    # la de Lsp.DesignerBinding hasta el 18-oct-2026
    'un evento por el prefijo On': "  PATRON_EVENTO = 'On' + PATRON_IDENT;",
    # la de Lsp.BuildRunner hasta el 18-oct-2026 (una de nueve)
    'la familia de una plataforma por su nombre a mano': "  if APlat.StartsWith('Android', True) then",
}
for regla in REGLAS:
    nombre = regla[0]
    planta = ('unit Plantado;\nimplementation\nprocedure CopiaAMano;\nbegin\n  // ' + PLANTADO[nombre] +
              '\n' + PLANTADO[nombre] + '\nend;\nend.\n')
    cazados = fuera_de_casa(regla, [('Plantado.pas', planta)])
    check('mutante "%s": la copia plantada se caza (y el comentario no)' % nombre,
          len(cazados) == 1 and ':6 ' in cazados[0], cazados)

# las otras formas de lanzar: los lanzadores con nombre propio (fuera de su casa) y
# los otros interpretes (revisor de baterias, 18-oct-2026)
REGLA_LANZA = next(r for r in REGLAS if r[0] == 'lanzar un programa')
for forma in ("  if not CreateProcessConHandles(Cmd, nil, 0, nil, SI, PI) then Exit;",
              "  Ok := CreateProcessEnContenedor(C, Cmd, nil, 0, nil, SI, PI);"):
    cazados = fuera_de_casa(REGLA_LANZA, [('Plantado.pas', 'unit Plantado;\nimplementation\nprocedure '
                                           'LanzaAMano;\nbegin\n' + forma + '\nend;\nend.\n')])
    check('mutante "%s": tambien %s' % (REGLA_LANZA[0], forma.strip()), len(cazados) == 1, cazados)
REGLA_SHELL = next(r for r in REGLAS if r[0] == 'lanzar un shell')
for forma in ("  Cmd := '\"' + Sys32 + '\\WindowsPowerShell\\v1.0\\powershell.exe\" -NoProfile -Command ' + X;",
              "  Cmd := 'pwsh -c ' + X;", "  Cmd := Sys32 + '\\cscript.exe //nologo ' + X;",
              "  Cmd := Git + '\\bin\\bash.exe -c ' + X;"):
    cazados = fuera_de_casa(REGLA_SHELL, [('Plantado.pas', 'unit Plantado;\nimplementation\nprocedure '
                                           'ShellAMano;\nbegin\n' + forma + '\nend;\nend.\n')])
    check('mutante "%s": tambien %s' % (REGLA_SHELL[0], forma.strip()), len(cazados) == 1, cazados)

# las otras formas del XML de proyecto a mano: un Pos de una etiqueta (ReadDproj), la linea
# de continuacion de una regex (el .groupproj) y un Contains; y lo que NO es leerlo: componer
REGLA_XML = next(r for r in REGLAS if r[0] == 'leer o editar XML de proyecto a mano')
for forma in ("  Op := Pos('<platform value=\"', Low, Scan);",
              "    '[ \\t]*<Projects\\s+Include=\"([^\"]*)\"\\s*(/>|>.*?</Projects>)', [roSingleLine]) do",
              "  if not Dproj.ToLower.Contains('<import ') then"):
    cazados = fuera_de_casa(REGLA_XML, [('Plantado.pas', 'unit Plantado;\nimplementation\nprocedure '
                                         'LeeAMano;\nbegin\n' + forma + '\nend;\nend.\n')])
    check('mutante "%s": tambien %s' % (REGLA_XML[0], forma.strip()), len(cazados) == 1, cazados)
# las otras formas de la raiz por su nombre: el sufijo (DesignClassOf), 'frame' dentro
# (EsFrame del ayudante) y la regex del ancestro (InspectUnit), hasta el 18-oct-2026; y
# lo que NO es juzgar: el fuente de una clase nueva que compone el scaffold
REGLA_RAIZ = next(r for r in REGLAS if r[0] == 'la raiz de un designer por el nombre de su clase')
for forma in ("  else if Name.EndsWith('DataModule', True) then",
              "  Result := A.ToLower.Contains('frame');",
              "  if TRegEx.IsMatch(UltimoTrozo(T.Ancestro), '(?i)\\AT(?:Form|DataModule|Frame)') then"):
    cazados = fuera_de_casa(REGLA_RAIZ, [('Plantado.pas', 'unit Plantado;\nimplementation\nprocedure '
                                          'RaizAMano;\nbegin\n' + forma + '\nend;\nend.\n')])
    check('mutante "%s": tambien %s' % (REGLA_RAIZ[0], forma.strip()), len(cazados) == 1, cazados)
# la otra forma del mensaje del lector a mano: su formato del RTL fuera de su casa
REGLA_LECTOR = next(r for r in REGLAS if r[0] == 'el mensaje del lector de forms partido a mano')
cazados = fuera_de_casa(REGLA_LECTOR, [('Plantado.pas', 'unit Plantado;\nimplementation\nprocedure '
                                        'PartesAMano;\nbegin\n  F := SPropertyException;\nend;\nend.\n')])
check('mutante "%s": tambien el formato del RTL fuera de su casa' % REGLA_LECTOR[0], len(cazados) == 1, cazados)
# la otra forma del evento por su nombre: mirar si empieza por On
REGLA_ON = next(r for r in REGLAS if r[0] == 'un evento por el prefijo On')
cazados = fuera_de_casa(REGLA_ON, [('Plantado.pas', 'unit Plantado;\nimplementation\nprocedure '
                                    "EventoAMano;\nbegin\n  if Prop.StartsWith('On') then X := 1;\nend;\nend.\n")])
check('mutante "%s": tambien mirar si el nombre empieza por On' % REGLA_ON[0], len(cazados) == 1, cazados)
# las otras formas de la plataforma por su nombre: el ABI por SameText (BuildRunner y
# add-deployfile) y su literal suelto; y lo que NO se caza: una fila de la tabla
REGLA_PLAT = next(r for r in REGLAS if r[0] == 'la familia de una plataforma por su nombre a mano')
for forma in ("  if SameText(APlatform, 'Android64') then",
              "    Abi := 'armeabi-v7a';"):
    cazados = fuera_de_casa(REGLA_PLAT, [('Plantado.pas', 'unit Plantado;\nimplementation\nprocedure '
                                          'PlataformaAMano;\nbegin\n' + forma + '\nend;\nend.\n')])
    check('mutante "%s": tambien %s' % (REGLA_PLAT[0], forma.strip()), len(cazados) == 1, cazados)
FILA = fuera_de_casa(REGLA_PLAT, [('Plantado.pas', 'unit Plantado;\nimplementation\nconst\n'
    "  X: TPlataformaConocida = (Nombre: 'Android64'; Sistema: spAndroid; Maquina: 0; Abi: 'arm64-v8a');\nend.\n")])
check('mutante "%s": una fila de la tabla no se caza' % REGLA_PLAT[0], FILA == [], FILA)
COMPONE_CLASE = fuera_de_casa(REGLA_RAIZ, [('Plantado.pas', 'unit Plantado;\nimplementation\nprocedure '
    "Compone;\nbegin\n  S := '  T' + ANombre + ' = class(TFrame)' + CRLF;\nend;\nend.\n")])
check('mutante "%s": componer el fuente de una clase nueva no se caza' % REGLA_RAIZ[0],
      COMPONE_CLASE == [], COMPONE_CLASE)
COMPONER = fuera_de_casa(REGLA_XML, [('Plantado.pas', 'unit Plantado;\nimplementation\nprocedure Compone;\n'
    "begin\n  S := '<Platform ' + XmlAtributo('value', P) + '>True</Platform>';\nend;\nend.\n")])
check('mutante "%s": componer un elemento con XmlAtributo no se caza' % REGLA_XML[0], COMPONER == [], COMPONER)

# las otras formas de la cabecera de un PNG: la firma en literal y byte a byte (el
# escritor del nodo) y por sus letras (su lector)
REGLA_PNG = next(r for r in REGLAS if r[0] == 'la cabecera de un PNG')
for forma in ("  F: array[0..7] of Byte = ($89, $50, $4E, $47, $0D, $0A, $1A, $0A);",
              "  Cab[0] := $89; Cab[1] := $50; Cab[2] := $4E; Cab[3] := $47;",
              "  if (B[1] <> Ord('P')) or (B[2] <> Ord('N')) or (B[3] <> Ord('G')) then Exit;"):
    cazados = fuera_de_casa(REGLA_PNG, [('Plantado.pas', 'unit Plantado;\nimplementation\nprocedure '
                                         'LeeAMano;\nbegin\n' + forma + '\nend;\nend.\n')])
    check('mutante "%s": tambien %s' % (REGLA_PNG[0], forma.strip()), len(cazados) == 1, cazados)

# la otra forma de trocear el argumento de una directiva: el bucle a mano, por la comilla
# que abre una ruta (el de DirectivasDeFichero hasta el 18-oct-2026)
REGLA_TROZOS = next(r for r in REGLAS if r[0] == 'trocear el argumento de una directiva a mano')
cazados = fuera_de_casa(REGLA_TROZOS, [('Plantado.pas', 'unit Plantado;\nimplementation\nprocedure '
                                        "TroceaAMano;\nbegin\n  if CharInSet(G[P], ['''', '\"']) then Q := P;\nend;\nend.\n")])
check('mutante "%s": tambien el bucle a mano (la comilla que abre una ruta)' % REGLA_TROZOS[0],
      len(cazados) == 1, cazados)

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
              "  TDirectory.Delete(Dir, False);", "  RemoveDirectory(PChar(Dir));", "  BorraLoNuestro(Ruta);",
              "  BorraNombre(Ruta);"):
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
    ('Lsp.Args.pas','ShellArgDenied'),
    ('Lsp.Guard.pas','BorradoDenegado'),
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

# ---- Lo que matamos, lo limpiamos (18-oct-2026): un TerminateProcess o un
# TerminateJobObject nuestro deja en la tabla de la sesion los atomos globales
# del RTL del muerto (Lsp.AtomosRtl): cada unidad que mata, limpia
# (BorraAtomosDeProceso tras el kill, BorraAtomosPropios antes de matarse).
# McpRunJob.dpr es el ayudante de LINUX de remote-run: alli no hay atomos.
MATA = re.compile(r'\bTerminate(?:Process|JobObject_?)\s*\(')
LIMPIA = re.compile(r'\bBorraAtomos(?:DeProceso|Propios)\b')
def matan_sin_limpiar(ficheros_texto):
    malas = []
    for f, t in ficheros_texto:
        if os.path.basename(f) == 'McpRunJob.dpr':
            continue
        c = '\n'.join(codigo(t))
        if MATA.search(c) and not LIMPIA.search(c):
            malas.append(os.path.basename(f))
    return malas
check('mutante de lo que matamos: una unidad que mata sin limpiar se caza',
      matan_sin_limpiar([('Plantado.pas', 'unit Plantado;\ninterface\nimplementation\nprocedure P;\nbegin\n'
                                          '  TerminateProcess(H, 1);\nend;\nend.\n')]) == ['Plantado.pas'])
MATAN = matan_sin_limpiar(TEXTOS)
check('lo que matamos, lo limpiamos: toda unidad con TerminateProcess/TerminateJobObject borra los atomos '
      'del RTL del muerto (Lsp.AtomosRtl; la maquina se cayo el 18-oct-2026)', not MATAN, MATAN)

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
    # (las dos de abajo, del revisor de version de la 1.18.0; __delphi-temp y reports
    # tenian sus comprobaciones de ausencia por mc, y el barrido de sus ~45 lineas
    # restantes, apuntado para la 1.19.0, se hizo el 18-oct-2026: las dos ultimas)
    ('el intermedio del escritor atomico a mano', r"delphi-patch-tmp", [],
     'mc.TEMPORAL_SUSTITUCION_EXT, leido de TEMPORAL_DE_SUSTITUCION_EXT (Lsp.Patch)'),
    ('la carpeta de las copias del IDE a mano', r"""(['"])ide-copias\1""", [],
     'mc.IDE_COPIAS, leido de IDE_COPIAS_SUB (Lsp.Casa)'),
    # (revisor del 2af de la 1.18.2: seis baterias componian la casa de capturas)
    ('la casa de capturas a mano', r"""(['"])captures\1""", [],
     'mc.casa_de_capturas, leido de CAPTURAS_SUB (Lsp.Casa)'),
    # (revisor de baterias, 18-oct-2026: 40 lineas en 17 baterias, y 4 de reports)
    ('la carpeta de los temporales a mano', r"""(['"])__delphi-temp\1""",
     # mira el FUENTE del servidor a proposito (su nombrador y su lector)
     [('test_round44.py', 'g_src')],
     'mc.TEMPORALES, leido de TempFolderName'),
    ('la carpeta de los informes a mano', r"""(['"])reports\1""", [],
     'mc.INFORMES, leido de CarpetaDeInformes'),
    # (revisor de baterias, 18-oct-2026: siete baterias con su lector, cada una
    # con su ceguera) quitar la mascara a mano para buscar letras, o mirar
    # solo lo que no va tras 'srv'
    ('la fuga de una letra real leida a mano', r"srv\[a-z\]:|\(\?<!srv\)",
     [('mcp_cliente.py', 'def fuga_de_letra')],
     'mc.fuga_de_letra: crudo o escapado en JSON, tras un \\n escapado, en URL, con o sin barra'),
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
    'el intermedio del escritor atomico a mano': "    t = glob.glob(os.path.join(d, '*.delphi-patch-tmp'))",
    'la carpeta de las copias del IDE a mano': "    c = os.path.join(cache, 'ide-copias', '37.0')",
    'la casa de capturas a mano': "    c = os.path.join(srv, mc.TEMPORALES, 'captures', '_local')",
    'la carpeta de los temporales a mano': "    t = os.path.join(raiz, '__delphi-temp', 'agente')",
    'la carpeta de los informes a mano': "    r = mc.buzon(os.path.join(srv, 'reports'))",
    'la fuga de una letra real leida a mano': "    low = re.sub('srv[a-z]:', '', raw.lower())",
}
for regla in REGLAS_PY:
    nombre = regla[0]
    planta = ('def copia_a_mano():\n    # ' + PLANTADO_PY[nombre] + '\n' + PLANTADO_PY[nombre] + '\n')
    cazados = fuera_de_casa_py(regla, [('plantado.py', planta)])
    check('mutante py "%s": la copia plantada se caza (y el comentario no)' % nombre,
          len(cazados) == 1 and ':3 ' in cazados[0], cazados)
    malos = fuera_de_casa_py(regla, TEXTOS_PY)
    check('"%s" en ninguna bateria - %s' % (nombre, regla[3]), not malos, malos)
# ---- LAS GLOBALES DEL BUILD (revisor E, 21-oct-2026): cada /p:Nombre que la orden de
# msbuild lleva (Lsp.BuildRunner) esta en GLOBALES_DE_LA_ORDEN, lo que la puerta da por
# dudoso al evaluar las Condition del .dproj: una global gana a lo escrito aun definida
# despues (medido con el msbuild del IDE), y la puerta no sabe su valor. Config y
# Platform son lo pedido y van aparte. Las salidas suplidas van por UN '/p:%s' desde su
# lista (SALIDAS_QUE_SUPLE_EL_BUILD) y GlobalesDelBuild la suma: la regex de /p:Nombre no
# las veia y estaban copiadas a mano (revisor Opus de la 1.22.0, H6). Otro /p: compuesto
# tiene que pasar por aqui.
BR = '\n'.join(codigo(next(t for f, t in TEXTOS if os.path.basename(f) == 'Lsp.BuildRunner.pas')))
PASADAS = set(re.findall(r'/p:([A-Za-z_]\w*)', BR)) - {'Config', 'Platform'}
_m = re.search(r'GLOBALES_DE_LA_ORDEN\s*:\s*TArray<string>\s*=\s*\[(.*?)\]', BR, re.S)
GLOBALES = set(re.findall(r"'(\w+)'", _m.group(1))) if _m else set()
check('mutante de las globales: un /p:Nuevo= que no esta en la lista se caza',
      not ((PASADAS | {'Nuevo'}) <= GLOBALES))
check('las globales del build: cada /p: de la orden de msbuild esta en GLOBALES_DE_LA_ORDEN (%d)' % len(PASADAS),
      _m is not None and len(PASADAS) >= 5 and PASADAS <= GLOBALES, sorted(PASADAS - GLOBALES))


def compuestas(texto):
    """Cuantos /p: compuestos (/p:%s) lleva la orden: solo el de las salidas suplidas."""
    return len(re.findall(r'/p:%s', texto))


SUMA = re.search(r'function GlobalesDelBuild\b.*?\bend;', BR, re.S)
check('las salidas suplidas: UN /p:%s en la orden y GlobalesDelBuild suma SALIDAS_QUE_SUPLE_EL_BUILD',
      compuestas(BR) == 1 and SUMA is not None and 'SALIDAS_QUE_SUPLE_EL_BUILD' in SUMA.group(0),
      (compuestas(BR), SUMA.group(0) if SUMA else None))
check('mutante de las suplidas: un segundo /p:%s compuesto se caza',
      compuestas(BR + "\n  X := Format(' /p:%s=%s', [A, B]);") != 1)
mc.fin('paisaje battery')
