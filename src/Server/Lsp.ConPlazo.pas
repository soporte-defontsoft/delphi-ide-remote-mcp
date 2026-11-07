unit Lsp.ConPlazo;

{ UN trabajo con el plazo del SERVIDOR. El de un cliente no se cumple siempre,
  medido dos veces en la 1.29: SQL Server tardaba 42 s en rendirse con un
  plazo de 5 (FireDAC, 6-nov-2026), y WinHTTP con uno de 2 s contestaba a
  los 4 aislado y, dentro de una tanda de peticiones, unas veces a los 2,5 y
  otras nunca (THTTPClient, delphi_api, mismo dia). El plazo lo pone quien
  pide, no el cliente.

  El trabajo corre en su hilo y quien lo pide espera hasta el plazo. A
  tiempo: lo que el trabajo dejo es de quien lo pidio. Vencido: AAlVencer
  corre en el hilo de quien pidio (cancelar lo que se pueda cancelar; lo que
  el trabajo tiene sigue vivo: nadie lo ha liberado aun) y quien pidio se va
  con False; el hilo, al acabar, llama a ALibera, porque lo que tenia ya no
  es de nadie. El protocolo de quien libera, escrito una vez (era el de
  AbreBase, en Lsp.BaseDeDatos): un estado que cambian los dos por
  TInterlocked, y si acaban a la vez gana el hilo y lo recoge quien pidio.

  El hilo hace el trabajo DE LA LLAMADA, y la lleva: quien llama, su
  workspace y su solo lectura (Lsp.Identidad.LlamadaDelHilo). Un hilo nuevo
  nace sin ella, y sin agente es el operador (CH11 de la 1.29). }

interface

uses
  System.SysUtils;

{ True si ATrabajo acabo dentro de APlazoMs: lo que dejo es de quien llama.
  False si no: AAlVencer ya corrio (puede ser nil) y lo que deje ATrabajo lo
  libera ALibera, en el hilo, cuando acabe. ATrabajo recoge sus propias
  excepciones (las apunta en lo suyo); si una se le escapa, el protocolo se
  cumple igual. }
function TrabajoConPlazo(const ATrabajo: TProc; APlazoMs: Cardinal; const AAlVencer, ALibera: TProc): Boolean;

implementation

uses
  System.Classes, System.SyncObjs,
  Lsp.Identidad; // LlamadaDelHilo: la llamada de quien pide, al hilo

type
  { La cita entre quien pide y el hilo. Estado 0 = esperando, 1 = quien pedia
    se fue (libera el hilo), 2 = el hilo termino (recoge quien pedia). }
  TCita = class
  public
    Listo: TEvent;
    Estado: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

constructor TCita.Create;
begin
  inherited Create;
  Listo := TEvent.Create(nil, True, False, '');
end;

destructor TCita.Destroy;
begin
  Listo.Free;
  inherited;
end;

function TrabajoConPlazo(const ATrabajo: TProc; APlazoMs: Cardinal; const AAlVencer, ALibera: TProc): Boolean;
var
  C: TCita;
  Trabajo, Libera: TProc;
  Llamada: TLlamadaDelHilo;
begin
  C := TCita.Create;
  Trabajo := ATrabajo;
  Libera := ALibera;
  Llamada := LlamadaDelHilo;
  TThread.CreateAnonymousThread(
    procedure
    begin
      try
        PonLlamadaDelHilo(Llamada);
        Trabajo();
      finally
        if TInterlocked.CompareExchange(C.Estado, 2, 0) = 1 then
        begin
          try
            Libera();
          finally
            C.Free;
          end;
        end
        else
          C.Listo.SetEvent;
      end;
    end).Start;
  Result := C.Listo.WaitFor(APlazoMs) = wrSignaled;
  if not Result then
  begin
    // lo del trabajo sigue vivo: nadie libera hasta que el estado cambie
    if Assigned(AAlVencer) then
      AAlVencer();
    if TInterlocked.CompareExchange(C.Estado, 1, 0) = 0 then
      Exit(False);
    // termino a la vez: es de quien pidio
    C.Listo.WaitFor(INFINITE);
    Result := True;
  end;
  C.Free;
end;

end.
