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
  byte a byte: el transporte solo cambia de forma cuando hay algo que mandar. }

interface

uses
  System.SysUtils;

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
  antes de que ConLatido vuelva. True = un latido no llego: el cliente se fue
  antes de la respuesta (A22). Una excepcion de ALlamada sale tal cual. }
function ConLatido(const AToken, ANombre: string; const ALlamada: TProc): Boolean;

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
  buzon, o si no se puede escribir, solo queda en el log. Nunca lanza. }
procedure DejaLaRespuestaEnElBuzon(const ABuzon, ATool, ARespuestaJson: string);

implementation

uses
  System.Classes, System.SyncObjs, System.JSON,
  Lsp.Settings, // ProgressSeconds
  Lsp.Json, // ValorJson: EL lector de un valor JSON de la casa
  Lsp.Casa, // BuzonDeMensajes, Slug
  Lsp.Identidad, // AgenteDeLaLlamada
  Lsp.Puertas, // EscribeDocumentoNuevo
  MCPServer.Logger,
  Lsp.Texts;

threadvar
  // un tipo gestionado en un threadvar no se libera solo al acabar el hilo:
  // por eso el transporte lo quita tras cada peticion
  GSumidero: TSumidero;

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

function ConLatido(const AToken, ANombre: string; const ALlamada: TProc): Boolean;
var
  Sumidero: TSumidero;
  PasoMs: Cardinal;
  Fin: TEvent;
  Latido: TThread;
  Perdido: Boolean;
begin
  Result := False;
  Sumidero := GSumidero;
  if (not Assigned(Sumidero)) or (AToken = '') or (ProgressSeconds <= 0) then
  begin
    ALlamada();
    Exit;
  end;
  PasoMs := Round(ProgressSeconds * 1000);
  if PasoMs = 0 then
    PasoMs := 1;
  Perdido := False;
  Fin := TEvent.Create(nil, True, False, '');
  try
    Latido := TThread.CreateAnonymousThread(
      procedure
      var
        Inicio: UInt64;
      begin
        Inicio := TThread.GetTickCount64;
        while (not Perdido) and (Fin.WaitFor(PasoMs) = wrTimeout) do
          if not Sumidero(MensajeDeProgreso(AToken, (TThread.GetTickCount64 - Inicio) / 1000, ANombre)) then
            Perdido := True;
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
  Result := Perdido;
end;

end.
