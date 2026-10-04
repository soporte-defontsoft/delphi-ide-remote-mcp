unit Lsp.DesignerMetaGen;

{ LAS TABLAS DEL DISENADOR, sacadas del FUENTE de cada Delphi instalado.

  Lo que dicen: las clases persistentes (las que pueden ir en un .dfm/.fmx),
  sus propiedades PUBLICADAS con su clase de tipo, los miembros de los
  enumerados y de los conjuntos, y de quien hereda cada clase. Es lo que
  leen delphi_designer info/prop/lint y el lint que va detras de cada
  edicion de un form (Lsp.DesignerMeta), en el formato de hechos de siempre:
    C TButton                     la clase
    H TButton TCustomButton       su padre
    P TButton Caption o TCaption  una propiedad publicada: clase y tipo (un
                                  enumerado o un conjunto, con su unidad:
                                  'e Vcl.Controls:TAlign', IdDeTipo)
    D TComponent Left             lo que guarda POR CODIGO (DefineProperties);
                                  'D TClase *': nombres que no se pueden leer
    X TDuplo UnoA:TDuplo,UnoB:TDuplo  varias la declaran con otras publicadas
                                  y ninguna gana el nombre: no se juzga
    N THttpServer OverbyteIcsHttpSrv:THttpServer  el nombre que escribe un
                                  form es de esta, no de la primera C
    E Vcl.Controls:TAlign alNone,alTop,...   los miembros de un enumerado
    S Vcl.Controls:TAnchors akLeft,akTop,... los de un conjunto

  De donde: hasta la 1.11 eran dos unidades Pascal GENERADAS a mano con la
  RTTI de UNA build de RAD Studio y compiladas dentro del exe; con otro
  Delphi "no esta en la tabla" dejaba de querer decir "no existe" (DSGN-049).
  David, 3-oct-2026: "no podemos depender de un pas hardcodeado a una
  version concreta". Ahora cada Delphi tiene la suya, leida de SU fuente:
  el Library Search Path y el Browsing Path de su IDE (Win32 y Win64),
  carpeta a carpeta sin bajar, como el compilador - asi entran tambien los
  componentes de terceros instalados desde su fuente (medido el 3-oct en
  este PC: Defontsoft, QuickReport, ICS, ZipMaster, TeeChart... estan en el
  Search Path, no en el Browsing). Sin compilar ni ejecutar nada (David).

  Como: cada unidad pasa por EL preprocesador (Lsp.Preproceso, con los
  simbolos derivados de la version del compilador) y por el lector de
  declaraciones (Lsp.PascalDecl); los nombres se resuelven con el alcance
  de cada unidad (sus uses, del ultimo al primero, y System), los tipos
  anidados en su clase y sus ancestros. Lo PUBLICADO lo dice la seccion
  del fuente; el LSP no lo da (medido en crudo el 3-oct-2026).

  Medido el 3-oct-2026 con el prototipo contra las tablas de la RTTI: VCL
  99,93 % de las propiedades identicas, FMX 98,8 %. Lo que no se puede
  sacar del fuente es la clase REAL de una propiedad objeto (TLabel.
  TextSettings declara TTextSettings y guarda un TLabelTextSettings, que
  elige el codigo): por eso la herencia (H) - el lint busca en los
  descendientes del tipo declarado antes de decir que algo no existe.

  Cuando: al arrancar el servidor, una por cada Delphi instalado, en el
  hilo del generador y de una en una (CalientaTablasDelDisenador); y si se
  instala o se toca algo en esas carpetas (cambia la huella del fuente), al
  primer uso, en ese mismo hilo - quien pregunta nunca genera, y mientras
  vale la de antes. En la cache del servidor (ServerCacheDir), con la huella
  en el nombre; la vieja se borra pasada una hora. }

interface

uses
  Lsp.Discovery;

type
  TMarcoDisenador = (mdVcl, mdFmx);
  TMarcosDisenador = set of TMarcoDisenador;

  TTablasDeFuente = record
    Hechos: array [TMarcoDisenador] of TArray<string>;
    Unidades: Integer; // las que se leyeron
    Ms: Integer;       // lo que tardo
    // las clases que dos unidades declaran con otras publicadas (X)
    Ambiguas: array [TMarcoDisenador] of TArray<string>;
  end;

  TEstadoTabla = (etLista, etSinFuente, etGenerandose, etFallo);

const
  { Sube cuando cambian las reglas del generador: una tabla de otra
    generacion no se reutiliza aunque el fuente sea el mismo. }
  GENERACION_TABLAS = 6; // 3: constantes del cuerpo, '?', ayudantes (revision de la 1.12.0); 4: los tipos de un DefineProperties, T y mayuscula (1.12.1); 5: EL identificador de Lsp.Pascal, con letras de cualquier alfabeto; Declared() de los tipos del compilador; la plataforma del IDE; una etiqueta @@END de un asm no cierra la rutina; 6: las comas de las restricciones de un generico no son parametros (su aridad), los class helpers aparte (revision de la 1.13.0)
  // lo que se recuerda un fallo del generador antes de intentarlo otra vez
  MINUTOS_REINTENTO_TABLA = 10;

// 'vcl' / 'fmx': el trozo del nombre de una tabla
function NombreDeMarco(AMarco: TMarcoDisenador): string;

{ EL nombrador de la identidad de un enumerado o un conjunto en los hechos
  P/E/S, con su unidad ('Vcl.Buttons:TButtonLayout'; sin unidad, los del
  compilador: 'Boolean'): dos unidades declaran tipos con el mismo nombre y
  otros miembros (el TIBProtocol de FireDAC y el de IBX, el TButtonLayout de
  Vcl.Buttons y el de un componente de terceros), y por el nombre solo
  ganaba el primero - el lint daba por malos valores buenos (revision de la
  1.12.0). Y su lector: el nombre que se ensena. }
function IdDeTipo(const AUnidad, ANombre: string): string;
function NombreDeIdDeTipo(const AId: string): string;
// Sus otros dos lectores: si es una identidad con unidad, y su unidad ('' sin
// ella). El ':' se leia a mano en cuatro sitios (revision de la 1.12.0)
function EsIdDeTipo(const AId: string): Boolean;
function UnidadDeIdDeTipo(const AId: string): string;

{ Lo que una clase guarda en el form POR CODIGO, sin publicarlo: los
  nombres de Filer.DefineProperty / DefineBinaryProperty de cada
  'procedure TClase.DefineProperties' de ATexto (con las cadenas: TextoActivo
  con AConCadenas), como 'TClase Nombre' - un literal, una suma de literales
  y constantes de su cuerpo o una lista constante con indice
  (NombresDelArgumento) -; 'TClase *' si alguno se construye de otra forma
  y no se puede leer. TComponent guarda asi Left y Top, TControl
  los Explicit*, TCustomForm TextHeight y PixelsPerInch, TField Lookup,
  QuickReport FontSize: sin ellos el lint daba por inexistente lo que el IDE
  escribe (230 avisos falsos en los Samples; revision de la 1.12.0). Y los
  nombres que van FUERA de un DefineProperties: en un metodo de un ayudante
  ('~Ayudante Nombre', o '~Ayudante *' si no se lee: FMX lee asi los nombres
  viejos Font.Size, WordWrap, TextAlign, en TTextSettingsInfo.TTextPropLoader),
  que son de las clases que lo nombran (ResuelveAyudantes); en una rutina
  suelta, '* Nombre': los guarda alguna clase del marco, no se sabe cual. }
function PropiedadesDefinidasPorCodigo(const ATexto: string): TArray<string>;

{ Los nombres de clase que ATexto registra en la paleta del IDE
  (RegisterComponents('Pagina', [TA, TB]) y RegisterNoIcon([TC])), tal como
  van escritos: quien se queda el nombre de una linea 'object X: TFoo'
  cuando dos unidades tienen un TFoo (el THttpServer de ICS, registrado, y
  el THTTPServer de HTTPIntr, un modulo). }
function RegistradosEnPaleta(const ATexto: string): TArray<string>;

{ Las tablas sacadas del fuente que hay en ACarpetas (cada una sin bajar;
  las primeras ganan cuando dos tienen la misma unidad), con los simbolos
  del compilador AVersionCompilador para APlataforma, la del IDE de esa
  instalacion (PlataformaDelIde): lo publicado sale de la RTTI de su
  disenador. ARaizBds: la carpeta de la instalacion; lo suyo gana a lo de
  terceros cuando dos clases se llaman igual. Pura: no mira el registro ni
  escribe nada. }
function GeneraTablasDeFuente(const ACarpetas: TArray<string>;
  const AVersionCompilador, ARaizBds: string;
  const APlataforma: string = 'Win64'): TTablasDeFuente;

{ Las carpetas de fuente de una instalacion: el Library Search Path y el
  Browsing Path de su IDE, de Win32 y de Win64, expandidas con sus macros,
  las que existen, sin repetir y en ese orden. }
function CarpetasDeFuente(const AInfo: TRadStudioInfo): TArray<string>;

{ La version del compilador de una instalacion ('37.0'), la que vale
  CompilerVersion: el RTLVersion que declara su System.pas (en cada Delphi
  moderno valen lo mismo; CompilerVersion lo pone el compilador y en el
  fuente vale 0.0); si no se encuentra, la de su dcc32.exe; si tampoco, la
  clave de la instalacion. La clave no sirve sola: la 12 es la 23.0 y su
  compilador el 36.0. }
function VersionDelCompilador(const AInfo: TRadStudioInfo;
  const ACarpetas: TArray<string>): string;

{ La huella del fuente de esas carpetas: cambia si se anade, se quita o se
  toca un .pas o un .inc de cualquiera de ellas. Y con la plataforma con la
  que se lee (APlataforma): la misma instalacion con el IDE de 64 bits
  anadido despues es otra tabla. }
function HuellaDeCarpetas(const ACarpetas: TArray<string>;
  const APlataforma: string = ''): string;

{ EL nombrador de una tabla en la cache, y su lector (la inversa): de que
  instalacion es, de que build, de que marco, de que fuente y de que
  generacion del generador. }
function NombreDeTabla(const AVersion, ABuild: string; AMarco: TMarcoDisenador;
  const AHuella: string; AGeneracion: Integer = GENERACION_TABLAS): string;
function LeeNombreDeTabla(const ANombre: string; out AVersion, ABuild: string;
  out AMarco: TMarcoDisenador; out AHuella: string; out AGeneracion: Integer): Boolean;

{ El fichero de la tabla de AMarco de la instalacion AInfo. Quien pregunta
  NUNCA la genera: si no esta se pide al hilo del generador (las dos de esa
  instalacion, de una en una para todo el servidor) y, mientras, vale la de
  antes (otra huella de la misma build); sin ninguna, se espera AEsperaMs
  (0 = nada). etSinFuente: esa instalacion no trae fuente; etGenerandose:
  no acabo a tiempo; etFallo: la generacion fallo hace poco, y ADetalle
  dice por que. }
function TablaDeInstalacion(const AInfo: TRadStudioInfo; AMarco: TMarcoDisenador;
  AEsperaMs: Cardinal; out AFichero, ADetalle: string): TEstadoTabla;

{ Al arrancar: las tablas de cada Delphi instalado, en el hilo del generador
  (prioridad baja, de una en una), y fuera las de los que ya no estan. Lo
  que tarda se apunta en el log. No espera. }
procedure CalientaTablasDelDisenador;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Hash,
  System.Math,
  System.StrUtils,
  System.RegularExpressions,
  System.Generics.Collections,
  System.Generics.Defaults,
  Lsp.Preproceso,
  Lsp.PascalDecl,
  Lsp.Pascal,           // CodigoPascal: el RTLVersion de System.pas
  Lsp.Patch,            // PatchLoadText: el fuente con su codificacion real
  Lsp.Guard,            // IdePlatformLibraryPaths, ServerCacheDir, EscribeEnCasaDelServidor
  Lsp.ConfigFabricator, // DEFAULT_NAMESPACES
  Lsp.NetDrives,        // NotaAlLog
  Lsp.Texts;

var
  // el servidor se cierra: el generador lo mira entre unidad y unidad
  GCerrando: Boolean;

function NombreDeMarco(AMarco: TMarcoDisenador): string;
begin
  if AMarco = mdFmx then
    Result := 'fmx'
  else
    Result := 'vcl';
end;

const
  SEP_ID_TIPO = ':';

function IdDeTipo(const AUnidad, ANombre: string): string;
begin
  if AUnidad = '' then
    Result := ANombre
  else
    Result := AUnidad + SEP_ID_TIPO + ANombre;
end;

function NombreDeIdDeTipo(const AId: string): string;
begin
  Result := AId.Substring(AId.IndexOf(SEP_ID_TIPO) + 1);
end;

function EsIdDeTipo(const AId: string): Boolean;
begin
  Result := AId.Contains(SEP_ID_TIPO);
end;

function UnidadDeIdDeTipo(const AId: string): string;
begin
  if EsIdDeTipo(AId) then
    Result := AId.Substring(0, AId.IndexOf(SEP_ID_TIPO))
  else
    Result := '';
end;

function RegistradosEnPaleta(const ATexto: string): TArray<string>;
var
  Lista: TList<string>;
  Lista2: TMatch;
begin
  Lista := TList<string>.Create;
  try
    for var Mt in TRegEx.Matches(ATexto, '(?is)' + PATRON_NO_IDENT_ANTES + 'Register(?:Components|NoIcon)\s*\((.*?)\)\s*;') do
    begin
      Lista2 := TRegEx.Match(Mt.Groups[1].Value, '\[([^\]]*)\]');
      if Lista2.Success then
        for var N in Lista2.Groups[1].Value.Split([',']) do
          if EsIdentificador(N.Trim, True) and not Lista.Contains(N.Trim) then
            Lista.Add(N.Trim);
    end;
    Result := Lista.ToArray;
  finally
    Lista.Free;
  end;
end;

{ Los nombres que da el primer argumento de un Filer.DefineProperty, que
  empieza en AP de ATexto: un literal; una suma de literales y de constantes
  de cadena de ACuerpo (FMX TCustomScrollBox: const VP = 'Viewport' y
  VP + '.Width'); o una constante lista de cadenas con un indice (FMX
  TColumn: OldPropertyNames[I]). nil si se construye de otra forma: no se
  adivina. Con 'TCustomScrollBox *' el lint aceptaba CUALQUIER propiedad en
  39 clases FMX (TListBox, TTreeView...; revision de la 1.12.0). }
function NombresDelArgumento(const ATexto: string; AP: Integer;
  const ACuerpo: string): TArray<string>;
var
  I, Prof, Ini: Integer;
  Expr, Nombre: string;
  Terminos: TArray<string>;
  EnCadena: Boolean;
  Mt: TMatch;
begin
  Result := nil;
  // la expresion hasta la coma (o el parentesis que cierra) de su nivel, y
  // sus sumandos, sin mirar dentro de las cadenas
  I := AP;
  Ini := AP;
  Prof := 0;
  EnCadena := False;
  Terminos := nil;
  while I <= Length(ATexto) do
  begin
    if ATexto[I] = '''' then
      EnCadena := not EnCadena
    else if not EnCadena then
    begin
      if CharInSet(ATexto[I], ['(', '[']) then
        Inc(Prof)
      else if CharInSet(ATexto[I], [')', ']']) then
      begin
        if Prof = 0 then
          Break;
        Dec(Prof);
      end
      else if (ATexto[I] = ',') and (Prof = 0) then
        Break
      else if (ATexto[I] = '+') and (Prof = 0) then
      begin
        Terminos := Terminos + [Copy(ATexto, Ini, I - Ini).Trim];
        Ini := I + 1;
      end;
    end;
    Inc(I);
  end;
  Terminos := Terminos + [Copy(ATexto, Ini, I - Ini).Trim];
  Expr := Copy(ATexto, AP, I - AP).Trim;
  // una constante lista de cadenas con su indice
  Mt := TRegEx.Match(Expr, '^(' + PATRON_IDENT + ')\s*\[[^\]]*\]$');
  if Mt.Success then
  begin
    Mt := TRegEx.Match(ACuerpo, '(?is)' + PatronIdentEntero(Mt.Groups[1].Value) +
      '\s*:\s*array\b[^=;]*?\bof\s+string\s*=\s*[\[(](.*?)[\])]\s*;');
    if Mt.Success then
      for var L in TRegEx.Matches(Mt.Groups[1].Value, '''((?:[^'']|'''')*)''') do
        Result := Result + [L.Groups[1].Value.Replace('''''', '''')];
    Exit;
  end;
  // una suma de literales y constantes de cadena (const X = '...' o
  // X: string = '...'; una asignacion X := no es una constante)
  Nombre := '';
  for var T in Terminos do
  begin
    Mt := TRegEx.Match(T, '^''((?:[^'']|'''')*)''$');
    if not Mt.Success and EsIdentificador(T) then
      Mt := TRegEx.Match(ACuerpo, '(?i)' + PatronIdentEntero(T) +
        '\s*(?::\s*string\s*)?=\s*''((?:[^'']|'''')*)''\s*;');
    if not Mt.Success then
      Exit(nil);
    Nombre := Nombre + Mt.Groups[1].Value.Replace('''''', '''');
  end;
  if Nombre <> '' then
    Result := [Nombre];
end;

function PropiedadesDefinidasPorCodigo(const ATexto: string): TArray<string>;
var
  Lista: TList<string>;
  Fin: TRegEx;
  Sig: TMatch;
  Clase, Cuerpo, E: string;
  Ini, Hasta, P: Integer;
  Cuerpos: TList<TPair<Integer, Integer>>; // los de los DefineProperties
  Dentro: Boolean;
  Cabeceras: TMatchCollection;
  Nombres: TArray<string>;
begin
  Lista := TList<string>.Create;
  Cuerpos := TList<TPair<Integer, Integer>>.Create;
  try
    // el cuerpo de un metodo acaba en la siguiente rutina de la COLUMNA 0: las
    // locales van sangradas (TCustomForm.DefineProperties tiene la suya)
    Fin := TRegEx.Create('(?im)^(?:(?:class\s+)?' + PatronPalabraDeRutina +
      '\s|initialization\b|finalization\b|end\.)');
    for var Mt in TRegEx.Matches(ATexto,
      '(?im)^\s*(?:class\s+)?procedure\s+(' + PATRON_IDENT_PUNTOS + ')\.DefineProperties\s*\(') do
    begin
      Clase := Mt.Groups[1].Value;
      Ini := Mt.Index + Mt.Length;
      Sig := Fin.Match(ATexto, Ini);
      if Sig.Success then
        Hasta := Sig.Index
      else
        Hasta := Length(ATexto) + 1;
      Cuerpo := Copy(ATexto, Ini, Hasta - Ini);
      Cuerpos.Add(TPair<Integer, Integer>.Create(Ini, Hasta));
      for var C in TRegEx.Matches(Cuerpo, '(?i)' + PATRON_NO_IDENT_ANTES + 'Define(?:Binary)?Property\s*\(\s*') do
      begin
        Nombres := NombresDelArgumento(Cuerpo, C.Index + C.Length, Cuerpo);
        if Length(Nombres) = 0 then
          Nombres := ['*']; // un nombre que se construye al vuelo
        for var N in Nombres do
        begin
          E := Clase + ' ' + N;
          if not Lista.Contains(E) then
            Lista.Add(E);
        end;
      end;
      // los tipos que nombra: un ayudante que lee por ella (FMX:
      // TTextControl.DefineProperties crea un TTextSettingsInfo.TTextPropLoader)
      // (T y una MAYUSCULA, como se nombra un tipo: con T[A-Za-z_] entraban
      // True o TextHeight como si fueran tipos; ruido, revision de la 1.12.0).
      // La mayuscula y lo de detras, de cualquier alfabeto (EL identificador,
      // Lsp.Pascal)
      for var C in TRegEx.Matches(Cuerpo, PATRON_NO_IDENT_ANTES + PATRON_NOMBRE_TIPO + PATRON_CAR_IDENT +
        '*(?:\.' + PATRON_NOMBRE_TIPO + PATRON_CAR_IDENT + '*)*' + PATRON_NO_IDENT_DESPUES) do
      begin
        E := '>' + Clase + ' ' + C.Value;
        if not Lista.Contains(E) then
          Lista.Add(E);
      end;
    end;
    // los nombres FUERA de esos cuerpos: los lee un AYUDANTE, en un metodo de
    // su clase ('~Ayudante Nombre'); a que clases sirve lo dice quien lo
    // nombra en su DefineProperties (Lsp.DesignerMetaGen, ResuelveAyudantes).
    // En una rutina suelta, de alguna clase ('* Nombre'): antes no contaba
    // como cabecera y sus literales iban a la clase del metodo de antes
    // (Data.Bind.Components ReadBufferProperties; revision)
    Cabeceras := TRegEx.Matches(ATexto,
      '(?im)^(?:class\s+)?' + PatronPalabraDeRutina + '\s+(' + PATRON_IDENT_PUNTOS + ')');
    for var C in TRegEx.Matches(ATexto, '(?i)' + PATRON_NO_IDENT_ANTES + 'Define(?:Binary)?Property\s*\(\s*') do
    begin
      P := C.Index + C.Length;
      Dentro := False;
      for var Cu in Cuerpos do
        if (P >= Cu.Key) and (P < Cu.Value) then
          Dentro := True;
      if Dentro then
        Continue;
      Clase := '';
      for var H in Cabeceras do
        if H.Index < P then
          Clase := H.Groups[1].Value;
      if Clase.Contains('.') then
        Clase := Clase.Substring(0, Clase.LastIndexOf('.'))
      else
        Clase := '';
      Nombres := NombresDelArgumento(ATexto, P, ATexto);
      if Length(Nombres) = 0 then
      begin
        // uno que no se lee vale solo para las clases que nombran al
        // ayudante ('~Ayudante *'); en una rutina suelta, para nadie
        if Clase = '' then
          Continue;
        Nombres := ['*'];
      end;
      for var N in Nombres do
      begin
        if Clase <> '' then
          E := '~' + Clase + ' ' + N
        else
          E := '* ' + N;
        if not Lista.Contains(E) then
          Lista.Add(E);
      end;
    end;
    Result := Lista.ToArray;
  finally
    Cuerpos.Free;
    Lista.Free;
  end;
end;

{ ---- el generador ---- }

type
  TInfoTipo = record
    Kind: Char;               // c e s m o ?: como lo daba la RTTI
    Nombre: string;           // el nombre de su informacion de tipo
    Miembros: TArray<string>; // enumerado o conjunto
    Unidad: string;           // donde se declara ('' = del compilador): IdDeTipo
  end;

  TUnidadLeida = class
  public
    Clave: string;      // el nombre de la unidad en minusculas
    Ruta: string;
    Prioridad: Integer; // 0 = de la instalacion, 1 = de terceros
    Orden: Integer;     // el de su carpeta en la lista
    Decl: TUnidadPas;
    UsesI, UsesImpl: TArray<string>; // claves de las unidades resueltas
    TiposI, TiposImpl, Anidados: TDictionary<string, TTipoPas>;
    MarcosEstado: Integer; // 0 sin mirar, 1 mirandose (un ciclo), 2 hecho
    Marcos: TMarcosDisenador;
    Definidas: TArray<string>; // PropiedadesDefinidasPorCodigo: 'TClase Nombre'
    Registra: TArray<string>;  // RegistradosEnPaleta: los nombres, sin resolver
    constructor Create;
    destructor Destroy; override;
  end;

  TCandidata = record
    Ruta: string;
    Orden: Integer;
  end;

  TGenerador = class
  private
    FBase: TSimbolosPascal;
    FPlataforma: string;
    FRaizBds: string;
    FCarpetas: TArray<string>;
    FCandidatas: TList<TCandidata>;
    FFicheros: TDictionary<string, string>;  // nombre de fichero (minusculas) -> ruta
    FTextos: TDictionary<string, string>;    // includes ya leidos, por ruta
    FUnidades: TObjectDictionary<string, TUnidadLeida>;
    FDueno: TDictionary<TTipoPas, TUnidadLeida>;
    FCadenas: TDictionary<TTipoPas, TArray<TTipoPas>>;
    FMiembro: TDictionary<string, TTipoPas>; // miembro de enumerado -> el enumerado
    FResueltas: TDictionary<string, string>; // ResuelveUnidad
    FIncluidos: TDictionary<string, string>; // TextoDeInclude: carpeta|nombre -> texto
    FEnCarpetas: TDictionary<string, string>; // include con subcarpeta -> su ruta
    FRegistradas: TDictionary<TTipoPas, Boolean>; // en la paleta (RegisterComponents)
    procedure Indexa(const ACarpetas: TArray<string>);
    function TextoDeInclude(const ANombre, ADir: string): string;
    function LeeFuente(const ARuta: string): string;
    procedure LeeConstantesDeSystem;
    procedure LeeUnidades;
    procedure Prepara;
    function ResuelveUnidad(const ANombre: string): string;
    function ResuelveUnidadSinCache(const L: string): string;
    function ContenedorDe(ATipo: TTipoPas): TTipoPas;
    function AnidadoEn(AClase: TTipoPas; const ANombre: string;
      out ADonde: TUnidadLeida): TTipoPas;
    function ResuelveTipo(const ANombre: string; AUnidad: TUnidadLeida;
      AContexto: TTipoPas; AEnImpl: Boolean; out ADonde: TUnidadLeida): TTipoPas;
    function Cadena(AClase: TTipoPas): TArray<TTipoPas>;
    function EsPersistente(const ACadena: TArray<TTipoPas>): Boolean;
    function Clasifica(const ATexto: string; AUnidad: TUnidadLeida;
      AContexto: TTipoPas; AEnImpl: Boolean; AProf: Integer = 0): TInfoTipo;
    function MiembrosDeBase(ATipo: TTipoPas; AUnidad: TUnidadLeida;
      AProf: Integer): TArray<string>;
    function MarcosDe(AUnidad: TUnidadLeida): TMarcosDisenador;
    function IdDeClase(ATipo: TTipoPas): string;
    function EsRaiz(const ACadena: TArray<TTipoPas>): Boolean;
    procedure ResuelveRegistradas;
    procedure ResuelveAyudantes;
    function HechosDeClase(ATipo: TTipoPas; const ACadena: TArray<TTipoPas>;
      AEnums, ASets: TDictionary<string, TArray<string>>): TArray<string>;
  public
    constructor Create(const AVersionCompilador, ARaizBds, APlataforma: string);
    destructor Destroy; override;
    function Genera(const ACarpetas: TArray<string>): TTablasDeFuente;
  end;

{ TUnidadLeida }

constructor TUnidadLeida.Create;
begin
  inherited Create;
  TiposI := TDictionary<string, TTipoPas>.Create;
  TiposImpl := TDictionary<string, TTipoPas>.Create;
  Anidados := TDictionary<string, TTipoPas>.Create;
end;

destructor TUnidadLeida.Destroy;
begin
  Anidados.Free;
  TiposImpl.Free;
  TiposI.Free;
  Decl.Free;
  inherited;
end;

{ TGenerador }

constructor TGenerador.Create(const AVersionCompilador, ARaizBds, APlataforma: string);
begin
  inherited Create;
  FPlataforma := APlataforma;
  FBase := SimbolosDeDelphi(AVersionCompilador, APlataforma);
  FRaizBds := IncludeTrailingPathDelimiter(ARaizBds);
  FCandidatas := TList<TCandidata>.Create;
  FFicheros := TDictionary<string, string>.Create;
  FTextos := TDictionary<string, string>.Create;
  FUnidades := TObjectDictionary<string, TUnidadLeida>.Create([doOwnsValues]);
  FDueno := TDictionary<TTipoPas, TUnidadLeida>.Create;
  FCadenas := TDictionary<TTipoPas, TArray<TTipoPas>>.Create;
  FMiembro := TDictionary<string, TTipoPas>.Create;
  FResueltas := TDictionary<string, string>.Create;
  FIncluidos := TDictionary<string, string>.Create;
  FEnCarpetas := TDictionary<string, string>.Create;
  FRegistradas := TDictionary<TTipoPas, Boolean>.Create;
end;

destructor TGenerador.Destroy;
begin
  FRegistradas.Free;
  FEnCarpetas.Free;
  FIncluidos.Free;
  FResueltas.Free;
  FMiembro.Free;
  FCadenas.Free;
  FDueno.Free;
  FUnidades.Free;
  FTextos.Free;
  FFicheros.Free;
  FCandidatas.Free;
  FBase.Free;
  inherited;
end;

procedure TGenerador.Indexa(const ACarpetas: TArray<string>);
var
  Ficheros: TArray<string>;
  N: string;
  C: TCandidata;
begin
  FCarpetas := ACarpetas;
  for var I := 0 to High(ACarpetas) do
  begin
    try
      Ficheros := TDirectory.GetFiles(ACarpetas[I]);
    except
      Continue; // una carpeta ilegible no para las demas
    end;
    for var F in Ficheros do
    begin
      N := AnsiLowerCase(ExtractFileName(F));
      if FFicheros.ContainsKey(N) then
        Continue; // la misma unidad (o include) en otra carpeta: gana la primera
      FFicheros.Add(N, F);
      if SameText(ExtractFileExt(F), '.pas') then
      begin
        C.Ruta := F;
        C.Orden := I;
        FCandidatas.Add(C);
      end;
    end;
  end;
end;

function TGenerador.LeeFuente(const ARuta: string): string;
var
  Enc: string;
begin
  try
    Result := PatchLoadText(ARuta, Enc);
  except
    Result := ''; // un fichero que no se deja leer es como si no estuviera
  end;
end;

{ El texto de un $I: junto a la unidad que lo pide, y si no, en cualquiera
  de las carpetas (con '.inc' detras si no lleva extension). Leido una vez:
  jvcl.inc lo piden 646 unidades. }
function TGenerador.TextoDeInclude(const ANombre, ADir: string): string;
var
  Candidatos: TArray<string>;
  Ruta, Clave: string;
begin
  Result := '';
  // lo ya buscado desde esa carpeta: jedi\jedi.inc lo piden cientos de
  // unidades, y cada busqueda son decenas de FileExists
  Clave := AnsiLowerCase(ADir) + '|' + AnsiLowerCase(ANombre);
  if FIncluidos.TryGetValue(Clave, Result) then
    Exit;
  try
    if TPath.IsPathRooted(ANombre) then
      Candidatos := [ANombre, ANombre + '.inc']
    else
    begin
      Candidatos := [TPath.Combine(ADir, ANombre), TPath.Combine(ADir, ANombre + '.inc')];
      // con subcarpeta ({$I jedi\jedi.inc}, el de JVCL), tambien desde cada
      // carpeta, como el compilador: sin el, jvcl.inc dejaba unidades enteras
      // en blanco (TJvZlibMultiple; revision de la 1.12.0). Esa busqueda no
      // depende de quien la pide: una vez por nombre
      if ExtractFilePath(ANombre) <> '' then
      begin
        if not FEnCarpetas.TryGetValue(AnsiLowerCase(ANombre), Ruta) then
        begin
          Ruta := '';
          for var C in FCarpetas do
            for var X in [TPath.Combine(C, ANombre), TPath.Combine(C, ANombre + '.inc')] do
              if (Ruta = '') and FileExists(X) then
                Ruta := X;
          FEnCarpetas.Add(AnsiLowerCase(ANombre), Ruta);
        end;
        if Ruta <> '' then
          Candidatos := Candidatos + [Ruta];
      end;
    end;
    if FFicheros.TryGetValue(AnsiLowerCase(ExtractFileName(ANombre)), Ruta) then
      Candidatos := Candidatos + [Ruta];
    if FFicheros.TryGetValue(AnsiLowerCase(ExtractFileName(ANombre)) + '.inc', Ruta) then
      Candidatos := Candidatos + [Ruta];
    for var C in Candidatos do
    begin
      if FTextos.TryGetValue(AnsiLowerCase(C), Result) then
        Break;
      if FileExists(C) then
      begin
        Result := LeeFuente(C);
        FTextos.Add(AnsiLowerCase(C), Result);
        Break;
      end;
    end;
  except
    Result := ''; // un nombre imposible ("<>|...): como si no estuviera
  end;
  FIncluidos.AddOrSetValue(Clave, Result);
end;

{ Las constantes simples del interface de System (RTLVersion131 = True...):
  lo que pregunta Declared() en un IF. CompilerVersion no: en el fuente vale
  0.0 y la pone el compilador. }
procedure TGenerador.LeeConstantesDeSystem;
var
  Ruta, Act: string;
  Sim: TSimbolosPascal;
  U: TUnidadPas;
  V: Double;
begin
  if not FFicheros.TryGetValue('system.pas', Ruta) then
    Exit;
  Sim := FBase.Copia;
  try
    Act := TextoActivo(LeeFuente(Ruta), Sim,
      function(const N: string): string
      begin
        Result := TextoDeInclude(N, ExtractFilePath(Ruta));
      end);
  finally
    Sim.Free;
  end;
  U := LeeUnidadPascal(Act);
  try
    for var C in U.Constantes do
    begin
      if SameText(C.Key, 'CompilerVersion') then
        Continue;
      if SameText(C.Value, 'True') then
        FBase.PonConstante(C.Key, 1)
      else if SameText(C.Value, 'False') then
        FBase.PonConstante(C.Key, 0)
      else if TryStrToFloat(C.Value, V, TFormatSettings.Invariant) then
        FBase.PonConstante(C.Key, V);
    end;
  finally
    U.Free;
  end;
end;

procedure TGenerador.LeeUnidades;
var
  Txt, Act, Dir: string;
  Sim: TSimbolosPascal;
  Decl: TUnidadPas;
  U: TUnidadLeida;
begin
  for var C in FCandidatas do
  begin
    if GCerrando then
      Abort;
    Txt := LeeFuente(C.Ruta);
    if Txt = '' then
      Continue;
    Dir := ExtractFilePath(C.Ruta);
    Sim := FBase.Copia; // cada unidad empieza con los simbolos del proyecto
    try
      try
        Act := TextoActivo(Txt, Sim,
          function(const N: string): string
          begin
            Result := TextoDeInclude(N, Dir);
          end);
      except
        // un include con un nombre imposible, una expresion rara: esa unidad
        // no, pero la tabla si (revision de la 1.12.0: tumbaba la generacion)
        Continue;
      end;
    finally
      Sim.Free;
    end;
    try
      Decl := LeeUnidadPascal(Act);
    except
      Continue; // lo que no se sabe leer no tumba la tabla
    end;
    if (Decl.Nombre = '') or FUnidades.ContainsKey(ClaveDeIdentificador(Decl.Nombre)) then
    begin
      Decl.Free;
      Continue;
    end;
    U := TUnidadLeida.Create;
    U.Clave := ClaveDeIdentificador(Decl.Nombre);
    U.Ruta := C.Ruta;
    U.Orden := C.Orden;
    if StartsText(FRaizBds, C.Ruta) then
      U.Prioridad := 0
    else
      U.Prioridad := 1;
    U.Decl := Decl;
    FUnidades.Add(U.Clave, U);
    // lo que guarda por codigo (Filer.DefineProperty): otra pasada que deja
    // las cadenas, solo en las que lo nombran (unas cien de 4.000)
    if ContainsText(Txt, 'DefineProperty') or ContainsText(Txt, 'DefineBinaryProperty') or
       ContainsText(Txt, 'RegisterComponents') or ContainsText(Txt, 'RegisterNoIcon') then
    begin
      Sim := FBase.Copia;
      try
        try
          var ConCadenas := TextoActivo(Txt, Sim,
            function(const N: string): string
            begin
              Result := TextoDeInclude(N, Dir);
            end, True);
          U.Definidas := PropiedadesDefinidasPorCodigo(ConCadenas);
          // y lo que registra en la paleta (quien se queda un nombre)
          U.Registra := RegistradosEnPaleta(ConCadenas);
        except
          U.Definidas := nil; // lo que no se sabe leer no tumba la tabla
          U.Registra := nil;
        end;
      finally
        Sim.Free;
      end;
    end;
  end;
end;

{ El nombre de unidad de un uses, resuelto contra las que se leyeron: el
  exacto; si no, con los prefijos del compilador (DEFAULT_NAMESPACES:
  'Classes' es System.Classes); si no, la unica que acaba en '.Nombre', y
  entre varias la de Vcl (un nombre sin prefijo es de antes de FMX). '' si
  no esta. }
function TGenerador.ResuelveUnidad(const ANombre: string): string;
var
  L: string;
begin
  L := ClaveDeIdentificador(ANombre);
  if FUnidades.ContainsKey(L) then
    Exit(L);
  // lo ya resuelto (los nombres con punto la preguntan mucho, y abajo se
  // recorren todas las unidades)
  if FResueltas.TryGetValue(L, Result) then
    Exit;
  Result := ResuelveUnidadSinCache(L);
  FResueltas.Add(L, Result);
end;

function TGenerador.ResuelveUnidadSinCache(const L: string): string;
var
  Sufijo: string;
  Vistas: TList<string>;
begin
  for var NS in DEFAULT_NAMESPACES.Split([';']) do
    if FUnidades.ContainsKey(ClaveDeIdentificador(NS) + '.' + L) then
      Exit(ClaveDeIdentificador(NS) + '.' + L);
  Result := '';
  Sufijo := '.' + L;
  Vistas := TList<string>.Create;
  try
    for var K in FUnidades.Keys do
      if K.EndsWith(Sufijo) then
        Vistas.Add(K);
    if Vistas.Count = 0 then
      Exit;
    Vistas.Sort;
    Result := Vistas[0];
    for var K in Vistas do
      if K.StartsWith('vcl.') then
        Exit(K);
  finally
    Vistas.Free;
  end;
end;

procedure TGenerador.Prepara;
var
  K: string;

  { TFoo y TFoo<A, B> son dos tipos en la misma unidad: el generico va con
    su aridad ('tfoo`2'), y con el nombre solo si no lo tiene ya uno que no
    es generico (REST.Backend.BindSource: el generico desciende del que no
    lo es, y por el nombre se encontraba a si mismo; revision de la 1.12.0) }
  procedure Pon(ADic: TDictionary<string, TTipoPas>; const AClave: string; T: TTipoPas);
  var
    Otro: TTipoPas;
  begin
    if T.Aridad > 0 then
    begin
      ADic.AddOrSetValue(AClave + '`' + IntToStr(T.Aridad), T);
      if not ADic.TryGetValue(AClave, Otro) then
        ADic.Add(AClave, T);
    end
    else
      ADic.AddOrSetValue(AClave, T);
  end;

begin
  for var U in FUnidades.Values do
  begin
    for var T in U.Decl.Tipos do
    begin
      FDueno.AddOrSetValue(T, U);
      if T.Contenedor <> '' then
        Pon(U.Anidados, ClaveDeIdentificador(T.NombreCompleto), T)
      else if T.EnImplementation then
        Pon(U.TiposImpl, ClaveDeIdentificador(T.Nombre), T)
      else
        Pon(U.TiposI, ClaveDeIdentificador(T.Nombre), T);
    end;
    SetLength(U.UsesI, Length(U.Decl.UsesInterface));
    for var I := 0 to High(U.Decl.UsesInterface) do
      U.UsesI[I] := ResuelveUnidad(U.Decl.UsesInterface[I]);
    SetLength(U.UsesImpl, Length(U.Decl.UsesImplementation));
    for var I := 0 to High(U.Decl.UsesImplementation) do
      U.UsesImpl[I] := ResuelveUnidad(U.Decl.UsesImplementation[I]);
  end;
  // los miembros de los enumerados, para los subrangos de enumerado
  // (TBorderStyle = bsNone..bsSingle): primero los de la instalacion
  for var Pase := 0 to 1 do
    for var U in FUnidades.Values do
      if U.Prioridad = Pase then
        for var T in U.TiposI.Values do
          if T.Clase = ctEnumerado then
            for var M in T.Miembros do
            begin
              K := ClaveDeIdentificador(M);
              if not FMiembro.ContainsKey(K) then
                FMiembro.Add(K, T);
            end;
end;

function TGenerador.ContenedorDe(ATipo: TTipoPas): TTipoPas;
var
  U: TUnidadLeida;
begin
  Result := nil;
  if (ATipo = nil) or (ATipo.Contenedor = '') or not FDueno.TryGetValue(ATipo, U) then
    Exit;
  if ATipo.Contenedor.Contains('.') then
    U.Anidados.TryGetValue(ClaveDeIdentificador(ATipo.Contenedor), Result)
  else if not (ATipo.EnImplementation and
               U.TiposImpl.TryGetValue(ClaveDeIdentificador(ATipo.Contenedor), Result)) then
    U.TiposI.TryGetValue(ClaveDeIdentificador(ATipo.Contenedor), Result);
end;

// Un tipo anidado en AClase o en uno de sus ancestros
function TGenerador.AnidadoEn(AClase: TTipoPas; const ANombre: string;
  out ADonde: TUnidadLeida): TTipoPas;
var
  U: TUnidadLeida;
begin
  Result := nil;
  ADonde := nil;
  for var X in Cadena(AClase) do
    if FDueno.TryGetValue(X, U) and
       U.Anidados.TryGetValue(ClaveDeIdentificador(X.NombreCompleto + '.' + ANombre), Result) then
    begin
      ADonde := U;
      Exit;
    end;
end;

{ Que tipo es ANombre escrito en AUnidad: dentro de AContexto (la clase
  donde se escribe: sus anidados y los de sus ancestros, y los de las que
  la contienen), en el implementation de la unidad si la referencia esta
  alli (AEnImpl), en su interface, en sus uses del ultimo al primero (el
  ultimo gana, como en el compilador) y en System. Con puntos:
  Unidad.Tipo o Clase.Anidado. nil si no se encuentra. }
function TGenerador.ResuelveTipo(const ANombre: string; AUnidad: TUnidadLeida;
  AContexto: TTipoPas; AEnImpl: Boolean; out ADonde: TUnidadLeida): TTipoPas;
var
  L, Pre, Resto: string;
  K: Integer;
  C: TTipoPas;
  UX: TUnidadLeida;

  function EnUnidad(const AClave: string): Boolean;
  var
    UU: TUnidadLeida;
  begin
    Result := (AClave <> '') and FUnidades.TryGetValue(AClave, UU) and
      UU.TiposI.TryGetValue(L, C);
    if Result then
      ADonde := UU;
  end;

begin
  Result := nil;
  ADonde := nil;
  if (ANombre = '') or (AUnidad = nil) then
    Exit;
  L := ClaveDeIdentificador(ANombre);
  if L.Contains('.') then
  begin
    // Unidad.Tipo (o Unidad.Clase.Anidado): el prefijo mas largo que es una unidad
    K := L.LastIndexOf('.');
    while K > 0 do
    begin
      Pre := L.Substring(0, K);
      Resto := L.Substring(K + 1);
      // la unidad, tambien sin su namespace (StdCtrls.TEdit es
      // Vcl.StdCtrls.TEdit), como en un uses
      if not FUnidades.ContainsKey(Pre) and (ResuelveUnidad(Pre) <> '') then
        Pre := ResuelveUnidad(Pre);
      if FUnidades.TryGetValue(Pre, UX) then
      begin
        if (not Resto.Contains('.') and UX.TiposI.TryGetValue(Resto, Result)) or
           UX.Anidados.TryGetValue(Resto, Result) then
        begin
          ADonde := UX;
          Exit;
        end;
      end;
      K := L.LastIndexOf('.', K - 1);
    end;
    // Clase.Anidado (o Record.Anidado): la clase en este alcance, y el
    // anidado en ella
    K := L.IndexOf('.');
    C := ResuelveTipo(ANombre.Substring(0, K), AUnidad, AContexto, AEnImpl, UX);
    if (C <> nil) and ((C.Clase = ctClase) or (C.Clase = ctRegistro)) then
      Result := AnidadoEn(C, L.Substring(K + 1), ADonde);
    Exit;
  end;
  // los anidados PROPIOS de la clase donde se escribe y de las que la
  // contienen...
  C := AContexto;
  while C <> nil do
  begin
    if FDueno.TryGetValue(C, UX) and
       UX.Anidados.TryGetValue(ClaveDeIdentificador(C.NombreCompleto) + '.' + L, Result) then
    begin
      ADonde := UX;
      Exit;
    end;
    C := ContenedorDe(C);
  end;
  // ...despues los tipos de la unidad, y solo despues los anidados de los
  // ancestros: TBitBtn.Style es el TButtonStyle de Vcl.Buttons y no el
  // TCustomButton.TButtonStyle (publico) que hereda - lo dice la RTTI
  if AEnImpl and AUnidad.TiposImpl.TryGetValue(L, Result) then
  begin
    ADonde := AUnidad;
    Exit;
  end;
  if AUnidad.TiposI.TryGetValue(L, Result) then
  begin
    ADonde := AUnidad;
    Exit;
  end;
  C := AContexto;
  while C <> nil do
  begin
    Result := AnidadoEn(C, L, ADonde);
    if Result <> nil then
      Exit;
    C := ContenedorDe(C);
  end;
  if AEnImpl then
    for var I := High(AUnidad.UsesImpl) downto 0 do
      if EnUnidad(AUnidad.UsesImpl[I]) then
        Exit(C);
  for var I := High(AUnidad.UsesI) downto 0 do
    if EnUnidad(AUnidad.UsesI[I]) then
      Exit(C);
  if (AUnidad.Clave <> 'system') and EnUnidad('system') then
    Exit(C);
  Result := nil;
end;

{ La clase y sus ancestros, del hijo al ultimo que se encuentra. Una
  marca mientras se calcula: un ciclo (o un anidado que se mira a si mismo
  desde su ancestro) no cuelga. }
function TGenerador.Cadena(AClase: TTipoPas): TArray<TTipoPas>;
var
  Lista: TList<TTipoPas>;
  X, A: TTipoPas;
  UX, UA: TUnidadLeida;
begin
  if FCadenas.TryGetValue(AClase, Result) then
    Exit;
  FCadenas.Add(AClase, [AClase]);
  Lista := TList<TTipoPas>.Create;
  try
    Lista.Add(AClase);
    X := AClase;
    while (X.Ancestro <> '') and (Lista.Count < 64) and FDueno.TryGetValue(X, UX) do
    begin
      // un ancestro generico, por su aridad (TFoo<A, B> no es TFoo)
      A := nil;
      if X.AncestroAridad > 0 then
        A := ResuelveTipo(X.Ancestro + '`' + IntToStr(X.AncestroAridad), UX,
          ContenedorDe(X), X.EnImplementation, UA);
      if A = nil then
        A := ResuelveTipo(X.Ancestro, UX, ContenedorDe(X), X.EnImplementation, UA);
      // un ancestro que es un ALIAS de clase es su destino (JVCL:
      // TJvGraphicControl = TJvExGraphicControl; con el alias la cadena se
      // cortaba y faltaban 232 clases: revision de la 1.12.0)
      var Saltos := 0;
      var UB: TUnidadLeida;
      while (A <> nil) and (A.Clase = ctAlias) and (Saltos < 8) and
            FDueno.TryGetValue(A, UB) do
      begin
        // el que se llama como su destino se busca fuera (como en Clasifica)
        if MismoIdentificador(UltimoTrozo(A.Base), A.Nombre) then
          A := ResuelveTipo(A.Base, UB, nil, A.EnImplementation, UA)
        else
          A := ResuelveTipo(A.Base, UB, ContenedorDe(A), A.EnImplementation, UA);
        Inc(Saltos);
      end;
      if (A = nil) or (A.Clase <> ctClase) or Lista.Contains(A) then
        Break;
      Lista.Add(A);
      X := A;
    end;
    Result := Lista.ToArray;
    FCadenas[AClase] := Result;
  finally
    Lista.Free;
  end;
end;

// Desciende de System.Classes.TPersistent: puede ir en un form, y su
// visibilidad por defecto es published ($M+)
function TGenerador.EsPersistente(const ACadena: TArray<TTipoPas>): Boolean;
var
  U: TUnidadLeida;
begin
  for var X in ACadena do
    if SameText(X.Nombre, 'TPersistent') and FDueno.TryGetValue(X, U) and
       (U.Clave = 'system.classes') then
      Exit(True);
  Result := False;
end;

function Info(AKind: Char; const ANombre: string;
  const AMiembros: TArray<string> = nil): TInfoTipo;
begin
  Result.Kind := AKind;
  Result.Nombre := ANombre;
  Result.Miembros := AMiembros;
  Result.Unidad := '';
end;

{ Los tipos que pone el compilador (no estan declarados en System.pas) con
  el nombre que les da su informacion de tipo en APlataforma: un alias
  debil toma el de su destino (LongInt es Integer; NativeInt, Int64 en Win64
  e Integer en Win32). }
function Intrinseco(const L, APlataforma: string; out AInfo: TInfoTipo): Boolean;
begin
  Result := True;
  if (L = 'string') or (L = 'unicodestring') then
    AInfo := Info('o', 'string')
  else if L = 'ansistring' then
    AInfo := Info('o', 'AnsiString')
  else if L = 'widestring' then
    AInfo := Info('o', 'WideString')
  else if L = 'shortstring' then
    AInfo := Info('o', 'ShortString')
  else if (L = 'char') or (L = 'widechar') then
    AInfo := Info('o', 'Char')
  else if L = 'ansichar' then
    AInfo := Info('o', 'AnsiChar')
  else if (L = 'integer') or (L = 'longint') then
    AInfo := Info('o', 'Integer')
  else if (L = 'cardinal') or (L = 'longword') then
    AInfo := Info('o', 'Cardinal')
  else if L = 'shortint' then
    AInfo := Info('o', 'ShortInt')
  else if L = 'smallint' then
    AInfo := Info('o', 'SmallInt')
  else if L = 'byte' then
    AInfo := Info('o', 'Byte')
  else if L = 'word' then
    AInfo := Info('o', 'Word')
  else if (L = 'nativeint') and not SameText(APlataforma, 'Win64') then
    AInfo := Info('o', 'Integer')
  else if (L = 'nativeuint') and not SameText(APlataforma, 'Win64') then
    AInfo := Info('o', 'Cardinal')
  else if (L = 'int64') or (L = 'nativeint') then
    AInfo := Info('o', 'Int64')
  else if (L = 'uint64') or (L = 'nativeuint') then
    AInfo := Info('o', 'UInt64')
  else if L = 'single' then
    AInfo := Info('o', 'Single')
  else if (L = 'double') or (L = 'real') then
    AInfo := Info('o', 'Double')
  else if L = 'extended' then
    AInfo := Info('o', 'Extended')
  else if L = 'currency' then
    AInfo := Info('o', 'Currency')
  else if L = 'comp' then
    AInfo := Info('o', 'Comp')
  else if L = 'variant' then
    AInfo := Info('o', 'Variant')
  else if L = 'olevariant' then
    AInfo := Info('o', 'OleVariant')
  else if L = 'pointer' then
    AInfo := Info('o', 'Pointer')
  else if L = 'boolean' then
    AInfo := Info('e', 'Boolean', ['False', 'True'])
  // los booleanos de otro tamano son enumerados para la RTTI, como Boolean
  else if L = 'bytebool' then
    AInfo := Info('e', 'ByteBool', ['False', 'True'])
  else if L = 'wordbool' then
    AInfo := Info('e', 'WordBool', ['False', 'True'])
  else if L = 'longbool' then
    AInfo := Info('e', 'LongBool', ['False', 'True'])
  else
    Result := False;
end;

{ Los miembros del enumerado de la base de un conjunto (o de un subrango
  de enumerado): los de su enumerado en linea, los de su base resuelta, o
  los que van de un miembro a otro. }
function TGenerador.MiembrosDeBase(ATipo: TTipoPas; AUnidad: TUnidadLeida;
  AProf: Integer): TArray<string>;
var
  Bajo, Alto: string;
  E: TTipoPas;
  I, J: Integer;
begin
  Result := nil;
  if Length(ATipo.Miembros) > 0 then
    Exit(ATipo.Miembros);
  if ATipo.Base.Contains('..') then
  begin
    Bajo := Trim(ATipo.Base.Substring(0, ATipo.Base.IndexOf('..')));
    Alto := Trim(ATipo.Base.Substring(ATipo.Base.IndexOf('..') + 2));
  end
  else if ATipo.Clase = ctSubrango then
  begin
    Bajo := Trim(ATipo.Base);
    Alto := Trim(ATipo.Alto);
  end
  else
  begin
    Result := Clasifica(ATipo.Base, AUnidad, ContenedorDe(ATipo),
      ATipo.EnImplementation, AProf + 1).Miembros;
    Exit;
  end;
  if not FMiembro.TryGetValue(ClaveDeIdentificador(UltimoTrozo(Bajo)), E) then
    Exit;
  I := -1;
  J := -1;
  for var K := 0 to High(E.Miembros) do
  begin
    if MismoIdentificador(E.Miembros[K], UltimoTrozo(Bajo)) then
      I := K;
    if MismoIdentificador(E.Miembros[K], UltimoTrozo(Alto)) then
      J := K;
  end;
  if (I >= 0) and (J >= I) then
    Result := Copy(E.Miembros, I, J - I + 1);
end;

{ Que es un tipo escrito como ATexto, como lo diria su informacion de
  tipo: la clase de tipo (c clase, e enumerado, s conjunto, m metodo, o
  lo demas) y su nombre. Un alias debil es su destino; uno fuerte ('type
  X') conserva su nombre. Lo que no se encuentra se queda con su nombre y
  'o'. }
function TGenerador.Clasifica(const ATexto: string; AUnidad: TUnidadLeida;
  AContexto: TTipoPas; AEnImpl: Boolean; AProf: Integer): TInfoTipo;
var
  T: TTipoPas;
  UT: TUnidadLeida;
  Destino: TInfoTipo;
begin
  if (ATexto = '') or (AProf > 16) then
    Exit(Info('?', '?'));
  if not ATexto.Contains('.') and Intrinseco(ClaveDeIdentificador(ATexto), FPlataforma, Result) then
    Exit;
  T := ResuelveTipo(ATexto, AUnidad, AContexto, AEnImpl, UT);
  if T = nil then
  begin
    if Intrinseco(ClaveDeIdentificador(UltimoTrozo(ATexto)), FPlataforma, Result) then
      Exit;
    // un tipo que el fuente no deja leer (su unidad no esta en las rutas: el
    // TUniConnection de UniDAC) es '?', no 'o': con 'o' el lint decia que no
    // tiene subpropiedades, y lo que no se sabe se calla (revision)
    Exit(Info('?', UltimoTrozo(ATexto)));
  end;
  // el nombre de la informacion de tipo de un anidado lleva su clase
  // (TCustomButton.TButtonStyle): medido en las tablas de la RTTI
  case T.Clase of
    ctClase:
      Result := Info('c', T.NombreCompleto);
    ctEnumerado:
      Result := Info('e', T.NombreCompleto, T.Miembros);
    ctConjunto:
      Result := Info('s', T.NombreCompleto, MiembrosDeBase(T, UT, AProf));
    ctSubrango:
      begin
        Result := Info('o', T.NombreCompleto);
        Result.Miembros := MiembrosDeBase(T, UT, AProf);
        if Length(Result.Miembros) > 0 then
          Result.Kind := 'e';
      end;
    ctAlias:
      begin
        // un anidado que se llama como su destino (TTouchInterceptingLayout.
        // TOverlayMode = TOverlayMode, el global): el destino se busca fuera
        // de la clase, o se encontraria a si mismo
        if MismoIdentificador(UltimoTrozo(T.Base), T.Nombre) then
          Destino := Clasifica(T.Base, UT, nil, T.EnImplementation, AProf + 1)
        else
          Destino := Clasifica(T.Base, UT, ContenedorDe(T), T.EnImplementation, AProf + 1);
        if T.Fuerte then
        begin
          // un tipo nuevo con lo del destino: su clase y sus miembros, su nombre
          Result := Destino;
          Result.Nombre := T.NombreCompleto;
          if Result.Kind = '?' then
            Result.Kind := 'o';
        end
        else
          Result := Destino;
      end;
    ctMetodo:
      Result := Info('m', T.NombreCompleto);
  else
    Result := Info('o', T.NombreCompleto);
  end;
  // la unidad de su identidad (IdDeTipo); un alias debil es su destino, con
  // la suya
  if ((T.Clase <> ctAlias) or T.Fuerte) and (UT <> nil) and (UT.Decl <> nil) then
    Result.Unidad := UT.Decl.Nombre;
end;

// Una raiz: un form, un frame o un modulo de datos (nunca va anidada en un form)
function TGenerador.EsRaiz(const ACadena: TArray<TTipoPas>): Boolean;
var
  U: TUnidadLeida;
begin
  for var X in ACadena do
    if MatchText(X.Nombre, ['TCustomForm', 'TCommonCustomForm', 'TCustomFrame', 'TFrame',
         'TDataModule']) and FDueno.TryGetValue(X, U) and
       MatchText(U.Clave, ['vcl.forms', 'fmx.forms', 'system.classes']) then
      Exit(True);
  Result := False;
end;

// Las clases que alguna unidad registra en la paleta, resueltas con el
// alcance de esa unidad (su uses dice de cual de los homonimos es)
procedure TGenerador.ResuelveRegistradas;
var
  T: TTipoPas;
  UX: TUnidadLeida;
begin
  for var U in FUnidades.Values do
    for var N in U.Registra do
    begin
      T := ResuelveTipo(N, U, nil, True, UX);
      if (T <> nil) and (T.Clase = ctClase) then
        FRegistradas.AddOrSetValue(T, True);
    end;
end;

{ Lo que lee un AYUDANTE ('~Ayudante Nombre', PropiedadesDefinidasPorCodigo)
  es de las clases que lo nombran en su DefineProperties ('>Clase Tipo'),
  con lo de los ayudantes de los que hereda (FMX: TText usa un
  TTextPropLoaderEx que anade Color a lo del TTextPropLoader de
  TTextControl). Con 'D *' a secas, Color valia en cualquier control FMX, y
  es justo el VCL-ismo que el lint esta para cazar. Lo que no nombra nadie,
  de alguna clase de su marco ('* Nombre'). }
procedure TGenerador.ResuelveAyudantes;
var
  Nombres: TObjectDictionary<string, TList<string>>; // ayudante -> lo que lee
  Padres: TObjectDictionary<string, TList<string>>;  // ayudante -> sus ayudantes ancestros
  Usados: TDictionary<string, Boolean>;
  L, LA: TList<string>;
  K: string;

  function ClaveDe(const AClase: string): string;
  begin
    Result := ClaveDeIdentificador(UltimoTrozo(AClase));
  end;

  procedure Usa(const AClave: string);
  var
    P: TList<string>;
  begin
    Usados.AddOrSetValue(AClave, True);
    if Padres.TryGetValue(AClave, P) then
      for var X in P do
        Usados.AddOrSetValue(X, True);
  end;

begin
  Nombres := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  Padres := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
  Usados := TDictionary<string, Boolean>.Create;
  try
    for var U in FUnidades.Values do
      for var Def in U.Definidas do
        if Def.StartsWith('~') then
        begin
          K := ClaveDe(Def.Substring(1, Def.IndexOf(' ') - 1));
          if not Nombres.TryGetValue(K, L) then
          begin
            L := TList<string>.Create;
            Nombres.Add(K, L);
          end;
          if not L.Contains(Def.Substring(Def.IndexOf(' ') + 1)) then
            L.Add(Def.Substring(Def.IndexOf(' ') + 1));
        end;
    if Nombres.Count = 0 then
      Exit;
    // lo de los ayudantes de los que hereda cada uno
    for var U in FUnidades.Values do
      for var T in U.Decl.Tipos do
        if (T.Clase = ctClase) and Nombres.TryGetValue(ClaveDeIdentificador(T.Nombre), L) then
          for var A in Cadena(T) do
            if (A <> T) and Nombres.TryGetValue(ClaveDeIdentificador(A.Nombre), LA) and (LA <> L) then
            begin
              for var N in LA do
                if not L.Contains(N) then
                  L.Add(N);
              if not Padres.ContainsKey(ClaveDeIdentificador(T.Nombre)) then
                Padres.Add(ClaveDeIdentificador(T.Nombre), TList<string>.Create);
              Padres[ClaveDeIdentificador(T.Nombre)].Add(ClaveDeIdentificador(A.Nombre));
            end;
    // quien lo nombra en su DefineProperties se lo queda
    for var U in FUnidades.Values do
    begin
      var Nuevas: TArray<string> := nil;
      for var Def in U.Definidas do
        if Def.StartsWith('>') then
        begin
          K := ClaveDe(Def.Substring(Def.IndexOf(' ') + 1));
          if Nombres.TryGetValue(K, L) then
          begin
            Usa(K);
            for var N in L do
              Nuevas := Nuevas + [Def.Substring(1, Def.IndexOf(' ') - 1) + ' ' + N];
          end;
        end;
      U.Definidas := U.Definidas + Nuevas;
    end;
    // el que no nombra nadie: de alguna clase de su marco
    for var U in FUnidades.Values do
    begin
      var Nuevas: TArray<string> := nil;
      for var Def in U.Definidas do
        // ...menos un '*' (uno que no se lee): sin clase que lo nombre no vale
        // para nadie, o el lint lo aceptaria todo
        if Def.StartsWith('~') and (Def.Substring(Def.IndexOf(' ') + 1) <> '*') and
           not Usados.ContainsKey(ClaveDe(Def.Substring(1, Def.IndexOf(' ') - 1))) then
          Nuevas := Nuevas + ['* ' + Def.Substring(Def.IndexOf(' ') + 1)];
      U.Definidas := U.Definidas + Nuevas;
    end;
  finally
    Usados.Free;
    Padres.Free;
    Nombres.Free;
  end;
end;

// La identidad de una clase (IdDeTipo): con la unidad que la declara
function TGenerador.IdDeClase(ATipo: TTipoPas): string;
var
  U: TUnidadLeida;
begin
  if FDueno.TryGetValue(ATipo, U) then
    Result := IdDeTipo(U.Decl.Nombre, ATipo.NombreCompleto)
  else
    Result := ATipo.NombreCompleto;
end;

{ Que marco tiene una unidad: la de Vcl.* es VCL, la de FMX.* es FMX, y las
  demas lo heredan de lo que usan (su interface entera, y lo que nombra su
  implementation). Sin ninguno, de los dos (System.Classes, Data.DB...). }
function TGenerador.MarcosDe(AUnidad: TUnidadLeida): TMarcosDisenador;
var
  X: TUnidadLeida;
begin
  if AUnidad.MarcosEstado = 2 then
    Exit(AUnidad.Marcos);
  if AUnidad.MarcosEstado = 1 then
    Exit([]); // un ciclo de uses: lo de esta vuelta lo pone quien la empezo
  AUnidad.MarcosEstado := 1;
  Result := [];
  if StartsText('vcl.', AUnidad.Clave) then
    Result := [mdVcl]
  else if StartsText('fmx.', AUnidad.Clave) then
    Result := [mdFmx]
  else
  begin
    for var K in AUnidad.UsesI do
      if (K <> '') and FUnidades.TryGetValue(K, X) then
        Result := Result + MarcosDe(X);
    for var K in AUnidad.UsesImpl do
      if StartsText('vcl.', K) then
        Include(Result, mdVcl)
      else if StartsText('fmx.', K) then
        Include(Result, mdFmx);
  end;
  AUnidad.Marcos := Result;
  AUnidad.MarcosEstado := 2;
end;

type
  TRefTipo = record
    Tipo: string;
    Clase: TTipoPas;
  end;

{ Los hechos de una clase persistente: C, H y sus propiedades publicadas,
  heredadas incluidas, en el orden en que se declaran desde la raiz. Una
  redeclarada sin tipo (property Caption;) toma el de la declaracion mas
  cercana; una con indices no va nunca a un form, tampoco redeclarada. Los
  enumerados y los conjuntos que usa van a AEnums/ASets. }
function TGenerador.HechosDeClase(ATipo: TTipoPas; const ACadena: TArray<TTipoPas>;
  AEnums, ASets: TDictionary<string, TArray<string>>): TArray<string>;
var
  Lineas, Orden: TList<string>;
  Pub: TDictionary<string, string>;
  TipoDe, PubTipo: TDictionary<string, TRefTipo>;
  ConIndices: TDictionary<string, Boolean>;
  Ref: TRefTipo;
  K, Padre, Id: string;
  C: TTipoPas;
  I: TInfoTipo;
  U: TUnidadLeida;
begin
  Lineas := TList<string>.Create;
  Orden := TList<string>.Create;
  Pub := TDictionary<string, string>.Create;
  TipoDe := TDictionary<string, TRefTipo>.Create;
  PubTipo := TDictionary<string, TRefTipo>.Create;
  ConIndices := TDictionary<string, Boolean>.Create;
  try
    // una clase anidada con su contenedor (TGridPanelLayout.TColumnCollection),
    // como la nombra la RTTI y como la escribe el tipo de una propiedad
    // ...con su unidad: su identidad (IdDeTipo), la de su padre tambien
    Lineas.Add('C ' + IdDeClase(ATipo));
    // el padre es el primer ancestro NO generico: los genericos no van a la
    // tabla, y por ellos la herencia se cortaba (TLocationSensor =
    // class(TSensor<...>): no llegaba a TComponent, que guarda Left y Top)
    Padre := 'TObject';
    for var N := 1 to High(ACadena) do
      if not ACadena[N].Generica then
      begin
        Padre := IdDeClase(ACadena[N]);
        Break;
      end;
    Lineas.Add('H ' + IdDeClase(ATipo) + ' ' + Padre);
    for var N := High(ACadena) downto 0 do
    begin
      C := ACadena[N];
      for var P in C.Propiedades do
      begin
        K := ClaveDeIdentificador(P.Nombre);
        // una declaracion con tipo es una propiedad NUEVA que tapa a la del
        // ancestro (TCustomColorListBox.Selected: TColor tapa a
        // TCustomListBox.Selected[Index]: Boolean); solo la redeclarada sin
        // tipo hereda los indices
        if P.Tipo <> '' then
        begin
          if P.ConIndices then
            ConIndices.AddOrSetValue(K, True)
          else
            ConIndices.Remove(K);
          Ref.Tipo := P.Tipo;
          Ref.Clase := C;
          TipoDe.AddOrSetValue(K, Ref);
        end;
        if P.DeClase then
          Continue;
        // la cadena es de una persistente: lo que va sin seccion es published.
        // Su tipo es el que tiene AL publicarse: una redeclaracion no
        // publicada de despues es otra propiedad (TInternetExplorer tapa
        // Name con un WideString publico, y la publicada sigue siendo la
        // TComponentName de TComponent)
        if (P.Visibilidad = vpPublicada) or (P.Visibilidad = vpDefecto) then
        begin
          if not Pub.ContainsKey(K) then
          begin
            Pub.Add(K, P.Nombre);
            Orden.Add(K);
          end;
          if TipoDe.TryGetValue(K, Ref) then
            PubTipo.AddOrSetValue(K, Ref);
        end;
      end;
    end;
    for K in Orden do
    begin
      if ConIndices.ContainsKey(K) then
        Continue;
      if PubTipo.TryGetValue(K, Ref) and FDueno.TryGetValue(Ref.Clase, U) then
        I := Clasifica(Ref.Tipo, U, Ref.Clase, Ref.Clase.EnImplementation)
      else
        I := Info('?', '?');
      // una clase, un enumerado o un conjunto, por su identidad con la
      // unidad: el de otra unidad con el mismo nombre es OTRO tipo
      Id := I.Nombre;
      if CharInSet(I.Kind, ['c', 'e', 's']) then
        Id := IdDeTipo(I.Unidad, I.Nombre);
      Lineas.Add(Format('P %s %s %s %s', [IdDeClase(ATipo), Pub[K], I.Kind, Id]));
      if (I.Kind = 'e') and (Length(I.Miembros) > 0) and not AEnums.ContainsKey(Id) then
        AEnums.Add(Id, I.Miembros)
      else if (I.Kind = 's') and (Length(I.Miembros) > 0) and not ASets.ContainsKey(Id) then
        ASets.Add(Id, I.Miembros);
    end;
    Result := Lineas.ToArray;
  finally
    ConIndices.Free;
    PubTipo.Free;
    TipoDe.Free;
    Pub.Free;
    Orden.Free;
    Lineas.Free;
  end;
end;

{ Lo que una clase publica y guarda por codigo, sin su nombre ni su padre:
  dos homonimas con la misma firma son la misma para un form. }
function FirmaDeClase(const AHechos: TArray<string>): string;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    for var H in AHechos do
      if (H.StartsWith('P ') or H.StartsWith('D ')) and (H.IndexOf(' ', 2) > 0) then
        L.Add(H.Substring(0, 2) + ClaveDeIdentificador(H.Substring(H.IndexOf(' ', 2) + 1)));
    L.Sort;
    Result := L.Text;
  finally
    L.Free;
  end;
end;

type
  // una clase que tiene un nombre que escribe un form
  TPrimera = record
    Id, Firma: string;
    Prioridad, Pase: Integer;
    Raiz, Registrada: Boolean;
  end;
  TCriterioPrimera = reference to function(const C: TPrimera): Boolean;

// Las que cumplen el criterio; si no lo cumple ninguna, todas (es una
// preferencia, no un filtro: sin ninguna registrada, no se quita nada)
function Filtra(const ALista: TArray<TPrimera>; const ACriterio: TCriterioPrimera): TArray<TPrimera>;
begin
  Result := nil;
  for var C in ALista do
    if ACriterio(C) then
      Result := Result + [C];
  if Result = nil then
    Result := ALista;
end;

function TGenerador.Genera(const ACarpetas: TArray<string>): TTablasDeFuente;
var
  T0: UInt64;
  Orden: TList<TUnidadLeida>;
  Emitidas: array [TMarcoDisenador] of TDictionary<string, Boolean>;
  Lineas: array [TMarcoDisenador] of TList<string>;
  Primeras: array [TMarcoDisenador] of TDictionary<string, TArray<TPrimera>>;
  Enums, Sets: array [TMarcoDisenador] of TDictionary<string, TArray<string>>;
  Ms: TMarcosDisenador;
  Hechos: TArray<string>;
  Cad: TArray<TTipoPas>;
  K, Id, Nombre, Amb: string;
  Pri: TPrimera;
  M: TMarcoDisenador;
begin
  T0 := GetTickCount64;
  Result := Default(TTablasDeFuente);
  Indexa(ACarpetas);
  LeeConstantesDeSystem;
  LeeUnidades;
  Prepara;
  ResuelveRegistradas;
  ResuelveAyudantes;
  Result.Unidades := FUnidades.Count;
  Orden := TList<TUnidadLeida>.Create;
  for M := Low(TMarcoDisenador) to High(TMarcoDisenador) do
  begin
    Emitidas[M] := TDictionary<string, Boolean>.Create;
    Lineas[M] := TList<string>.Create;
    Primeras[M] := TDictionary<string, TArray<TPrimera>>.Create;
    Enums[M] := TDictionary<string, TArray<string>>.Create;
    Sets[M] := TDictionary<string, TArray<string>>.Create;
  end;
  try
    Orden.AddRange(FUnidades.Values);
    // lo de la instalacion antes que lo de terceros, por el orden de sus
    // carpetas: la primera de un nombre es la que nombra un form
    Orden.Sort(TComparer<TUnidadLeida>.Construct(
      function(const A, B: TUnidadLeida): Integer
      begin
        Result := CompareValue(A.Prioridad, B.Prioridad);
        if Result = 0 then
          Result := CompareValue(A.Orden, B.Orden);
        if Result = 0 then
          Result := CompareStr(A.Clave, B.Clave);
      end));
    // las del interface primero: una clase privada de un implementation no
    // le quita el nombre a una publica
    for var Pase := 0 to 1 do
      for var U in Orden do
      begin
        Ms := MarcosDe(U);
        if Ms = [] then
          Ms := [mdVcl, mdFmx];
        // lo que guarda por codigo un ayudante de la unidad ('* Nombre'): de
        // alguna clase de su marco
        if Pase = 0 then
          for var Def in U.Definidas do
            if Def.StartsWith('* ') then
              for M in Ms do
                if not Emitidas[M].ContainsKey('d|' + ClaveDeIdentificador(Def)) then
                begin
                  Lineas[M].Add('D ' + Def);
                  Emitidas[M].Add('d|' + ClaveDeIdentificador(Def), True);
                end;
        for var T in U.Decl.Tipos do
        begin
          if (T.Clase <> ctClase) or T.Generica or
             (T.EnImplementation <> (Pase = 1)) then
            Continue;
          // cada clase por su IDENTIDAD, con su unidad: el TFont de
          // Vcl.Graphics y el de TeeChart (Tee.Format) son dos clases, y una
          // propiedad sabe de cual es (revision de la 1.12.0: por el nombre,
          // la primera tapaba a la otra)
          Id := IdDeClase(T);
          K := ClaveDeIdentificador(Id);
          Cad := Cadena(T);
          if not EsPersistente(Cad) then
            Continue;
          for M in Ms do
          begin
            if Emitidas[M].ContainsKey(K) then
              Continue;
            Hechos := HechosDeClase(T, Cad, Enums[M], Sets[M]);
            // lo que guarda por codigo, en ELLA (no en cada descendiente: el
            // lint sube por la herencia, y la tabla no engorda)
            for var Def in U.Definidas do
              if MismoIdentificador(Def.Substring(0, Def.IndexOf(' ')), T.NombreCompleto) then
                Hechos := Hechos + ['D ' + Id + Def.Substring(Def.IndexOf(' '))];
            Lineas[M].AddRange(Hechos);
            Emitidas[M].Add(K, True);
            // ...pero un form escribe el NOMBRE ('object X: TScrollBar'):
            // quien se lo queda se decide abajo, con todas las que lo tienen
            Nombre := ClaveDeIdentificador(T.NombreCompleto);
            Pri.Id := Id;
            Pri.Firma := FirmaDeClase(Hechos);
            Pri.Prioridad := U.Prioridad;
            Pri.Pase := Pase;
            Pri.Raiz := EsRaiz(Cad);
            Pri.Registrada := FRegistradas.ContainsKey(T);
            if not Primeras[M].ContainsKey(Nombre) then
              Primeras[M].Add(Nombre, nil);
            Primeras[M][Nombre] := Primeras[M][Nombre] + [Pri];
          end;
        end;
      end;
    for M := Low(TMarcoDisenador) to High(TMarcoDisenador) do
    begin
      { Quien se queda el NOMBRE que escribe un form, entre las clases del
        marco que lo tienen: las del interface antes que las del
        implementation; una raiz (form, frame, modulo: nunca va anidada) no
        compite (el THTTPServer de HTTPIntr es un TWebModule, el de ICS un
        componente); la que el fuente registra en la paleta
        (RegisterComponents) gana; si todas publican lo mismo, la primera; si
        no, la de la instalacion gana a las de terceros; y entre iguales el
        form no dice cual: AMBIGUA, no se juzga (X). Si no es la primera que
        se escribio, N lo dice (TMetaTable toma la primera C de un nombre). }
      for var Par in Primeras[M] do
      begin
        var Cs := Par.Value;
        Cs := Filtra(Cs, function(const C: TPrimera): Boolean begin Result := C.Pase = 0; end);
        Cs := Filtra(Cs, function(const C: TPrimera): Boolean begin Result := not C.Raiz; end);
        Cs := Filtra(Cs, function(const C: TPrimera): Boolean begin Result := C.Registrada; end);
        var Iguales := True;
        for var C in Cs do
          if C.Firma <> Cs[0].Firma then
            Iguales := False;
        if not Iguales then
          Cs := Filtra(Cs, function(const C: TPrimera): Boolean begin Result := C.Prioridad = 0; end);
        Iguales := True;
        for var C in Cs do
          if C.Firma <> Cs[0].Firma then
            Iguales := False;
        if not Iguales then
        begin
          Amb := NombreDeIdDeTipo(Par.Value[0].Id) + ' ';
          for var I := 0 to High(Cs) do
            Amb := Amb + IfThen(I > 0, ',') + Cs[I].Id;
          Lineas[M].Add('X ' + Amb);
          Result.Ambiguas[M] := Result.Ambiguas[M] + [Amb];
        end
        else if Cs[0].Id <> Par.Value[0].Id then
          Lineas[M].Add('N ' + NombreDeIdDeTipo(Cs[0].Id) + ' ' + Cs[0].Id);
      end;
      for var E in Enums[M] do
        Lineas[M].Add('E ' + E.Key + ' ' + string.Join(',', E.Value));
      for var S in Sets[M] do
        Lineas[M].Add('S ' + S.Key + ' ' + string.Join(',', S.Value));
      Result.Hechos[M] := Lineas[M].ToArray;
    end;
  finally
    for M := Low(TMarcoDisenador) to High(TMarcoDisenador) do
    begin
      Sets[M].Free;
      Enums[M].Free;
      Primeras[M].Free;
      Lineas[M].Free;
      Emitidas[M].Free;
    end;
    Orden.Free;
  end;
  Result.Ms := Integer(GetTickCount64 - T0);
end;

function GeneraTablasDeFuente(const ACarpetas: TArray<string>;
  const AVersionCompilador, ARaizBds, APlataforma: string): TTablasDeFuente;
var
  G: TGenerador;
begin
  G := TGenerador.Create(AVersionCompilador, ARaizBds, APlataforma);
  try
    Result := G.Genera(ACarpetas);
  finally
    G.Free;
  end;
end;

{ ---- de donde sale el fuente de una instalacion ---- }

function CarpetasDeFuente(const AInfo: TRadStudioInfo): TArray<string>;
var
  Vistas: TDictionary<string, Boolean>;
  Lista: TList<string>;
begin
  Vistas := TDictionary<string, Boolean>.Create;
  Lista := TList<string>.Create;
  try
    // el Search Path primero: lo que el compilador encontraria
    for var Valor in ['Search Path', 'Browsing Path'] do
      for var Plat in ['Win32', 'Win64'] do
        for var C in IdePlatformLibraryPaths(AInfo.Version, Plat, Valor) do
          if not Vistas.ContainsKey(AnsiLowerCase(C)) and TDirectory.Exists(C) then
          begin
            Vistas.Add(AnsiLowerCase(C), True);
            Lista.Add(C);
          end;
    Result := Lista.ToArray;
  finally
    Lista.Free;
    Vistas.Free;
  end;
end;

function VersionDelCompilador(const AInfo: TRadStudioInfo;
  const ACarpetas: TArray<string>): string;
var
  M: TMatch;
  V: string;
begin
  for var C in ACarpetas do
    if FileExists(TPath.Combine(C, 'System.pas')) then
    begin
      try
        M := TRegEx.Match(CodigoPascal(TFile.ReadAllText(TPath.Combine(C, 'System.pas'))),
          '(?i)\bRTLVersion\s*=\s*([0-9]+(\.[0-9]+)?)\s*;');
        if M.Success then
          Exit(FormatFloat('0.0', StrToFloat(M.Groups[1].Value, TFormatSettings.Invariant),
            TFormatSettings.Invariant));
      except
        // ilegible: lo que sigue
      end;
      Break;
    end;
  V := VersionDeFichero(TPath.Combine(TPath.Combine(AInfo.RootDir, 'bin'), 'dcc32.exe'));
  if V.CountChar('.') >= 1 then
  begin
    var Partes := V.Split(['.']);
    Exit(Partes[0] + '.' + Partes[1]);
  end;
  Result := AInfo.Version;
end;

function HuellaDeCarpetas(const ACarpetas: TArray<string>; const APlataforma: string): string;
var
  Sb: TStringBuilder;
  Sr: TSearchRec;
  N: Integer;
  Tam, Ultima, T: Int64;
  Ext: string;
begin
  Sb := TStringBuilder.Create;
  try
    for var C in ACarpetas do
    begin
      N := 0;
      Tam := 0;
      Ultima := 0;
      // UNA pasada por carpeta: el tamano y la fecha vienen en la entrada del
      // directorio (antes, la lista y despues una consulta por fichero: ~8.000
      // llamadas por minuto en el camino de las peticiones; revision de la
      // 1.12.0). La fecha en UTC, tal cual: el cambio de hora no la mueve.
      if FindFirst(TPath.Combine(C, '*'), faAnyFile, Sr) = 0 then
      try
        repeat
          if (Sr.Attr and faDirectory) <> 0 then
            Continue;
          Ext := LowerCase(ExtractFileExt(Sr.Name));
          if (Ext <> '.pas') and (Ext <> '.inc') then
            Continue;
          Inc(N);
          Inc(Tam, Sr.Size);
          T := Int64(Sr.FindData.ftLastWriteTime.dwHighDateTime) shl 32 or
            Sr.FindData.ftLastWriteTime.dwLowDateTime;
          if T > Ultima then
            Ultima := T;
        until FindNext(Sr) <> 0;
      finally
        FindClose(Sr);
      end;
      Sb.Append(AnsiLowerCase(C)).Append('|').Append(N).Append('|').Append(Tam)
        .Append('|').Append(Ultima).Append(#10);
    end;
    if APlataforma <> '' then
      Sb.Append(APlataforma);
    Result := THashMD5.GetHashString(Sb.ToString).Substring(0, 12).ToLower;
  finally
    Sb.Free;
  end;
end;

{ ---- la cache ---- }

const
  PREFIJO_TABLA = 'tabla';
  EXT_TABLA = '.txt';

function NombreDeTabla(const AVersion, ABuild: string; AMarco: TMarcoDisenador;
  const AHuella: string; AGeneracion: Integer): string;
begin
  Result := Format('%s_%s_%s_%s_%s_g%d%s', [PREFIJO_TABLA, AVersion, ABuild,
    NombreDeMarco(AMarco), AHuella, AGeneracion, EXT_TABLA]);
end;

function LeeNombreDeTabla(const ANombre: string; out AVersion, ABuild: string;
  out AMarco: TMarcoDisenador; out AHuella: string; out AGeneracion: Integer): Boolean;
var
  Partes: TArray<string>;
  N: string;
begin
  Result := False;
  AVersion := '';
  ABuild := '';
  AMarco := mdVcl;
  AHuella := '';
  AGeneracion := 0;
  N := ExtractFileName(ANombre);
  if not SameText(ExtractFileExt(N), EXT_TABLA) then
    Exit;
  Partes := ChangeFileExt(N, '').Split(['_']);
  if (Length(Partes) <> 6) or not SameText(Partes[0], PREFIJO_TABLA) or
     not Partes[5].StartsWith('g') or
     not TryStrToInt(Partes[5].Substring(1), AGeneracion) then
    Exit;
  if SameText(Partes[3], NombreDeMarco(mdFmx)) then
    AMarco := mdFmx
  else if not SameText(Partes[3], NombreDeMarco(mdVcl)) then
    Exit;
  AVersion := Partes[1];
  ABuild := Partes[2];
  AHuella := Partes[4];
  Result := True;
end;

type
  // lo que se sabe de una instalacion sin leer su fuente, por un rato
  TDatosInstalacion = record
    Carpetas: TArray<string>;
    Huella: string;
    VersionCompilador: string;
    Plataforma: string;  // la del IDE: PlataformaDelIde
    ConFuente: Boolean;
    Tick: UInt64;
  end;

  // un fallo del generador: se recuerda un rato, y no se repite en cada
  // llamada (cada intento son segundos de CPU)
  TFalloTabla = record
    Huella: string;
    Mensaje: string;
    Tick: UInt64;
  end;

const
  // la huella recorre ~120 carpetas: se mira, como mucho, una vez por minuto
  VIDA_DATOS_MS = 60000;
  // la clave del mutex de la generacion (NombreDeMutex)
  CLAVE_GENERACION = 'tablas-disenador';
  // lo que se recuerda un fallo (DSGN-053)
  VIDA_FALLO_MIN = MINUTOS_REINTENTO_TABLA;
  // una instalacion con una tabla anterior que sirve no se regenera mas de una
  // vez cada tanto: guardar un .pas de una carpeta del Search Path (los
  // componentes que uno escribe) cambia la huella cada vez
  PAUSA_REGENERAR_MS = 10 * 60000;
  // lo que se espera a que OTRO proceso acabe la suya
  ESPERA_MUTEX_MS = 10 * 60000;
  // lo que no es vigente se borra con mas de una hora: otro proceso (que vea
  // otras carpetas: el servicio no conecta las letras de red de la sesion)
  // puede estar usandolo, y la hora corta cualquier ping-pong entre los dos
  EDAD_PURGA = 1 / 24;

var
  { La cola del generador. UN hilo genera, de una en una; quien pide una
    tabla nunca la genera el mismo (con el cerrojo de las ediciones cogido
    paraba el servidor diez segundos: revision de la 1.12.0) - la pide y, si
    puede, espera con TMonitor.Wait. Todo lo de abajo, bajo GGenLock. }
  GGenLock: TObject;
  GCola: TList<TRadStudioInfo>;
  GCalentar: Boolean;     // la vuelta del arranque: todas las instalaciones
  GEnCurso: string;       // la version que se esta generando
  GTrabajando: Boolean;   // GHilo esta dando vueltas
  GHilo: TThread;
  GUltimaGen: TDictionary<string, UInt64>;    // por version
  GFallos: TDictionary<string, TFalloTabla>;  // por version
  GDatosLock: TObject;
  GDatos: TDictionary<string, TDatosInstalacion>;

function DatosDeInstalacion(const AInfo: TRadStudioInfo; AFresco: Boolean = False): TDatosInstalacion;
var
  Ahora: UInt64;
begin
  Ahora := GetTickCount64;
  if not AFresco then
  begin
    TMonitor.Enter(GDatosLock);
    try
      if GDatos.TryGetValue(AInfo.Version, Result) and (Ahora - Result.Tick < VIDA_DATOS_MS) then
        Exit;
    finally
      TMonitor.Exit(GDatosLock);
    end;
  end;
  Result := Default(TDatosInstalacion);
  Result.Carpetas := CarpetasDeFuente(AInfo);
  for var C in Result.Carpetas do
    if FileExists(TPath.Combine(C, 'System.pas')) then
    begin
      Result.ConFuente := True;
      Break;
    end;
  if Result.ConFuente then
  begin
    Result.VersionCompilador := VersionDelCompilador(AInfo, Result.Carpetas);
    Result.Plataforma := PlataformaDelIde(AInfo.RootDir);
    Result.Huella := HuellaDeCarpetas(Result.Carpetas, Result.Plataforma);
  end;
  Result.Tick := Ahora;
  TMonitor.Enter(GDatosLock);
  try
    GDatos.AddOrSetValue(AInfo.Version, Result);
  finally
    TMonitor.Exit(GDatosLock);
  end;
end;

{ Lo que hay que borrar de la cache del disenador: de esa instalacion, las
  tablas que no son las de ahora (otra huella, otra build, una generacion MAS
  VIEJA - la de un servidor mas nuevo no es de este) con mas de una hora, y
  los .tmp de un escritor que murio a medias. }
procedure PurgaTablasViejas(const ADir, AVersion: string; const AVigentes: array of string);
var
  V, B, H: string;
  M: TMarcoDisenador;
  G: Integer;
  Vigente: Boolean;
  Edad: TDateTime;
begin
  try
    for var F in TDirectory.GetFiles(ADir) do
    begin
      if not FileAge(F, Edad) or (Now - Edad < EDAD_PURGA) then
        Continue;
      if SameText(ExtractFileExt(F), '.tmp') then
      begin
        System.SysUtils.DeleteFile(F);
        Continue;
      end;
      if not LeeNombreDeTabla(F, V, B, M, H, G) or not SameText(V, AVersion) or
         (G > GENERACION_TABLAS) then
        Continue;
      Vigente := False;
      for var X in AVigentes do
        if SameText(ExtractFileName(F), ExtractFileName(X)) then
          Vigente := True;
      if not Vigente then
        System.SysUtils.DeleteFile(F);
    end;
  except
    // limpiar nunca tumba nada
  end;
end;

// Las tablas de una instalacion que ya no esta (desinstalada): no las va a
// leer nadie
procedure PurgaTablasDeLoQueNoEsta(const ADir: string; const AInstaladas: TArray<TRadStudioInfo>);
var
  V, B, H: string;
  M: TMarcoDisenador;
  G: Integer;
  Esta: Boolean;
begin
  try
    if not TDirectory.Exists(ADir) then
      Exit;
    for var F in TDirectory.GetFiles(ADir) do
    begin
      if not LeeNombreDeTabla(F, V, B, M, H, G) then
        Continue;
      Esta := False;
      for var I in AInstaladas do
        if SameText(I.Version, V) then
          Esta := True;
      if not Esta then
        System.SysUtils.DeleteFile(F);
    end;
  except
    // limpiar nunca tumba nada
  end;
end;

{ La tabla de antes de esa instalacion y marco (la misma build y generacion,
  otra huella), la mas reciente: la que vale mientras se genera la nueva.
  '' si no hay. }
function TablaAnterior(const ADir: string; const AInfo: TRadStudioInfo;
  AMarco: TMarcoDisenador): string;
var
  V, B, H: string;
  M: TMarcoDisenador;
  G: Integer;
  Edad, Mejor: TDateTime;
begin
  Result := '';
  Mejor := 0;
  try
    if not TDirectory.Exists(ADir) then
      Exit;
    for var F in TDirectory.GetFiles(ADir) do
      if LeeNombreDeTabla(F, V, B, M, H, G) and SameText(V, AInfo.Version) and
         SameText(B, AInfo.Build) and (M = AMarco) and (G = GENERACION_TABLAS) and
         FileAge(F, Edad) and (Edad > Mejor) then
      begin
        Mejor := Edad;
        Result := F;
      end;
  except
    Result := '';
  end;
end;

{ Las dos tablas de una instalacion, si no estan: en el hilo del generador.
  Un fallo se recuerda (GFallos); el cierre del servidor la corta (EAbort). }
procedure GeneraYGuarda(const AInfo: TRadStudioInfo);
var
  D: TDatosInstalacion;
  Dir, Cabecera: string;
  Ficheros: array [TMarcoDisenador] of string;
  Tablas: TTablasDeFuente;
  M: TMarcoDisenador;
  Mutex: THandle;
  Espera: UInt64;
  R: DWORD;
  Mio: Boolean;
  Fallo: TFalloTabla;
begin
  D := Default(TDatosInstalacion);
  try
    // la huella FRESCA: con la de hace un minuto un proceso podia generar (y
    // dejar vigente) una tabla que ya no era la del fuente, y purgar la buena
    D := DatosDeInstalacion(AInfo, True);
    if not D.ConFuente then
      Exit;
    Dir := ServerCacheDir('designer');
    for M := Low(TMarcoDisenador) to High(TMarcoDisenador) do
      Ficheros[M] := TPath.Combine(Dir, NombreDeTabla(AInfo.Version, AInfo.Build, M, D.Huella));
    if FileExists(Ficheros[mdVcl]) and FileExists(Ficheros[mdFmx]) then
      Exit;
    // ...y de una en una entre PROCESOS: el servicio y las instancias de las
    // baterias comparten la cache, y cada generacion son segundos de CPU. Un
    // mutex que creo otra cuenta puede no dejarse crear: se abre con lo justo
    // para esperarlo y soltarlo; sin el, se genera igual (es solo CPU)
    Mutex := CreateMutex(nil, False, PChar(NombreDeMutex(CLAVE_GENERACION)));
    if Mutex = 0 then
      Mutex := OpenMutex(SYNCHRONIZE or MUTEX_MODIFY_STATE, False,
        PChar(NombreDeMutex(CLAVE_GENERACION)));
    Mio := False;
    try
      if Mutex <> 0 then
      begin
        Espera := GetTickCount64;
        repeat
          R := WaitForSingleObject(Mutex, 1000);
        until (R <> WAIT_TIMEOUT) or GCerrando or (GetTickCount64 - Espera > ESPERA_MUTEX_MS);
        if (R <> WAIT_OBJECT_0) and (R <> WAIT_ABANDONED) then
          Exit; // otro proceso no acaba, o el servidor se cierra: ya se pedira
        Mio := True;
      end;
      if FileExists(Ficheros[mdVcl]) and FileExists(Ficheros[mdFmx]) then
        Exit; // la genero otro mientras se esperaba
      Tablas := GeneraTablasDeFuente(D.Carpetas, D.VersionCompilador, AInfo.RootDir, D.Plataforma);
      CrearCarpeta(Dir);
      for M := Low(TMarcoDisenador) to High(TMarcoDisenador) do
      begin
        Cabecera := Format('# designer table %s of RAD Studio %s (build %s, compiler %s, %s): ' +
          '%d units read from %d source folders in %d ms by DelphiLspMcp %s (generation %d)',
          [UpperCase(NombreDeMarco(M)), AInfo.Version, AInfo.Build, D.VersionCompilador, D.Plataforma,
          Tablas.Unidades, Length(D.Carpetas), Tablas.Ms, SERVER_VERSION, GENERACION_TABLAS]);
        EscribeEnCasaDelServidor(Ficheros[M],
          Cabecera + sLineBreak + string.Join(sLineBreak, Tablas.Hechos[M]) + sLineBreak);
      end;
      PurgaTablasViejas(Dir, AInfo.Version, [Ficheros[mdVcl], Ficheros[mdFmx]]);
      NotaAlLog(MsgFmt(SL_DESIGNER_TABLAS_GENERADAS_FMT, [AInfo.Version, AInfo.Build,
        Tablas.Unidades, Tablas.Ms, Length(Tablas.Hechos[mdVcl]), Length(Tablas.Hechos[mdFmx])]));
    finally
      if Mio then
        ReleaseMutex(Mutex);
      if Mutex <> 0 then
        CloseHandle(Mutex);
    end;
  except
    on EAbort do
      ; // el servidor se cierra: no es un fallo
    on E: Exception do
    begin
      NotaAlLog(MsgFmt(SL_DESIGNER_TABLAS_FALLO_FMT, [AInfo.Version, E.Message]));
      Fallo.Huella := D.Huella;
      Fallo.Mensaje := E.Message;
      Fallo.Tick := GetTickCount64;
      TMonitor.Enter(GGenLock);
      try
        GFallos.AddOrSetValue(AInfo.Version, Fallo);
      finally
        TMonitor.Exit(GGenLock);
      end;
    end;
  end;
end;

// La vuelta del arranque: lo de las instalaciones que ya no estan se borra, y
// las que estan se ponen en la cola
procedure Calienta;
var
  Todas: TArray<TRadStudioInfo>;
begin
  try
    Todas := DiscoverAllRadStudios;
    PurgaTablasDeLoQueNoEsta(ServerCacheDir('designer'), Todas);
    TMonitor.Enter(GGenLock);
    try
      for var Info in Todas do
        GCola.Add(Info);
    finally
      TMonitor.Exit(GGenLock);
    end;
  except
    on E: Exception do
      NotaAlLog(MsgFmt(SL_DESIGNER_TABLAS_FALLO_FMT, ['*', E.Message]));
  end;
end;

// Bajo GGenLock: esa version esta en la cola o generandose
function EnColaLocked(const AVersion: string): Boolean;
begin
  if SameText(GEnCurso, AVersion) then
    Exit(True);
  for var I in GCola do
    if SameText(I.Version, AVersion) then
      Exit(True);
  Result := False;
end;

// El cuerpo del hilo del generador: hasta que no queda nada
procedure Trabaja;
var
  Info: TRadStudioInfo;
  Calentar: Boolean;
begin
  repeat
    TMonitor.Enter(GGenLock);
    try
      if GCerrando or ((GCola.Count = 0) and not GCalentar) then
      begin
        GTrabajando := False;
        GEnCurso := '';
        TMonitor.PulseAll(GGenLock);
        Exit;
      end;
      Calentar := GCalentar;
      GCalentar := False;
      if not Calentar then
      begin
        Info := GCola[0];
        GCola.Delete(0);
        GEnCurso := Info.Version;
      end;
    finally
      TMonitor.Exit(GGenLock);
    end;
    if Calentar then
      Calienta
    else
      GeneraYGuarda(Info);
    TMonitor.Enter(GGenLock);
    try
      if not Calentar then
        GUltimaGen.AddOrSetValue(Info.Version, GetTickCount64);
      GEnCurso := '';
      TMonitor.PulseAll(GGenLock);
    finally
      TMonitor.Exit(GGenLock);
    end;
  until False;
end;

// Bajo GGenLock: que el hilo del generador este dando vueltas
procedure ArrancaLocked;
begin
  if GTrabajando or GCerrando then
    Exit;
  if GHilo <> nil then
  begin
    // ya dijo que no trabaja (GTrabajando lo pone el bajo este cerrojo): le
    // queda salir del procedimiento, un instante, y no vuelve a pedir el cerrojo
    GHilo.WaitFor;
    FreeAndNil(GHilo);
  end;
  GHilo := TThread.CreateAnonymousThread(Trabaja);
  GHilo.FreeOnTerminate := False;
  GHilo.Priority := tpLower;
  GTrabajando := True;
  GHilo.Start;
end;

function TablaDeInstalacion(const AInfo: TRadStudioInfo; AMarco: TMarcoDisenador;
  AEsperaMs: Cardinal; out AFichero, ADetalle: string): TEstadoTabla;
var
  D: TDatosInstalacion;
  Dir, Anterior: string;
  Fallo: TFalloTabla;
  Ultima, T0: UInt64;
  Resto: Int64;

  function FalloLocked: Boolean;
  begin
    Result := GFallos.TryGetValue(AInfo.Version, Fallo) and (Fallo.Huella = D.Huella) and
      (GetTickCount64 - Fallo.Tick < VIDA_FALLO_MIN * 60000);
    if Result then
      ADetalle := Fallo.Mensaje;
  end;

begin
  AFichero := '';
  ADetalle := '';
  D := DatosDeInstalacion(AInfo);
  if not D.ConFuente then
    Exit(etSinFuente);
  Dir := ServerCacheDir('designer');
  AFichero := TPath.Combine(Dir, NombreDeTabla(AInfo.Version, AInfo.Build, AMarco, D.Huella));
  if FileExists(AFichero) then
    Exit(etLista);
  AFichero := '';
  Anterior := TablaAnterior(Dir, AInfo, AMarco);
  TMonitor.Enter(GGenLock);
  try
    if FalloLocked then
      Exit(etFallo);
    // se pide; con una anterior que sirve, no mas de una vez cada tanto
    if not EnColaLocked(AInfo.Version) and
       not ((Anterior <> '') and GUltimaGen.TryGetValue(AInfo.Version, Ultima) and
            (GetTickCount64 - Ultima < PAUSA_REGENERAR_MS)) then
    begin
      GCola.Add(AInfo);
      ArrancaLocked;
    end;
  finally
    TMonitor.Exit(GGenLock);
  end;
  // mientras, vale la de antes: no se espera
  if Anterior <> '' then
  begin
    AFichero := Anterior;
    Exit(etLista);
  end;
  // sin ninguna: un rato, a la que se esta generando
  T0 := GetTickCount64;
  TMonitor.Enter(GGenLock);
  try
    while EnColaLocked(AInfo.Version) do
    begin
      Resto := Int64(AEsperaMs) - Int64(GetTickCount64 - T0);
      if Resto <= 0 then
        Break;
      TMonitor.Wait(GGenLock, Cardinal(Resto));
    end;
  finally
    TMonitor.Exit(GGenLock);
  end;
  // el generador recalculo la huella: puede ser otra que la de hace un minuto
  D := DatosDeInstalacion(AInfo);
  AFichero := TPath.Combine(Dir, NombreDeTabla(AInfo.Version, AInfo.Build, AMarco, D.Huella));
  if FileExists(AFichero) then
    Exit(etLista);
  AFichero := '';
  TMonitor.Enter(GGenLock);
  try
    if FalloLocked then
      Exit(etFallo);
  finally
    TMonitor.Exit(GGenLock);
  end;
  Result := etGenerandose;
end;

procedure CalientaTablasDelDisenador;
begin
  TMonitor.Enter(GGenLock);
  try
    GCalentar := True;
    ArrancaLocked;
  finally
    TMonitor.Exit(GGenLock);
  end;
end;

initialization
  GGenLock := TObject.Create;
  GCola := TList<TRadStudioInfo>.Create;
  GUltimaGen := TDictionary<string, UInt64>.Create;
  GFallos := TDictionary<string, TFalloTabla>.Create;
  GDatosLock := TObject.Create;
  GDatos := TDictionary<string, TDatosInstalacion>.Create;

finalization
  { El hilo del generador puede seguir vivo al cerrar (una instancia corta de
    las baterias vive menos que una generacion): se le avisa (el generador lo
    mira entre unidad y unidad y sale con EAbort) y se le espera un momento,
    mientras las unidades que usa siguen vivas. Lo suyo NO se libera: si no
    ha salido todavia lo esta usando (antes, la finalization lo liberaba
    debajo de el: revision de la 1.12.0), y la memoria la devuelve el
    proceso al terminar. }
  GCerrando := True;
  if GHilo <> nil then
    WaitForSingleObject(GHilo.Handle, 5000);

end.
