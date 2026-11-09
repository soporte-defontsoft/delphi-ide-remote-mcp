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

implementation

uses
  System.Classes, System.SyncObjs, System.JSON,
  Lsp.Settings, // ProgressSeconds
  Lsp.Json, // ValorJson: EL lector de un valor JSON de la casa
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
