unit Lsp.FormRender;

{ delphi_designer command=preview, la mitad del SERVIDOR: lanza los
  renderizadores de forms (src\Render: DelphiFormRenderVcl y
  DelphiFormRenderFmx, junto al exe del servidor como DelphiStyleConvert) y
  lee lo que contestan. Cada pieza, una vez:

    FormRenderExe          donde esta el renderizador de un framework: el
                           nombre del exe solo se compone aqui
    ComponeOrdenDeRender   LA orden, un interruptor por parametro de preview
                           (test_paisaje vigila que nadie mas la componga);
                           su inversa es ParseaArgumentos del ayudante
    LeeRespuestaDeRender   la inversa de FormRenderProtocolo.inc, que incluyen
                           el ayudante (el escritor, FormRender.Comun.Responde)
                           y este lector
    CorreRender            lo lanza con RunCapturedIn y su tiempo limite,
                           FUERA del AppContainer de delphi_test: el contenedor
                           no deja crear ventanas, y el VCL y el FMX mueren al
                           crear la form (medido 6 y 7-oct-2026, vault
                           renderform-ayudantes-2026-10-07). El ayudante lleva
                           ademas su propio vigia, un poco antes, para contestar
                           el por que.

  Por que procesos aparte y no una unidad del servidor: los paquetes de
  diseno del IDE se cargan EN el renderizador; si uno revienta muere el
  renderizador y el servidor contesta el error (src\Render\README.md). }

interface

type
  TPeticionRender = record
    Framework: string;         // vcl | fmx
    Path: string;              // el .dfm/.fmx, ya pasado por la puerta de lectura
    Salida: string;            // el .png que escribe el renderizador
    Estados: TArray<string>;   // Componente.Propiedad=Valor, uno por entrada
    Componente: string;        // '' = la form entera
    Estilo: string;            // fichero (ya por la puerta), plataforma, none o ''
    NoVisuales: Boolean;       // dibujar los no visuales
    Bds: string;               // la version del Delphi del servidor (37.0)
    Raiz: string;              // form | frame, por el lector de clases del servidor; '' = que mire el ayudante
  end;

  { Una propiedad que el lector se salto (IGNORED=, el OnError de TReader que
    el ayudante contesta Ignore): lo que dijo tal cual y, si casa con su forma
    ('Error reading Panel1.Color: Invalid property value', SPropertyException
    de System.RTLConsts), sus partes. Uno traducido, o de otra forma, queda
    solo en Texto (David, 7-oct-2026: que guien al modelo). }
  TIgnorada = record
    Texto: string;
    Componente, Propiedad, Motivo: string; // '' si no casa
  end;

  TRespuestaRender = record
    Fallo: string;             // '' = hay imagen; si no, el mensaje para el agente
    Error: string;             // ERROR= del ayudante, tal cual
    Codigo: Cardinal;          // su codigo de salida
    Captura: string;           // CAPTURE=
    Ancho, Alto: Integer;      // SIZE=
    Dpi, Sesion: Integer;      // DPI=, SESSION=
    RaizNombre, RaizClase, RaizTipo: string; // ROOT=<nombre>:<clase>:<form|frame>
    Fidelidad, Estilo, Paquetes: string;     // FIDELITY=, STYLE=, PACKAGES=
    Componentes: Integer;      // COMPONENTS=
    Sustituidas, Avisos: TArray<string>;
    Ignoradas: TArray<TIgnorada>;
    NoVisuales: TArray<string>; // NONVISUALS=: 'Nombre:Clase'
    NoVisualesDibujados: Integer; // NONVISUAL=
    HayRect: Boolean;          // RECT= del componente pedido
    RectX, RectY, RectW, RectH: Integer;
    MsCarga, MsPintado: Integer; // MS=
    MsTotal: Int64;            // lo que tardo de verdad, lanzamiento incluido
  end;

{ El renderizador de AFramework (vcl|fmx) junto al exe del servidor; '' si
  no esta. ANombre sale siempre, para decir cual falta. }
function FormRenderExe(const AFramework: string; out ANombre: string): string;

{ LA orden de un render: '' y AOrden, o el rechazo. Un valor con comillas o
  con un caracter de control se niega: el lector de argumentos de Delphi no
  tiene escape para una comilla, y lo que fuera detras seria OTRO
  interruptor (un --out fuera de la jaula). }
function ComponeOrdenDeRender(const AExe: string; const APeticion: TPeticionRender;
  out AOrden: string): string;

{ El --root de un render (form | frame), por EL lector de clases del servidor
  (InspectUnit): solo cuando la cadena de la clase de la unidad LLEGA a la
  raiz del marco (TForm/TCustomForm/TForm3D/TDataModule, TFrame/TCustomFrame)
  y su designer es el form pedido (un X.fmx al lado de un X.dfm: la unidad
  es del .dfm). Si no se sabe, '': que mire el ayudante. La unidad, ya por la
  puerta de lectura de quien llama. Nunca lanza (segunda revision de la
  1.17.0: un sufijo adivinado viajaba como un hecho). }
function RaizParaElRender(const ARuta: string): string;

{ Una linea IGNORED= -> sus partes (TIgnorada): el UNICO lector del texto de
  TReader. Componente es el Name del objeto (o su clase, el de un item de una
  coleccion: lo que pone TReader) y Propiedad su ruta (Font.Size). }
function IgnoradaDeTexto(const ATexto: string): TIgnorada;

{ La salida del renderizador -> sus campos (las lineas '#' son traza). }
function LeeRespuestaDeRender(const ASalida: string): TRespuestaRender;

{ Lanza el renderizador y lee lo que contesta. Fallo = '' si hay imagen en
  APeticion.Salida; si no, el mensaje que toca (el ERROR= del ayudante tal
  cual si ya lleva su etiqueta). Nunca lanza. }
function CorreRender(const APeticion: TPeticionRender): TRespuestaRender;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Diagnostics,
  System.RegularExpressions,
  Lsp.Guard,
  Lsp.BuildRunner,  // RunCapturedIn: el lanzador de los programas externos
  Lsp.ProjectUnits, // InspectUnit: la clase de la unidad y a que raiz llega
  Lsp.DesignerForma, // UnidadDeDesigner
  Lsp.Texts,
  Lsp.Styles,
  Lsp.DesignerBin,
  Lsp.Casa;         // ServerDir: la carpeta del exe del servidor

const
  {$I ..\Render\FormRenderProtocolo.inc}

  // Lo que espera el servidor, y el vigia del ayudante un poco antes: asi es
  // el ayudante quien contesta por que se paro (RENDER-007). Medido el
  // 7-oct-2026: una form estandar 20 ms, FichaCliente con 112 paquetes del
  // IDE ~1,2 s (9,4 s la primera vez, con la cache de disco fria).
  RENDER_TIEMPO_MS = 75000;
  RENDER_TIEMPO_AYUDANTE_MS = 60000;

  // Windows no pudo cargar el exe o sus paquetes de ejecucion (rtl/vcl/fmx
  // del Delphi): no hay ERROR= porque no llego a correr nada suyo
  STATUS_DLL_NOT_FOUND_ = $C0000135;
  STATUS_ENTRYPOINT_NOT_FOUND_ = $C0000139;
  STATUS_INVALID_IMAGE_FORMAT_ = $C000007B;

function FormRenderExe(const AFramework: string; out ANombre: string): string;
begin
  if SameText(AFramework, 'fmx') then
    ANombre := 'DelphiFormRenderFmx.exe'
  else
    ANombre := 'DelphiFormRenderVcl.exe';
  Result := ServerDir(ANombre);
  if not TFile.Exists(Result) then
    Result := '';
end;

function RaizParaElRender(const ARuta: string): string;
var
  Unidad: TUnitInfo;
begin
  Result := '';
  try
    if (InspectUnit(UnidadDeDesigner(ARuta), Unidad) <> '') or (Unidad.ClassName = '') or
       not SameFileName(Unidad.Designer, TPath.GetFullPath(ARuta)) then
      Exit;
    if Unidad.DesignRoot = 'TFrame' then
      Result := 'frame'
    else if Unidad.DesignRoot <> '' then
      Result := 'form';
  except
    Result := ''; // una unidad que no se deja leer: que mire el ayudante
  end;
end;

{ Un valor que viaja como UN argumento entre comillas }
function ValorDeArgumento(const AValor: string): Boolean;
begin
  for var C in AValor do
    if (C = '"') or (C < ' ') then
      Exit(False);
  Result := True;
end;

function ComponeOrdenDeRender(const AExe: string; const APeticion: TPeticionRender;
  out AOrden: string): string;

  function Arg(const AInterruptor, AValor: string): string;
  begin
    Result := ' ' + AInterruptor + ' "' + AValor + '"';
  end;

begin
  Result := '';
  AOrden := '';
  // un valor vacio no se pasa nunca: el lector de Delphi se salta un "" y
  // tomaria el interruptor siguiente como valor
  for var V in TArray<string>.Create(APeticion.Path, APeticion.Salida,
    APeticion.Componente, APeticion.Estilo, APeticion.Bds) + APeticion.Estados do
    if not ValorDeArgumento(V) then
      Exit(MsgFmt(SR_DESIGNER_VALOR_CON_COMILLAS_FMT, [V]));
  AOrden := '"' + AExe + '"' + Arg('--path', APeticion.Path) +
    Arg('--out', APeticion.Salida) +
    ' --nonvisual ' + (if APeticion.NoVisuales then 'on' else 'off') +
    ' --timeout ' + IntToStr(RENDER_TIEMPO_AYUDANTE_MS);
  if APeticion.Bds <> '' then
    AOrden := AOrden + Arg('--bds', APeticion.Bds);
  for var E in APeticion.Estados do
    if E <> '' then
      AOrden := AOrden + Arg('--state', E);
  if APeticion.Componente <> '' then
    AOrden := AOrden + Arg('--component', APeticion.Componente);
  if (APeticion.Raiz = 'form') or (APeticion.Raiz = 'frame') then
    AOrden := AOrden + ' --root ' + APeticion.Raiz;
  if APeticion.Estilo <> '' then
    AOrden := AOrden + Arg('--style', APeticion.Estilo);
end;

function IgnoradaDeTexto(const ATexto: string): TIgnorada;
var
  M: TMatch;
begin
  Result := Default(TIgnorada);
  Result.Texto := ATexto;
  // 'Error reading %s%s%s: %s' (SPropertyException): el Name, sin puntos; un
  // punto; la ruta de la propiedad, que si los lleva (Font.Size); el motivo
  M := TRegEx.Match(ATexto, '\AError reading ([^.:\s]+)\.([^:\s]+): (.+)\z');
  if M.Success then
  begin
    Result.Componente := M.Groups[1].Value;
    Result.Propiedad := M.Groups[2].Value;
    Result.Motivo := M.Groups[3].Value;
  end;
end;

function LeeRespuestaDeRender(const ASalida: string): TRespuestaRender;
var
  L, V: string;
  Trozos: TArray<string>;
  P: Integer;

  function Es(const AClave: string): Boolean;
  begin
    Result := L.StartsWith(AClave);
    if Result then
      V := L.Substring(Length(AClave));
  end;

begin
  Result := Default(TRespuestaRender);
  Result.Sesion := -1;
  for var Linea in ASalida.Replace(#13, '').Split([#10]) do
  begin
    L := Linea;
    if (L = '') or L.StartsWith('#') then
      Continue;
    if Es(FR_CAPTURE) then
      Result.Captura := V
    else if Es(FR_SIZE) then
    begin
      Trozos := V.Split(['x']);
      if Length(Trozos) = 2 then
      begin
        Result.Ancho := StrToIntDef(Trozos[0], 0);
        Result.Alto := StrToIntDef(Trozos[1], 0);
      end;
    end
    else if Es(FR_DPI) then
      Result.Dpi := StrToIntDef(V, 0)
    else if Es(FR_SESSION) then
      Result.Sesion := StrToIntDef(V, -1)
    else if Es(FR_ROOT) then
    begin
      Trozos := V.Split([':']);
      if Length(Trozos) = 3 then
      begin
        Result.RaizNombre := Trozos[0];
        Result.RaizClase := Trozos[1];
        Result.RaizTipo := Trozos[2];
      end;
    end
    else if Es(FR_FIDELITY) then
      Result.Fidelidad := V
    else if Es(FR_PACKAGES) then
      Result.Paquetes := V
    else if Es(FR_COMPONENTS) then
      Result.Componentes := StrToIntDef(V, 0)
    else if Es(FR_SUBSTITUTED) then
      Result.Sustituidas := V.Split([','], TStringSplitOptions.ExcludeEmpty)
    else if Es(FR_IGNORED) then
      Result.Ignoradas := Result.Ignoradas + [IgnoradaDeTexto(V)]
    else if Es(FR_NONVISUALS) then
      Result.NoVisuales := V.Split([','], TStringSplitOptions.ExcludeEmpty)
    else if Es(FR_NONVISUAL) then
      Result.NoVisualesDibujados := StrToIntDef(V, 0)
    else if Es(FR_RECT) then
    begin
      // <Nombre>=<izq>,<arriba>,<ancho>,<alto>: el nombre no lleva '='
      P := V.LastIndexOf('=');
      Trozos := V.Substring(P + 1).Split([',']);
      if (P > 0) and (Length(Trozos) = 4) then
      begin
        Result.HayRect := True;
        Result.RectX := StrToIntDef(Trozos[0], 0);
        Result.RectY := StrToIntDef(Trozos[1], 0);
        Result.RectW := StrToIntDef(Trozos[2], 0);
        Result.RectH := StrToIntDef(Trozos[3], 0);
      end;
    end
    else if Es(FR_STYLE) then
      Result.Estilo := V
    else if Es(FR_WARNING) then
      Result.Avisos := Result.Avisos + [V]
    else if Es(FR_MS) then
    begin
      Trozos := V.Split([',']);
      if Length(Trozos) = 2 then
      begin
        Result.MsCarga := StrToIntDef(Trozos[0], 0);
        Result.MsPintado := StrToIntDef(Trozos[1], 0);
      end;
    end
    else if Es(FR_ERROR) then
      Result.Error := V;
  end;
end;

{ La forma del VALOR decide, nunca una lista de propiedades.
  Se pregunta al unico juez de lectura por cada fichero existente.
  El ayudante interpreta relativos desde la form o desde su cwd (el PNG). }
function LiteralesDeRenderDenegados(const APeticion: TPeticionRender): string;
var
  Bases: TArray<string>;
  BytesLeidos: Int64;
  Doc: TStyleDoc;
  Form: TArray<TLineaForm>;
  Texto, Valor, Prop: string;

  function Comprueba(const AProp, AValor: string): string;
  var
    Ruta: string;
  begin
    Result := '';
    // El valor se juzga por su texto ANTES de alargarlo o preguntar si existe.
    if RutaSinTocarElDisco(AValor) then
      Exit(MsgFmt(SR_DESIGNER_LITERAL_FUERA_FMT, [AProp]));
    if AValor = '' then
      Exit;
    for var Base in Bases do
    begin
      try
        Ruta := TPath.GetFullPath(TPath.Combine(Base, AValor));
      except
        Continue; // una cadena que no es ruta no nombra un fichero
      end;
      if TFile.Exists(Ruta) and (ReadPathDenied(Ruta) <> '') then
        Exit(MsgFmt(SR_DESIGNER_LITERAL_FUERA_FMT, [AProp]));
    end;
  end;

  function CompruebaForm(const ARuta: string): string;
  begin
    Result := '';
    // 65 MiB de texto costaron 416 MiB en el servidor; la pasada previa
    // sucede antes del job. El presupuesto total se mira ANTES de cargar.
    const TOPE_LITERAL_BYTES = 16 * 1024 * 1024;
    Inc(BytesLeidos, TFile.GetSize(ARuta));
    if BytesLeidos > TOPE_LITERAL_BYTES then
      Exit(MsgFmt(SR_DESIGNER_LITERAL_TOPE_FMT, [TOPE_LITERAL_BYTES div (1024 * 1024)]));
    Doc := TStyleDoc.Create(ARuta); // tambien el binario, por el lector existente
    try
      Form := LineasDeForm(Doc.Lines);
      for var I := 0 to High(Doc.Lines) do
        if Form[I].Clase = clfPropiedad then
        begin
          Prop := Form[I].Prop;
          Valor := ValorEnteroDe(Doc.Lines, Form, I);
          if LeeLiteralDeForm(Valor, Texto) then
          begin
            Result := Comprueba(Prop, Texto);
            if Result <> '' then
              Exit;
          end
          else if Valor = '(' then
          begin
            // Strings de una lista: el mismo lector, no otra gramatica.
            Valor := '';
            for var K := I + 1 to Form[I].Fin - 1 do
            begin
              Valor := Valor + Doc.Lines[K].Trim;
              if Valor.EndsWith('+') then
                Continue;
              if LeeLiteralDeForm(Valor, Texto) then
              begin
                Result := Comprueba(Prop, Texto);
                if Result <> '' then
                  Exit;
              end;
              Valor := '';
            end;
          end;
        end;
    finally
      Doc.Free;
    end;
  end;

begin
  Result := '';
  BytesLeidos := 0;
  Bases := [TPath.GetDirectoryName(APeticion.Path),
    TPath.GetDirectoryName(APeticion.Salida)];
  try
    Result := CompruebaForm(APeticion.Path);
    if Result <> '' then
      Exit;
    // Los frames y ancestros que el ayudante puede resolver son hermanos.
    for var Hermano in WalkFiles(Bases[0], ['*' + ExtractFileExt(APeticion.Path)], False, False) do
      if not EsEnlace(Hermano) and not SameFileName(Hermano, APeticion.Path) then
      begin
        Result := CompruebaForm(Hermano);
        if Result <> '' then
          Exit;
      end;
    for var Estado in APeticion.Estados do
    begin
      var P := Pos('=', Estado);
      if P = 0 then
        Continue; // el lector de state dara su diagnostico de forma
      Prop := Copy(Estado, 1, P - 1).Trim;
      Valor := Copy(Estado, P + 1, MaxInt).Trim;
      Result := Comprueba(Prop, Valor); // state se entrega crudo a SetPropValue
      if Result = '' then
        if LeeLiteralDeForm(Valor, Texto) then
          Result := Comprueba(Prop, Texto);
      if Result <> '' then
        Exit;
    end;
  except
    Result := MsgText(SR_DESIGNER_LITERAL_NO_VERIFICABLE);
  end;
end;

function CorreRender(const APeticion: TPeticionRender): TRespuestaRender;
var
  Exe, Nombre, Orden, Salida, Fallo: string;
  Codigo: Cardinal;
  Reloj: TStopwatch;
begin
  Result := Default(TRespuestaRender);
  Result.Fallo := LiteralesDeRenderDenegados(APeticion);
  if Result.Fallo <> '' then
    Exit;
  Exe := FormRenderExe(APeticion.Framework, Nombre);
  if Exe = '' then
  begin
    Result.Fallo := MsgFmt(SR_DESIGNER_SIN_RENDER_FMT, [Nombre, ServerDir('')]);
    Exit;
  end;
  Fallo := ComponeOrdenDeRender(Exe, APeticion, Orden);
  if Fallo <> '' then
  begin
    Result.Fallo := Fallo;
    Exit;
  end;
  Reloj := TStopwatch.StartNew;
  try
    // en la carpeta del png: nada relativo del ayudante cae en la del servidor
    Salida := RunCapturedIn(Orden, TPath.GetDirectoryName(APeticion.Salida),
      RENDER_TIEMPO_MS, Codigo);
  except
    on E: Exception do
    begin
      Result.Fallo := MsgFmt(SR_DESIGNER_RENDER_NO_ARRANCA_FMT, [Nombre, E.Message]);
      Exit;
    end;
  end;
  Result := LeeRespuestaDeRender(Salida);
  Result.Codigo := Codigo;
  Result.MsTotal := Reloj.ElapsedMilliseconds;
  if (Codigo = FR_RC_OK) and (Result.Error = '') and TFile.Exists(APeticion.Salida) then
    Exit;
  if Result.Error <> '' then
    // con etiqueta (un estado que no existe, el vigia) sale tal cual
    Result.Fallo := MsgEnvuelve(SR_DESIGNER_RENDER_FALLO_FMT, Result.Error,
      [TPath.GetFileName(APeticion.Path), Result.Error])
  else if (Codigo = STATUS_DLL_NOT_FOUND_) or (Codigo = STATUS_ENTRYPOINT_NOT_FOUND_) or
    (Codigo = STATUS_INVALID_IMAGE_FORMAT_) then
    Result.Fallo := MsgFmt(SR_DESIGNER_RENDER_SIN_BPL_FMT, [Nombre, APeticion.Bds, Codigo])
  else if Result.MsTotal >= RENDER_TIEMPO_MS then
    Result.Fallo := MsgFmt(SR_DESIGNER_RENDER_TIEMPO_FMT, [Nombre, RENDER_TIEMPO_MS div 1000])
  else
    Result.Fallo := MsgFmt(SR_DESIGNER_RENDER_FALLO_FMT, [TPath.GetFileName(APeticion.Path),
      MsgFmt(SF_DESIGNER_RENDER_SIN_RESPUESTA_FMT, [Codigo, Copy(Salida.Trim, 1, 300)])]);
end;

end.
