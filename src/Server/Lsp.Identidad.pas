unit Lsp.Identidad;

{ QUIEN LLAMA: la identidad de cada peticion (el nombre que el cliente da en
  initialize, atado a su sesion HTTP, o el del proceso stdio) y el registro
  de las sesiones: viva, caducada o desalojada, con su motivo. Lo usan el
  transporte HTTP (vendor, [local change]), el confinamiento por agente y la
  temporal de cada agente.

  Sale de Lsp.Guard el 8-oct-2026 (la 1.18.0, la version de la limpieza),
  movido sin cambiar una linea. No usa nada de la jaula: debajo solo tiene
  Lsp.Settings (cuanto dura una sesion sin uso). Sus objetos - el cerrojo,
  la lista de sesiones y la de las caducadas - se crean en su
  initialization, como se creaban en la de Lsp.Guard. }

interface

{ WHO is calling - as far as this server can honestly know.

  Two-phase, the way the operator asked: the SHARED token (Bearer) is the door,
  the same for everyone. Then the handshake's clientInfo.name is bound to the
  session id the server issues in `initialize` - and that id is a secret the
  server generated, returned once, and the client echoes on every request. So
  the NAME is fixed at connect time and cannot be re-declared per call: to be
  taken for another agent you would have to steal their session id, not just
  type their name. That is the whole gain over the old self-declared 'agent'
  string.

  Not authentication (one token still lets anyone connect), but enough to keep
  agents working in different projects from stepping on each other, and to
  stop casual impersonation. A real per-agent token is the next rung.

  Bound at initialize; read on every tool call via the per-thread context the
  HTTP layer sets before dispatch. '' when unknown (stdio with no name, or a
  request before initialize) - callers treat that as 'anon'. }
procedure BindSessionIdentity(const ASessionId, AName: string);
procedure SetThreadIdentityBySession(const ASessionId: string);
procedure SetThreadIdentity(const AName: string); // stdio: one process, one name
procedure ClearThreadIdentity;
function CurrentAgent: string;               // '' = unknown
function CurrentAgentOr(const ADefault: string): string;

{ El REGISTRO de sesiones HTTP - uno solo, el mismo que guarda la identidad
  (hasta 1.0.16 el servidor HTTP llevaba un anillo aparte de ids conocidos:
  dos escritores para la misma cosa). Una sesion nace en initialize
  (BindSessionIdentity, con nombre o sin el), se toca en cada peticion que
  la usa y CADUCA tras SessionTimeoutMinutes de inactividad: [Server]
  SessionTimeoutMinutes en settings.ini o DELPHI_MCP_SESSION_TIMEOUT_MINUTES
  (720 por defecto, 0 = nunca). La puerta HTTP contesta 404 a una sesion
  desconocida o caducada - lo que manda el contrato streamable-HTTP - y el
  cliente vuelve a hacer initialize. Un initialize con un id viejo siempre
  pasa: es el arreglo, no el problema. }
type
  // ssEvicted: cerrada para hacer sitio (SESIONES_MAX); salia "desconocida"
  TSessionState = (ssUnknown, ssExpired, ssAlive, ssEvicted);
const
  SESIONES_MAX = 256;
type
  TSesion = record
    Id, Nombre: string;
    UltimoUso: TDateTime;
  end;
function SessionState(const ASessionId: string): TSessionState; // viva = la toca
function LiveSessionCount: Integer;                             // purga las caducadas

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Generics.Collections,
  Lsp.Settings;         // SessionTimeoutMinutes: cuanto dura una sesion sin uso

var
  GIdentLock: TCriticalSection;
  GSesiones: TList<TSesion>;  // sesiones HTTP: id, nombre atado en initialize, ultimo uso
  GCaducadas: TStringList;    // las ultimas que caducaron: su motivo no se pierde al purgarlas
threadvar
  TCurrentAgent: string; // WHO is calling on THIS thread (the HTTP request)
{ A name safe to use as a folder tag: letters, digits, dash, underscore, dot.
  Anything else collapses to '-', so a declared name can never traverse. }
function SanitizeAgent(const AName: string): string;
var
  C: Char;
begin
  Result := '';
  for C in AName.Trim do
    if CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_', '-', '.']) then
      Result := Result + C
    else
      Result := Result + '-';
  Result := Result.Trim(['-', '.']);
  if Length(Result) > 40 then
    Result := Copy(Result, 1, 40);
end;

const
  MINUTOS_POR_DIA = 1440;

{ Bajo GIdentLock. -1 = no esta. }
function IndiceDeSesion(const AId: string): Integer;
var
  I: Integer;
begin
  for I := 0 to GSesiones.Count - 1 do
    if GSesiones[I].Id = AId then
      Exit(I);
  Result := -1;
end;

function SesionCaducada(const S: TSesion; ATopeMin: Double): Boolean;
begin
  Result := (ATopeMin > 0) and ((Now - S.UltimoUso) * MINUTOS_POR_DIA > ATopeMin);
end;

{ Bajo GIdentLock. Una sesion que caduca se RECUERDA (las ultimas 512): la
  purga de cualquier peticion se llevaba todas las caducadas, y la segunda
  que volvia oia "desconocida, el servidor se reinicio" (SYS-007) en vez de
  "caducada" (SYS-008; septima revision). Y con SU motivo, en el campo (el
  Object), no en otra lista: la expulsada por el tope tambien oia SYS-007
  (octava revision). }
procedure RecuerdaCaducada(const AId: string; AEstado: TSessionState = ssExpired);
var
  K: Integer;
begin
  K := GCaducadas.IndexOf(AId);
  if K < 0 then
    K := GCaducadas.Add(AId);
  GCaducadas.Objects[K] := TObject(NativeInt(Ord(AEstado)));
  while GCaducadas.Count > 512 do
    GCaducadas.Delete(0);
end;

procedure PurgaSesionesCaducadas(ATopeMin: Double);
var
  I: Integer;
begin
  for I := GSesiones.Count - 1 downto 0 do
    if SesionCaducada(GSesiones[I], ATopeMin) then
    begin
      RecuerdaCaducada(GSesiones[I].Id);
      GSesiones.Delete(I);
    end;
end;

procedure BindSessionIdentity(const ASessionId, AName: string);
var
  Clean, Id: string;
  I: Integer;
  S: TSesion;
begin
  Id := ASessionId.Trim;
  if Id = '' then
    Exit;
  Clean := SanitizeAgent(AName);
  GIdentLock.Enter;
  try
    I := IndiceDeSesion(Id);
    if I >= 0 then
    begin
      S := GSesiones[I];
      if Clean <> '' then
        S.Nombre := Clean;
      S.UltimoUso := Now;
      GSesiones[I] := S;
    end
    else
    begin
      S.Id := Id;
      S.Nombre := Clean;
      S.UltimoUso := Now;
      GSesiones.Add(S);
      // lleno: se va la que lleva MAS tiempo sin usarse, no la mas vieja (una
      // sesion en uso contestaba 404 tras 256 initialize de otros; sexta revision)
      while GSesiones.Count > SESIONES_MAX do
      begin
        var Menos := 0;
        for var K := 1 to GSesiones.Count - 1 do
          if GSesiones[K].UltimoUso < GSesiones[Menos].UltimoUso then
            Menos := K;
        RecuerdaCaducada(GSesiones[Menos].Id, ssEvicted);
        GSesiones.Delete(Menos);
      end;
    end;
  finally
    GIdentLock.Leave;
  end;
end;

function SessionState(const ASessionId: string): TSessionState;
var
  Id: string;
  I: Integer;
  S: TSesion;
  Tope: Double;
begin
  Id := ASessionId.Trim;
  if Id = '' then
    Exit(ssUnknown);
  Tope := SessionTimeoutMinutes;
  GIdentLock.Enter;
  try
    I := IndiceDeSesion(Id);
    if I < 0 then
    begin
      // purgada por otra peticion (o expulsada por el tope): con su motivo
      var K := GCaducadas.IndexOf(Id);
      if K >= 0 then
        Result := TSessionState(NativeInt(GCaducadas.Objects[K]))
      else
        Result := ssUnknown;
    end
    else if SesionCaducada(GSesiones[I], Tope) then
    begin
      RecuerdaCaducada(Id);
      GSesiones.Delete(I);
      Result := ssExpired;
    end
    else
    begin
      S := GSesiones[I];
      S.UltimoUso := Now;
      GSesiones[I] := S;
      Result := ssAlive;
    end;
    PurgaSesionesCaducadas(Tope);
  finally
    GIdentLock.Leave;
  end;
end;

function LiveSessionCount: Integer;
begin
  GIdentLock.Enter;
  try
    PurgaSesionesCaducadas(SessionTimeoutMinutes);
    Result := GSesiones.Count;
  finally
    GIdentLock.Leave;
  end;
end;

procedure SetThreadIdentityBySession(const ASessionId: string);
var
  I: Integer;
begin
  TCurrentAgent := '';
  if ASessionId.Trim = '' then
    Exit;
  GIdentLock.Enter;
  try
    I := IndiceDeSesion(ASessionId.Trim);
    if I >= 0 then
      TCurrentAgent := GSesiones[I].Nombre;
  finally
    GIdentLock.Leave;
  end;
end;

procedure SetThreadIdentity(const AName: string);
begin
  TCurrentAgent := SanitizeAgent(AName);
end;

procedure ClearThreadIdentity;
begin
  TCurrentAgent := '';
end;

function CurrentAgent: string;
begin
  Result := TCurrentAgent;
end;

function CurrentAgentOr(const ADefault: string): string;
begin
  if TCurrentAgent <> '' then
    Result := TCurrentAgent
  else
    Result := ADefault;
end;

initialization
  GIdentLock := TCriticalSection.Create;
  GSesiones := TList<TSesion>.Create;
  GCaducadas := TStringList.Create;

finalization

  GSesiones.Free;
  GCaducadas.Free;
  GIdentLock.Free;

end.