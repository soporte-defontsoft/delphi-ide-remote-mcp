unit Lsp.DesignerBin;

{ Un .dfm BINARIO, y el camino de ida y vuelta a texto que usa el propio IDE
  ("Ver como texto" y guardar): las funciones de System.Classes que Delphi
  trae de serie, sin procesos ni ficheros temporales. Los .fmx son siempre
  texto: esto es solo VCL.

  Dos formas binarias, medidas con convert.exe (2026-09-24):
    - el fichero REAL en disco envuelve el flujo en una cabecera de recurso de
      16 bits: FF 0A 00 + NOMBRE EN MAYUSCULAS + 00 + flags/tamano + TPF0...
    - un flujo a pelo empieza por TPF0 (lo que escribe un WriteComponent).
  Un designer de texto empieza siempre por object/inherited/inline: nunca por
  $FF ni por TPF0.

  UN NOMBRADOR para la forma del fichero: hasta hoy cuatro sitios (Lsp.Patch,
  Lsp.ProjectUnits, Mcp.Tools.Designer, delphi_upload) comparaban los bytes a
  mano, cada uno con su copia de la regla. Y un solo conversor, el de la RTL:
  lo que escribe to-binary es byte a byte lo que escribe el IDE, y lo que lee
  to-text es lo que ensena "Ver como texto". Decision de David (24-sep-2026)
  tras el reporte de Hermes: un form legacy binario dejaba ciego al agente. }

interface

uses
  System.SysUtils;

type
  TDesignerShape = (dsText, dsTpf0, dsResource);

{ La forma de un designer a partir de sus primeros bytes. }
function DesignerShapeOf(const ABytes: TBytes): TDesignerShape;
function IsBinaryDesignerBytes(const ABytes: TBytes): Boolean;
{ Lo mismo leyendo del disco: False si no existe o no llega a 4 bytes. }
function IsBinaryDesignerFile(const APath: string): Boolean;
{ Binario (cualquiera de las dos formas) -> texto, como "Ver como texto" del
  IDE. Devuelve '' si bien; si no, el motivo (fichero danado, no es un
  designer). El texto sale ASCII con CRLF, que es lo que escribe convert.exe. }
function DesignerBinaryToText(const ABytes: TBytes; out AText: string): string;
function DesignerFileToText(const APath: string; out AText: string): string;
{ Texto -> binario CON envoltorio de recurso (la forma en disco del IDE).
  Devuelve '' si bien; si no, el error del parser con su linea. }
function DesignerTextToBinary(const AText: string; out ABytes: TBytes): string;

implementation

uses
  System.Classes, System.IOUtils;

function DesignerShapeOf(const ABytes: TBytes): TDesignerShape;
begin
  Result := dsText;
  if Length(ABytes) < 4 then
    Exit;
  if ABytes[0] = $FF then
    Exit(dsResource);
  if (ABytes[0] = $54) and (ABytes[1] = $50) and (ABytes[2] = $46) and (ABytes[3] = $30) then
    Exit(dsTpf0);
end;

function IsBinaryDesignerBytes(const ABytes: TBytes): Boolean;
begin
  Result := DesignerShapeOf(ABytes) <> dsText;
end;

function IsBinaryDesignerFile(const APath: string): Boolean;
var
  S: TFileStream;
  B: TBytes;
begin
  Result := False;
  if not TFile.Exists(APath) then
    Exit;
  S := TFileStream.Create(APath, fmOpenRead or fmShareDenyNone);
  try
    if S.Size < 4 then
      Exit;
    SetLength(B, 4);
    S.ReadBuffer(B[0], 4);
  finally
    S.Free;
  end;
  Result := IsBinaryDesignerBytes(B);
end;

function DesignerBinaryToText(const ABytes: TBytes; out AText: string): string;
var
  Entrada, Salida: TMemoryStream;
  Bytes: TBytes;
begin
  Result := '';
  AText := '';
  Entrada := TMemoryStream.Create;
  Salida := TMemoryStream.Create;
  try
    if Length(ABytes) > 0 then
      Entrada.WriteBuffer(ABytes[0], Length(ABytes));
    Entrada.Position := 0;
    try
      case DesignerShapeOf(ABytes) of
        dsResource: ObjectResourceToText(Entrada, Salida);
        dsTpf0: ObjectBinaryToText(Entrada, Salida);
      else
        Exit('no es un designer binario: empieza como texto');
      end;
    except
      on E: Exception do
        Exit('designer BINARIO danado o que no es un .dfm: no pude convertirlo ' +
          'a texto (' + E.ClassName + ': ' + E.Message + ')');
    end;
    SetLength(Bytes, Salida.Size);
    if Salida.Size > 0 then
      Move(Salida.Memory^, Bytes[0], Salida.Size);
    // El texto de un .dfm es ASCII: lo que no cabe va como #NNN. UTF-8 lo lee
    // tal cual y no inventa nada.
    AText := TEncoding.UTF8.GetString(Bytes);
  finally
    Entrada.Free;
    Salida.Free;
  end;
end;

function DesignerFileToText(const APath: string; out AText: string): string;
begin
  AText := '';
  if not TFile.Exists(APath) then
    Exit('no existe ' + APath);
  Result := DesignerBinaryToText(TFile.ReadAllBytes(APath), AText);
end;

function DesignerTextToBinary(const AText: string; out ABytes: TBytes): string;
var
  Entrada, Salida: TMemoryStream;
  Bytes: TBytes;
begin
  Result := '';
  ABytes := nil;
  Entrada := TMemoryStream.Create;
  Salida := TMemoryStream.Create;
  try
    // El parser de la RTL (el mismo que usa el IDE al cargar un .dfm de
    // texto) lee los bytes como ANSI: darle UTF-8 convertia una 'o' con
    // acento en #195#179 (medido 24-sep-2026). Lo normal en un .dfm de
    // texto es que lo no-ASCII vaya como #NNN, que es como lo escribe el IDE
    // y como lo escribe to-text; una 'o' en crudo se le da en ANSI, y lo que
    // ANSI no puede representar se rechaza en vez de escribir '?'.
    Bytes := TEncoding.ANSI.GetBytes(AText);
    if TEncoding.ANSI.GetString(Bytes) <> AText then
      Exit('el texto lleva caracteres que no caben en la pagina de codigos ' +
        'ANSI de esta maquina: en un .dfm de texto se escriben como #NNNN ' +
        '(codigo decimal del caracter, fuera de las comillas), como hace el ' +
        'IDE. Corrigelos y repite.');
    if Length(Bytes) > 0 then
      Entrada.WriteBuffer(Bytes[0], Length(Bytes));
    Entrada.Position := 0;
    try
      ObjectTextToResource(Entrada, Salida);
    except
      on E: Exception do
        Exit('no pude convertir el texto a designer binario (' + E.ClassName +
          ': ' + E.Message + ')');
    end;
    SetLength(ABytes, Salida.Size);
    if Salida.Size > 0 then
      Move(Salida.Memory^, ABytes[0], Salida.Size);
  finally
    Entrada.Free;
    Salida.Free;
  end;
end;

end.
