unit Lsp.RegistroDelIde;

{ LA puerta de escribir del REGISTRO del IDE (EscribeClaveDelIde,
  BorraClaveDelIde) y la copia en la casa de lo que del IDE se pisa o se borra
  (GuardaCopiaDelIde), con su tope. Vivian en Lsp.Patch (V94 de la depuracion de
  la 1.23, B6 de la 1.28): se mudaron sin cambiar una linea. }

interface

uses
  System.SysUtils; // TProc: lo que guarda una copia

type
  { Un valor que EscribeClaveDelIde pone en una clave del IDE: texto o entero }
  TValorDelIde = record
    Nombre: string;
    Texto: string;
    Entero: Integer;
    EsEntero: Boolean;
  end;

function ValorDeTexto(const ANombre, ATexto: string): TValorDelIde;
function ValorEntero(const ANombre: string; AEntero: Integer): TValorDelIde;

{ LA puerta de escribir del REGISTRO del IDE, la gemela de EscribeBytes con
  el IDE como lugar: AValores en la clave SOFTWARE\Embarcadero\BDS\<AVersion>\
  <ASubclave> del usuario (se crea si no esta; sus otros valores no se tocan).
  La que ya estaba se exporta ANTES a la casa del servidor con reg.exe - el
  exportador de Windows: abrir la copia la devuelve - por el nombrador de las
  copias del IDE (FicheroDeClaveDelIde), y la que ya dice esos valores ni se
  escribe ni se copia (A4). Devuelve la copia, '' si no hubo. Lanza si no pudo
  copiar o escribir: sin copia no se toca (V10, 24-oct-2026: los asientos de
  SDKs y perfiles se pisaban y se borraban sin copia). }
function EscribeClaveDelIde(const AVersion, ASubclave: string;
  const AValores: array of TValorDelIde): string;
{ ...y BORRAR una clave del IDE entera (con sus subclaves), exportada antes
  igual. '' si no estaba. Lanza si no pudo copiar o borrar. }
function BorraClaveDelIde(const AVersion, ASubclave: string): string;
{ La copia en la casa de algo del IDE antes de pisarlo o borrarlo (lo dice su
  cuerpo): la del registro, aqui, y la de un fichero del IDE, la de
  CopiaAntesDePisar en Lsp.Puertas. }
function GuardaCopiaDelIde(const ANombre: string; const AGuarda: TProc<string>): string;

implementation

uses
  System.IOUtils,
  System.Win.Registry, // EscribeClaveDelIde: la puerta del registro del IDE
  Winapi.Windows,
  Lsp.Puertas,         // LugarDeEscrituraDenegado, BorraFichero: la casa por su puerta
  Lsp.Guard,           // CrearCarpeta
  Lsp.Casa,            // CopiaDelIde, CopiasDelIde, FicheroDeClaveDelIde: el nombrador de las copias
  Lsp.Discovery,       // ClaveDelIde: la clave del IDE
  Lsp.BuildRunner,     // RunCaptured: reg.exe, la copia de una clave
  Lsp.ProcessLaunch,   // EnComillas: los argumentos de esa linea
  Lsp.Texts;

const
  // cuantas copias de UN fichero del IDE se guardan: politica de la casa, no
  // hay juez. Repetir get-sdk tras actualizar el destino (lo que manda su
  // descripcion) copia el .sdk cada vez, y ide-copias crecia sin limite
  // (revisor de P3)
  COPIAS_DEL_IDE_POR_FICHERO = 10;

{ La copia en la casa de algo del IDE que se va a pisar o borrar: ANombre la
  nombra (CopiaDelIde: la ruta de un fichero, o FicheroDeClaveDelIde para una
  clave del registro) y AGuarda la escribe en la ruta que se le da - copiar el
  fichero, exportar la clave -. Luego, las mas viejas de ese nombre fuera.
  Lanza si no se pudo: sin copia no se toca. Era el cuerpo de
  CopiaAntesDePisar, solo para ficheros (V10: el registro, sin copia). }
function GuardaCopiaDelIde(const ANombre: string; const AGuarda: TProc<string>): string;
var
  Motivo: string;
  Copias: TArray<string>;
begin
  Result := CopiaDelIde(ANombre);
  Motivo := LugarDeEscrituraDenegado(Result, ltCasa);
  if Motivo <> '' then
    raise Exception.Create(Motivo);
  CrearCarpeta(TPath.GetDirectoryName(Result));
  AGuarda(Result);
  // las mas viejas de ESE fichero fuera, por la puerta de borrar de la casa.
  // La purga nunca para lo que se iba a hacer (la copia ya esta), y la que
  // se acaba de hacer no se borra aunque el reloj haya vuelto atras (el
  // sello es la hora local: el cambio de hora repite una)
  try
    Copias := CopiasDelIde(ANombre);
  except
    Copias := nil;
  end;
  for var I := 0 to Length(Copias) - COPIAS_DEL_IDE_POR_FICHERO - 1 do
    if not SameText(Copias[I], Result) then
      try
        BorraFichero(Copias[I], ltCasa);
      except
      end;
end;

function ValorDeTexto(const ANombre, ATexto: string): TValorDelIde;
begin
  Result := Default(TValorDelIde);
  Result.Nombre := ANombre;
  Result.Texto := ATexto;
end;

function ValorEntero(const ANombre: string; AEntero: Integer): TValorDelIde;
begin
  Result := Default(TValorDelIde);
  Result.Nombre := ANombre;
  Result.Entero := AEntero;
  Result.EsEntero := True;
end;

{ La clave AClave (bajo HKCU) exportada a ACopia por reg.exe, el exportador
  de Windows: un .reg que se devuelve abriendolo. Lanza si no quedo. }
procedure ExportaClaveDelIde(const AClave, ACopia: string);
var
  Sistema: array[0..MAX_PATH] of Char;
  Dir, Salida: string;
  Codigo: Cardinal;
begin
  // reg.exe POR SU RUTA, la de System32, donde el agente no escribe: un
  // programa nunca se busca por su nombre a secas (CLAUDE.md, 13-oct-2026);
  // cada argumento por EL compositor (EnComillas), sin shell
  SetString(Dir, Sistema, GetSystemDirectory(Sistema, Length(Sistema)));
  // sin la carpeta del sistema, 'reg.exe' a secas se buscaria en la actual
  if Dir = '' then
    raise Exception.Create(MsgFmt(SR_IDE_CLAVE_SIN_COPIA_FMT, [AClave, SysErrorMessage(GetLastError)]));
  Salida := RunCaptured(EnComillas(TPath.Combine(Dir, 'reg.exe')) + ' export ' +
    EnComillas('HKCU\' + AClave) + ' ' + EnComillas(ACopia) + ' /y', 30000, Codigo);
  if (Codigo <> 0) or not TFile.Exists(ACopia) then
    raise Exception.Create(MsgFmt(SR_IDE_CLAVE_SIN_COPIA_FMT, [AClave, Salida.Trim]));
end;

{ La copia previa de una clave del IDE (AClave, la de AVersion y ASubclave), antes
  de escribirla o de borrarla. }
function CopiaDeClaveDelIde(const AVersion, ASubclave, AClave: string): string;
begin
  Result := GuardaCopiaDelIde(FicheroDeClaveDelIde(AVersion, ASubclave),
    procedure(ACopia: string)
    begin
      ExportaClaveDelIde(AClave, ACopia);
    end);
end;

{ La clave abierta en R ya dice AValores: cada uno esta, con su tipo y su dato. }
function ClaveYaDice(R: TRegistry; const AValores: array of TValorDelIde): Boolean;
begin
  for var V in AValores do
    try
      if not R.ValueExists(V.Nombre) then
        Exit(False);
      if V.EsEntero then
      begin
        if (R.GetDataType(V.Nombre) <> rdInteger) or (R.ReadInteger(V.Nombre) <> V.Entero) then
          Exit(False);
      end
      else if not (R.GetDataType(V.Nombre) in [rdString, rdExpandString]) or
        (R.ReadString(V.Nombre) <> V.Texto) then
        Exit(False);
    except
      Exit(False); // lo que no se lee no es igual
    end;
  Result := True;
end;

function EscribeClaveDelIde(const AVersion, ASubclave: string;
  const AValores: array of TValorDelIde): string;
var
  R: TRegistry;
  Clave: string;
begin
  Result := '';
  Clave := ClaveDelIde(AVersion, ASubclave);
  R := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    R.RootKey := HKEY_CURRENT_USER;
    if R.OpenKey('\' + Clave, False) then
    begin
      if ClaveYaDice(R, AValores) then
        Exit;
      R.CloseKey;
      Result := CopiaDeClaveDelIde(AVersion, ASubclave, Clave);
    end;
    if not R.OpenKey('\' + Clave, True) then
      raise Exception.Create(MsgFmt(SR_IDE_CLAVE_NO_ESCRITA_FMT, [Clave]));
    for var V in AValores do
      if V.EsEntero then
        R.WriteInteger(V.Nombre, V.Entero)
      else
        R.WriteString(V.Nombre, V.Texto);
    R.CloseKey;
  finally
    R.Free;
  end;
end;

function BorraClaveDelIde(const AVersion, ASubclave: string): string;
var
  R: TRegistry;
  Clave: string;
begin
  Result := '';
  Clave := ClaveDelIde(AVersion, ASubclave);
  R := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    R.RootKey := HKEY_CURRENT_USER;
    if not R.KeyExists('\' + Clave) then
      Exit;
    Result := CopiaDeClaveDelIde(AVersion, ASubclave, Clave);
    if not R.DeleteKey('\' + Clave) then
      raise Exception.Create(MsgFmt(SR_IDE_CLAVE_NO_ESCRITA_FMT, [Clave]));
  finally
    R.Free;
  end;
end;

end.
