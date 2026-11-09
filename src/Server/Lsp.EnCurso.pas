unit Lsp.EnCurso;

{ R3 de A22 (1.29.1): las operaciones LARGAS que escriben y siguen en marcha.
  Medido el 7-nov-2026 (opencode, el informe de un agente): mientras
  un delphi_move copy de ~5.000 ficheros seguia en el servidor, delphi_list de
  su destino decia WS-008 "does not exist", y repetir un borrado ya hecho
  SYS-012 NOT_FOUND; el agente lo tomo por fallido y lo repitio encima. El
  latido (Lsp.Progreso) evita casi todos los cortes, pero Hermes corta a los
  300 s pase lo que pase y un agente puede lanzar llamadas en paralelo sobre
  la misma carpeta.

  UN registro para todo el proceso. La llamada larga que ESCRIBE se apunta al
  pasar la puerta (EmpiezaLlamada) con sus rutas (RutasDeLaLlamada: las de la
  puerta), su agente, su tool, su huella (tool + argumentos) y cuando empezo,
  y se borra al acabar (TerminaLlamada, en el finally del gestor de tools:
  pase lo que pase con la tool). Lo que dice el registro a OTRA llamada:
  - la MISMA (el mismo agente CON NOMBRE y la misma huella) mientras sigue:
    se niega (SYS-042); su respuesta va a la llamada que la empezo, o al
    buzon de ese agente si su cliente se fue (Lsp.Progreso). Sin nombre no
    hay "el mismo agente": su repetida la juzga el cruce de rutas;
  - una que ESCRIBE en sus rutas (dentro, o la carpeta que las contiene): se
    niega (SYS-043), diciendo cual sigue y desde cuando; salvo un build o
    un test sobre otro build o test (EN_LA_FILA_DEL_BUILD): esos ya esperan
    su turno solos;
  - una que LEE sus rutas: contesta como siempre y lleva SYS-044: lo que ve
    puede estar a medias.
  Que operaciones son LARGAS es una regla de la casa sin juez (cuanto tarda
  algo no lo dice nadie antes de hacerlo): UNA lista con nombre,
  OPERACIONES_LARGAS, vigilada por test_paisaje. Una escritura corta (una
  edicion) no se apunta: va en fila por el cerrojo de escritura. Un escritor
  cuyas rutas no ve la puerta (delphi_changeset commit: van en sus
  operaciones, no en sus argumentos) pregunta a EscrituraEnCurso. Una
  negativa no lleva la nota SYS-044. }

interface

uses
  System.JSON;

{ Al pasar la puerta: '' si la llamada sigue (y queda apuntada si es larga y
  escribe), o la negativa SYS-042 / SYS-043. Guarda en el hilo las rutas de
  la llamada para NotaDeLaLlamada. }
function EmpiezaLlamada(const AToolName: string; const AArguments: TJSONObject): string;

{ La nota SYS-044 para la respuesta de esta llamada si alguna de sus rutas la
  esta cambiando OTRA llamada larga; '' si no. }
function NotaDeLaLlamada: string;

{ Para un escritor cuyas rutas no ve la puerta (delphi_changeset commit): la
  negativa SYS-043 si una operacion larga de otra llamada esta en alguna de
  ARutas; '' si no. }
function EscrituraEnCurso(const ARutas: TArray<string>): string;

{ Al acabar la llamada, pase lo que pase: la borra del registro y olvida sus
  rutas. }
procedure TerminaLlamada;

implementation

uses
  System.SysUtils, System.StrUtils, System.Classes, System.SyncObjs,
  System.Generics.Collections,
  Lsp.PuertaDeLaLlamada, // RutasDeLaLlamada y LlamadaLee: lo que la puerta ya sabe
  Lsp.Rutas,             // RutaDentroDe: EL juez de "esta dentro de"
  Lsp.Identidad,         // AgenteDeLaLlamada
  Lsp.Texts;

const
  // las tools cuyas llamadas que ESCRIBEN se apuntan: las que recorren o
  // reescriben un arbol, o lanzan un build (las del 7-nov-2026 lo eran).
  // Gramatica de la casa, UNA (test_paisaje)
  OPERACIONES_LARGAS: array[0..6] of string = ('delphi_move', 'delphi_delete',
    'delphi_build', 'delphi_package', 'delphi_test', 'delphi_git', 'delphi_paserver');
  // las que ya se ponen en fila SOLAS: compilan por RunMsBuild, que no deja
  // correr dos msbuild a la vez (GBuildLock, Lsp.BuildRunner), y cada test
  // corre en su contenedor. Dos de ellas sobre el mismo proyecto esperan su
  // turno, como antes de R3: negar la segunda quitaba a dos agentes probar
  // el mismo proyecto a la vez (medido el 9-nov-2026 por
  // test_delphi_test_servicio, S5-S7). Gramatica de la casa, UNA (test_paisaje)
  EN_LA_FILA_DEL_BUILD: array[0..1] of string = ('delphi_build', 'delphi_test');

type
  TOperacion = record
    Hilo: TThreadID;
    Agente, Tool, Huella: string;
    Rutas: TArray<string>;
    Inicio: TDateTime;
  end;

var
  GLock: TCriticalSection = nil;
  GOps: TList<TOperacion> = nil;

threadvar
  // las rutas de la llamada en curso de este hilo; un tipo gestionado en un
  // threadvar no se libera solo: TerminaLlamada lo vacia
  TRutas: TArray<string>;

{ Una ruta de la llamada y una de la operacion se tocan si una esta dentro de
  la otra (o son la misma): ARuta, la de la operacion. }
function SeTocan(const ALlamada, AOperacion: TArray<string>; out ARuta: string): Boolean;
begin
  for var X in ALlamada do
    for var Y in AOperacion do
      if RutaDentroDe(X, Y) or RutaDentroDe(Y, X) then
      begin
        ARuta := Y;
        Exit(True);
      end;
  Result := False;
end;

function Desde(const AOp: TOperacion): string;
begin
  Result := FormatDateTime('hh:nn:ss', AOp.Inicio);
end;

function Segundos(const AOp: TOperacion): Integer;
begin
  Result := Round((Now - AOp.Inicio) * SecsPerDay);
end;

{ La negativa SYS-043 si alguna de ARutas la tiene una operacion larga de
  OTRA llamada; salvo un build o un test (AToolName) sobre otro build o test,
  que esperan su turno solos. Con el cerrojo tomado. }
function CruceConOtra(const ARutas: TArray<string>; const AToolName: string): string;
var
  Ruta: string;
begin
  Result := '';
  for var Op in GOps do
    if (Op.Hilo <> TThread.CurrentThread.ThreadID) and SeTocan(ARutas, Op.Rutas, Ruta) and
       not (MatchText(AToolName, EN_LA_FILA_DEL_BUILD) and MatchText(Op.Tool, EN_LA_FILA_DEL_BUILD)) then
      Exit(MsgFmt(SR_SYS_OPERACION_EN_CURSO_FMT, [Ruta, Op.Tool, Desde(Op), Segundos(Op)]));
end;

{ Las de ESTE hilo fuera: una llamada nueva en un hilo que Indy reutiliza no
  hereda lo de la anterior, aunque algo se saltara su TerminaLlamada. Con el
  cerrojo tomado. }
procedure QuitaLasDelHilo;
begin
  for var I := GOps.Count - 1 downto 0 do
    if GOps[I].Hilo = TThread.CurrentThread.ThreadID then
      GOps.Delete(I);
end;

function EmpiezaLlamada(const AToolName: string; const AArguments: TJSONObject): string;
var
  Rutas: TArray<string>;
  Que, Agente, Huella: string;
  Larga: Boolean;
  Op: TOperacion;
begin
  Result := '';
  Rutas := RutasDeLaLlamada(AToolName, AArguments);
  TRutas := Rutas;
  // lo que LEE no se niega ni se apunta: si toca algo en curso lo dice su nota
  if LlamadaLee(AToolName, AArguments, Que) then
    Exit;
  Larga := MatchText(AToolName, OPERACIONES_LARGAS);
  Agente := AgenteDeLaLlamada('');
  // la huella: la tool y sus argumentos tal como pasaron la entrada (rutas ya
  // traducidas y alargadas: la misma llamada da la misma huella)
  Huella := LowerCase(AToolName) + #0;
  if Assigned(AArguments) then
    Huella := Huella + AArguments.ToJSON;
  GLock.Enter;
  try
    QuitaLasDelHilo;
    // la MISMA llamada: el mismo agente y la misma huella. AgenteDeLaLlamada
    // da '' a todo cliente sin nombre: dos de ellos no son "el mismo", y su
    // repetida va al cruce de rutas como cualquier otra (hallazgo 4 del
    // revisor de la 1.29.1)
    if Larga and (Agente <> '') then
      for Op in GOps do
        if (Op.Agente = Agente) and (Op.Huella = Huella) then
        begin
          TRutas := nil; // una negativa no lleva la nota SYS-044
          Exit(MsgFmt(SR_SYS_OPERACION_REPETIDA_FMT, [Op.Tool, Desde(Op), Segundos(Op)]));
        end;
    Result := CruceConOtra(Rutas, AToolName);
    if Result <> '' then
    begin
      TRutas := nil;
      Exit;
    end;
    if Larga then
    begin
      Op.Hilo := TThread.CurrentThread.ThreadID;
      Op.Agente := Agente;
      Op.Tool := AToolName;
      Op.Huella := Huella;
      Op.Rutas := Rutas;
      Op.Inicio := Now;
      GOps.Add(Op);
    end;
  finally
    GLock.Leave;
  end;
end;

function NotaDeLaLlamada: string;
var
  Ruta: string;
begin
  Result := '';
  if Length(TRutas) = 0 then
    Exit;
  GLock.Enter;
  try
    for var Op in GOps do
      if (Op.Hilo <> TThread.CurrentThread.ThreadID) and SeTocan(TRutas, Op.Rutas, Ruta) then
        Exit(MsgFmt(SN_SYS_OPERACION_EN_CURSO_FMT, [Ruta, Op.Tool, Desde(Op), Segundos(Op)]));
  finally
    GLock.Leave;
  end;
end;

function EscrituraEnCurso(const ARutas: TArray<string>): string;
begin
  GLock.Enter;
  try
    Result := CruceConOtra(ARutas, '');
  finally
    GLock.Leave;
  end;
end;

procedure TerminaLlamada;
begin
  TRutas := nil;
  GLock.Enter;
  try
    QuitaLasDelHilo;
  finally
    GLock.Leave;
  end;
end;

initialization
  GLock := TCriticalSection.Create;
  GOps := TList<TOperacion>.Create;

finalization
  FreeAndNil(GOps);
  FreeAndNil(GLock);

end.
