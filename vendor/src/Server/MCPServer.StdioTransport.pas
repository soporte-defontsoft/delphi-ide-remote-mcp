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
  while not Eof(Input) do
  begin
    try
      Readln(Input, InputLine);

      if InputLine.Trim = '' then
        Continue;

      // [local change] secrets in arguments never reach the log
      TLogger.Info('Received: ' + MaskSecretValues(InputLine));

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

  TLogger.Info('STDIO transport stopped - EOF reached');
end;

end.
