unit Lsp.LogSink;

{ EL log del servidor en disco: uno solo para los tres anfitriones (servicio,
  terminal y bandeja).

  Hasta el 26-sep-2026 lo escribia la ventana de la bandeja (UTrayMain). El
  diseno de David del 21-ago -la vista en vivo se queda, la memoria acotada,
  no se pierde nada- se programo DENTRO del formulario, como "lo que ensena la
  ventana acaba en disco", y el servicio y el terminal, que no tienen ventana,
  se quedaron sin log. El servicio es produccion desde el 20-sep: seis dias
  sin una linea (logs\actual.log paro el 20-sep a las 18:09) y nada lo dijo.
  El montaje del servidor ya vivia en Lsp.Host para los tres; el log se habia
  quedado fuera. Ahora lo enciende TMcpHost al crearse -un anfitrion nuevo lo
  tiene sin acordarse de nada- y la bandeja solo cuelga encima su ventana
  (SetLogTap).

  En disco, junto al exe:
    logs\actual.log               la cola en vivo, anadida cada medio segundo:
                                  un proceso matado desde fuera pierde medio
                                  segundo, no horas (2026-08-23: nada desde
                                  las 11:54 para un diagnostico de las 14:00)
    logs\aaaammdd-hhnnss[-N].log  un bloque cada [Log] LinesPerFile lineas: es
                                  actual.log RENOMBRADO, nunca una copia; se
                                  guardan los [Log] MaxFiles mas nuevos

  Puede haber varios procesos con el mismo exe (el terminal stdio de un
  cliente local junto al servicio, las baterias): cada escritura abre
  actual.log para ANADIR -Windows pone cada trozo al final y entero aunque
  escriban dos a la vez- y lo cierra, compartiendo lectura, escritura y
  borrado, asi que otro puede leerlo, escribir o renombrarlo mientras tanto.
  Lo que no se pudo escribir espera a la siguiente vuelta, acotado: un disco
  con problemas nunca tumba el servidor.

  La carpeta es la casa del servidor, no la de un agente. Aun asi nunca se
  escribe ni se poda a traves de un enlace: una bateria tiene el exe DENTRO
  de su jaula, y un junction plantado en logs\ haria escribir y borrar fuera
  de ella (norma dura del 25-sep). Y la poda solo toca nombres que compone
  este mismo nombrador.

  Las tiras base64 NO se guardan, se dice su tamano (SinBase64): una captura
  viaja dentro de la respuesta y el transporte registra la respuesta entera.
  Y TODA linea pasa por el enmascarador de secretos (MaskSecretValues): el
  transporte HTTP enmascaraba la peticion pero registraba la RESPUESTA tal
  cual, y con el servicio escribiendo a disco eso llega al fichero. Aqui,
  que es por donde pasa cada linea, vale para cualquier camino que venga. }

interface

const
  { Tope de lineas esperando a ser escritas (aqui y en la ventana de la
    bandeja). Sin tope, un disco o una ventana que no drenan acumulan memoria
    sin fin: medido el 21-ago en la bandeja, 16 minutos de peticiones
    apiladas. Lo que pasa del tope se cuenta y se dice, no se guarda. }
  LOG_BUF_CAP = 5000;

type
  { Quien ve cada linea ademas del disco (la ventana de la bandeja). Se llama
    desde el hilo que registra, dentro del cerrojo del log: ha de ser breve. }
  TLogTap = reference to procedure(const ALine: string);

{ Enciende el log en disco. Idempotente: TMcpHost.Create lo llama siempre. }
procedure StartLogSink;

{ Cuelga -o, con nil, descuelga- al que ve las lineas ademas del disco. Al
  volver, ninguna llamada al anterior sigue en curso. }
procedure SetLogTap(const ATap: TLogTap);

{ Lleva ya a disco lo pendiente, sin esperar al proximo medio segundo. El
  anfitrion lo llama al cerrar: la cola de una sesion es justo lo que pide un
  post-mortem. }
procedure FlushLogSink;

{ <carpeta del exe>\logs: el unico sitio que compone esa ruta. }
function LogDir: string;

{ [Log] LinesPerFile (por defecto 2000, minimo 100): las lineas de un bloque,
  y las que guarda como mucho la ventana de la bandeja. }
function LogLinesPerFile: Integer;

{ Lo que se dice al arrancar sobre el log (TMcpHost.StartupNotes): donde
  esta y como rota, igual en los tres anfitriones. }
function LogSinkNote: string;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.IOUtils,
  MCPServer.Logger,
  Lsp.Guard; // ServerDir, LogIniSettings, CrearCarpeta, EsEnlace

const
  LIVE_LOG_NAME = 'actual.log';
  DRAIN_MS = 500;
  { Desde cuantos simbolos seguidos una tira es base64 y no texto: un sha256
    son 64, una palabra o una ruta no llegan; una captura son cientos de
    miles. }
  BASE64_MIN = 256;

type
  TLogDrain = class(TThread)
  protected
    procedure Execute; override;
  end;

var
  GLock: TCriticalSection;      // el buffer, el tap y el cierre
  GDrainLock: TCriticalSection; // una escritura a disco a la vez
  GBuf: TStringList;
  GDropped: Integer;
  GTap: TLogTap;
  GClosed: Boolean;
  GStop: TEvent;
  GDrain: TLogDrain;
  GAjustesLeidos: Boolean;
  GLinesPerFile: Integer = 2000;
  GMaxFiles: Integer = 10;
  GLinesInLive: Integer;        // las de actual.log que ha visto ESTE proceso

function LogDir: string;
begin
  Result := ServerDir('logs');
end;

{ [Log] del settings.ini, por el lector central (LogIniSettings, Lsp.Guard):
  hasta hoy lo leia la bandeja con su propio TIniFile. Aqui solo se acota. }
procedure LeeAjustes;
begin
  if GAjustesLeidos then
    Exit;
  GAjustesLeidos := True;
  LogIniSettings(GLinesPerFile, GMaxFiles);
  if GLinesPerFile < 100 then
    GLinesPerFile := 100;
  if GMaxFiles < 1 then
    GMaxFiles := 1;
end;

function LogLinesPerFile: Integer;
begin
  LeeAjustes;
  Result := GLinesPerFile;
end;

function LogSinkNote: string;
begin
  LeeAjustes;
  Result := Format('Log en disco: %s (actual.log en vivo; un bloque cada %d ' +
    'lineas, se guardan los %d mas nuevos - [Log] LinesPerFile/MaxFiles en ' +
    'settings.ini).', [LogDir, GLinesPerFile, GMaxFiles]);
end;

{ EL nombre de un bloque y, debajo, su inverso: quien escribe (CierraBloque)
  y quien reconoce (Poda) hablan el mismo formato, y la poda nunca toca un
  fichero que este nombrador no compondria. N = 1 es el nombre sin sufijo. }
function NombreDeBloque(const AStamp: string; AN: Integer): string;
begin
  if AN <= 1 then
    Result := AStamp + '.log'
  else
    Result := AStamp + '-' + IntToStr(AN) + '.log';
end;

{ La clave de orden de un nombre de bloque, '' si no lo es: el sello y el
  sufijo en seis cifras. Por orden alfabetico, el "-2" de un segundo quedaba
  DELANTE del primero de ese segundo ('-' va antes que '.'). }
function ClaveDeBloque(const ANombre: string): string;
var
  S, Suf: string;
  N, I: Integer;
begin
  Result := '';
  if not ANombre.EndsWith('.log', True) then
    Exit;
  S := ANombre.Substring(0, ANombre.Length - 4);
  if (S.Length < 15) or (S.Chars[8] <> '-') then
    Exit;
  for I := 0 to 14 do
    if (I <> 8) and not CharInSet(S.Chars[I], ['0'..'9']) then
      Exit;
  N := 1;
  if S.Length > 15 then
  begin
    if S.Chars[15] <> '-' then
      Exit;
    Suf := S.Substring(16);
    N := StrToIntDef(Suf, 0);
    if (N < 2) or (IntToStr(N) <> Suf) then
      Exit; // "-01", "-1", "-x": no los compone NombreDeBloque
  end;
  Result := S.Substring(0, 15) + Format('%.6d', [N]);
end;

{ Las lineas que ya tiene actual.log al arrancar (la cola de la ejecucion
  anterior): el bloque sigue donde estaba en vez de empezar otro en cada
  reinicio - un dia de despliegues son decenas de reinicios, y con un bloque
  por reinicio MaxFiles se comeria la historia en una tarde. }
function LineasDe(const AFichero: string): Integer;
var
  F: TFileStream;
  B: TBytes;
  X: Byte;
begin
  Result := 0;
  try
    if not TFile.Exists(AFichero) or EsEnlace(AFichero) then
      Exit;
    F := TFileStream.Create(AFichero, fmOpenRead or fmShareDenyNone);
    try
      if F.Size > 64 * 1024 * 1024 then
        Exit(MaxInt div 2); // desmesurado: que la primera vuelta lo cierre
      SetLength(B, F.Size);
      if Length(B) > 0 then
        F.ReadBuffer(B[0], Length(B));
    finally
      F.Free;
    end;
    for X in B do
      if X = 10 then
        Inc(Result);
  except
    Result := 0;
  end;
end;

{ Anade el trozo al final de actual.log. False si no se pudo: el trozo
  vuelve a la cola y se reintenta en la siguiente vuelta. }
function Anade(AChunk: TStringList): Boolean;
var
  Dir, Vivo: string;
  Bytes: TBytes;
  H: THandle;
  Escritos: DWORD;
  Intento: Integer;
begin
  Result := False;
  Dir := LogDir;
  Vivo := TPath.Combine(Dir, LIVE_LOG_NAME);
  try
    if EsEnlace(Dir) then
      Exit;
    CrearCarpeta(Dir);
    if EsEnlace(Dir) or EsEnlace(Vivo) then
      Exit;
  except
    Exit;
  end;
  Bytes := TEncoding.UTF8.GetBytes(AChunk.Text);
  if Length(Bytes) = 0 then
    Exit(True);
  for Intento := 1 to 3 do
  begin
    // FILE_APPEND_DATA: cada escritura va al final, entera, aunque otro
    // proceso este escribiendo a la vez. Sin seguir un enlace en el nombre.
    H := CreateFile(PChar(Vivo), FILE_APPEND_DATA,
      FILE_SHARE_READ or FILE_SHARE_WRITE or FILE_SHARE_DELETE, nil,
      OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL or FILE_FLAG_OPEN_REPARSE_POINT, 0);
    if H <> INVALID_HANDLE_VALUE then
    begin
      try
        Result := WriteFile(H, Bytes[0], Length(Bytes), Escritos, nil) and
          (Escritos = DWORD(Length(Bytes)));
      finally
        CloseHandle(H);
      end;
      Exit;
    end;
    Sleep(20);
  end;
end;

{ Se guardan los GMaxFiles bloques mas nuevos. Solo cuenta lo que
  ClaveDeBloque reconoce: un notas.log del operador no es un bloque. }
procedure Poda(const ADir: string);
var
  Lista: TStringList;
  F, Clave: string;
  I: Integer;
begin
  Lista := TStringList.Create;
  try
    for F in TDirectory.GetFiles(ADir, '*.log') do
    begin
      Clave := ClaveDeBloque(TPath.GetFileName(F));
      if Clave <> '' then
        Lista.Add(Clave + '|' + F);
    end;
    Lista.Sort;
    for I := 0 to Lista.Count - 1 - GMaxFiles do
      TFile.Delete(Lista[I].Substring(Lista[I].IndexOf('|') + 1));
  finally
    Lista.Free;
  end;
end;

{ Cierra el bloque: actual.log pasa a llamarse por su sello. }
procedure CierraBloque;
var
  Dir, Vivo, Stamp, Bloque: string;
  N: Integer;
begin
  GLinesInLive := 0;
  Dir := LogDir;
  if EsEnlace(Dir) then
    Exit;
  Vivo := TPath.Combine(Dir, LIVE_LOG_NAME);
  Stamp := FormatDateTime('yyyymmdd"-"hhnnss', Now);
  N := 1;
  repeat
    Bloque := TPath.Combine(Dir, NombreDeBloque(Stamp, N));
    Inc(N);
  until not TFile.Exists(Bloque);
  // RENOMBRAR, no copiar: el bloque ES la cola en vivo. Si otro proceso con
  // el mismo exe acaba de renombrarla, aqui no hay nada que mover y ya esta:
  // su bloque existe y lo que se escriba ahora empieza el siguiente.
  if MoveFile(PChar(Vivo), PChar(Bloque)) then
    Poda(Dir);
end;

{ Lo que no se pudo escribir vuelve DELANTE de lo que llego despues, para
  que en disco el orden sea el de los hechos. Lo que no cabe se cuenta. }
procedure Devuelve(AChunk: TStringList);
var
  Nuevo: TStringList;
  S: string;
begin
  GLock.Enter;
  try
    Nuevo := TStringList.Create;
    for S in AChunk do
      if Nuevo.Count < LOG_BUF_CAP then
        Nuevo.Add(S)
      else
        Inc(GDropped);
    for S in GBuf do
      if Nuevo.Count < LOG_BUF_CAP then
        Nuevo.Add(S)
      else
        Inc(GDropped);
    GBuf.Free;
    GBuf := Nuevo;
  finally
    GLock.Leave;
  end;
end;

procedure FlushLogSink;
var
  Chunk: TStringList;
  Dropped: Integer;
begin
  if not Assigned(GDrainLock) then
    Exit;
  Chunk := nil;
  Dropped := 0;
  GDrainLock.Enter;
  try
    GLock.Enter;
    try
      if (GBuf = nil) or ((GBuf.Count = 0) and (GDropped = 0)) then
        Exit;
      Chunk := GBuf;
      GBuf := TStringList.Create;
      Dropped := GDropped;
      GDropped := 0;
    finally
      GLock.Leave;
    end;
    try
      if Dropped > 0 then
        Chunk.Add(Format('... %d lineas de log descartadas (buffer lleno) ...',
          [Dropped]));
      if Anade(Chunk) then
      begin
        Inc(GLinesInLive, Chunk.Count);
        if GLinesInLive >= GLinesPerFile then
          try
            CierraBloque;
          except
            // renombrar o podar fallo: se reintenta al cerrar el proximo
          end;
      end
      else
        Devuelve(Chunk);
    finally
      Chunk.Free;
    end;
  finally
    GDrainLock.Leave;
  end;
end;

{ Las tiras base64 no van al log (David, 2026-09-26: "y si ignoramos
  base64?"). Desde el 25-sep una captura viaja DENTRO de la respuesta, y el
  transporte registra la respuesta entera: cientos de KB en una sola linea
  que no dicen nada en un diagnostico, con una rotacion que cuenta lineas y
  no bytes. Igual las subidas de delphi_upload y los trozos de delphi_fetch.
  Queda su tamano, y el resto de la linea entero. Una tira son BASE64_MIN
  simbolos seguidos del alfabeto, contando la barra que JSON escapa ("\/"). }
function SinBase64(const ALinea: string): string;
var
  I, J, K, N, Largo: Integer;
  SB: TStringBuilder;

  { Lo que ocupa en APos un simbolo base64: 1, 2 ("\/") o 0 si no lo es. }
  function Simbolo(APos: Integer): Integer;
  var
    C: Char;
  begin
    C := ALinea.Chars[APos];
    if CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '+', '/', '=']) then
      Result := 1
    else if (C = '\') and (APos + 1 < Largo) and (ALinea.Chars[APos + 1] = '/') then
      Result := 2
    else
      Result := 0;
  end;

begin
  Largo := ALinea.Length;
  if Largo < BASE64_MIN then
    Exit(ALinea);
  SB := TStringBuilder.Create(Largo);
  try
    I := 0;
    while I < Largo do
    begin
      J := I;
      N := 0;
      while J < Largo do
      begin
        K := Simbolo(J);
        if K = 0 then
          Break;
        Inc(J, K);
        Inc(N);
      end;
      if J = I then
      begin
        SB.Append(ALinea.Chars[I]);
        Inc(I);
      end
      else
      begin
        if N >= BASE64_MIN then
          SB.Append('[base64: ').Append(N).Append(' caracteres]')
        else
          SB.Append(ALinea, I, J - I);
        I := J;
      end;
    end;
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ El gancho del logger: se llama desde cualquier hilo, dentro de su cerrojo.
  Solo apunta la linea (y se la pasa a quien mire); el disco es del hilo que
  drena. }
procedure Recibe(const ALine: string);
var
  L: string;
begin
  L := SinBase64(MaskSecretValues(ALine));
  GLock.Enter;
  try
    if GClosed then
      Exit;
    if GBuf.Count >= LOG_BUF_CAP then
      Inc(GDropped)
    else
      GBuf.Add(L);
    if Assigned(GTap) then
      try
        GTap(L);
      except
        // la ventana no puede tumbar a quien registra
      end;
  finally
    GLock.Leave;
  end;
end;

procedure SetLogTap(const ATap: TLogTap);
begin
  GLock.Enter;
  try
    GTap := ATap;
  finally
    GLock.Leave;
  end;
end;

procedure StartLogSink;
begin
  if Assigned(GDrain) then
    Exit;
  LeeAjustes;
  GLinesInLive := LineasDe(TPath.Combine(LogDir, LIVE_LOG_NAME));
  TLogger.OnLogMessage := Recibe;
  GDrain := TLogDrain.Create(False);
end;

procedure TLogDrain.Execute;
begin
  NameThreadForDebugging('LogSink');
  while GStop.WaitFor(DRAIN_MS) = wrTimeout do
    try
      FlushLogSink;
    except
      // nada de lo que pase escribiendo el log puede parar el log
    end;
end;

initialization
  GLock := TCriticalSection.Create;
  GDrainLock := TCriticalSection.Create;
  GBuf := TStringList.Create;
  GStop := TEvent.Create(nil, True, False, '');

finalization
  // Primero se cierra la entrada: una linea que llegue desde aqui (otro hilo
  // que aun registra) se descarta en vez de tocar lo que se va a liberar.
  GLock.Enter;
  try
    GClosed := True;
    GTap := nil;
  finally
    GLock.Leave;
  end;
  TLogger.OnLogMessage := nil;
  if Assigned(GDrain) then
  begin
    GStop.SetEvent;
    GDrain.WaitFor;
    FreeAndNil(GDrain);
  end;
  FlushLogSink; // lo ultimo que se registro
  FreeAndNil(GStop);
  FreeAndNil(GDrainLock);
  FreeAndNil(GBuf);
  // GLock NO se libera: un hilo que registre en el ultimo instante aun lo
  // toma en Recibe (el logger no espera a nadie al quitar el gancho). Son
  // unos bytes al salir del proceso.
end.
