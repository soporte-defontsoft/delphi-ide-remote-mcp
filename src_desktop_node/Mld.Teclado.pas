unit Mld.Teclado;

{ EL MAPA DE TECLADO del escritorio: que tecla hay que pulsar para que salga
  un caracter, preguntandoselo a quien lo sabe.

  Un codigo evdev es una POSICION del teclado, no un caracter. El nodo tecleaba
  con una tabla fija de teclado AMERICANO, y en un escritorio en espanol la
  tecla 12 no es '-' sino la comilla: "1015-14" salia "1015'14" y el nodo
  contestaba que lo habia escrito bien (medido contra el Fedora de David el
  2026-09-21). El teclado numerico, que parecia la salida barata, tampoco
  vale: el teclado virtual de libei no entrega esas teclas y el caracter se
  PIERDE sin aviso (medido el mismo dia).

  Lo que si vale: el propio canal de entrada (libei) entrega el mapa de
  teclado del escritorio como texto XKB, y libxkbcommon -que esta en todo
  escritorio Wayland, porque el compositor depende de ella- sabe leerlo. Se
  recorre una vez y se apunta, para cada caracter, la tecla y el NIVEL en que
  aparece: 0 = sola, 1 = con Mayusculas, 2 = con AltGr, 3 = con las dos.

  Nada se instala en el destino: las dos librerias se abren en caliente, como
  el resto del nodo, y si alguna falta el nodo sigue con la tabla de siempre. }

interface

uses
  System.Generics.Collections,
  Mld.Dyn;

type
  TPulsacion = record
    Codigo: Cardinal;  // evdev (el keycode de XKB menos 8)
    Nivel: Integer;    // 0 sola, 1 Mayus, 2 AltGr, 3 Mayus+AltGr
  end;

  TMapaTeclado = class
  private
    FLib: TLibreria;
    FTeclas: TDictionary<Cardinal, TPulsacion>; // por punto de codigo Unicode
    FMuertas: TDictionary<Cardinal, TPulsacion>; // por keysym XKB de tecla MUERTA (dead_acute...)
    FError: string;
    FDistribucion: string;
  public
    constructor Create;
    destructor Destroy; override;
    { ATexto: el mapa XKB tal como lo entrega el escritorio (acabado en #0). }
    function Cargar(ATexto: Pointer): Boolean;
    function Buscar(ACaracter: Cardinal; out APulsacion: TPulsacion): Boolean;
    { Las pulsaciones que dan un caracter: una si el teclado lo tiene directo,
      DOS si sale por tecla muerta (la muerta y luego la base: "´" + "i" =
      "í"), como lo teclea una persona en un teclado espanol. False si no
      hay forma. Medido: hasta el 2026-09-22 "í" se rechazaba en el layout
      Spanish, que la tiene por tecla muerta (informe de Hermes). }
    function Secuencia(ACaracter: Cardinal; out APulsaciones: TArray<TPulsacion>): Boolean;
    function Cuantas: Integer;
    function CuantasMuertas: Integer;
    property Distribucion: string read FDistribucion;
    property Error: string read FError;
  end;

implementation

uses
  System.SysUtils;

const
  XKB_FORMATO_TEXTO_V1 = 1;

type
  TXkbCtxNuevo = function(AFlags: Integer): Pointer; cdecl;
  TXkbCtxUnref = procedure(ACtx: Pointer); cdecl;
  TXkbMapaDeTexto = function(ACtx: Pointer; ATexto: Pointer;
    AFormato, AFlags: Integer): Pointer; cdecl;
  TXkbMapaUnref = procedure(AMapa: Pointer); cdecl;
  TXkbMapaCodigo = function(AMapa: Pointer): Cardinal; cdecl;
  TXkbNiveles = function(AMapa: Pointer; ATecla, ADistrib: Cardinal): Cardinal; cdecl;
  TXkbSimbolos = function(AMapa: Pointer; ATecla, ADistrib, ANivel: Cardinal;
    out ASimbolos: PCardinal): Integer; cdecl;
  TXkbAUnicode = function(ASimbolo: Cardinal): Cardinal; cdecl;
  TXkbNombreDistrib = function(AMapa: Pointer; AIdx: Cardinal): MarshaledAString; cdecl;

const
  { Keysyms XKB de las teclas muertas (xkbcommon-keysyms.h). }
  XKB_DEAD_MIN = $FE50;
  XKB_DEAD_MAX = $FE5D;

  { Signo diacritico combinante (Unicode) -> keysym de la tecla muerta que lo
    pone. }
  DIACRITICOS: array[0..12] of array[0..1] of Cardinal = (
    ($0300, $FE50),  // grave
    ($0301, $FE51),  // agudo (acute)
    ($0302, $FE52),  // circunflejo
    ($0303, $FE53),  // virgulilla (tilde)
    ($0304, $FE54),  // macron
    ($0306, $FE55),  // breve
    ($0307, $FE56),  // punto superior
    ($0308, $FE57),  // dieresis
    ($030A, $FE58),  // anillo
    ($030B, $FE59),  // doble agudo
    ($030C, $FE5A),  // caron
    ($0327, $FE5B),  // cedilla
    ($0328, $FE5C)); // ogonek

  { Caracter precompuesto -> letra base + diacritico combinante. Latin-1
    Supplement y Latin Extended-A (U+00C0..U+017F), 161 filas GENERADAS de
    la descomposicion canonica de Unicode (unicodedata, Python), no
    escritas a mano: (precompuesto, base, combinante). }
  DESCOMPOSICION: array[0..160] of array[0..2] of Cardinal = (
    (192, 65, $0300), (193, 65, $0301), (194, 65, $0302), (195, 65, $0303), (196, 65, $0308), (197, 65, $030A), (199, 67, $0327), (200, 69, $0300), (201, 69, $0301), (202, 69, $0302), (203, 69, $0308), (204, 73, $0300), (205, 73, $0301), (206, 73, $0302), (207, 73, $0308), (209, 78, $0303), (210, 79, $0300), (211, 79, $0301), (212, 79, $0302), (213, 79, $0303), (214, 79, $0308), (217, 85, $0300), (218, 85, $0301), (219, 85, $0302), (220, 85, $0308), (221, 89, $0301), (224, 97, $0300), (225, 97, $0301), (226, 97, $0302), (227, 97, $0303), (228, 97, $0308), (229, 97, $030A), (231, 99, $0327), (232, 101, $0300), (233, 101, $0301), (234, 101, $0302), (235, 101, $0308), (236, 105, $0300), (237, 105, $0301), (238, 105, $0302), (239, 105, $0308), (241, 110, $0303), (242, 111, $0300), (243, 111, $0301), (244, 111, $0302), (245, 111, $0303), (246, 111, $0308), (249, 117, $0300), (250, 117, $0301), (251, 117, $0302), (252, 117, $0308), (253, 121, $0301), (255, 121, $0308), (256, 65, $0304), (257, 97, $0304), (258, 65, $0306), (259, 97, $0306), (260, 65, $0328), (261, 97, $0328), (262, 67, $0301), (263, 99, $0301), (264, 67, $0302), (265, 99, $0302), (266, 67, $0307), (267, 99, $0307), (268, 67, $030C), (269, 99, $030C), (270, 68, $030C), (271, 100, $030C), (274, 69, $0304), (275, 101, $0304), (276, 69, $0306), (277, 101, $0306), (278, 69, $0307), (279, 101, $0307), (280, 69, $0328), (281, 101, $0328), (282, 69, $030C), (283, 101, $030C), (284, 71, $0302), (285, 103, $0302), (286, 71, $0306), (287, 103, $0306), (288, 71, $0307), (289, 103, $0307), (290, 71, $0327), (291, 103, $0327), (292, 72, $0302), (293, 104, $0302), (296, 73, $0303), (297, 105, $0303), (298, 73, $0304), (299, 105, $0304), (300, 73, $0306), (301, 105, $0306), (302, 73, $0328), (303, 105, $0328), (304, 73, $0307), (308, 74, $0302), (309, 106, $0302), (310, 75, $0327), (311, 107, $0327), (313, 76, $0301), (314, 108, $0301), (315, 76, $0327), (316, 108, $0327), (317, 76, $030C), (318, 108, $030C), (323, 78, $0301), (324, 110, $0301), (325, 78, $0327), (326, 110, $0327), (327, 78, $030C), (328, 110, $030C), (332, 79, $0304), (333, 111, $0304), (334, 79, $0306), (335, 111, $0306), (336, 79, $030B), (337, 111, $030B), (340, 82, $0301), (341, 114, $0301), (342, 82, $0327), (343, 114, $0327), (344, 82, $030C), (345, 114, $030C), (346, 83, $0301), (347, 115, $0301), (348, 83, $0302), (349, 115, $0302), (350, 83, $0327), (351, 115, $0327), (352, 83, $030C), (353, 115, $030C), (354, 84, $0327), (355, 116, $0327), (356, 84, $030C), (357, 116, $030C), (360, 85, $0303), (361, 117, $0303), (362, 85, $0304), (363, 117, $0304), (364, 85, $0306), (365, 117, $0306), (366, 85, $030A), (367, 117, $030A), (368, 85, $030B), (369, 117, $030B), (370, 85, $0328), (371, 117, $0328), (372, 87, $0302), (373, 119, $0302), (374, 89, $0302), (375, 121, $0302), (376, 89, $0308), (377, 90, $0301), (378, 122, $0301), (379, 90, $0307), (380, 122, $0307), (381, 90, $030C), (382, 122, $030C));

constructor TMapaTeclado.Create;
begin
  inherited Create;
  FLib := TLibreria.Create;
  FTeclas := TDictionary<Cardinal, TPulsacion>.Create;
  FMuertas := TDictionary<Cardinal, TPulsacion>.Create;
end;

destructor TMapaTeclado.Destroy;
begin
  FMuertas.Free;
  FTeclas.Free;
  FLib.Free;
  inherited;
end;

function TMapaTeclado.CuantasMuertas: Integer;
begin
  Result := FMuertas.Count;
end;

function TMapaTeclado.Secuencia(ACaracter: Cardinal;
  out APulsaciones: TArray<TPulsacion>): Boolean;
var
  Directa, Muerta, Base: TPulsacion;
  I, J: Integer;
  Combinante, Keysym: Cardinal;
begin
  APulsaciones := nil;
  if FTeclas.TryGetValue(ACaracter, Directa) then
  begin
    APulsaciones := [Directa];
    Exit(True);
  end;
  Result := False;
  if FMuertas.Count = 0 then
    Exit;
  for I := Low(DESCOMPOSICION) to High(DESCOMPOSICION) do
    if DESCOMPOSICION[I][0] = ACaracter then
    begin
      Combinante := DESCOMPOSICION[I][2];
      Keysym := 0;
      for J := Low(DIACRITICOS) to High(DIACRITICOS) do
        if DIACRITICOS[J][0] = Combinante then
          Keysym := DIACRITICOS[J][1];
      if (Keysym <> 0) and FMuertas.TryGetValue(Keysym, Muerta) and
         FTeclas.TryGetValue(DESCOMPOSICION[I][1], Base) then
      begin
        APulsaciones := [Muerta, Base];
        Exit(True);
      end;
      Exit;
    end;
end;

function TMapaTeclado.Cuantas: Integer;
begin
  Result := FTeclas.Count;
end;

function TMapaTeclado.Buscar(ACaracter: Cardinal; out APulsacion: TPulsacion): Boolean;
begin
  Result := FTeclas.TryGetValue(ACaracter, APulsacion);
end;

function TMapaTeclado.Cargar(ATexto: Pointer): Boolean;
var
  CtxNuevo: TXkbCtxNuevo;
  CtxUnref: TXkbCtxUnref;
  MapaDeTexto: TXkbMapaDeTexto;
  MapaUnref: TXkbMapaUnref;
  CodigoMin, CodigoMax: TXkbMapaCodigo;
  Niveles: TXkbNiveles;
  Simbolos: TXkbSimbolos;
  AUnicode: TXkbAUnicode;
  NombreDistrib: TXkbNombreDistrib;
  Ctx, Mapa, Dir: Pointer;
  Tecla, Nivel, Cuantos, Car: Cardinal;
  N: Integer;
  Lista: PCardinal;
  P: TPulsacion;

  function Uno(const ASimbolo: string; out ADir: Pointer): Boolean;
  begin
    Result := FLib.Simbolo(ASimbolo, ADir);
    if not Result then
      FError := Format('falta %s en libxkbcommon (%s)', [ASimbolo, FLib.Error]);
  end;

begin
  Result := False;
  FTeclas.Clear;
  FMuertas.Clear;
  if ATexto = nil then
  begin
    FError := 'el escritorio no entrego mapa de teclado';
    Exit;
  end;
  if not FLib.Abierta and not FLib.Abrir('libxkbcommon.so.0') then
  begin
    FError := 'no pude abrir libxkbcommon.so.0 (' + FLib.Error + ')';
    Exit;
  end;
  if not (Uno('xkb_context_new', Dir)) then Exit;
  CtxNuevo := TXkbCtxNuevo(Dir);
  if not (Uno('xkb_context_unref', Dir)) then Exit;
  CtxUnref := TXkbCtxUnref(Dir);
  if not (Uno('xkb_keymap_new_from_string', Dir)) then Exit;
  MapaDeTexto := TXkbMapaDeTexto(Dir);
  if not (Uno('xkb_keymap_unref', Dir)) then Exit;
  MapaUnref := TXkbMapaUnref(Dir);
  if not (Uno('xkb_keymap_min_keycode', Dir)) then Exit;
  CodigoMin := TXkbMapaCodigo(Dir);
  if not (Uno('xkb_keymap_max_keycode', Dir)) then Exit;
  CodigoMax := TXkbMapaCodigo(Dir);
  if not (Uno('xkb_keymap_num_levels_for_key', Dir)) then Exit;
  Niveles := TXkbNiveles(Dir);
  if not (Uno('xkb_keymap_key_get_syms_by_level', Dir)) then Exit;
  Simbolos := TXkbSimbolos(Dir);
  if not (Uno('xkb_keysym_to_utf32', Dir)) then Exit;
  AUnicode := TXkbAUnicode(Dir);
  if not (Uno('xkb_keymap_layout_get_name', Dir)) then Exit;
  NombreDistrib := TXkbNombreDistrib(Dir);

  Ctx := CtxNuevo(0);
  if Ctx = nil then
  begin
    FError := 'xkb_context_new devolvio nil';
    Exit;
  end;
  try
    Mapa := MapaDeTexto(Ctx, ATexto, XKB_FORMATO_TEXTO_V1, 0);
    if Mapa = nil then
    begin
      FError := 'libxkbcommon no entendio el mapa del escritorio';
      Exit;
    end;
    try
      if NombreDistrib(Mapa, 0) <> nil then
        FDistribucion := string(UTF8String(NombreDistrib(Mapa, 0)));
      // Solo la distribucion 0, la primera de la lista del usuario. Los
      // niveles, del mas simple al mas rebuscado: si un caracter sale en
      // varias teclas gana la que menos modificadores pide.
      for Nivel := 0 to 3 do
        for Tecla := CodigoMin(Mapa) to CodigoMax(Mapa) do
        begin
          if Tecla < 8 then
            Continue;
          Cuantos := Niveles(Mapa, Tecla, 0);
          if Nivel >= Cuantos then
            Continue;
          Lista := nil;
          N := Simbolos(Mapa, Tecla, 0, Nivel, Lista);
          if (N <> 1) or (Lista = nil) then
            Continue; // ninguno, o una tecla que emite varios simbolos
          // Una tecla MUERTA no da caracter (xkb_keysym_to_utf32 = 0): se
          // apunta por su keysym, para componer tildes con ella.
          if (Lista^ >= XKB_DEAD_MIN) and (Lista^ <= XKB_DEAD_MAX) then
          begin
            if not FMuertas.ContainsKey(Lista^) then
            begin
              P.Codigo := Tecla - 8;
              P.Nivel := Nivel;
              FMuertas.Add(Lista^, P);
            end;
            Continue;
          end;
          Car := AUnicode(Lista^);
          if (Car < 32) or (Car = 127) then
            Continue; // sin caracter (modificadores, flechas...) o de control
          // El teclado NUMERICO se salta: repite cifras y signos, y el
          // teclado virtual de libei no entrega sus teclas (medido).
          if (Tecla - 8 >= 71) and (Tecla - 8 <= 83) then
            Continue;
          if (Tecla - 8 = 55) or (Tecla - 8 = 98) or (Tecla - 8 = 96) or
             (Tecla - 8 = 117) then
            Continue;
          if FTeclas.ContainsKey(Car) then
            Continue;
          P.Codigo := Tecla - 8;
          P.Nivel := Nivel;
          FTeclas.Add(Car, P);
        end;
      Result := FTeclas.Count > 0;
      if not Result then
        FError := 'el mapa del escritorio no trae ningun caracter';
    finally
      MapaUnref(Mapa);
    end;
  finally
    CtxUnref(Ctx);
  end;
end;

end.
