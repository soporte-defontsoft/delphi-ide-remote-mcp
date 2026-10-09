unit Lsp.DesignerMeta;

{ Resolves designer property paths against the framework tables of the
  ACTIVE Delphi, generated from ITS source (Lsp.DesignerMetaGen): classes,
  published properties (what TReader streams against), enum and set
  members, and who inherits from whom. The class a class-typed property
  REALLY holds at runtime is chosen by code (TLabel.TextSettings declares
  TTextSettings and holds a TLabelTextSettings), so going down such a
  property, what a descendant of the declared type publishes is not
  denied. The framework describes itself; the server hardcodes no error
  rules.

  Silence policy (a lint false positive would poison trust): unknown
  classes (user forms, third-party components), classes without table
  data, collection items, binary blocks and list values are NOT judged.

  Field origin (Fase 3): a hand-edited .fmx with VCL-isms packaged
  cleanly - the compiler only checks a form resource's text grammar - and
  crashed at form-load on the device, silently. Hours of blind debugging
  that these warnings turn into seconds at edit time. }

interface

uses
  System.Generics.Collections;

type
  TPropRec = record
    Kind: Char;         // c=class e=enum s=set m=method r=record o=other
    TypeName: string;   // el que se ensena: 'TButtonLayout'
    // la clave de su enumerado o conjunto en Enums/Sets, con su unidad
    // ('Vcl.Buttons:TButtonLayout', Lsp.DesignerMetaGen.IdDeTipo): dos
    // unidades declaran tipos con el mismo nombre y otros miembros (el
    // TIBProtocol de FireDAC y el de IBX), y por el nombre solo ganaba el
    // primero (2.121 avisos falsos en los forms de David: revision de la 1.12.0)
    TypeId: string;
    // su nombre como se declara ('Caption'): la clave va en minusculas, y un
    // diccionario aparte solo para esto repetia las 138.000 claves de la
    // tabla VCL (memoria: revision de la 1.12.0)
    Name: string;
  end;

  TMetaTable = class
  public
    // las clases por su IDENTIDAD, con su unidad ('vcl.graphics:tfont' ->
    // 'TFont'): el TFont de la VCL y el de TeeChart son dos (revision de la
    // 1.12.0); todas las claves de abajo que son de una clase, igual
    Classes: TDictionary<string, string>;
    // el NOMBRE que escribe un form ('tfont') -> la identidad de la primera
    // (la de la instalacion antes que la de terceros: Lsp.DesignerMetaGen)
    PorNombre: TDictionary<string, string>;
    // la identidad como se escribe ('Vcl.StdCtrls:TButton'), por la clave
    IdEscrito: TDictionary<string, string>;
    Props: TDictionary<string, TPropRec>;    // ClaveProp(clase, prop)
    PropNames: TDictionary<string, string>;  // class lower -> 'A, B...' cap
    Enums: TDictionary<string, string>;      // enum lower -> ',a,b,' lower
    EnumShow: TDictionary<string, string>;   // enum lower -> 'A, B, C'
    Sets: TDictionary<string, string>;       // set lower -> ',a,b,' lower
    SetShow: TDictionary<string, string>;    // set lower -> 'A, B, C'
    Padres: TDictionary<string, string>;     // clase lower -> su padre lower (H)
    Hijas: TObjectDictionary<string, TList<string>>; // padre lower -> sus hijas
    // lo que una clase guarda por codigo (D): ClaveProp(clase, nombre) -> el
    // nombre original; ClaveProp(clase, '*') = nombres que se construyen al
    // vuelo; ClaveProp('*', nombre) = de alguna clase (un ayudante suelto)
    Definidas: TDictionary<string, string>;
    // clase que varias unidades declaran con otras publicadas (X): lower ->
    // 'Nombre|Unidad1,Unidad2'. No esta en Classes: no se juzga
    Ambiguas: TDictionary<string, string>;
    // clase lower -> su SetName pone el Text desde el nombre (T)
    TextoEsNombre: TDictionary<string, Boolean>;
    // tipo 'o' lower -> su base: integer, int64, char, single, float, string
    // o variant (B, Lsp.DesignerMetaGen: lo que TReader mira de un valor)
    Bases: TDictionary<string, string>;
    // tipo entero lower -> sus constantes con nombre, ',a,b,' lower, o '*'
    // si acepta cualquier identificador (I: RegisterIntegerConsts); y como
    // se ensenan ('clBlack, clMaroon')
    Constantes: TDictionary<string, string>;
    ConstantesShow: TDictionary<string, string>;
    // tipo entero lower -> lo que su IdentTo ABIERTA lee ademas de sus
    // nombres, sacado de su cuerpo: ';hex=x' (x y un hexadecimal) y
    // ';ins=2a' (una 'a' en el sitio 2 y otra vez al mapa: clRed es claRed).
    // Sin entrada, no se sabe que mas lee (generacion 12)
    FormasAbiertas: TDictionary<string, string>;
    // clase lower -> el ControlStyle de su constructor (K): 'AS', A de
    // csAcceptsControls y S de csSetCaption, '+', '-', '?' o '.'
    Estilos: TDictionary<string, string>;
    constructor Create(const AFacts: array of string);
    // AClase y sus ancestros por Padres, de ella hacia arriba (claves, 64
    // eslabones a lo sumo): EL recorrido de la herencia de los de abajo, que
    // eran cuatro bucles iguales (revision de la 1.17.0)
    function CadenaDe(const AClase: string): TArray<string>;
    // la tabla de un fichero generado (una linea por hecho)
    class function DeFichero(const AFichero: string): TMetaTable;
    { Una hija, nieta... de AClase que publica AProp (la primera que se
      encuentra, por generaciones): la instancia de una propiedad objeto
      puede ser de un descendiente del tipo declarado. }
    function PublicadaEnDescendiente(const AClase, AProp: string;
      out ADescendiente: string): Boolean;
    // Lo que publican AClase y todos sus descendientes, sin repetir, para el
    // aviso de lo que no publica nadie de la familia (cortado como PropNames)
    function PublicadasDeLaFamilia(const AClase: string): string;
    { AClase o un ancestro suyo guarda ANombre por codigo (DefineProperties:
      Left/Top de TComponent, los Explicit* de TControl...), o guarda nombres
      que no se pueden leer ('*'): el form lo escribe sin publicarlo. }
    function DefinidaPorCodigo(const AClase, ANombre: string): Boolean;
    { La clase que nombra un form o quien pregunta: su nombre ('TButton') o
      su identidad ('Vcl.StdCtrls:TButton'). AId, la identidad en minusculas;
      False si no esta o si es ambigua (Ambiguas). }
    function ClaseDeNombre(const ANombre: string; out AId: string): Boolean;
    { AClase (su identidad, 'vcl.stdctrls:tbutton') es AAncestro o desciende
      de el, por Padres. AAncestro, otra identidad ('Vcl.Controls:TWinControl'):
      el TControl de la VCL no es el de FMX. Lo que pregunta delphi_designer
      insert/set: un padre VCL es un TWinControl, el Text de un control FMX
      nuevo es de los TTextControl, insert solo pone controles. }
    function Desciende(const AClase, AAncestro: string): Boolean;
    { Al nacer, el Text (Caption en la VCL) de AClase es su Name: lo decide
      el SetName mas cercano de su cadena que el fuente sobrescribe (hecho T,
      Lsp.DesignerMetaGen.SetNamesDeTexto). Lo que escribe insert. }
    function TextoSigueAlNombre(const AClase: string): Boolean;
    { El valor ABandera (0 csAcceptsControls, 1 csSetCaption) del ControlStyle
      de AClase: lo dice el constructor mas cercano de su cadena que lo toca
      (hecho K); '.' si ninguno, '?' si no se sabe. }
    function EstiloDe(const AClase: string; ABandera: Integer): Char;
    { El disenador deja soltar controles dentro de AClase: su ControlStyle
      tiene csAcceptsControls (un TPanel si; un TPageControl no, sus paginas
      si; un TButton no). Lo que no se sabe, si: no se niega por ello. }
    function AceptaControles(const AClase: string): Boolean;
    // Lo que AClase y sus ancestros guardan por codigo ('*' incluido)
    function DefinidasDeLaCadena(const AClase: string): TArray<string>;
    destructor Destroy; override;
  end;

{ LA clave de una propiedad, o de un nombre guardado por codigo, de una clase
  en las tablas (Props, Definidas): su identidad y el nombre, en minusculas,
  con un '|' en medio, que no sale ni en una identidad ('Unidad:Clase', con
  puntos en las anidadas: TGridPanelLayout.TCellItem) ni en un nombre
  (Viewport.Width). Con un '.' compuesto a mano en ocho sitios, buscar por
  'clase.' cogia tambien lo de sus clases anidadas (info TGridPanelLayout
  listaba lo de TCellItem; revision de la 1.12.0). ClaveProp(AClase, '') es
  el prefijo de todas las de una clase. }
function ClaveProp(const AClase, ANombre: string): string;

const
  { Lo que espera una llamada del disenador (info, prop, lint) a una tabla
    que se esta generando: la primera tras instalar, actualizar o tocar las
    rutas del IDE tarda segundos. El lint que va detras de cada edicion de
    un form no espera (0): dice que no valido. }
  ESPERA_TABLA_MS = 30000; // hay clientes MCP que se rinden al minuto
  { Las identidades de las clases que se preguntan por su nombre con
    TMetaTable.Desciende (unidad:clase: el TControl de la VCL no es el de
    FMX): las RAICES del marco - que es un control, que es un padre VCL. Lo
    que hace una clase concreta (si su Text sigue al nombre) no va aqui: lo
    dice el fuente (hecho T, TextoSigueAlNombre). }
  ID_VCL_CONTROL = 'Vcl.Controls:TControl';
  ID_VCL_WINCONTROL = 'Vcl.Controls:TWinControl';
  ID_FMX_CONTROL = 'FMX.Controls:TControl';
  // un frame en linea (inline) de un form: su clase es del proyecto, no de
  // la tabla, y es un TFrame (lo que set juzga de su tamano y su sitio)
  ID_VCL_FRAME = 'Vcl.Forms:TFrame';
  ID_FMX_FRAME = 'FMX.Forms:TFrame';
  // un form FMX no es un control: es de esta (revision de la 1.17.0, la raiz
  // de un insert)
  ID_FMX_FORMA = 'FMX.Forms:TCommonCustomForm';
  // lo que una propiedad de clase guarda: un componente (una referencia) o un
  // objeto suyo (TFont, una lista de cadenas)
  ID_COMPONENTE = 'System.Classes:TComponent';
  ID_CADENAS = 'System.Classes:TStrings';

type
  { Por que no hay tabla, de las dos formas que hacen falta: la respuesta
    entera de info/prop/lint (DSGN-050/051/053/054) y la razon de la nota
    que va tras una edicion (DSGN-052), que nunca dice "vuelve a llamar": la
    edicion ya esta escrita. Vacio = hay tabla. }
  TFaltaTabla = record
    Negativa: string;
    Razon: string;
  end;

{ El lint de las lineas de un form contra la tabla del framework del Delphi
  activo: los avisos. Nunca lanza: sin tabla, o con un fallo, no juzga y
  AFalta dice por que (antes, una excepcion aqui salia por delphi_edit como
  fallo de una edicion YA escrita: revision de la 1.12.0). ANotas, lo que NO
  ha podido comprobar (un objeto de una clase que no esta en la tabla o que
  es ambigua): no son avisos, y una edicion no los pone bajo "the app
  CRASHES" (un form con el TSslContext de ICS lo decia en cada edicion:
  revision de la 1.12.0). }
function DesignerMetaLint(const AIsFmx: Boolean; const ALines: TArray<string>;
  out ANotas: TArray<string>; out AFalta: TFaltaTabla;
  AEsperaMs: Cardinal = ESPERA_TABLA_MS): TArray<string>;

{ EL juez de una linea de propiedad de un form, ALhs = ARhs en un objeto de
  la clase AClase (su identidad): si la clase publica (o guarda por codigo)
  esa ruta y si el valor es de los que existen. '' = nada que decir - o no
  se puede saber, y entonces calla (la politica de silencio de arriba); si
  no, el aviso. AHoja, la propiedad final cuando se llego a ella (AHayHoja):
  su tipo. Estaba dentro del bucle del lint; delphi_designer set le pregunta
  ANTES de escribir (1.17.0). }
function JuzgaPropiedad(M: TMetaTable; const AClase, ALhs, ARhs: string;
  out AHoja: TPropRec; out AHayHoja: Boolean): string;

{ Lo que toma una propiedad de tipo 'o' por su base (hecho B), como la lee
  TReader.ReadPropValue: un entero, o una de las constantes que registra su
  tipo (hecho I: clRed en un TColor); un Int64; un caracter; un numero; una
  cadena. '' si AValor (escrito como en el form) vale, o si la base no se
  sabe (calla); si no, lo que toma, para el mensaje, y AParecida la
  constante que quiso decir (' Did you mean clRed?'). Lo pregunta
  delphi_designer set antes de escribir. }
function BaseQueNoCasa(M: TMetaTable; const AHoja: TPropRec; const AValor: string;
  out AAviso: string;
  out AParecida: string): string;

// El mismo lint contra una tabla dada (las pruebas le dan la suya)
function LintConTabla(M: TMetaTable; const AIsFmx: Boolean;
  const ALines: TArray<string>; out ANotas: TArray<string>): TArray<string>;

{ Por que una clase no esta en la tabla M: no existe para ella (DSGN-015),
  o dos unidades la declaran con otras publicadas (DSGN-056). Lo dicen info,
  prop e insert de delphi_designer. }
function ClaseQueNoEsta(M: TMetaTable; const AClass, AFramework: string): string;

{ The framework table of the ACTIVE Delphi - what delphi_designer asks about
  classes, published properties and enum members. nil when there is none
  (that install has no source, it is still being generated after
  AEsperaMs, its generation failed or it cannot be read): AFalta then says
  which, ready for the agent. Never raises. }
function MetaTable(const AIsFmx: Boolean; out AFalta: TFaltaTabla;
  AEsperaMs: Cardinal = ESPERA_TABLA_MS): TMetaTable;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.StrUtils,
  System.RegularExpressions,
  System.IOUtils,
  Lsp.Texts,
  Lsp.Discovery,       // DiscoverRadStudio: el Delphi activo
  Lsp.DesignerMetaGen, // la tabla de ese Delphi, sacada de su fuente
  Lsp.DesignerBin,
  Lsp.Pascal;

type
  TJubilada = record
    Tabla: TMetaTable;
    Tick: UInt64;
  end;

const
  { Lo que vive una tabla sustituida (otra huella del mismo Delphi y marco)
    despues de sustituirse: quien la tuviera en la mano la usa unos
    milisegundos (un lint, un info). La de VCL ocupa ~95 MB leida (medido el
    3-oct-2026): se quedaban todas hasta el final, una mas por regeneracion. }
  VIDA_JUBILADA_MS = 5 * 60000;

var
  GMetaLock: TObject;
  // las tablas ya leidas, por su fichero (una huella nueva es otro fichero),
  // y las sustituidas que esperan su hora; todo bajo GMetaLock
  GTablas: TObjectDictionary<string, TMetaTable>;
  GJubiladas: TList<TJubilada>;

// Bajo GMetaLock: las leidas de esa instalacion y marco que no son AFichero
// se retiran, y se liberan las retiradas que ya cumplieron
procedure JubilaLocked(const AFichero: string);
var
  V, B, H, V2, B2, H2: string;
  M, M2: TMarcoDisenador;
  G, G2: Integer;
  J: TJubilada;
begin
  if LeeNombreDeTabla(AFichero, V, B, M, H, G) then
    for var K in GTablas.Keys.ToArray do
      if not SameText(K, AFichero) and LeeNombreDeTabla(K, V2, B2, M2, H2, G2) and
         SameText(V, V2) and (M = M2) then
      begin
        J.Tabla := GTablas.ExtractPair(K).Value;
        J.Tick := TThread.GetTickCount64;
        GJubiladas.Add(J);
      end;
  for var I := GJubiladas.Count - 1 downto 0 do
    if TThread.GetTickCount64 - GJubiladas[I].Tick > VIDA_JUBILADA_MS then
    begin
      GJubiladas[I].Tabla.Free;
      GJubiladas.Delete(I);
    end;
end;

function MetaTable(const AIsFmx: Boolean; out AFalta: TFaltaTabla;
  AEsperaMs: Cardinal): TMetaTable;
var
  Info: TRadStudioInfo;
  Fichero, Detalle, Nombre: string;
  Marco: TMarcoDisenador;
begin
  Result := nil;
  AFalta := Default(TFaltaTabla);
  try
    Info := DiscoverRadStudio;
    Nombre := Trim(Info.DelphiName + ' ' + Info.Version);
    if Nombre = '' then
      Nombre := 'RAD Studio';
    if AIsFmx then
      Marco := mdFmx
    else
      Marco := mdVcl;
    case TablaDeInstalacion(Info, Marco, AEsperaMs, Fichero, Detalle) of
      etSinFuente:
        begin
          AFalta.Negativa := MsgFmt(SR_DESIGNER_SIN_FUENTE_FMT, [Nombre]);
          AFalta.Razon := MsgFmt(SF_DSGN_RAZON_SIN_FUENTE_FMT, [Nombre]);
          Exit;
        end;
      etGenerandose:
        begin
          AFalta.Negativa := MsgFmt(SR_DESIGNER_GENERANDOSE_FMT, [Nombre]);
          AFalta.Razon := MsgFmt(SF_DSGN_RAZON_GENERANDOSE_FMT, [Nombre]);
          Exit;
        end;
      etFallo:
        begin
          AFalta.Negativa := MsgFmt(SR_DESIGNER_TABLA_FALLO_FMT,
            [Nombre, Detalle, MINUTOS_REINTENTO_TABLA]);
          AFalta.Razon := MsgFmt(SF_DSGN_RAZON_FALLO_FMT, [Nombre, Detalle]);
          Exit;
        end;
    end;
    // Lazy: the facts become dictionaries once per table file, on the first
    // designer call that needs them, never at startup (hermes, release audit
    // 2026-08-26, P2.9), under a lock
    TMonitor.Enter(GMetaLock);
    try
      if not GTablas.TryGetValue(AnsiLowerCase(Fichero), Result) then
      begin
        Result := TMetaTable.DeFichero(Fichero);
        GTablas.Add(AnsiLowerCase(Fichero), Result);
        JubilaLocked(AnsiLowerCase(Fichero));
      end;
    finally
      TMonitor.Exit(GMetaLock);
    end;
  except
    // el fichero purgado por otro proceso entre mirarlo y leerlo, un disco...
    on E: Exception do
    begin
      Result := nil;
      AFalta.Negativa := MsgFmt(SR_DESIGNER_TABLA_ERROR_FMT, [E.Message]);
      AFalta.Razon := MsgFmt(SF_DSGN_RAZON_ERROR_FMT, [E.Message]);
    end;
  end;
end;

const
  SEP_CLAVE_PROP = '|';

function ClaveProp(const AClase, ANombre: string): string;
begin
  Result := ClaveDeIdentificador(AClase) + SEP_CLAVE_PROP + ClaveDeIdentificador(ANombre);
end;

constructor TMetaTable.Create(const AFacts: array of string);
var
  F, Names, Formas: string;
  P: TArray<string>;
  R: TPropRec;
  L: TList<string>;
begin
  inherited Create;
  Classes := TDictionary<string, string>.Create;
  PorNombre := TDictionary<string, string>.Create;
  IdEscrito := TDictionary<string, string>.Create;
  Props := TDictionary<string, TPropRec>.Create;
  PropNames := TDictionary<string, string>.Create;
  Enums := TDictionary<string, string>.Create;
  EnumShow := TDictionary<string, string>.Create;
  Sets := TDictionary<string, string>.Create;
  SetShow := TDictionary<string, string>.Create;
  Padres := TDictionary<string, string>.Create;
  Hijas := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  Definidas := TDictionary<string, string>.Create;
  Ambiguas := TDictionary<string, string>.Create;
  TextoEsNombre := TDictionary<string, Boolean>.Create;
  Bases := TDictionary<string, string>.Create;
  Constantes := TDictionary<string, string>.Create;
  ConstantesShow := TDictionary<string, string>.Create;
  FormasAbiertas := TDictionary<string, string>.Create;
  Estilos := TDictionary<string, string>.Create;
  for F in AFacts do
  begin
    P := F.Split([' ']);
    if Length(P) < 2 then
      Continue;
    if (P[0] = 'C') then
    begin
      Classes.AddOrSetValue(ClaveDeIdentificador(P[1]), NombreDeIdDeTipo(P[1]));
      IdEscrito.AddOrSetValue(ClaveDeIdentificador(P[1]), P[1]);
      if not PorNombre.ContainsKey(ClaveDeIdentificador(NombreDeIdDeTipo(P[1]))) then
        PorNombre.Add(ClaveDeIdentificador(NombreDeIdDeTipo(P[1])), ClaveDeIdentificador(P[1]));
    end
    else if (P[0] = 'P') and (Length(P) >= 4) then
    begin
      R.Kind := P[3][1];
      if Length(P) >= 5 then
        R.TypeId := P[4]
      else
        R.TypeId := '?';
      R.TypeName := NombreDeIdDeTipo(R.TypeId);
      R.Name := P[2];
      Props.AddOrSetValue(ClaveProp(P[1], P[2]), R);
      if PropNames.TryGetValue(ClaveDeIdentificador(P[1]), Names) then
      begin
        if Length(Names) < 200 then
          PropNames[ClaveDeIdentificador(P[1])] := Names + ', ' + P[2]
        else if not Names.EndsWith('...') then
          PropNames[ClaveDeIdentificador(P[1])] := Names + '...';
      end
      else
        PropNames.Add(ClaveDeIdentificador(P[1]), P[2]);
    end
    else if (P[0] = 'E') and (Length(P) >= 3) then
    begin
      Enums.AddOrSetValue(ClaveDeIdentificador(P[1]), ',' + ClaveDeIdentificador(P[2]) + ',');
      EnumShow.AddOrSetValue(ClaveDeIdentificador(P[1]), P[2].Replace(',', ', '));
    end
    else if (P[0] = 'S') and (Length(P) >= 3) then
    begin
      Sets.AddOrSetValue(ClaveDeIdentificador(P[1]), ',' + ClaveDeIdentificador(P[2]) + ',');
      SetShow.AddOrSetValue(ClaveDeIdentificador(P[1]), P[2].Replace(',', ', '));
    end
    else if (P[0] = 'N') and (Length(P) >= 3) then
      // el nombre que escribe un form es de OTRA que la primera C (la
      // registrada en la paleta, la que no es un modulo...): van al final
      PorNombre.AddOrSetValue(ClaveDeIdentificador(P[1]), ClaveDeIdentificador(P[2]))
    else if (P[0] = 'T') and (Length(P) >= 3) then
      TextoEsNombre.AddOrSetValue(ClaveDeIdentificador(P[1]), P[2] = '1')
    else if (P[0] = 'B') and (Length(P) >= 3) then
      Bases.AddOrSetValue(ClaveDeIdentificador(P[1]), LowerCase(P[2]))
    else if (P[0] = 'I') and (Length(P) >= 3) then
    begin
      // '*' cualquiera; '*a,b' abierta (esos nombres y algo mas); 'a,b' esos;
      // detras de ';', las formas de la abierta
      Names := P[2];
      Formas := '';
      if Names.Contains(';') then
      begin
        Formas := Copy(Names, Pos(';', Names), MaxInt);
        Names := Copy(Names, 1, Pos(';', Names) - 1);
        FormasAbiertas.AddOrSetValue(ClaveDeIdentificador(P[1]), Formas);
      end;
      if Names.StartsWith('*') then
        Delete(Names, 1, 1);
      if Names = '' then
        Constantes.AddOrSetValue(ClaveDeIdentificador(P[1]), '*')
      else
        Constantes.AddOrSetValue(ClaveDeIdentificador(P[1]),
          IfThen(P[2].StartsWith('*'), '*', '') + ',' + ClaveDeIdentificador(Names) + ',');
      ConstantesShow.AddOrSetValue(ClaveDeIdentificador(P[1]), Names.Replace(',', ', '));
    end
    else if (P[0] = 'K') and (Length(P) >= 3) and (Length(P[2]) = 2) then
      Estilos.AddOrSetValue(ClaveDeIdentificador(P[1]), P[2])
    else if (P[0] = 'X') and (Length(P) >= 3) then
      Ambiguas.AddOrSetValue(ClaveDeIdentificador(P[1]), P[1] + '|' + P[2])
    else if (P[0] = 'D') and (Length(P) >= 3) then
      Definidas.AddOrSetValue(ClaveProp(P[1], P[2]), P[2])
    else if (P[0] = 'H') and (Length(P) >= 3) then
    begin
      Padres.AddOrSetValue(ClaveDeIdentificador(P[1]), ClaveDeIdentificador(P[2]));
      if not Hijas.TryGetValue(ClaveDeIdentificador(P[2]), L) then
      begin
        L := TList<string>.Create;
        Hijas.Add(ClaveDeIdentificador(P[2]), L);
      end;
      L.Add(ClaveDeIdentificador(P[1]));
    end;
  end;
end;

destructor TMetaTable.Destroy;
begin
  Estilos.Free;
  FormasAbiertas.Free;
  ConstantesShow.Free;
  Constantes.Free;
  Bases.Free;
  TextoEsNombre.Free;
  Ambiguas.Free;
  Definidas.Free;
  Hijas.Free;
  Padres.Free;
  Sets.Free;
  SetShow.Free;
  EnumShow.Free;
  Enums.Free;
  PropNames.Free;
  Props.Free;
  IdEscrito.Free;
  PorNombre.Free;
  Classes.Free;
  inherited;
end;

function TMetaTable.PublicadasDeLaFamilia(const AClase: string): string;
var
  Cola: TQueue<string>;
  Vistas, Nombres: TDictionary<string, Boolean>;
  Hs: TList<string>;
  C, Lista: string;
begin
  Result := '';
  Cola := TQueue<string>.Create;
  Vistas := TDictionary<string, Boolean>.Create;
  Nombres := TDictionary<string, Boolean>.Create;
  try
    Cola.Enqueue(ClaveDeIdentificador(AClase));
    Vistas.Add(ClaveDeIdentificador(AClase), True);
    while (Cola.Count > 0) and (Length(Result) < 200) do
    begin
      C := Cola.Dequeue;
      if PropNames.TryGetValue(C, Lista) then
        for var X in Lista.Split([', ']) do
        begin
          // PropNames va cortada con '...' PEGADO al ultimo nombre ('Foo...')
          var N := X;
          if N.EndsWith('...') then
            N := N.Substring(0, N.Length - 3);
          if (N <> '') and not Nombres.ContainsKey(ClaveDeIdentificador(N)) then
          begin
            Nombres.Add(ClaveDeIdentificador(N), True);
            if Result = '' then
              Result := N
            else
              Result := Result + ', ' + N;
          end;
        end;
      if Hijas.TryGetValue(C, Hs) then
        for var H in Hs do
          if not Vistas.ContainsKey(H) then
          begin
            Vistas.Add(H, True);
            Cola.Enqueue(H);
          end;
    end;
    if Length(Result) >= 200 then
      Result := Result + '...';
  finally
    Nombres.Free;
    Vistas.Free;
    Cola.Free;
  end;
end;

function TMetaTable.ClaseDeNombre(const ANombre: string; out AId: string): Boolean;
var
  L: string;
begin
  AId := '';
  L := ClaveDeIdentificador(ANombre.Trim);
  if EsIdDeTipo(L) then
  begin
    Result := Classes.ContainsKey(L);
    if Result then
      AId := L;
    Exit;
  end;
  if Ambiguas.ContainsKey(L) then
    Exit(False);
  Result := PorNombre.TryGetValue(L, AId);
end;

function TMetaTable.DefinidaPorCodigo(const AClase, ANombre: string): Boolean;
var
  C: string;
begin
  // los que lee un ayudante para alguna clase del marco ('D * Font.Size')
  if Definidas.ContainsKey(ClaveProp('*', ANombre)) then
    Exit(True);
  for C in CadenaDe(AClase) do
    if Definidas.ContainsKey(ClaveProp(C, ANombre)) or Definidas.ContainsKey(ClaveProp(C, '*')) then
      Exit(True);
  Result := False;
end;

function TMetaTable.CadenaDe(const AClase: string): TArray<string>;
var
  C: string;
begin
  Result := [];
  C := ClaveDeIdentificador(AClase);
  while (C <> '') and (Length(Result) < 64) do
  begin
    Result := Result + [C];
    // la clave y la salida en variables distintas: un out de string se vacia
    // ANTES de la llamada, y con la misma la clave llegaria vacia
    var Padre: string;
    if not Padres.TryGetValue(C, Padre) then
      Break;
    C := Padre;
  end;
end;

function TMetaTable.TextoSigueAlNombre(const AClase: string): Boolean;
begin
  Result := False;
  for var C in CadenaDe(AClase) do
    if TextoEsNombre.TryGetValue(C, Result) then
      Break;
  // el SetName de TControl solo lo hace con csSetCaption en su ControlStyle
  // (TControlListButton lo quita y publica Caption: revision de la 1.17.0)
  if Result and Desciende(AClase, ID_VCL_CONTROL) then
    Result := EstiloDe(AClase, 1) <> '-';
end;

function TMetaTable.EstiloDe(const AClase: string; ABandera: Integer): Char;
var
  E: string;
begin
  for var C in CadenaDe(AClase) do
    if Estilos.TryGetValue(C, E) and (E[ABandera + 1] <> '.') then
      Exit(E[ABandera + 1]);
  Result := '.';
end;

function TMetaTable.AceptaControles(const AClase: string): Boolean;
begin
  Result := EstiloDe(AClase, 0) <> '-';
end;

function TMetaTable.Desciende(const AClase, AAncestro: string): Boolean;
var
  Meta: string;
begin
  Meta := ClaveDeIdentificador(AAncestro);
  for var C in CadenaDe(AClase) do
    if C = Meta then
      Exit(True);
  Result := False;
end;

function TMetaTable.DefinidasDeLaCadena(const AClase: string): TArray<string>;
var
  C: string;
  Lista: TList<string>;
begin
  Lista := TList<string>.Create;
  try
    for C in CadenaDe(AClase) do
      for var Par in Definidas do
        if Par.Key.StartsWith(ClaveProp(C, '')) and not Lista.Contains(Par.Value) then
          Lista.Add(Par.Value);
    Result := Lista.ToArray;
  finally
    Lista.Free;
  end;
end;

class function TMetaTable.DeFichero(const AFichero: string): TMetaTable;
begin
  Result := TMetaTable.Create(TFile.ReadAllLines(AFichero, TEncoding.UTF8));
end;

function TMetaTable.PublicadaEnDescendiente(const AClase, AProp: string;
  out ADescendiente: string): Boolean;
var
  Cola: TQueue<string>;
  Vistas: TDictionary<string, Boolean>;
  Hs: TList<string>;
begin
  Result := False;
  ADescendiente := '';
  Cola := TQueue<string>.Create;
  Vistas := TDictionary<string, Boolean>.Create;
  try
    Cola.Enqueue(ClaveDeIdentificador(AClase));
    while Cola.Count > 0 do
    begin
      if not Hijas.TryGetValue(Cola.Dequeue, Hs) then
        Continue;
      for var H in Hs do
      begin
        if Vistas.ContainsKey(H) then
          Continue;
        Vistas.Add(H, True);
        if Props.ContainsKey(ClaveProp(H, AProp)) then
        begin
          ADescendiente := H;
          Exit(True);
        end;
        Cola.Enqueue(H);
      end;
    end;
  finally
    Vistas.Free;
    Cola.Free;
  end;
end;

function ClaseQueNoEsta(M: TMetaTable; const AClass, AFramework: string): string;
var
  A: string;
begin
  if M.Ambiguas.TryGetValue(ClaveDeIdentificador(AClass.Trim), A) then
    Result := MsgFmt(SR_DESIGNER_CLASE_AMBIGUA_FMT, [A.Substring(0, A.IndexOf('|')),
      UpperCase(AFramework), A.Substring(A.IndexOf('|') + 1)])
  else
    Result := MsgFmt(SR_DESIGNER_CLASS_FMT, [AClass, UpperCase(AFramework)]);
end;

function DesignerMetaLint(const AIsFmx: Boolean; const ALines: TArray<string>;
  out ANotas: TArray<string>; out AFalta: TFaltaTabla; AEsperaMs: Cardinal): TArray<string>;
var
  M: TMetaTable;
begin
  Result := nil;
  ANotas := nil;
  M := MetaTable(AIsFmx, AFalta, AEsperaMs);
  if M = nil then
    Exit;
  try
    Result := LintConTabla(M, AIsFmx, ALines, ANotas);
  except
    on E: Exception do
    begin
      Result := nil;
      ANotas := nil;
      AFalta.Negativa := MsgFmt(SR_DESIGNER_TABLA_ERROR_FMT, [E.Message]);
      AFalta.Razon := MsgFmt(SF_DSGN_RAZON_ERROR_FMT, [E.Message]);
    end;
  end;
end;

function JuzgaPropiedad(M: TMetaTable; const AClase, ALhs, ARhs: string;
  out AHoja: TPropRec; out AHayHoja: Boolean): string;
var
  SIdx: Integer;
  Cur, CurShow, Seg, Key, Have, Members, V, Desc: string;
  Segs: TArray<string>;
  R: TPropRec;
begin
  Result := '';
  AHayHoja := False;
  AHoja := Default(TPropRec);
  Cur := AClase;
  if not M.Classes.TryGetValue(Cur, CurShow) then
    Exit;
  Segs := ALhs.Split(['.']);
  for SIdx := 0 to High(Segs) do
  begin
    Seg := ClaveDeIdentificador(Segs[SIdx]);
    Key := ClaveProp(Cur, Seg);
    // going down a class-typed property, the instance may be of a
    // DESCENDANT of the declared type (TLabel.TextSettings declares
    // TTextSettings and holds a TLabelTextSettings, chosen by code): what
    // a descendant publishes is not denied. The object of a form line is
    // its exact class: no such leeway at segment 0.
    if not M.Props.TryGetValue(Key, R) and (SIdx > 0) and
       M.PublicadaEnDescendiente(Cur, Seg, Desc) then
    begin
      Cur := Desc;
      Key := ClaveProp(Cur, Seg);
      M.Classes.TryGetValue(Cur, CurShow);
    end;
    if not M.Props.TryGetValue(Key, R) then
    begin
      // lo que la clase guarda POR CODIGO (Filer.DefineProperty) lo
      // escribe el IDE sin publicarlo: Left/Top de un no visual, los
      // Explicit*, TextHeight, Viewport.Width (con su punto: es UN
      // nombre de la clase del objeto), y bajando por una propiedad objeto
      // lo que guarda ESA clase (FMX TPosition guarda Point). DESPUES de
      // lo publicado: preguntado antes, el 'TCustomScrollBox *' callaba
      // todo TListBox, valores incluidos (Align = alClient; revision)
      if M.DefinidaPorCodigo(Cur, string.Join('.', Segs, SIdx, Length(Segs) - SIdx)) or
         ((SIdx > 0) and M.DefinidaPorCodigo(AClase, ALhs)) then
        Exit;
      // down a class-typed property whose type has descendants: what no
      // class of the family publishes (TTextSettings publishes nothing;
      // its descendants do)
      if (SIdx > 0) and M.Hijas.ContainsKey(Cur) then
      begin
        Have := M.PublicadasDeLaFamilia(Cur);
        if Have <> '' then
          Result := MsgFmt(SF_DSGN_NO_EXISTE_EN_LA_FAMILIA_FMT,
            [Segs[SIdx], CurShow, Have]);
        Exit;
      end;
      if not M.PropNames.TryGetValue(Cur, Have) then
        Exit; // class without data: silence, never guess
      // (What the DESIGNER writes without publishing it - Left/Top of a
      // non-visual component, the VCL's Explicit* and DesignSize, FMX's
      // Viewport.Width - was a hand list here until 1.12.0, after field
      // reports of 2026-08-24 and round 8. It is streamed by the class's
      // own DefineProperties, and the table now reads those names from
      // the source: DefinidaPorCodigo, at the top of this branch.)
      Exit(MsgFmt(SF_DSGN_NO_EXISTE_SEGUN_FRAMEWORK_FMT,
        [Segs[SIdx], CurShow, Have]));
    end;
    if SIdx < High(Segs) then
    begin
      if R.Kind = '?' then
        Exit; // a type the source did not let us read: silence
      if R.Kind <> 'c' then
        Exit(MsgFmt(SF_DSGN_SIN_SUBPROPIEDADES_FMT, [Segs[SIdx], R.TypeName]));
      // descend into the declared type (its descendants, above): one that
      // publishes nothing but has descendants is not "no data". By its
      // IDENTITY: TeeChart's TFont is not the VCL's
      Cur := ClaveDeIdentificador(R.TypeId);
      if (not M.Classes.TryGetValue(Cur, CurShow)) or
         (not M.PropNames.ContainsKey(Cur) and not M.Hijas.ContainsKey(Cur)) then
        Exit; // no data for the subtree: silence
    end
    else
    begin
      AHoja := R;
      AHayHoja := True;
      // leaf value checks, only where the table can KNOW
      // Un enumerado es UN identificador (ReadIdent): su valor, o Tipo.valor
      // con el nombre del tipo, que GetEnumValue tambien lee. Un numero, una
      // cadena o Vcl.Controls.TAlign.alClient no los lee: se escribian y el
      // form no cargaba (revision de la 1.17.0)
      if R.Kind = 'e' then
      begin
        V := ARhs;
        if (Pos('.', V) > 0) and SameText(Copy(V, 1, Pos('.', V) - 1), R.TypeName) then
          V := Copy(V, Pos('.', V) + 1, MaxInt);
        if not M.EnumShow.TryGetValue(ClaveDeIdentificador(R.TypeId), Have) then
          Have := '?';
        if not EsIdentificador(V, False) or
           (M.Enums.TryGetValue(ClaveDeIdentificador(R.TypeId), Members) and
            not Members.Contains(',' + ClaveDeIdentificador(V) + ',')) then
          Exit(MsgFmt(SF_DSGN_NO_ES_VALOR_FMT, [ARhs, R.TypeName, Have]));
      end
      // un conjunto, entre corchetes y de nombres sueltos (ReadSet): un
      // numero, una cadena o [fsBold,] no los lee
      else if R.Kind = 's' then
      begin
        if not (ARhs.StartsWith('[') and ARhs.EndsWith(']')) then
        begin
          V := ARhs;
          if not EsIdentificador(V, False) and M.SetShow.TryGetValue(ClaveDeIdentificador(R.TypeId), Have) then
            V := Have.Split([','])[0].Trim;
          Exit(MsgFmt(SF_DSGN_ES_UN_SET_FMT, [R.TypeName, V]));
        end;
        if ARhs.Substring(1, Length(ARhs) - 2).Trim <> '' then
          for V in ARhs.Substring(1, Length(ARhs) - 2).Split([',']) do
            if not EsIdentificador(V.Trim, False) or
               (M.Sets.TryGetValue(ClaveDeIdentificador(R.TypeId), Members) and
                not Members.Contains(',' + ClaveDeIdentificador(V.Trim) + ',')) then
              Exit(MsgFmt(SF_DSGN_NO_ES_ELEMENTO_FMT, [IfThen(V.Trim = '', ARhs, V.Trim), R.TypeName]));
      end;
    end;
  end;
end;

{ Si AValor carga por una de las formas de una lista abierta (AFormas, las
  de FormasAbiertas) con sus nombres ALista (',a,b,' en minusculas). }
function CargaPorSusFormas(const AFormas, AValor, ALista: string): Boolean;
var
  N: Integer;
begin
  Result := False;
  for var F in AFormas.Split([';'], TStringSplitOptions.ExcludeEmpty) do
    if F.StartsWith('hex=') and (Length(F) = 5) then
    begin
      // la letra como la compara su cuerpo (Chars[0] = 'x', con su caja) y un
      // hexadecimal que quepa en 64 bits (StrToInt64 de '$' y el resto)
      if (Length(AValor) >= 2) and (Length(AValor) <= 17) and (AValor[1] = F[5]) and
         TRegEx.IsMatch(Copy(AValor, 2, MaxInt), '\A[0-9A-Fa-f]+\z') then
        Exit(True);
    end
    else if F.StartsWith('ins=') and (Length(F) >= 6) then
    begin
      N := StrToIntDef(Copy(F, 5, Length(F) - 5), -1);
      if (N >= 0) and (Length(AValor) > N) and ALista.Contains(',' +
           ClaveDeIdentificador(Copy(AValor, 1, N) + F[Length(F)] + Copy(AValor, N + 1, MaxInt)) + ',') then
        Exit(True);
    end;
end;

{ Como se ensenan esas formas: la letra y un hexadecimal; los nombres sin la
  letra que inserta, con un ejemplo de los suyos (clAliceblue por
  claAliceblue). }
function FormasQueSeEnsenan(const AFormas: string; const ANombres: TArray<string>): string;
var
  N: Integer;
  C: Char;
  Ejemplo: string;
begin
  Result := '';
  for var F in AFormas.Split([';'], TStringSplitOptions.ExcludeEmpty) do
    if F.StartsWith('hex=') and (Length(F) = 5) then
      Result := Result + IfThen(Result <> '', '; ') + MsgFmt(SF_DESIGNER_FORMA_HEX_FMT, [F[5]])
    else if F.StartsWith('ins=') and (Length(F) >= 6) then
    begin
      N := StrToIntDef(Copy(F, 5, Length(F) - 5), -1);
      C := F[Length(F)];
      Ejemplo := '';
      for var Nm in ANombres do
        if (N >= 0) and (Length(Nm) > N) and (Nm[N + 1] = C) then
        begin
          Ejemplo := MsgFmt(SF_DESIGNER_FORMA_INSERTA_EJEMPLO_FMT, [Copy(Nm, 1, N) + Copy(Nm, N + 2, MaxInt), Nm]);
          Break;
        end;
      Result := Result + IfThen(Result <> '', '; ') + MsgFmt(SF_DESIGNER_FORMA_INSERTA_FMT, [C, Ejemplo]);
    end;
end;

function BaseQueNoCasa(M: TMetaTable; const AHoja: TPropRec; const AValor: string;
  out AAviso: string;
  out AParecida: string): string;
const
  MAX_MUESTRA = 12;
var
  Base, K, Lista, Show, Formas: string;
  Nombres: TArray<string>;
  Tope: Integer;
  N: Int64;
  Abierta: Boolean;
begin
  Result := '';
  AParecida := '';
  AAviso := '';
  if AHoja.Kind <> 'o' then
    Exit;
  K := ClaveDeIdentificador(AHoja.TypeId);
  if not M.Bases.TryGetValue(K, Base) then
    Exit;
  if (Base = 'integer') or (Base = 'int64') then
  begin
    // y que quepa donde lo lee el cargador: ReadInteger lee 32 bits (un
    // $FFFF0000 sale del texto como Int64 y el form no carga), ReadInt64 64
    // (revision de la 1.17.0)
    if EsEnteroDeForm(AValor) then
    begin
      if TryStrToInt64(AValor, N) and
         ((Base = 'int64') or ((N >= Low(Integer)) and (N <= High(Integer)))) then
        Exit;
      Exit(MsgText(IfThen(Base = 'int64', SF_DESIGNER_TOMA_ENTERO64, SF_DESIGNER_TOMA_ENTERO32)));
    end;
    // un identificador solo si el tipo registra constantes, y entonces una
    // de las suyas (ReadPropValue le pregunta a su IdentToInt); un Int64 no
    if (Base = 'integer') and M.Constantes.TryGetValue(K, Lista) then
    begin
      if Lista = '*' then
      begin
        if EsIdentificador(AValor, False) then
          Exit;
        Exit(MsgText(SF_DESIGNER_TOMA_CONSTANTE));
      end;
      if EsIdentificador(AValor, False) and Lista.Contains(',' + ClaveDeIdentificador(AValor) + ',') then
        Exit;
      Abierta := Lista.StartsWith('*');
      Show := M.ConstantesShow[K];
      Nombres := Show.Split([', ']);
      if EsIdentificador(AValor, False) then
      begin
        Tope := Length(AValor) div 3;
        if Tope < 2 then
          Tope := 2;
        var Cerca := ElMasParecido(AValor, Nombres, Tope);
        if Cerca <> '' then
          AParecida := MsgFmt(SF_DESIGNER_QUIZAS_FMT, [Cerca]);
      end;
      if Length(Nombres) > MAX_MUESTRA then
        Show := string.Join(', ', Copy(Nombres, 0, MAX_MUESTRA)) + ', ...';
      // ABIERTA (su IdentTo lee mas que sus nombres): con sus formas leidas
      // del fuente (generacion 12) el juicio es exacto - 'Rojo' en un
      // TAlphaColor se escribia y el form no abria; clRed y xFF00FF00 si
      // cargan (segunda revision de la 1.17.0) -; sin ellas no se sabe que
      // mas lee: se escribe, y con su aviso siempre
      // ...y lo que su lector tambien toma se ensena SIEMPRE, sea cual sea el
      // valor: con uno que no era un nombre ('rojo' entre comillas) solo se
      // daban los nombres (3.9 de la 1.18.0, Hermes)
      if Abierta and M.FormasAbiertas.TryGetValue(K, Formas) then
      begin
        if EsIdentificador(AValor, False) and CargaPorSusFormas(Formas, AValor, Lista) then
        begin
          AParecida := '';
          Exit;
        end;
        Exit(MsgFmt(SF_DESIGNER_TOMA_ABIERTA_FMT, [Show, FormasQueSeEnsenan(Formas, Nombres)]));
      end;
      if Abierta and EsIdentificador(AValor, False) then
      begin
        AAviso := MsgFmt(SN_DESIGNER_CONSTANTE_ABIERTA_FMT, [AValor, AHoja.TypeName, AParecida]);
        AParecida := '';
        Exit;
      end;
      Exit(MsgFmt(SF_DESIGNER_TOMA_CONSTANTES_FMT, [Show]));
    end;
    Exit(MsgText(SF_DESIGNER_TOMA_ENTERO));
  end;
  if (Base = 'float') or (Base = 'single') then
  begin
    // LA gramatica del numero (Lsp.DesignerBin): con exponente, y un $hex
    // tambien, que ReadFloat lee como entero
    if not EsNumeroDeForm(AValor) then
      Result := MsgText(SF_DESIGNER_TOMA_NUMERO);
  end
  else if Base = 'char' then
  begin
    if not EsCaracterDeForm(AValor) then
      Result := MsgText(SF_DESIGNER_TOMA_CARACTER);
  end
  else if Base = 'string' then
  begin
    if not EsLiteralDeForm(AValor) then
      Result := MsgText(SF_DESIGNER_TOMA_CADENA);
  end
  // un Variant: lo que ReadVariant lee - un numero, una cadena, True, False,
  // Null o nil; un identificador cualquiera, no (Valor = Hola pasaba)
  else if Base = 'variant' then
  begin
    if not (EsNumeroDeForm(AValor) or EsLiteralDeForm(AValor) or
            MatchText(AValor, ['True', 'False', 'Null', 'nil'])) then
      Result := MsgText(SF_DESIGNER_TOMA_VARIANTE);
  end;
end;

function LintConTabla(M: TMetaTable; const AIsFmx: Boolean;
  const ALines: TArray<string>; out ANotas: TArray<string>): TArray<string>;
var
  Stack: TStack<string>;    // owner class per nesting level ('' = unknown)
  Warns, Notas: TStringList;
  I: Integer;
  Lhs, Rhs, Cur, Have: string;
  OClave, OClase: string;
  R: TPropRec;
  Hoja: Boolean;
  Unknown: string;
  Form: TArray<TLineaForm>;

  procedure Warn(const AMsg: string);
  begin
    Warns.Add(MsgFmt(SF_DSGN_LINEA_AVISO_FMT,
      [I + 1, ALines[I].Trim, AMsg]));
  end;

  // lo que no se ha podido comprobar, con la misma forma de linea
  procedure Nota(const AMsg: string);
  begin
    Notas.Add(MsgFmt(SF_DSGN_LINEA_AVISO_FMT,
      [I + 1, ALines[I].Trim, AMsg]));
  end;

begin
  ANotas := nil;
  Stack := TStack<string>.Create;
  Warns := TStringList.Create;
  Notas := TStringList.Create;
  Unknown := ',';
  // EL lector de las lineas (Lsp.DesignerBin.LineasDeForm), el mismo del
  // arbol: lo de dentro de una coleccion (las clases de sus items no salen en
  // el texto), de una lista o de un bloque binario no se juzga, y una cadena
  // partida se juzga entera. Aqui habia un salto propio, uno de los cuatro
  try
    Form := LineasDeForm(ALines);
    for I := 0 to High(ALines) do
      case Form[I].Clase of
        clfObjeto:
          begin
            OClave := Form[I].Clave;
            OClase := Form[I].ClaseObj;
            // the name is optional: 'object TMemo' is an unnamed component, and
            // without it its properties went to the PARENT (and its end popped the
            // parent: 1.12.0 review, a FireDAC sample). THE reader of that line
            // (Lsp.DesignerBin), shared with binding, tree and the rename
            Cur := ClaveDeIdentificador(OClase);
            // The ROOT object and an inline frame are user classes by definition
            // (a form, a frame, a data module): never judged. With the tables
            // read from the library paths a user's TForm1 can share its name
            // with a demo's (202 form classes there: TForm1, TAboutBox...), and
            // judging it said TextHeight/PixelsPerInch did not exist (1.12.0
            // review: 33 Samples forms).
            if (Stack.Count = 0) or (OClave = 'inline') then
            begin
              Stack.Push('');
              Continue;
            end;
            // the NAME a form writes -> the class identity (with its unit)
            if not M.ClaseDeNombre(OClase, Cur) then
            begin
              Cur := ClaveDeIdentificador(OClase);
              // Not judging an unknown class is right (a user form or a
              // third-party component is not an error), but saying NOTHING was
              // read as "checked and fine" - and lint's own description promises
              // unknown classes (field round 8). One honest line, no verdict:
              // it says why that whole subtree went unchecked.
              // ...but NOT for the root object, nor for inherited/inline: a form,
              // a frame and a data module are user classes by definition and no
              // table will ever hold them. Only a nested `object` of an unknown
              // class is worth a word (a third-party component, or a typo).
              if (Stack.Count > 0) and (OClave = 'object') and
                 not Unknown.Contains(',' + Cur + ',') then
              begin
                Unknown := Unknown + Cur + ',';
                if M.Ambiguas.TryGetValue(Cur, Have) then
                  Nota(MsgFmt(SN_LINT_CLASE_AMBIGUA_FMT, [OClase,
                    IfThen(AIsFmx, 'FMX', 'VCL'), Have.Substring(Have.IndexOf('|') + 1)]))
                else
                  Nota(MsgFmt(SN_LINT_UNKNOWN_CLASS_FMT,
                    [OClase, IfThen(AIsFmx, 'FMX', 'VCL')]));
              end;
              Cur := '';
            end;
            Stack.Push(Cur);
          end;
        clfFin:
          if Stack.Count > 0 then
            Stack.Pop;
        clfPropiedad:
          begin
            // lo de un item de una coleccion: su clase no sale en el texto
            if Form[I].Coleccion > 0 then
              Continue;
            Lhs := Form[I].Prop;
            Rhs := ValorEnteroDe(ALines, Form, I);
            // una coleccion, una lista o un bloque binario (lo que guarda la
            // clase por codigo, DefineProperties): no se juzgan
            if EsValorDeBloque(Rhs) then
              Continue;
            if Stack.Count = 0 then
              Continue;
            Cur := Stack.Peek;
            if Cur = '' then
              Continue;
            // en FMX Left/Top no colocan un control: los guarda TComponent, el
            // sitio del icono de un no visual (3.7 de la 1.18.0, Hermes)
            if AIsFmx and MatchText(Lhs, ['Left', 'Top']) and M.Desciende(Cur, ID_FMX_CONTROL) then
            begin
              Warn(MsgFmt(SF_DSGN_FMX_LEFT_TOP_FMT,
                [Lhs, IfThen(SameText(Lhs, 'Left'), 'Position.X', 'Position.Y')]));
              Continue;
            end;
            // EL juez de una linea, el mismo que pregunta delphi_designer set
            Have := JuzgaPropiedad(M, Cur, Lhs, Rhs, R, Hoja);
            if Have <> '' then
              Warn(Have)
            // ...y el juez de tipos de set, con la hoja: un numero, una cadena,
            // un entero o una constante suya. Decia CLEAN de Color = 'hola'
            // (3.1 de la 1.18.0); lo que no se puede saber (una lista abierta
            // sin sus formas) va a las notas
            else if Hoja then
            begin
              var Aviso, Parecida: string;
              var Toma := BaseQueNoCasa(M, R, Rhs, Aviso, Parecida);
              if Toma <> '' then
                Warn(MsgFmt(SF_DSGN_LINT_TIPO_FMT, [Lhs, R.TypeName, Toma, Rhs, Parecida]))
              else if Aviso <> '' then
                Nota(Aviso);
            end;
          end;
      end;
    Result := Warns.ToStringArray;
    ANotas := Notas.ToStringArray;
  finally
    Notas.Free;
    Warns.Free;
    Stack.Free;
  end;
end;

initialization
  GMetaLock := TObject.Create;
  GTablas := TObjectDictionary<string, TMetaTable>.Create([doOwnsValues]);
  GJubiladas := TList<TJubilada>.Create;

finalization
  for var J in GJubiladas do
    J.Tabla.Free;
  GJubiladas.Free;
  GTablas.Free;
  GMetaLock.Free;

end.
