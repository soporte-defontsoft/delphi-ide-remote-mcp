unit MCPServer.StdioTransport;

interface

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  MCPServer.Types,
  MCPServer.JsonRpcProcessor,
  MCPServer.Logger;

type
  TMCPStdioTransport = class
  private
    FManagerRegistry: IMCPManagerRegistry;
    FCoreManager: IMCPCapabilityManager;
    FJsonRpcProcessor: TMCPJsonRpcProcessor;
  public
    constructor Create(ManagerRegistry: IMCPManagerRegistry; CoreManager: IMCPCapabilityManager);
    destructor Destroy; override;
    procedure Run;
  end;

implementation

uses
  System.Generics.Collections, // [local change 1.29.1] la cola del lector de stdin
  Lsp.Identidad, // [local change] el nombre de una peticion moderna
  Lsp.Progreso, // [local change 1.29.1] el latido de una llamada larga (F8)
  Lsp.Json, // [local change 1.29.1] ObjetoJson, CampoDeTexto
  Lsp.Texts; // [local change 2026-09-28] MsgExcepcion

const
  // [local change 1.29.1] lo que el lector deja en la cola al acabar stdin:
  // una linea de JSON-RPC no lleva un #0
  FIN_DE_STDIN = #0'fin';

{ TMCPStdioTransport }

constructor TMCPStdioTransport.Create(ManagerRegistry: IMCPManagerRegistry; CoreManager: IMCPCapabilityManager);
begin
  inherited Create;
  FManagerRegistry := ManagerRegistry;
  FCoreManager := CoreManager;
  FJsonRpcProcessor := TMCPJsonRpcProcessor.Create(ManagerRegistry);
end;

destructor TMCPStdioTransport.Destroy;
begin
  FJsonRpcProcessor.Free;
  inherited;
end;

procedure TMCPStdioTransport.Run;
var
  InputLine: string;
  Response: string;
  Lineas: TThreadedQueue<string>;
  Lector: TThread;
begin
  TLogger.Info('STDIO transport started - reading from stdin, writing to stdout');
  TLogger.Info('Logging to stderr');

  // [local change 2026-09-27] MCP por stdio es UTF-8: sin esto Readln
  // decodificaba con la pagina de codigos ANSI (CP1252) y "cancion" con
  // tilde, o un simbolo, llegaba como mojibake que se escribia en disco
  // contestando OK (quinta revision, medido). La salida ya viajaba en ASCII
  // (ToJSON escapa a \uXXXX), pero se declara igual: un contrato para los dos.
  SetTextCodePage(Input, CP_UTF8);
  SetTextCodePage(Output, CP_UTF8);
  InputLine := '';
  // [local change 1.29.1, F8] el latido de una llamada larga sale como una
  // linea mas de stdout (Lsp.Progreso). Lo escribe el hilo del latido mientras
  // este espera a la tool: nunca a la vez que la respuesta de abajo
  PonSumideroDelHilo(
    function(const AMensaje: string): Boolean
    begin
      try
        Writeln(Output, AMensaje);
        Flush(Output);
        TLogger.Info('Sent: ' + AMensaje);
        Result := True;
      except
        Result := False;
      end;
    end);
  // [local change 1.29.1, A22] stdin lo lee OTRO hilo: mientras una llamada
  // corre, el notifications/cancelled de su cliente se atiende AL LLEGAR (su
  // respuesta ira al buzon); antes se leia al acabar ella y ya no casaba con
  // nada (revisor de la 1.29.1). Lo demas va a la cola, en su orden, y lo
  // procesa este hilo como siempre
  Lineas := TThreadedQueue<string>.Create(1024, INFINITE, INFINITE);
  Lector := TThread.CreateAnonymousThread(
    procedure
    var
      L: string;
      V: TJSONObject;
    begin
      try
        while not Eof(Input) do
        begin
          Readln(Input, L);
          V := ObjetoJson(L); // EL lector de la casa (Lsp.Json); nil si no es un objeto
          try
            if (V <> nil) and TMCPJsonRpcProcessor.NoSeContesta(V) and
               (CampoDeTexto(V, 'method') = 'notifications/cancelled') then
            begin
              TLogger.Info('Received: ' + MaskSecretValues(L));
              AtiendeCancelaciones(V, '');
              Continue;
            end;
          finally
            V.Free;
          end;
          Lineas.PushItem(L);
        end;
      except
        on E: Exception do
          TLogger.Error('Error reading STDIO: ' + E.Message);
      end;
      Lineas.PushItem(FIN_DE_STDIN);
    end);
  Lector.FreeOnTerminate := False;
  Lector.Start;
  while True do
  begin
    InputLine := Lineas.PopItem;
    if InputLine = FIN_DE_STDIN then
      Break;
    try
      if InputLine.Trim = '' then
        Continue;

      // [local change] secrets in arguments never reach the log
      TLogger.Info('Received: ' + MaskSecretValues(InputLine));

      // [local change] sin handshake el nombre viene en cada peticion, y sin el
      // un proceso stdio sigue siendo del operador que lo lanzo (la regla de
      // Lsp.Identidad); una peticion de la sesion conserva el de su initialize
      var Moderna := TMCPJsonRpcProcessor.LeeModernaDeTexto(InputLine);
      if Moderna.Es then
        SetThreadIdentity(Moderna.Cliente);

      Response := FJsonRpcProcessor.ProcessRequest(InputLine, '');

      if Response <> '' then
      begin
        Writeln(Output, Response);
        Flush(Output);
        TLogger.Info('Sent: ' + Response);
      end;

    except
      on E: Exception do
      begin
        TLogger.Error('Error processing STDIO request: ' + E.Message);

        // [local change 2026-09-28] el compositor de todos los errores JSON-RPC,
        // con el id de la peticion y el mensaje con su etiqueta (salia id null y
        // sin etiqueta; septima revision)
        Writeln(Output, TMCPJsonRpcProcessor.ErrorParaElCuerpo(InputLine,
          JSONRPC_INTERNAL_ERROR, MsgExcepcion(E.ClassName, E.Message)));
        Flush(Output);
      end;
    end;
  end;

  Lector.WaitFor;
  Lector.Free;
  Lineas.Free;
  QuitaSumideroDelHilo;
  TLogger.Info('STDIO transport stopped - EOF reached');
end;

end.
