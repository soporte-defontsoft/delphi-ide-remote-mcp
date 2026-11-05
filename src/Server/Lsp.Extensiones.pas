unit Lsp.Extensiones;

{ Que es un fichero por su EXTENSION: fuente, designer, estilo, proyecto,
  manifiesto de despliegue; las listas de extensiones del motor y sus mascaras.
  Sin abrir ningun fichero. Vivia en Lsp.Patch (V94 de la depuracion de la
  1.23, B6 de la 1.28): se mudo sin cambiar una linea. }

interface

{ Los ficheros que edita el motor de Pascal (delphi_edit): sus fuentes y
  sus designers; el resto, el de texto. Vivia en Lsp.Changeset con su
  propia lista; aqui sale de las del motor (novena revision). }
function EsDelMotorPascal(const APath: string): Boolean;

const
  // LAS listas de extensiones del motor: quien pregunte por una extension
  // Delphi las usa. Estaban copiadas en AvisosDeLlaves, FileOps (x4),
  // ProjectUnits y TextEdit (decima revision)
  SOURCE_EXTS: array [0 .. 3] of string = ('.pas', '.dpr', '.dpk', '.inc');
  DESIGNER_EXTS: array [0 .. 1] of string = ('.dfm', '.fmx');
  PROJECT_EXTS: array [0 .. 1] of string = ('.dproj', '.groupproj');
  // el manifiesto de despliegue del IDE: al lado del .dproj y con su nombre
  EXT_MANIFIESTO = '.deployproj';

{ Si APath es un designer por su extension (DESIGNER_EXTS: .dfm, .fmx), sea
  de texto o binario. EL predicado: estaba escrito a mano con su lista en
  nueve sitios (4.1 de la 1.18.0, al pasarselo al detector). }
function EsRutaDeDesigner(const APath: string): Boolean;
{ Si APath es un estilo de FMX por su extension (.style), de texto o
  binario: el de texto lo lee el parser de los forms (TParser). EL
  predicado: estaba comparado a mano en Lsp.TextEdit y Mcp.Tools.Styles, y
  el escritor necesita saberlo (M4 de la 1.23). }
function EsRutaDeEstilo(const APath: string): Boolean;
{ Si APath es un FUENTE por su extension (SOURCE_EXTS: .pas, .dpr, .dpk,
  .inc): lo que lee dcc, cada uno con su propio BOM (medido el 9-oct-2026,
  tambien un .inc incluido desde un .pas sin BOM). EL predicado, como
  EsRutaDeDesigner: estaba escrito a mano con su lista en cinco sitios. }
function EsRutaDeFuente(const APath: string): Boolean;
{ Si APath es un PROYECTO del IDE por su extension (PROJECT_EXTS: .dproj,
  .groupproj): lo que lleva delphi_config, y ni delphi_edit ni delphi_textedit
  escriben. EL predicado: los dos rechazos se mandaban el uno al otro y
  ninguno a delphi_config (Hermes, dirigido de la 1.20.1). }
function EsRutaDeProyecto(const APath: string): Boolean;
{ LA negativa de escribir un fichero de PROYECTO por una tool de texto
  (EDIT-128, que manda a delphi_config y delphi_create); '' si APath no lo es.
  La piden las tres puertas que escriben texto, delphi_edit, delphi_textedit y
  delphi_changeset: estaba a mano en las tres, y la del changeset solo negaba
  editar, asi que un create de un .dproj se apilaba y se escribia (C4 del
  cierre de la 1.26). }
function ProyectoDenegado(const APath: string): string;
{ Si APath es un fichero que el IDE carga como XML: un proyecto
  (EsRutaDeProyecto) o su manifiesto de despliegue (.deployproj). Lo que de
  ellos escribe el servidor lo juzga antes el parser del IDE (PatchSaveText). }
function EsXmlDelIde(const APath: string): Boolean;
{ Si APath es un manifiesto de despliegue del IDE (EXT_MANIFIESTO), por como
  acaba: tambien el Project de un <Import> ($(MSBuildProjectName).deployproj),
  que no es una ruta. EL predicado: estaba a mano en el build, en la mudanza y
  en EsXmlDelIde (paisaje medido el 23-oct-2026). }
function EsManifiesto(const APath: string): Boolean;
{ ...y el de ADproj, al lado y con su nombre (la regla del IDE). EL
  compositor: estaba escrito tres veces (dos en el build y uno en config). }
function ManifiestoDe(const ADproj: string): string;
{ Si APath es un fichero de DELPHI: lo del motor de Pascal (EsDelMotorPascal:
  fuentes y designers) o un proyecto del IDE (PROJECT_EXTS). Lo que
  delphi_textedit no edita y lo que el changeset no mueve ni borra suelto -
  eso lo hacen delphi_move y delphi_delete enteros (B de la 1.19.2) -. Estaba
  escrito en ExtGate (Lsp.TextEdit); a la segunda, aqui. }
function EsFicheroDeDelphi(const APath: string): Boolean;
{ Las mascaras de fichero de una de esas listas ('.dfm' -> '*.dfm'), para
  recorrer una carpeta con ellas. Las escribian a mano Mcp.Tools.Workspace
  (las de delphi_search y delphi_list), Lsp.Rename (las de designer) y
  Lsp.BuildRunner (las de fuente) (revisor propio de la 4.1, 9-oct-2026). }
function MascarasDe(const AExts: array of string): TArray<string>;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Lsp.Rutas, // TieneExtension: LA comparacion de una extension
  Lsp.Texts;

function EsRutaDeDesigner(const APath: string): Boolean;
begin
  Result := TieneExtension(APath, DESIGNER_EXTS);
end;

function EsRutaDeEstilo(const APath: string): Boolean;
begin
  Result := SameText(TPath.GetExtension(APath), '.style');
end;

function EsRutaDeFuente(const APath: string): Boolean;
begin
  Result := TieneExtension(APath, SOURCE_EXTS);
end;

function EsRutaDeProyecto(const APath: string): Boolean;
begin
  Result := TieneExtension(APath, PROJECT_EXTS);
end;

function ProyectoDenegado(const APath: string): string;
begin
  Result := '';
  if EsRutaDeProyecto(APath) then
    Result := MsgFmt(SR_EDIT_FICHERO_DE_PROYECTO_FMT, [TPath.GetFileName(APath)]);
end;

function EsXmlDelIde(const APath: string): Boolean;
begin
  Result := EsRutaDeProyecto(APath) or EsManifiesto(APath);
end;

function EsManifiesto(const APath: string): Boolean;
begin
  Result := APath.Trim.EndsWith(EXT_MANIFIESTO, True);
end;

function ManifiestoDe(const ADproj: string): string;
begin
  Result := TPath.ChangeExtension(ADproj, EXT_MANIFIESTO);
end;

function EsFicheroDeDelphi(const APath: string): Boolean;
begin
  Result := EsDelMotorPascal(APath) or EsRutaDeProyecto(APath);
end;

function MascarasDe(const AExts: array of string): TArray<string>;
begin
  Result := [];
  for var E in AExts do
    Result := Result + ['*' + E];
end;

function EsDelMotorPascal(const APath: string): Boolean;
begin
  Result := EsRutaDeFuente(APath) or EsRutaDeDesigner(APath);
end;

end.
