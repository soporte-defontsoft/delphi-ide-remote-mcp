# Jaula 1.13.0: informe de Codex

Fecha: 2026-10-04. Rama local: codex/jaula-1.13.0, desde 0ae2c57.
Worktree autorizado por David: D:\SandBox-lsp\testsserver\LSP-MCP-Server-codex.
TEMP/TMP exclusivos: D:\SandBox-lsp\testsserver\codex-tests.
Sin push, tag, publicacion, despliegue ni cambios en el servicio.

## 1. Controles en rutas

Causa medida: sin jaula, delphi_list con NUL al final no rechazaba la ruta;
Win32 truncaba el nombre y la tool devolvia un resultado vacio valido.
Con jaula muchos controles caian en GUARD-011 del canonicalizador; ese borde
no convertia los controles en anomalias independientes.
PathAnomaly devolvia vacio para controles #0..#31.

Arreglo en Lsp.Guard.PathAnomaly: rechazar cualquier control antes de normalizar.
Mensaje GUARD-032 INVALID_PARAM en Lsp.Texts, sin repetir la ruta peligrosa.
LspTests.Rutas mide los 32 controles en tres posiciones y una ruta normal.
test_ruta_controles.py mide los 32 al final con/sin jaula, una lectura normal,
un junction hacia una victima externa y la integridad de la victima.

Rojo antes del arreglo: 265/266 unitarios (Control 0).
Verde: 69/0 checks E2E. Mutante sin el bucle: 5 PASS / 64 FAIL.
El fuente se restauro con SHA256 identico; el grupo se recompilo.

## 2. Menores de Git, ronda 16

Tres causas reproducidas por las tools de una copia del servidor:

- Raiz del repo declarada como junction: Git devuelve su ruta real y el juez
  negaba GIT-041 aunque el argumento y el repo eran de esa raiz.
  DondeViveElRepo pide FormaDeclarada con el argumento ya admitido.
  El traductor existente acepta las equivalencias de las raices locales que
  contienen ese argumento; no abre otras raices.
- Repo bare desde una subcarpeta: el remoto relativo se resolvia desde GitDir
  en el juez y desde el -C de la llamada en Git. Medido con ../../remote.git:
  rechazo GIT-044 por el servidor y exit 0 por Git.
  RemotoDenegado recibe Repo como base cuando no existe arbol.
- fetch/pull heredaban fetch.recurseSubmodules=true (tambien un ajuste propio
  del submodulo): consultaban el repo externo y escribian el FETCH_HEAD del
  submodulo. GitLinea anade --no-recurse-submodules a ambas ordenes,
  incluyendo el fetch previo de pull. Las trazas confirman ese fetch y el
  fetch interno de Git, con recursion desactivada.

test_git_jaula_113.py: victima externa, junction, hashes de todos sus ficheros,
remoto bare permitido, raiz enlazada, fetch/pull y trazas de todas las ordenes.
Mutantes: sin opcion de recursion 16/4; base GitDir 19/1; sin referencia en
FormaDeclarada 19/1. Restauracion SHA256 identica y compilacion en cada caso.

Sin arreglo a ciegas:

- RealPath de raiz de unidad: los unitarios existentes de RaizSiUnidad y
  RealPath ya cubren unidad con/sin barra, distinta de la carpeta actual;
  pasan. El codigo ya contiene la correccion.
- Avisos de git remote: no se obtuvo un aviso real en remote get-url con
  core.fsyncObjectFiles=true, core.fsync=bogus ni core.checkStat=bogus.
  fetch con el primer ajuste dio exit 0. No se ha supuesto ni corregido un
  parser de avisos sin poder reproducirlo.
- GIT-036: fetch origin inexistente llega a Git, devuelve su error real de
  ref ausente y GIT-036. No se ha cambiado su catalogo ni su semantica.
- El fetch previo de pull se mide y queda cubierto por el compositor comun.

## 3. Consulta ls-remote

Antes: Unknown command; la bateria inicial daba 6/3.
Ahora: consulta de lectura, opciones --heads/--tags/--refs/--symref/--exit-code,
mismo RemotoDenegado y politica de hosts que fetch/pull.
GitCommandIsQuery y la tabla de accesos la anuncian y admiten con ReadOnlyToken.
Descripcion de command y bloque generado de docs/TOOLS.md sincronizados.

test_git_jaula_113.py pasa 20/0. Comprueba refs, ausencia de FETCH_HEAD por
ls-remote, rechazo del remoto externo, host no permitido, tools/list y
credencial HTTP realmente RO (control init rechazado).
La primera version del fixture usaba una variable RO inexistente: fue
sustituida antes de dar la prueba por valida.
Mutantes independientes: sin orden 17/3; sin clasificacion de consulta 19/1;
sin anuncio de acceso 19/1. Bytes restaurados exactamente.

## 4. Recorridos y nombres externos

Se traslado el WalkFiles ya existente de Mcp.Tools.Workspace a Lsp.Guard.
Conserva mascaras, deduplicacion, ciclos y tolerancia a carpetas ilegibles;
comprueba la lectura de la raiz y de los enlaces antes de recorrerlos.
La pasada adicional de papelera tambien comprueba los enlaces de fichero.
La purga al pasar queda despues de admitir el enlace.

Fugas medidas y lectores sustituidos:

- Lsp.TestRunner.discover: anunciaba JaulaVictimaTests.dpr de fuera.
- Mcp.Tools.DelphiLsp.symbols de carpeta: anunciaba la unidad externa.
- Lsp.References: el barrido enumeraba la unidad externa y el rechazo de una
  lectura posterior revelaba su nombre. Barridos de fuentes y de proyectos
  consumidores pasan por el lector comun.
- Lsp.Rename: una vez corregido references, sus propios avisos de DFM seguian
  anunciando JaulaVictima.dfm y bloqueando el rename local.
- Mcp.Tools.FileOps.PurgeOwnershipDenied: leia .by de fuera y anunciaba
  JaulaVictimaDueno (FILE-008) al purgar una carpeta propia.

test_jaula_recorridos.py: 10/0. test_jaula_lectores_guardas.py: 7/0.
Sin EnlaceLegible en el descenso: 6/4 y 6/1 respectivamente; la victima sigue
intacta. Ese mutante pone rojas las cinco tools afectadas.

Auditado y SIN atribuirle un arreglo:

- Session.FindDproj: la unidad suelta con dproj de fuera tras junction no
  expuso su nombre en symbols. Esta guarda NO prueba que no lo seleccione
  internamente; no se cambia su mecanismo sin una medida de esa seleccion.
- Styles.lint: ReadPathDenied antes de leer cada fichero impide el nombre
  externo; la guarda queda verde con el mutante del lector comun.
- FileOps.ClearReadOnlyTree: llamada en la rama de carpeta ya vacia, no se
  alcanza un arbol con ficheros en el flujo medido.
- FileOps.borrado de carpeta: con junction externo no anuncia sus unidades
  ni cambia la victima. La enumeracion RTL permanece; no es un fix medido.
- PAServer: el recorrido indicado se usa como booleano de presencia tras
  copiar el SDK; no emite los nombres enumerados. Sin experimento remoto
  de get-sdk (no se toca un destino para fabricar esta medida).
- Vault.Seed.HasNotes: booleano de presencia, sin emision de nombres.
  No se aplica la jaula general del agente al vault de arranque.
- ProjectUnits.FicherosBajo ya rechaza enlaces de fichero/carpeta y de raiz;
  es el recorrido de mudanzas, con filtros y avisos de artefactos propios.
- BuildRunner.UnitSourceFolders conserva su filtro ReadPathDenied del borde.
  test_missing_units: 24/0 en la regresion; el intermitente no se ha visto.
  No se afirma haberlo corregido ni se sustituye su recorrido sin una causa.

Un symlink de fichero del DFM hermano de rename no se midio (esta cuenta
no puede crearlo); se retiro la comprobacion adicional propuesta para ese
caso. K16b sigue siendo NOTA por la misma limitacion, sin cambio de permisos.

## 5. Sospecha de mascara

Se probaron cuatro constantes de contenido que comienzan por {, [{, [" y []
seguidas de un UNC ficticio de dos barras, con symbols full, digest de carpeta
y completion reales. No se obtuvo una cadena NO exenta que cumpliera esa
forma; los campos de contenido tienen exencion deliberada.
No se ha cambiado EnmascaraJsonSalvo ni se presenta una prueba sintetica de
la funcion como evidencia de una fuga real. La sospecha no queda descartada
para productores futuros: falta una respuesta real que active esa ruta.

## Regresion y evidencia

BuildGroup quiet make Release: grupo completo OK.
Exe medido SHA256: CBB3CEACE53167F00B644344ECC9FA443A17A17BF62F5301C9265AF8BDA8E54C.
Unitarios: 266 encontrados, 266 pasan, 0 ignorados/fallos/errores/fugas.
Regresion completa FINAL: 114 baterias / 3570 PASS / 1 FAIL / 1 roja / 17 notas.
Exit 1 exclusivamente por R2 preexistente de test_letras_red (detalle abajo).
Log integro: D:\SandBox-lsp\testsserver\codex-tests\regresion-final.log.

La primera pasada dio 3559 PASS / 12 FAIL en 114 baterias (7 rojas).
Causas medidas y correcciones del arnes/contrato:

- K7 de test_delphi_test_contenedor: Writeln imprimia el prefijo VE antes de
  que GetDirectories fallase. Salida VE SONDA K7 NO; no era acceso concedido.
  La sonda enumera antes de imprimir. Sin cambiar el check: 44/0.
  Su mutante vuelve a 43/1 y el fixture queda restaurado byte a byte.
- docs/TOOLS.md: las dos lineas generadas de ls-remote estaban desfasadas.
  Actualizadas usando tools_md.render del tools/list de la copia.
  test_docs_consistency: 20/0.
- I7 de test_identificadores esperaba una raiz en la negativa de una ruta
  con salto de linea. GUARD-032 ahora la rechaza sin citar NINGUNA ruta.
  La guarda exige ese codigo y ausencia tanto de la raiz real como virtual.
  test_identificadores: 35/0; el bucle de controles tiene su mutante 5/64.
- L7 de test_round40 suponia TEMP en C: y contenido en D:. Con TEMP propio
  en D:, confundia texto deliberadamente literal con una ruta del servidor.
  El contenido de prueba usa una letra distinta de TEMP; los checks de ruta
  y contenido siguen iguales. Verde 13/0; mutante de letra fija 12/1.
- test_tray y test_workspace_tools usaban el repo del codigo como fixture
  Git; en un worktree su .git comun queda fuera de sus Roots y GIT-041 es
  correcto. Ademas workspace suponia la rama main. Ahora crean un repo
  independiente dentro de su BASE; la jaula del servidor no se amplia al
  .git comun. Verdes 16/0 y 107/0; mutantes de status al repo del codigo
  15/1 y 106/1. Todas las restauraciones se cotejaron con SHA256.

Rojo previo investigado: R2 de test_letras_red, 52/1 tanto en esta rama como
contra COPIA del exe publicado 1.12.1. PathDenied niega tambien por el prefijo
textual de ReadOnlyPaths, mientras el check espera que mande solo la ruta
real. No se cambia esa politica fuera del encargo ni se relaja el check.
Queda para revision de David/Claude, con ambos logs.

Logs de causas, verdes y mutantes: D:\SandBox-lsp\testsserver\codex-tests.
Backups originales (una copia por fichero):
D:\Vaults\AI-Memory\backups\codex\lsp-mcp-server\20261004_174443.
Todos los cambios de fuente y documentacion se hicieron por delphi_*.
El grupo y las baterias se ejecutaron con el arnes permitido.
Auditoria de 15 ficheros contra backup: BOM, CRLF y bytes no ASCII conservados;
sin U+FFFD. diff --check exit 0.

## Entrega local para revision

Commits locales, todos con Co-authored-by: Codex <noreply@openai.com>:
- d008260: controles, Git y recorridos medidos, baterias y contrato ls-remote.
- d159001: sonda K7 enumera antes de anunciar el resultado.
- 78635cb: fixtures independientes del worktree/TEMP y negativa GUARD-032.

La rama no se ha fusionado en main. Antes de integrar, revisar los cambios
concurrentes de Claude, especialmente Lsp.Guard, Lsp.Texts, Workspace y TOOLS.
Pendientes de criterio o de medida: R2 de ReadOnlyPaths; avisos de remote;
seleccion interna de FindDproj; respuesta real del caso de mascara del punto 5.
No se marca ninguna de esas teorias como fallo arreglado.
