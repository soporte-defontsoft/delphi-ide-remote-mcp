unit Lsp.InlineImages;

{ Una imagen en la MISMA respuesta de la tool: captura en UN SOLO PASO (David,
  25-sep-2026: "1 solo paso es lo logico"). Antes el agente capturaba y luego
  bajaba el fichero en una segunda llamada, y los ficheros se acumulaban.

  Tres piezas, cada una una vez:
    - AttachImage: una tool deja una imagen para la respuesta de ESTA llamada.
    - WrapWithAttachedImages: el host la envuelve junto al texto (lo llama el
      gestor de tools, en el mismo punto que el filtro de salida). Vale para
      cualquier tool, hoy y manana.
    - DeliverCapture: como se ENTREGA una captura, la misma en toda tool que
      capture (delphi_desktop, delphi_adb): o inline, escalada en memoria y con
      su temporal consumido al momento, o fichero + enlace de descarga.
  La proxima tool que capture algo llama a DeliverCapture y ya esta. }

interface

uses
  System.JSON;

{ Descarta lo adjuntado en este hilo: el host lo llama al empezar cada
  llamada (los hilos del servidor HTTP se reutilizan). }
procedure ClearAttachedImages;

{ Deja una imagen para la respuesta de la llamada en curso. }
procedure AttachImage(const ABytes: TArray<Byte>; const AMime: string);

{ El texto de la tool + las imagenes adjuntas, como array de contenido MCP
  (item text + items image en base64). nil si no hay nada adjunto. Se lleva
  los adjuntos: una segunda llamada devuelve nil. }
function WrapWithAttachedImages(const AText: string): TJSONArray;

{ Entrega una captura ya en disco (AFile) en AReturn. AInline = el parametro
  inline de la tool ('false'/'0'/'no' = fichero + enlace), AMaxWidth = el
  maxwidth (0 = el de la casa). True si viajo inline. Nunca modifica AFile:
  si es un temporal del agente (IsAgentCapture) lo consume; un out= se queda. }
function DeliverCapture(const AToolName, AFile, AInline: string;
  AMaxWidth, AOriginX, AOriginY: Integer; ATapScaleX, ATapScaleY: Double;
  AReturn: TJSONObject): Boolean;

{ EL nombrador del frame y su inversa. Un frame es la geometria de la imagen
  que el agente mira, dentro del token: '<imgW>x<imgH>@<srcW>x<srcH>+<ox>+<oy>'
  = la imagen mide imgW x imgH y cubre srcW x srcH del espacio de tap,
  empezando en (ox,oy). Sin estado: el token lo lleva todo, el agente lo
  copia y el servidor convierte. Absorbe las TRES cuentas que el agente hacia
  a mano: dividir por la escala inline, sumar el origen de un recorte y
  multiplicar por el tapScale de Android (David, 25-sep-2026: 'arregla la
  fuga'; un modelo pequeno se salta la cuenta y pulsa donde no es). }
function FrameOf(AImgW, AImgH, ASrcW, ASrcH, AOX, AOY: Integer): string;

{ x,y medidos sobre la imagen de AFrame -> pixeles del espacio de tap. Sin
  frame, AX/AY tal cual (pixeles de la captura, como siempre). '' = bien;
  si no, el rechazo: frame mal formado o punto fuera de su imagen. }
function FramePoint(const AFrame, AX, AY: string; out AOutX, AOutY: Integer): string;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.StrUtils,
  System.RegularExpressions,
  Lsp.Base64,   // BytesToBase64: EL codificador de la casa
  Lsp.Imagen,   // EscalaPngBytes: escalar en memoria
  Lsp.Guard,    // IsAgentCapture / ConsumeAgentCapture
  Lsp.Files,    // DownloadLinkFor: el enlace, el mismo que da delphi_fetch
  Lsp.Texts;

const
  INLINE_MAXWIDTH = 1280; // legible y ligero: ~300 KB de un escritorio de 3440

type
  TAdjunto = record
    Bytes: TArray<Byte>;
    Mime: string;
  end;

threadvar
  // Por hilo, nunca en un campo: las tools son singletons y el servidor HTTP
  // atiende varias llamadas a la vez.
  TAdjuntos: TArray<TAdjunto>;

procedure ClearAttachedImages;
begin
  TAdjuntos := nil;
end;

procedure AttachImage(const ABytes: TArray<Byte>; const AMime: string);
var
  A: TAdjunto;
begin
  A.Bytes := ABytes;
  A.Mime := AMime;
  TAdjuntos := TAdjuntos + [A];
end;

function WrapWithAttachedImages(const AText: string): TJSONArray;
var
  Item: TJSONObject;
  Lista: TArray<TAdjunto>;
  I: Integer;
begin
  Result := nil;
  Lista := TAdjuntos;
  TAdjuntos := nil;
  if Length(Lista) = 0 then
    Exit;
  Result := TJSONArray.Create;
  Item := TJSONObject.Create;
  Item.AddPair('type', 'text');
  Item.AddPair('text', AText);
  Result.AddElement(Item);
  for I := 0 to High(Lista) do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('type', 'image');
    Item.AddPair('data', BytesToBase64(Lista[I].Bytes));
    Item.AddPair('mimeType', Lista[I].Mime);
    Result.AddElement(Item);
  end;
end;

function FrameOf(AImgW, AImgH, ASrcW, ASrcH, AOX, AOY: Integer): string;
begin
  Result := Format('%dx%d@%dx%d+%d+%d', [AImgW, AImgH, ASrcW, ASrcH, AOX, AOY]);
end;

function FramePoint(const AFrame, AX, AY: string; out AOutX, AOutY: Integer): string;
var
  M: TMatch;
  IW, IH, SW, SH, OX, OY, X, Y: Integer;
begin
  Result := '';
  AOutX := StrToIntDef(AX.Trim, -1);
  AOutY := StrToIntDef(AY.Trim, -1);
  if AFrame.Trim = '' then
    Exit; // sin frame: pixeles de la captura, el contrato de siempre
  M := TRegEx.Match(AFrame.Trim, '^(\d{1,6})x(\d{1,6})@(\d{1,6})x(\d{1,6})\+(-?\d{1,6})\+(-?\d{1,6})$');
  if not M.Success then
    Exit(Format(SR_CAPTURE_FRAME_BAD_FMT, [AFrame.Trim]));
  IW := StrToInt(M.Groups[1].Value);
  IH := StrToInt(M.Groups[2].Value);
  SW := StrToInt(M.Groups[3].Value);
  SH := StrToInt(M.Groups[4].Value);
  OX := StrToInt(M.Groups[5].Value);
  OY := StrToInt(M.Groups[6].Value);
  if (IW <= 0) or (IH <= 0) or (SW <= 0) or (SH <= 0) then
    Exit(Format(SR_CAPTURE_FRAME_BAD_FMT, [AFrame.Trim]));
  X := AOutX;
  Y := AOutY;
  if (X < 0) or (Y < 0) or (X >= IW) or (Y >= IH) then
    Exit(Format(SR_CAPTURE_FRAME_OUT_FMT, [AX.Trim, AY.Trim, IW, IH]));
  AOutX := OX + Round(X * SW / IW);
  AOutY := OY + Round(Y * SH / IH);
end;

function DeliverCapture(const AToolName, AFile, AInline: string;
  AMaxWidth, AOriginX, AOriginY: Integer; ATapScaleX, ATapScaleY: Double;
  AReturn: TJSONObject): Boolean;
var
  Bytes: TArray<Byte>;
  Escala: Double;
  MaxW, W, H, W0, H0, SrcW, SrcH: Integer;
  Fallo, Enlace: string;

  // El frame de la imagen que el agente va a mirar (IW x IH): cubre la
  // region del fichero en el espacio de tap, desde el origen.
  procedure PonFrame(IW, IH: Integer);
  begin
    if (IW <= 0) or (SrcW <= 0) then
      Exit;
    AReturn.AddPair('frame', FrameOf(IW, IH, SrcW, SrcH, AOriginX, AOriginY));
    AReturn.AddPair('frameNote', SN_CAPTURE_FRAME_NOTE);
  end;

begin
  Result := False;
  if not TamanoPng(AFile, W0, H0) then
  begin
    W0 := 0;
    H0 := 0;
  end;
  SrcW := Round(W0 * ATapScaleX);
  SrcH := Round(H0 * ATapScaleY);
  if not MatchText(AInline.Trim, ['false', '0', 'no']) and TFile.Exists(AFile) then
  begin
    MaxW := AMaxWidth;
    if MaxW <= 0 then
      MaxW := INLINE_MAXWIDTH;
    Fallo := EscalaPngBytes(TFile.ReadAllBytes(AFile), MaxW, Bytes, Escala, W, H);
    if Fallo = '' then
    begin
      AttachImage(Bytes, 'image/png');
      PonFrame(W, H);
      AReturn.AddPair('inlineImage', TJSONBool.Create(True));
      AReturn.AddPair('inlineWidth', TJSONNumber.Create(W));
      AReturn.AddPair('inlineHeight', TJSONNumber.Create(H));
      AReturn.AddPair('inlineScale', TJSONNumber.Create(Escala));
      AReturn.AddPair('inlineBytes', TJSONNumber.Create(Length(Bytes)));
      if IsAgentCapture(AFile) then
      begin
        ConsumeAgentCapture(AFile);
        AReturn.AddPair('consumed', TJSONBool.Create(True));
        // La ruta de un fichero que ya no existe es una invitacion a pedirlo
        // (hermes recompuso una esta manana): fuera. Toda tool de captura la
        // anuncia como 'screenshot'.
        AReturn.RemovePair('screenshot').Free;
      end;
      AReturn.AddPair('inlineNote', Format(SN_CAPTURE_INLINE_NOTE_FMT,
        [FormatFloat('0.000', Escala, TFormatSettings.Invariant)]));
      Exit(True);
    end;
    // no se pudo escalar: se dice y se entrega como fichero, que nada se pierde
    AReturn.AddPair('inlineWarning', Fallo);
  end;
  // fichero + enlace listo para copiar: un agente que recompone la ruta a
  // mano se inventa carpetas (hermes, 25-sep-2026)
  PonFrame(W0, H0);
  Enlace := DownloadLinkFor(AToolName, AFile);
  if Enlace <> '' then
  begin
    AReturn.AddPair('download', Enlace);
    AReturn.AddPair('downloadNote', SN_FETCH_DOWNLOAD);
    if IsAgentCapture(AFile) then
      AReturn.AddPair('consumedOnDownload', TJSONBool.Create(True)); // se borra al recogerla
  end;
end;

end.
