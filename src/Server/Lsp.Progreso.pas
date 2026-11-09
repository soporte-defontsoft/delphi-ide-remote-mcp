unit Lsp.Progreso;

{ F8 de la 1.29.1: el LATIDO de una llamada larga. Medido el 9-nov-2026 (P1):
  Claude Code (la app y el CLI) abandona una llamada tras 300 s sin noticias y
  opencode tras 60, y un notifications/progress con el progressToken de la
  llamada les reinicia la cuenta; Hermes corta a los 300 s pase lo que pase.
  Hasta la 1.29 el servidor no mandaba ninguno: una copia o un build largos se
  daban por perdidos aunque acabaran, y el agente los repetia encima.

  UNO para todas las tools y los dos transportes: el transporte pone el
  SUMIDERO del hilo (como llega un mensaje a ESE cliente: una linea de stdio,
  un evento del stream HTTP) y el procesador JSON-RPC envuelve el tools/call
  en ConLatido. Una llamada que acaba antes del primer latido sale como antes,
  byte a byte: el transporte solo cambia de forma cuando hay algo que mandar.

  A22: la respuesta de una llamada cuyo cliente dejo de esperar va a su buzon.
  Se sabia por un latido que no se puede escribir (el cliente colgo). Medido
  el 9-nov-2026 con Hermes (SDK mcp 2.3.0, jsonrpc_dispatcher "courtesy
  cancel for timed-out request"): corta a los 300 s, manda un
  notifications/cancelled con el id de la peticion y NO cuelga, asi que el
  latido seguia llegando y la respuesta se perdia (tres rondas: su buzon
  vacio). Cada tools/call queda EN VUELO (workspace del token, sesion, id)
  mientras dura, y un cancelled que casa (AtiendeCancelaciones) la da por
  perdida igual que un latido que no llega. }

interface

uses
  System.SysUtils, System.JSON;

type
  { Escribe UN mensaje JSON-RPC al cliente de la llamada en curso. False = no
    llego (el cliente ya no esta): no se vuelve a intentar. Lo llama el hilo
    del latido mientras el de la peticion espera a la tool, nunca a la vez que
    el transporte escribe la respuesta (ConLatido acaba antes de volver). }
  TSumidero = reference to function(const AMensaje: string): Boolean;

{ El sumidero de las llamadas de ESTE hilo: lo pone el transporte antes de
  procesar una peticion y lo quita despues (QuitaSumideroDelHilo). }
procedure PonSumideroDelHilo(const ASumidero: TSumidero);
procedure QuitaSumideroDelHilo;

{ Corre ALlamada. Con sumidero en el hilo, un AToken (el JSON del progressToken
  tal cual: un numero o un texto entre comillas) y ProgressSeconds > 0, cada
  ProgressSeconds que siga en marcha manda un notifications/progress con los
  segundos que lleva y SYS-040 (ANombre: la tool); el ultimo latido acaba
  antes de que ConLatido vuelva. Mientras dura esta EN VUELO con su AId (el
  JSON del id de la peticion) y ASesion ('' sin sesion), para
  AtiendeCancelaciones. True = el cliente dejo de esperar antes de la
  respuesta: un latido no llego o mando su cancelled (A22). Una excepcion de
  ALlamada sale tal cual. }
function ConLatido(const AToken, ANombre, AId, ASesion: string; const ALlamada: TProc): Boolean;

{ Los notifications/cancelled de AValor (uno, o los de un lote): la llamada
  EN VUELO con ese requestId, del mismo workspace y de la misma sesion
  (ASesion, '' sin sesion), queda por perdida y su respuesta ira al buzon al
  acabar. Lo demas no se toca. Lo llama quien recibe una notificacion: el
  transporte HTTP (que no las pasa al procesador) y el procesador (stdio). }
procedure AtiendeCancelaciones(AValor: TJSONValue; const ASesion: string);

{ El notifications/progress de un latido, compuesto aqui y en ningun otro
  sitio. }
function MensajeDeProgreso(const AToken: string; ASegundos: Double; const ANombre: string): string;

{ A22 de la 1.29.1: el buzon (delphi_messages) del agente de la llamada en
  curso, '' si no tiene agente. Se toma mientras la llamada tiene su
  identidad: el transporte la quita al acabar. }
function BuzonDeEstaLlamada: string;

{ La respuesta de ATool que no llego a su cliente (un latido o la respuesta no
  se pudieron escribir: dejo de esperar) al buzon ABuzon, como un mensaje
  (SYS-041) con su texto tal como habria llegado - ya enmascarado por el
  filtro de salida -: cada respuesta de ese agente lo avisa hasta que lo lee,
  y asi no repite a ciegas lo que ya se hizo (el remote-run que corrio dos
  veces, 7-nov-2026). ARespuestaJson: la respuesta JSON-RPC o su result. Sin
  buzon, o si no se puede escribir, solo queda en el log. UNA vez por
  llamada: si el procesador ya la dejo (un cancelled), el transporte no la
  deja otra vez cuando tampoco puede escribirla. Nunca lanza. }
procedure DejaLaRespuestaEnElBuzon(const ABuzon, ATool, ARespuestaJson: string);

implementation

uses
  System.Classes, System.SyncObjs, System.Generics.Collections,
  Lsp.Settings, // ProgressSeconds, CurrentWorkspaceName
  Lsp.Json, // ValorJson: EL lector de un valor JSON de la casa
  Lsp.Casa, // BuzonDeMensajes, Slug
  Lsp.Identidad, // AgenteDeLaLlamada
  Lsp.Puertas, // EscribeDocumentoNuevo
  MCPServer.Logger,
  Lsp.Texts;

type
  { Una llamada en vuelo, para que un notifications/cancelled la encuentre: el
    workspace de su token, su sesion y su id. Perdido lo pone un latido que
    no llega o el cancelled que casa; ConLatido lo lee al acabar. }
  TEnVuelo = class
    Workspace, Sesion, Id: string;
    Perdido: Boolean;
  end;

var
  GVuelosLock: TCriticalSection = nil;
  GVuelos: TList<TEnVuelo> = nil;

threadvar
  // un tipo gestionado en un threadvar no se libera solo al acabar el hilo:
  // por eso el transporte lo quita tras cada peticion
  GSumidero: TSumidero;
  // la respuesta de la llamada de este hilo ya esta en el buzon (la pone a
  // False ConLatido, por donde pasa toda llamada que puede dejarla)
  GDejada: Boolean;

procedure PonSumideroDelHilo(const ASumidero: TSumidero);
begin
  GSumidero := ASumidero;
end;

procedure QuitaSumideroDelHilo;
begin
  GSumidero := nil;
end;

function MensajeDeProgreso(const AToken: string; ASegundos: Double; const ANombre: string): string;
var
  Msg, Params: TJSONObject;
  Token: TJSONValue;
  Segundos: string;
begin
  Segundos := FormatFloat('0.#', ASegundos, TFormatSettings.Invariant);
  Msg := TJSONObject.Create;
  try
    Msg.AddPair('jsonrpc', '2.0');
    Msg.AddPair('method', 'notifications/progress');
    Params := TJSONObject.Create;
    Msg.AddPair('params', Params);
    // el token tal como lo mando el cliente (JSONRpcProcessor.TokenDeProgreso:
    // su ToJSON); uno que no se lea es un null, nunca otro texto
    Token := ValorJson(AToken);
    if not Assigned(Token) then
      Token := TJSONNull.Create;
    Params.AddPair('progressToken', Token);
    // lo que lleva, en segundos: crece en cada latido, como pide el protocolo
    Params.AddPair('progress', TJSONNumber.Create(StrToFloat(Segundos, TFormatSettings.Invariant)));
    Params.AddPair('message', MsgFmt(SN_SYS_SIGUE_EN_MARCHA_FMT, [ANombre, Segundos]));
    Result := Msg.ToJSON;
  finally
    Msg.Free;
  end;
end;

function BuzonDeEstaLlamada: string;
var
  Agente: string;
begin
  Agente := AgenteDeLaLlamada('');
  if Agente = '' then
    Exit('');
  Result := BuzonDeMensajes(Agente);
end;

{ El texto de una respuesta: el de su content (los trozos de texto, por
  orden), el message de su error, o el JSON tal cual si no es ninguno. }
function TextoDeLaRespuesta(const AJson: string): string;
var
  O, R: TJSONObject;
  C: TJSONValue;
  Partes: TArray<string>;
begin
  Result := AJson;
  O := ObjetoJson(AJson);
  if O = nil then
    Exit;
  try
    if O.GetValue('error') is TJSONObject then
      Exit(CampoDeTexto(O.GetValue('error'), 'message'));
    R := O;
    if O.GetValue('result') is TJSONObject then
      R := TJSONObject(O.GetValue('result'));
    C := R.GetValue('content');
    Partes := [];
    if C is TJSONArray then
      for var V in TJSONArray(C) do
        if CampoDeTexto(V, 'text') <> '' then
          Partes := Partes + [CampoDeTexto(V, 'text')];
    if Length(Partes) > 0 then
      Result := string.Join(#10#10, Partes);
  finally
    O.Free;
  end;
end;

procedure DejaLaRespuestaEnElBuzon(const ABuzon, ATool, ARespuestaJson: string);
var
  Motivo, Ruta: string;
  Ahora: TDateTime;
begin
  if GDejada then
    Exit;
  GDejada := True;
  if ABuzon = '' then
  begin
    TLogger.Info('The answer of ' + ATool + ' did not reach its client, which has no mailbox');
    Exit;
  end;
  try
    Ahora := Now;
    Ruta := EscribeDocumentoNuevo(ABuzon, SelloDeDocumento(Ahora) + '-' +
      Slug('answer ' + ATool), MsgFmt(SN_SYS_RESPUESTA_PERDIDA_FMT, [ATool, ATool,
      FormatDateTime('yyyy-mm-dd hh:nn:ss', Ahora), TextoDeLaRespuesta(ARespuestaJson)]), Motivo);
    if Ruta <> '' then
      TLogger.Info('The answer of ' + ATool + ' did not reach its client: left in its mailbox, ' +
        ExtractFileName(Ruta))
    else
      TLogger.Info('The answer of ' + ATool + ' did not reach its client and could not be left ' +
        'in its mailbox: ' + Motivo);
  except
    on E: Exception do
      TLogger.Info('The answer of ' + ATool + ' did not reach its client and could not be left ' +
        'in its mailbox: ' + E.Message);
  end;
end;

{ Corre ALlamada con su latido (si lo pidio) mientras Vuelo esta en vuelo. }
procedure CorreConLatido(const AToken, ANombre: string; const ALlamada: TProc; Vuelo: TEnVuelo);
var
  Sumidero: TSumidero;
  PasoMs: Cardinal;
  Fin: TEvent;
  Latido: TThread;
begin
  Sumidero := GSumidero;
  if (not Assigned(Sumidero)) or (AToken = '') or (ProgressSeconds <= 0) then
  begin
    ALlamada();
    Exit;
  end;
  PasoMs := Round(ProgressSeconds * 1000);
  if PasoMs = 0 then
    PasoMs := 1;
  Fin := TEvent.Create(nil, True, False, '');
  try
    // un cliente que dejo de esperar (su cancelled o un latido que no
    // llego) no recibe mas latidos
    Latido := TThread.CreateAnonymousThread(
      procedure
      var
        Inicio: UInt64;
      begin
        Inicio := TThread.GetTickCount64;
        while (not Vuelo.Perdido) and (Fin.WaitFor(PasoMs) = wrTimeout) do
          if not Vuelo.Perdido and
             not Sumidero(MensajeDeProgreso(AToken, (TThread.GetTickCount64 - Inicio) / 1000, ANombre)) then
            Vuelo.Perdido := True;
      end);
    Latido.FreeOnTerminate := False;
    Latido.Start;
    try
      ALlamada();
    finally
      Fin.SetEvent;
      Latido.WaitFor;
      Latido.Free;
    end;
  finally
    Fin.Free;
  end;
end;

function ConLatido(const AToken, ANombre, AId, ASesion: string; const ALlamada: TProc): Boolean;
var
  Vuelo: TEnVuelo;
begin
  GDejada := False;
  Vuelo := TEnVuelo.Create;
  try
    Vuelo.Workspace := CurrentWorkspaceName;
    Vuelo.Sesion := ASesion;
    Vuelo.Id := AId;
    if AId <> '' then
    begin
      GVuelosLock.Enter;
      try
        GVuelos.Add(Vuelo);
      finally
        GVuelosLock.Leave;
      end;
    end;
    try
      CorreConLatido(AToken, ANombre, ALlamada, Vuelo);
    finally
      if AId <> '' then
      begin
        GVuelosLock.Enter;
        try
          GVuelos.Remove(Vuelo);
        finally
          GVuelosLock.Leave;
        end;
      end;
    end;
    Result := Vuelo.Perdido;
  finally
    Vuelo.Free;
  end;
end;

procedure AtiendeCancelaciones(AValor: TJSONValue; const ASesion: string);
var
  Params, IdV: TJSONValue;
  Id, Workspace: string;
  N: Integer;
begin
  if AValor is TJSONArray then
  begin
    for var V in TJSONArray(AValor) do
      AtiendeCancelaciones(V, ASesion);
    Exit;
  end;
  if not (AValor is TJSONObject) or (CampoDeTexto(AValor, 'method') <> 'notifications/cancelled') then
    Exit;
  Params := TJSONObject(AValor).GetValue('params');
  if not (Params is TJSONObject) then
    Exit;
  IdV := TJSONObject(Params).GetValue('requestId');
  if IdV = nil then
    Exit;
  // el id como lo escribio el cliente (586, "abc"): la misma forma que el
  // del tools/call en vuelo
  Id := IdV.ToJSON;
  Workspace := CurrentWorkspaceName;
  N := 0;
  GVuelosLock.Enter;
  try
    for var V in GVuelos do
      if (V.Id = Id) and SameText(V.Workspace, Workspace) and (V.Sesion = ASesion) then
      begin
        V.Perdido := True;
        Inc(N);
      end;
  finally
    GVuelosLock.Leave;
  end;
  if N > 0 then
    TLogger.Info('notifications/cancelled for request ' + Id +
      ': its client stopped waiting; its answer will go to the mailbox')
  else
    TLogger.Info('notifications/cancelled for request ' + Id + ': no call of this client is running with that id');
end;

initialization
  GVuelosLock := TCriticalSection.Create;
  GVuelos := TList<TEnVuelo>.Create;

finalization
  // las entradas son de sus llamadas; al cerrar no queda ninguna en vuelo
  FreeAndNil(GVuelos);
  FreeAndNil(GVuelosLock);

end.
