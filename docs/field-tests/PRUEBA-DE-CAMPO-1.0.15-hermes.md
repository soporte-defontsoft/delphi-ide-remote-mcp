# Prueba de campo de la v1.0.15-beta — encargo para el agente Hermes

Eres un probador EXTERNO de este servidor MCP. Trabajas con tu propio token
(`[Workspace.Hermes]`), dentro de tu propia jaula, sobre un proyecto real:
**GalateaFMX**, que está en tu sandbox. No conoces el código del servidor ni te
hace falta: lo que se prueba es **lo que las tools te dicen y te dejan hacer**.

Un fallo que encuentres tú vale más que diez baterías verdes: las baterías las
escribió quien hizo el código.

## Cómo se trabaja

1. **Todo por las tools `delphi_*`.** Si una tool te lo pone más difícil que
   hacerlo a mano, ESO es un hallazgo: repórtalo, no lo rodees.
2. **Primera llamada: `delphi_workspace`.** Apunta lo que contesta: `roots`
   (tu jaula), `access`, y el bloque `server` — tiene que decir
   `version: 1.0.15-beta`, `mode`, `transport` y `account`. Si dice otra
   versión, para y repórtalo: estarías probando otro servidor.
3. **Las rutas del servidor son unidades virtuales** (`srvd:\...`). Úsalas tal
   cual te las dan; no son discos tuyos.
4. **Cada fase acaba en un reporte** con `delphi_report` (formato abajo),
   también cuando todo ha ido bien. No esperes al final para reportar.
5. **Si una tool se niega**, lee el mensaje entero: casi siempre dice qué hacer.
   Si el mensaje no te ayuda, eso también es un hallazgo.

## Lo que NO se hace (reglas duras)

- **No salgas de tu jaula** ni intentes saltártela "para probar". Si crees que
  un rechazo de jaula es injusto, repórtalo y sigue.
- **En un escritorio remoto, teclea SOLO en algo que acabas de abrir y nace
  vacío**: el buscador del menú de inicio, la calculadora, un campo de la
  propia app GalateaFMX. **Nunca en un terminal, nunca en un editor de textos
  que ya tuviera un documento, nunca en un navegador con sesión abierta.**
  Haz una captura ANTES de teclear para ver dónde está el foco.
- **No abras, leas ni copies ficheros de credenciales**, ni en el escritorio
  remoto ni en el servidor. Si GalateaFMX te pide usuario y contraseña, **para
  y pídeselos a David**; no los busques.
- **No pulses "guardar", "descartar", "eliminar" ni "enviar"** en nada que no
  hayas creado tú en esta prueba.
- **No publiques nada**: ni `git push`, ni tags. `git status`/`diff`/`log` sí.
- Si una llamada contesta "session expired" o no contesta, **comprueba si se
  ejecutó antes de repetirla** (una captura, un `delphi_read`): puede haberse
  ejecutado igual.

## Fase 0 — Orientación (5 minutos)

- `delphi_workspace` (ver arriba).
- `delphi_help` — léelo: es lo que el servidor dice de sí mismo. Apunta
  cualquier cosa que prometa y luego no cumpla.
- `delphi_projects` sobre tu raíz: localiza el `.dproj` de GalateaFMX.
- `delphi_config` `command=view` sobre ese `.dproj`: plataformas activas, SDK
  y perfil del proyecto.
- `delphi_paserver` `command=profiles`: qué perfiles y SDK hay, con su glibc.

**Reporta:** ¿te ha quedado claro en cinco llamadas qué puedes hacer y dónde?
¿Qué te ha faltado saber?

## Fase 1 — Compilar GalateaFMX

1. `delphi_build` para **Win64** (Debug). Apunta tiempo, errores, y si la
   respuesta te dice dónde ha quedado el binario.
2. `delphi_build` para **Linux64**. Fíjate en los campos `sdk` y `sdkNote`:
   tienen que decir con qué SDK ha enlazado y quién lo decidió (el proyecto o
   el IDE).
3. Si falla por una unit no encontrada, NO edites search paths a ciegas:
   `delphi_config command=view section=searchpaths` y reporta lo que ves.
4. Repite un build con `verbosity=normal` y otro con `quiet`: ¿la versión
   corta te basta para saber si compila? ¿la larga trae lo que falta?

## Fase 2 — Desplegar y ejecutar en Linux

1. `delphi_paserver command=test-connection name=<perfil>` contra el perfil
   Linux que uses (pregunta a David cuál si hay varios).
2. `delphi_build target=Deploy platform=Linux64 profile=<perfil>`.
3. `delphi_paserver command=remote-run project=<dproj> name=<perfil>`: la app
   tiene ventana, así que lo normal es `stillRunning=true` con salida parcial.
   Apunta si la respuesta lo explica bien.
4. **NUEVO en 1.0.15 — repetir `get-sdk`**: `delphi_paserver command=get-sdk
   name=<perfil>` sobre un SDK que YA existe. Tiene que contestar bien, con
   pulls en `already up to date` y una nota `incremental`. Antes de esta
   versión acababa RECHAZADO. Reporta lo que veas.

## Fase 3 — Ver y manejar la app (el escritorio remoto)

Con `delphi_adb_linux profile=<perfil>`:

1. `command=status` y luego `command=screenshot`. Baja la captura con
   `delphi_fetch` y MÍRALA. ¿Se ve GalateaFMX?
2. `command=windows` si la ventana está tapada.
3. **Entra en la app** hasta donde puedas sin credenciales. Si pide login,
   para y pídeselas a David (regla dura).
4. **NUEVO en 1.0.15 — el teclado.** En un campo de texto de la app (o en el
   buscador del menú de inicio), escribe con `command=type`:
   `Prueba 1015-14/2 Año @ (x); ¿ok?`
   Haz captura y compara carácter a carácter. La respuesta tiene que decir
   con qué teclado ha escrito (`teclado: el del escritorio (...)`). Reporta
   CUALQUIER carácter que salga distinto, y cuál es la distribución.
5. **NUEVO en 1.0.15 — el texto se teclea, no se ejecuta.** Escribe en ese
   mismo campo: `hola; echo INYECCION $(id) 'q'`. Tiene que aparecer
   LITERAL. Si ves que algo se ha ejecutado, o la llamada falla con un error
   de sintaxis de shell, es un fallo GRAVE: repórtalo como `kind=bug` con el
   texto exacto de la respuesta.
6. Pide un carácter que ese teclado no tenga (por ejemplo un emoji): tiene
   que rechazarse POR SU NOMBRE, sin escribir otra cosa.
7. Recorre la app: abre dos o tres pantallas, vuelve atrás, ciérrala por su
   botón. ¿Las coordenadas de la captura caen donde pulsas? ¿Cada respuesta
   trae su captura nueva?

Si tu servidor tiene sesión de escritorio abierta, repite 1–2 con
`delphi_desktop` (el escritorio del propio Windows). Sin sesión abierta no
funciona **a propósito** (el usuario tiene que poder ver lo que haces): apunta
si el mensaje lo explica.

## Fase 4 — Editar como lo haría un agente (sobre una COPIA)

No toques el GalateaFMX bueno. Crea un proyecto de juguete en tu jaula:

1. `delphi_create kind=project-fmx name=PruebaHermes dir=<tu raíz>\PruebaHermes`.
2. **NUEVO — subcarpetas**: `delphi_create kind=unit name=UModelo
   project=<dpr> dir=Dominio\Modelos` y un `kind=form-fmx ... dir=Vistas`.
   Comprueba con `delphi_read` del `.dpr` que quedan registradas con su ruta
   relativa, y `delphi_build`.
3. Prueba lo que NO debe colar en `dir`: una ruta absoluta, `..\fuera`, un
   nombre con comillas. Las tres tienen que rechazarse.
4. **NUEVO — mover y borrar carpetas**: `delphi_move` de `Dominio` a `Nucleo`
   y `delphi_build` (tiene que seguir compilando); `delphi_delete` de la
   carpeta y `delphi_build` otra vez.
5. **NUEVO — modo fragmento**: crea un `.md` con un párrafo de una sola línea
   muy larga (500+ caracteres) que contenga un número dos veces. Con
   `delphi_textedit`:
   - `fragment` + `atline` + `new` sobre un trozo único → tiene que cambiar
     SOLO eso.
   - el número repetido → tiene que rechazarse diciendo cuántas veces sale y
     enseñando la línea.
   - sin `atline` → rechazo.
   - dentro de `edits`: `[{"fragment":"...","new":"...","atline":N}]`.
   Repite uno con `delphi_edit` sobre un `.pas`. ¿El mensaje de rechazo te
   basta para corregir a la primera?
6. `delphi_changeset`: un cambio que toque el `.pas` y el `.md` a la vez,
   con `preview` y `commit`.
7. `delphi_symbols` sobre una unit con un bloque `{$IFDEF LINUX}`: la rutina
   de dentro NO sale, y la descripción de la tool tiene que avisarlo.
8. `delphi_package` de la carpeta de salida **Linux64**: la respuesta tiene
   que traer `linuxNote` (el `chmod +x`).

## Fase 5 — Lo que tú veas

Media hora libre usando el servidor para algo que te parezca natural en
GalateaFMX (buscar dónde se usa una clase con `delphi_references`, un
`delphi_rename_symbol` en preview, `delphi_diagnostics` de una unit grande,
`delphi_styles lint`). Apunta fricciones: parámetros que no adivinas a la
primera, respuestas demasiado largas o demasiado cortas, mensajes que no
dicen qué hacer, tiempos que se van de madre.

## Cómo reportar

Una llamada a `delphi_report` por hallazgo (o por fase, si fue bien):

```json
{
  "agent": "hermes",
  "from": "Hermes - prueba de campo 1.0.15",
  "kind": "bug | limitation | suggestion | question",
  "title": "Fase 3.4 - la @ sale como 2 en teclado X",
  "message": "QUÉ HICE (la llamada exacta, con sus parámetros)\nQUÉ PASÓ (la respuesta LITERAL, pegada)\nQUÉ ESPERABA\nGRAVEDAD: bloquea | molesta | cosmético\nREPRODUCIBLE: siempre | a veces | una vez"
}
```

Reglas del reporte:

- **Pega la respuesta literal**, no la resumas: el fallo suele estar en una
  palabra.
- **Una cosa por reporte.** Tres fallos = tres reportes.
- Distingue **lo que has medido** de lo que supones. "Creo que" va marcado.
- Si algo te sorprendió para bien, dilo también: sirve para saber qué no tocar.
- Al terminar, un último reporte `title: "RESUMEN prueba de campo 1.0.15"`
  con: fases hechas, fases que no pudiste hacer y por qué, y tus tres
  hallazgos más importantes por orden.

## Qué hay de nuevo en esta versión (para que sepas dónde mirar)

- Modo fragmento en toda la familia de edición.
- Subcarpetas de proyecto: `delphi_create dir=`, mover y borrar carpetas.
- `delphi_adb_linux type`: teclea con el teclado real del escritorio destino,
  y el texto viaja como texto, nunca como orden de shell (arreglo de
  SEGURIDAD).
- `get-sdk` repetido ya no se rechaza.
- Ficheros en CP1252 ya no rompen `delphi_styles lint` ni esconden notas del
  vault.
- `delphi_workspace` dice con qué cuenta de Windows corre el servidor.

El detalle está en `CHANGELOG.md`, entrada `[1.0.15-beta]`.
