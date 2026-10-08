unit Lsp.Listas;

{ COMO SE ESCRIBE UNA LISTA EN UNA RESPUESTA: una pagina (TPagina), donde se
  acumula lo que no cabe (TPorCarpeta) y los ficheros agrupados por carpeta
  (TListaDeFicheros). Un sitio para las tres, y cada tool que lista los usa:
  cada una escribia lo suyo a mano y cada una a su manera. }

interface

uses
  System.JSON,
  System.Generics.Collections;

type
  { UNA pagina de una lista recorrida entera. delphi_search y delphi_projects
    contaban, cortaban y escribian total/shown/offset/hasMore/nextOffset cada
    una a mano, y delphi_list ni paginaba: cortaba en 500 y lo de detras no
    se alcanzaba (Hermes en la raiz de referencia de un ERP, 5-oct-2026: las
    500 primeras entradas eran copias de backups\). Se empieza con PaginaDe. }
  TPagina = record
    Desde, Max, Total, Mostrados: Integer;
    { uno mas de la lista: True si cae en ESTA pagina (y ya cuenta como
      mostrado) }
    function Entra: Boolean;
    function HayMas: Boolean;
    function Siguiente: Integer;
    { total, shown, offset (si no es 0), hasMore y nextOffset (si hay mas):
      lo que hace falta para pedir la siguiente sin adivinar }
    procedure Report(AObj: TJSONObject);
  end;

  { DONDE esta una lista que no cabe, no solo cuanto: la carpeta de cada
    entrada a dos niveles bajo la raiz ('.' la propia raiz), y las que mas
    acumulan. Con eso el agente elige root en vez de pasear paginas: en una
    maquina de trabajo las listas las copan las copias de seguridad y los
    componentes (delphi_projects lo hacia a mano: 7.025 proyectos, 6.420
    eran copias; 20-sep-2026). Se empieza con Default(TPorCarpeta). }
  TPorCarpeta = record
    Carpetas: TArray<string>;
    Cuentas: TArray<Integer>;
    Ultima: Integer; // un paseo da seguidas las de una carpeta
    procedure Add(const AFichero, ARaiz: string);
    { byFolder: las ACuantas que mas, "carpeta = N", de mas a menos }
    procedure Report(AObj: TJSONObject; ACuantas: Integer = 10);
  end;

  { UNA lista de ficheros en una respuesta, agrupada por carpeta: la carpeta
    UNA vez -completa, con su unidad virtual, para usarla tal cual en la
    llamada siguiente- y debajo cada fichero por su nombre:
      folders = [ dir: "srvd:\...\Ventas", files = [ name: "UVentas.pas", ... ] ]
    La ruta repetida en cada entrada era el 42% de una pagina de delphi_list
    (34.500 tokens de Qwen3.8 por 500 entradas), el 30% de delphi_projects y
    el 20% de delphi_references; y un modelo pequeno compone la ruta de la
    forma agrupada igual de bien (45/45 contra 44/45 de la plana, medido el
    6-oct-2026). David: "centralizamos un organizador de respuestas para
    files y siempre lo usamos".
    - Se agrupa por carpeta aunque las entradas lleguen desordenadas
      (delphi_projects recorre por mascara, delphi_references por extension).
    - Cada pagina se sostiene sola: se agrupa solo lo que se anade, asi que la
      primera carpeta de una pagina lleva su dir aunque empezara en la
      anterior ("las siguientes paginas deben empezar indicando la ruta otra
      vez", David).
    - El dir sale ENMASCARADO aqui (MaskDriveText, idempotente: srvd:\ no se
      vuelve a tocar), tambien para las tools cuyo eco no pasa por el filtro
      de salida (delphi_search).
    La lista se cuelga de la respuesta al FINAL (Cuelga), detras de los
    contadores y las notas, como iban; si nadie la cuelga, se libera aqui. }
  TListaDeFicheros = class
  private
    FCarpetas: TJSONArray;
    FColgada: Boolean;
    FHijos: string;
    FIndice: TDictionary<string, TJSONArray>;
    FFicheros: TDictionary<string, TJSONObject>;
    function Grupo(const ADir: string): TJSONArray;
  public
    { AHijos: como se llama la lista de cada carpeta ('files'; 'dirs' para
      una lista de carpetas) }
    constructor Create(const AHijos: string = 'files');
    destructor Destroy; override;
    { la lista, en AObj como ACampo: desde aqui es de la respuesta }
    procedure Cuelga(AObj: TJSONObject; const ACampo: string = 'folders');
    { la entrada de AFichero (ruta completa) en su carpeta, con 'name' ya
      puesto: la tool le anade lo suyo }
    function Add(const AFichero: string): TJSONObject;
    { la entrada de AFichero, la MISMA si ya estaba: para una lista de
      aciertos por fichero que no llegan seguidos (los usos de references) }
    function Fichero(const AFichero: string): TJSONObject;
    { ARuta como NOMBRE suelto en su carpeta, sin objeto: una lista de
      carpetas (delphi_list dirs=true), que no lleva nada mas }
    procedure AddNombre(const ARuta: string);
  end;

{ El campo ACampo de AObj -una lista PLANA de entradas con 'path': los usos
  de references, los cambios de un rename- pasa a la forma del organizador,
  EN SU SITIO (el orden de la respuesta no cambia): la carpeta una vez, el
  fichero una vez y sus entradas en 'hits', sin la ruta. Para las tools que
  arman la lista plana por dentro (rename consume la de references) y la
  agrupan al contestar. Un campo que no esta, que no es una lista o con
  alguna entrada sin 'path' se deja como esta: nada se pierde. }
procedure AgrupaPorFichero(AObj: TJSONObject; const ACampo: string);

{ ...la otra forma: UNA entrada por fichero (una unidad con lo que declara,
  un proyecto de tests): cada entrada pasa a su carpeta como el fichero
  mismo, con 'name' en vez de 'path' y lo demas igual, en su sitio. Si alguna
  entrada no trae 'path', el campo se deja como esta: nada se pierde. }
procedure AgrupaPorCarpeta(AObj: TJSONObject; const ACampo: string);

{ La pagina que pide quien llama: un offset negativo es 0, un maximo que no
  es positivo es APorDefecto y uno mayor que ATope es ATope. }
function PaginaDe(AOffset, AMax, APorDefecto, ATope: Integer): TPagina;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.StrUtils,
  Lsp.NetDrives, // SinBarraFinal
  Lsp.Mascara;   // MaskDriveText

{ TPagina }

function PaginaDe(AOffset, AMax, APorDefecto, ATope: Integer): TPagina;
begin
  Result := Default(TPagina);
  if AOffset > 0 then
    Result.Desde := AOffset;
  if AMax <= 0 then
    AMax := APorDefecto;
  if AMax > ATope then
    AMax := ATope;
  Result.Max := AMax;
end;

function TPagina.Entra: Boolean;
begin
  Inc(Total);
  Result := (Total > Desde) and (Mostrados < Max);
  if Result then
    Inc(Mostrados);
end;

function TPagina.HayMas: Boolean;
begin
  Result := Total > Desde + Mostrados;
end;

function TPagina.Siguiente: Integer;
begin
  Result := Desde + Mostrados;
end;

procedure TPagina.Report(AObj: TJSONObject);
begin
  AObj.AddPair('total', TJSONNumber.Create(Total));
  AObj.AddPair('shown', TJSONNumber.Create(Mostrados));
  if Desde > 0 then
    AObj.AddPair('offset', TJSONNumber.Create(Desde));
  // Truncated lists used to be a wall: the cap hit, no way to ask for the
  // rest (hermes, release audit 2026-08-26). hasMore + nextOffset make the
  // next page one deterministic call away.
  AObj.AddPair('hasMore', TJSONBool.Create(HayMas));
  if HayMas then
    AObj.AddPair('nextOffset', TJSONNumber.Create(Siguiente));
end;

{ TPorCarpeta }

procedure TPorCarpeta.Add(const AFichero, ARaiz: string);
var
  Carpeta, Raiz, Rel: string;
  I: Integer;
begin
  Carpeta := SinBarraFinal(TPath.GetDirectoryName(AFichero));
  Raiz := SinBarraFinal(ARaiz);
  if SameText(Carpeta, Raiz) then
    // en la propia raiz: decia la raiz recortada a dos segmentos y parecia
    // OTRA carpeta
    Rel := '.'
  else if StartsText(IncludeTrailingPathDelimiter(Raiz), Carpeta) then
  begin
    Rel := Carpeta.Substring(Length(IncludeTrailingPathDelimiter(Raiz)));
    var Trozos := Rel.Split([TPath.DirectorySeparatorChar]);
    if Length(Trozos) > 2 then
      Rel := Trozos[0] + TPath.DirectorySeparatorChar + Trozos[1];
  end
  else
    Rel := Carpeta;
  if (Ultima < Length(Carpetas)) and SameText(Carpetas[Ultima], Rel) then
  begin
    Inc(Cuentas[Ultima]);
    Exit;
  end;
  for I := 0 to High(Carpetas) do
    if SameText(Carpetas[I], Rel) then
    begin
      Inc(Cuentas[I]);
      Ultima := I;
      Exit;
    end;
  Carpetas := Carpetas + [Rel];
  Cuentas := Cuentas + [1];
  Ultima := High(Carpetas);
end;

procedure TPorCarpeta.Report(AObj: TJSONObject; ACuantas: Integer);
var
  Quedan: TArray<Integer>;
  Arr: TJSONArray;
  I, J, Mejor, MejorN: Integer;
begin
  Quedan := Copy(Cuentas);
  Arr := TJSONArray.Create;
  AObj.AddPair('byFolder', Arr);
  for I := 1 to ACuantas do
  begin
    Mejor := -1;
    MejorN := 0;
    for J := 0 to High(Quedan) do
      if Quedan[J] > MejorN then
      begin
        MejorN := Quedan[J];
        Mejor := J;
      end;
    if Mejor < 0 then
      Break;
    Arr.Add(Format('%s = %d', [Carpetas[Mejor], MejorN]));
    Quedan[Mejor] := 0;
  end;
end;

{ TListaDeFicheros }

constructor TListaDeFicheros.Create(const AHijos: string);
begin
  inherited Create;
  FHijos := AHijos;
  FIndice := TDictionary<string, TJSONArray>.Create;
  FFicheros := TDictionary<string, TJSONObject>.Create;
  FCarpetas := TJSONArray.Create;
end;

destructor TListaDeFicheros.Destroy;
begin
  FIndice.Free; // los arrays y las entradas son de FCarpetas
  FFicheros.Free;
  if not FColgada then
    FCarpetas.Free;
  inherited;
end;

procedure TListaDeFicheros.Cuelga(AObj: TJSONObject; const ACampo: string);
begin
  if FColgada then
    Exit;
  AObj.AddPair(ACampo, FCarpetas);
  FColgada := True;
end;

function TListaDeFicheros.Grupo(const ADir: string): TJSONArray;
var
  Clave: string;
begin
  Clave := ADir.ToLower;
  if FIndice.TryGetValue(Clave, Result) then
    Exit;
  var G := TJSONObject.Create;
  FCarpetas.AddElement(G);
  G.AddPair('dir', MaskDriveText('', ADir));
  Result := TJSONArray.Create;
  G.AddPair(FHijos, Result);
  FIndice.Add(Clave, Result);
end;

function TListaDeFicheros.Add(const AFichero: string): TJSONObject;
begin
  // la carpeta PRIMERO: si GetDirectoryName lanza (una ruta con < > |), no
  // queda un objeto suelto (revisor de la 1.15.0)
  var G := Grupo(TPath.GetDirectoryName(AFichero));
  Result := TJSONObject.Create;
  G.AddElement(Result);
  Result.AddPair('name', TPath.GetFileName(AFichero));
end;

function TListaDeFicheros.Fichero(const AFichero: string): TJSONObject;
begin
  if FFicheros.TryGetValue(AFichero.ToLower, Result) then
    Exit;
  Result := Add(AFichero);
  FFicheros.Add(AFichero.ToLower, Result);
end;

{ La entrada de una lista plana trae la ruta que la agrupa: un 'path' que
  no esta o esta vacio es como si no lo trajera (las dos AgrupaPor* dejan
  entonces el campo como esta). }
function TienePath(V: TJSONValue): Boolean;
begin
  Result := (V is TJSONObject) and (TJSONObject(V).GetValue('path') <> nil) and
    (TJSONObject(V).GetValue('path').Value.Trim <> '');
end;

procedure AgrupaPorFichero(AObj: TJSONObject; const ACampo: string);
var
  Par: TJSONPair;
  Lista: TListaDeFicheros;
  E: TJSONObject;
  Hits: TJSONArray;
begin
  Par := AObj.Get(ACampo);
  if (Par = nil) or not (Par.JsonValue is TJSONArray) then
    Exit;
  // una entrada sin 'path' deja el campo como esta, como AgrupaPorCarpeta:
  // se saltaba y se perdia en silencio (revisor de baterias de la 1.15.0)
  for var V in TJSONArray(Par.JsonValue) do
    if not TienePath(V) then
      Exit;
  Lista := TListaDeFicheros.Create;
  try
    for var V in TJSONArray(Par.JsonValue) do
    begin
      E := Lista.Fichero(TJSONObject(V).GetValue('path').Value);
      if E.GetValue('hits') is TJSONArray then
        Hits := TJSONArray(E.GetValue('hits'))
      else
      begin
        Hits := TJSONArray.Create;
        E.AddPair('hits', Hits);
      end;
      var Uso := V.Clone as TJSONObject;
      Uso.RemovePair('path').Free;
      Hits.AddElement(Uso);
    end;
    // el par se queda la lista agrupada y libera la plana (SetJsonValue)
    Par.JsonValue := Lista.FCarpetas;
    Lista.FColgada := True;
  finally
    Lista.Free;
  end;
end;

procedure AgrupaPorCarpeta(AObj: TJSONObject; const ACampo: string);
var
  Par: TJSONPair;
  Lista: TListaDeFicheros;
begin
  Par := AObj.Get(ACampo);
  if (Par = nil) or not (Par.JsonValue is TJSONArray) then
    Exit;
  for var V in TJSONArray(Par.JsonValue) do
    if not TienePath(V) then
      Exit;
  Lista := TListaDeFicheros.Create;
  try
    for var V in TJSONArray(Par.JsonValue) do
    begin
      var E := Lista.Add(TJSONObject(V).GetValue('path').Value);
      for var P in TJSONObject(V) do
        if P.JsonString.Value <> 'path' then
          E.AddPair(P.JsonString.Value, P.JsonValue.Clone as TJSONValue);
    end;
    // el par se queda la lista agrupada y libera la plana (SetJsonValue)
    Par.JsonValue := Lista.FCarpetas;
    Lista.FColgada := True;
  finally
    Lista.Free;
  end;
end;

procedure TListaDeFicheros.AddNombre(const ARuta: string);
begin
  // (SinBarraFinal, la de la casa: la de la RTL convierte D:\ en D:, la
  // carpeta actual; lo vigila test_raiz_unidad)
  Grupo(TPath.GetDirectoryName(SinBarraFinal(ARuta))).Add(
    TPath.GetFileName(SinBarraFinal(ARuta)));
end;

end.
