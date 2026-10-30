unit Lsp.Reparse;

{ LA pregunta "es esto un ENLACE": del servidor y de los renderizadores, que no
  enlazan el guard (V126 de la 1.24). Sin dependencias: Lsp.Rutas arrastraria
  Lsp.Texts hasta el ayudante.

  Un punto de reparse no es por si mismo un enlace. Lo dice su etiqueta: el bit
  "name surrogate" (IsReparseTagNameSurrogate de winnt.h) es el de los que
  apuntan a OTRA entidad con nombre: junction, symlink, el de WSL. Sin el son el
  contenido del propio fichero: un marcador de OneDrive, de dedup, un alias de
  WindowsApps (8000001B, medido aqui con el atributo 00000420). Con solo el
  atributo, un proyecto en un Documentos de OneDrive era todo enlaces: no se
  recorria, no se purgaba, sus hermanos no se leian. }

interface

uses
  System.SysUtils;

{ La etiqueta es de un enlace. }
function EtiquetaDeEnlace(ATag: Cardinal): Boolean;

{ FSCTL_GET_REPARSE_POINT del propio ARuta (sin seguirlo): su REPARSE_DATA_BUFFER
  y cuantos bytes trae, con su etiqueta al principio. False si no es un punto de
  reparse o no se deja leer. Se abre con acceso 0: no molesta a otro escritor. }
function DatosDeReparse(const ARuta: string; out ABuf: TBytes; out ADevuelto: Cardinal): Boolean;

{ ARuta es un enlace. Uno cuya etiqueta no se deja leer cuenta como enlace (una
  ACE que se la quita a la cuenta del servicio): Windows lo atraviesa igual y
  quien pregunta es quien no debe seguirlo. Lo que no existe no lo es. }
function EsEnlace(const ARuta: string): Boolean;

implementation

uses
  Winapi.Windows;

function EtiquetaDeEnlace(ATag: Cardinal): Boolean;
const
  BIT_NAME_SURROGATE = $20000000;
begin
  Result := (ATag and BIT_NAME_SURROGATE) <> 0;
end;

function DatosDeReparse(const ARuta: string; out ABuf: TBytes; out ADevuelto: Cardinal): Boolean;
const
  FSCTL_GET_REPARSE_POINT = $000900A8;
  MAXIMUM_REPARSE_DATA_BUFFER_SIZE = 16 * 1024;
var
  H: THandle;
begin
  Result := False;
  ABuf := nil;
  ADevuelto := 0;
  H := CreateFile(PChar(ARuta), 0, FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil,
    OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT or FILE_FLAG_BACKUP_SEMANTICS, 0);
  if H = INVALID_HANDLE_VALUE then
    Exit;
  try
    SetLength(ABuf, MAXIMUM_REPARSE_DATA_BUFFER_SIZE);
    Result := DeviceIoControl(H, FSCTL_GET_REPARSE_POINT, nil, 0, @ABuf[0], Length(ABuf), ADevuelto, nil) and
      (ADevuelto >= SizeOf(Cardinal));
  finally
    CloseHandle(H);
  end;
end;

function EsEnlace(const ARuta: string): Boolean;
var
  A, Devuelto: Cardinal;
  Buf: TBytes;
begin
  A := GetFileAttributes(PChar(ARuta));
  if (A = INVALID_FILE_ATTRIBUTES) or ((A and FILE_ATTRIBUTE_REPARSE_POINT) = 0) then
    Exit(False);
  Result := not DatosDeReparse(ARuta, Buf, Devuelto) or EtiquetaDeEnlace(PCardinal(@Buf[0])^);
end;

end.
