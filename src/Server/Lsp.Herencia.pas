unit Lsp.Herencia;

{ LA cadena de ancestros de una clase, por EL MOTOR.

  "Que clase es este ancestro" (el TBaseForm de 'TForm1 = class(TBaseForm)')
  lo decide el compilador: la unidad que lo declara entre las del uses, el
  ultimo gana, y un nombre cualificado lo dice el solo. Imitarlo con una
  lista nuestra es deuda (norma 6 del paisaje): references lo hacia por la
  CADENA DE NOMBRES de lo escaneado y juntaba dos TFoo de dos unidades; el
  juez de la raiz del disenador y los componentes heredados lo hacian por un
  barrido de la carpeta del form, y se quedaban con la PRIMERA unidad en
  orden de ficheros que declaraba el nombre, no con la del uses (medido el
  15-oct-2026: con la homonima delante, lint negaba una propiedad publicada
  por la base real; detras, CLEAN). Tres mecanismos para una pregunta, dos
  de ellos equivocados.

  Aqui se le pregunta al motor: la definicion del identificador escrito en
  class(...), en la posicion que anota el lector de clases
  (TTipoPas.AncestroLinea/AncestroColumna), salto a salto. Un recorredor
  por llamada, con sus caches (el texto y las clases de cada fichero, y cada
  salto, UNA vez). Quien recorre decide donde parar: references, al salir
  del barrido; el disenador, en la primera clase que sus tablas conocen. Y
  el motor solo entra cuando hace falta: un form sobre TForm no lo arranca. }

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Lsp.Client,
  Lsp.PascalDecl;

type
  TCadenaPorElMotor = class
  private
    FClient: TLspClient;
    FTextos: TObjectDictionary<string, TStringList>;   // la vista del codigo de cada fichero
    FUnidades: TObjectDictionary<string, TUnidadPas>;  // y sus clases (EL lector, Lsp.PascalDecl)
    FSaltos: TDictionary<string, string>;              // (fichero|linea) de una clase -> la de su ancestro ('' = no)
    FAbiertos: TDictionary<string, Boolean>;           // lo que este recorredor abrio en el motor
    FIlegibles: TArray<string>;
    FAlcance: TFunc<string, Boolean>;
    FAbre: TProc<string>;
    procedure AbreEnElMotor(const AFile: string);
  public
    constructor Create(AClient: TLspClient);
    destructor Destroy; override;
    { La vista del codigo de un fichero (Lsp.Pascal) y sus clases, leidas UNA
      vez. Uno que no se deja leer queda vacio y se dice (Ilegibles). }
    function LineasDe(const APath: string): TStringList;
    function UnidadDe(const APath: string): TUnidadPas;
    { El tipo cuyo nombre se declara en ALinea de AFile; nil si ninguno. }
    function TipoEn(const AFile: string; ALinea: Integer): TTipoPas;
    { La declaracion del ancestro ESCRITO de la clase declarada en (AFile,
      ALinea), por el motor. False sin ancestro escrito (desciende de
      TObject), sin posicion (una cabecera partida en lineas: la cadena sale
      por ahi), si el motor no contesta o contesta un fichero que no puede
      ensenar, o uno fuera de Alcance. Nunca lanza. }
    function AncestroDe(const AFile: string; ALinea: Integer; out AFile2: string;
      out ALinea2: Integer): Boolean;
    { EL recorredor: el siguiente salto de la cadena desde (AFile, ALinea),
      contando los saltos contra UN tope (TOPE_SALTOS). True y la posicion
      del ancestro en AFile/ALinea; False sin ancestro (AncestroDe) o con el
      tope hecho. Quien recorre decide que hacer en cada salto y cuando parar
      antes (references al dar con el abuelo, el disenador en la primera
      clase de sus tablas); tres bucles lo hacian cada uno con su cuenta y su
      tope, 8 o 20 (D2 de la auditoria de duplicados, 1.21.4). ASalto empieza
      en 0 y es suyo. test_paisaje: nadie llama a AncestroDe salvo este. }
    function Siguiente(var AFile: string; var ALinea: Integer; var ASalto: Integer): Boolean;
    property Client: TLspClient read FClient;
    { Que ficheros valen como destino de un salto; nil = todo lo que el motor
      puede ensenar (references: solo los del barrido, que un parentesco de
      aqui nunca pasa por la RTL y leer System.pas cuesta segundos). }
    property Alcance: TFunc<string, Boolean> read FAlcance write FAlcance;
    { Quien abre un fichero en el motor antes de preguntarle por el (nil = la
      sesion, Lsp.Session.AbreEn, sin contar en ningun presupuesto). }
    property Abre: TProc<string> read FAbre write FAbre;
    property Ilegibles: TArray<string> read FIlegibles;
  end;

{ El motor del proyecto de AFile, listo para preguntar por el, o nil: sin
  ajustes de proyecto el motor no cruza unidades, y para nada se arranca uno
  (ResolveSettings lo sabe sin arrancarlo); tampoco si no se puede abrir.
  Nunca lanza. }
function MotorPara(const AFile: string): TLspClient;

{ Un recorredor sobre el motor de AFile (MotorPara); nil sin motor. Para
  quien no maneja motores (el disenador): lo crea, lo usa, lo libera. }
function CadenaPara(const AFile: string): TCadenaPorElMotor;

const
  { Hasta donde sube el recorredor: una jerarquia circular en fuentes a medio
    escribir no acaba nunca, y ninguna real llega aqui. UNO para los tres
    recorridos (eran 8 en el disenador y 20 en references). }
  TOPE_SALTOS = 20;

implementation

uses
  System.JSON,
  Lsp.Session,
  Lsp.Pascal,          // CodigoPascal: la vista del codigo
  Lsp.ConfigFabricator, // MotorPuedeEnsenar: EL juez de "fuera" de lo que dice el motor
  Lsp.References;      // UbicacionDeLsp: EL lector de una ubicacion del motor

const
  SIN_ANCESTRO = '';

function MotorPara(const AFile: string): TLspClient;
var
  RootDir, Settings: string;
begin
  Result := nil;
  try
    // un fichero sin proyecto no arranca motor (FindDproj: sin hacer los
    // ajustes, que hace AcquireFor)
    if TLspSession.Instance.FindDproj(AFile) = '' then
      Exit;
    Result := TLspSession.Instance.AcquireFor(AFile, Settings);
  except
    Result := nil;
  end;
end;

function CadenaPara(const AFile: string): TCadenaPorElMotor;
var
  Motor: TLspClient;
begin
  Motor := MotorPara(AFile);
  if Motor = nil then
    Result := nil
  else
    Result := TCadenaPorElMotor.Create(Motor);
end;

{ TCadenaPorElMotor }

constructor TCadenaPorElMotor.Create(AClient: TLspClient);
begin
  inherited Create;
  FClient := AClient;
  FTextos := TObjectDictionary<string, TStringList>.Create([doOwnsValues]);
  FUnidades := TObjectDictionary<string, TUnidadPas>.Create([doOwnsValues]);
  FSaltos := TDictionary<string, string>.Create;
  FAbiertos := TDictionary<string, Boolean>.Create;
end;

destructor TCadenaPorElMotor.Destroy;
begin
  FAbiertos.Free;
  FSaltos.Free;
  FUnidades.Free;
  FTextos.Free;
  inherited;
end;

function TCadenaPorElMotor.LineasDe(const APath: string): TStringList;
begin
  if not FTextos.TryGetValue(APath.ToLower, Result) then
  begin
    Result := TStringList.Create;
    try
      Result.Text := CodigoPascal(TLspClient.LoadSourceText(APath));
    except
      FIlegibles := FIlegibles + [APath];
    end;
    FTextos.Add(APath.ToLower, Result);
  end;
end;

function TCadenaPorElMotor.UnidadDe(const APath: string): TUnidadPas;
begin
  if not FUnidades.TryGetValue(APath.ToLower, Result) then
  begin
    Result := LeeFuentePascal(LineasDe(APath).Text);
    FUnidades.Add(APath.ToLower, Result);
  end;
end;

function TCadenaPorElMotor.TipoEn(const AFile: string; ALinea: Integer): TTipoPas;
begin
  Result := UnidadDe(AFile).TipoQueEmpiezaEn(ALinea);
end;

procedure TCadenaPorElMotor.AbreEnElMotor(const AFile: string);
begin
  if FAbiertos.ContainsKey(AFile.ToLower) then
    Exit;
  FAbiertos.Add(AFile.ToLower, True);
  if Assigned(FAbre) then
    FAbre(AFile)
  else
    TLspSession.Instance.AbreEn(FClient, AFile);
end;

function TCadenaPorElMotor.Siguiente(var AFile: string; var ALinea: Integer;
  var ASalto: Integer): Boolean;
var
  F2: string;
  L2: Integer;
begin
  Result := False;
  if ASalto >= TOPE_SALTOS then
    Exit;
  Inc(ASalto);
  if not AncestroDe(AFile, ALinea, F2, L2) then
    Exit;
  AFile := F2;
  ALinea := L2;
  Result := True;
end;

function TCadenaPorElMotor.AncestroDe(const AFile: string; ALinea: Integer;
  out AFile2: string; out ALinea2: Integer): Boolean;
var
  Clave, Guardado, Uri: string;
  T: TTipoPas;
  R: TJSONObject;
  Col: Integer;
begin
  Result := False;
  AFile2 := '';
  ALinea2 := -1;
  Clave := AFile.ToLower + '|' + ALinea.ToString;
  if FSaltos.TryGetValue(Clave, Guardado) then
  begin
    if Guardado = SIN_ANCESTRO then
      Exit;
    AFile2 := Guardado.Substring(0, Guardado.LastIndexOf('|'));
    ALinea2 := StrToInt(Guardado.Substring(Guardado.LastIndexOf('|') + 1));
    Exit(True);
  end;
  FSaltos.Add(Clave, SIN_ANCESTRO);
  try
    T := TipoEn(AFile, ALinea);
    if (T = nil) or (T.Clase <> ctClase) or (T.AncestroLinea < 0) then
      Exit;
    AbreEnElMotor(AFile);
    // (uno dentro del identificador, como references con sus candidatos)
    R := FClient.Definition(TLspClient.PathToUri(AFile), T.AncestroLinea, T.AncestroColumna + 1);
    try
      if not UbicacionDeLsp(R.GetValue('result'), Uri, ALinea2, Col) or
         not MotorPuedeEnsenar(TLspClient.UriToPath(Uri)) then
        Exit;
    finally
      R.Free;
    end;
    AFile2 := TLspClient.UriToPath(Uri);
    if Assigned(FAlcance) and not FAlcance(AFile2) then
    begin
      AFile2 := '';
      ALinea2 := -1;
      Exit;
    end;
    FSaltos[Clave] := AFile2 + '|' + ALinea2.ToString;
    Result := True;
  except
    // un fichero que no se deja abrir, un motor que no contesta: la cadena
    // sale por aqui, y quien recorre lo dice como sepa
    AFile2 := '';
    ALinea2 := -1;
    Result := False;
  end;
end;

end.
