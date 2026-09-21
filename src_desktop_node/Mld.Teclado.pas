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
    FError: string;
    FDistribucion: string;
  public
    constructor Create;
    destructor Destroy; override;
    { ATexto: el mapa XKB tal como lo entrega el escritorio (acabado en #0). }
    function Cargar(ATexto: Pointer): Boolean;
    function Buscar(ACaracter: Cardinal; out APulsacion: TPulsacion): Boolean;
    function Cuantas: Integer;
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

constructor TMapaTeclado.Create;
begin
  inherited Create;
  FLib := TLibreria.Create;
  FTeclas := TDictionary<Cardinal, TPulsacion>.Create;
end;

destructor TMapaTeclado.Destroy;
begin
  FTeclas.Free;
  FLib.Free;
  inherited;
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
