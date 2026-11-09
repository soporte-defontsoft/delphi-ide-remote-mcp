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
  Lsp.Identidad, // [local change] el nombre de una peticion moderna
  Lsp.Progreso, // [local change 1.29.1] el latido de una llamada larga (F8)
  Lsp.Texts; // [local change 2026-09-28] MsgExcepcion

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
  while not Eof(Input) do
  begin
    try
      Readln(Input, InputLine);

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

  QuitaSumideroDelHilo;
  TLogger.Info('STDIO transport stopped - EOF reached');
end;

end.
