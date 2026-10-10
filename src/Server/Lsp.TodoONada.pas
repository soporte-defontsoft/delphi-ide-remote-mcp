unit Lsp.TodoONada;

{ TODO O NADA: la foto de los ficheros que una operacion va a tocar
  (TFotoDeFicheros) y el envoltorio que la deshace si algo falla a medias
  (FicherosTodoONada): lo que devuelve los bytes, los atributos, las
  carpetas recien creadas y lo que no existia. La usan las tandas de
  ediciones, el changeset, los cambios de proyecto y el disenador.

  Sale de Lsp.Guard el 8-oct-2026 (la 1.18.0, la version de la limpieza),
  movida sin cambiar una linea. Va ENCIMA de la jaula: para deshacer
  pregunta a las puertas de escritura (EscrituraDenegada) y usa los
  escritores de Lsp.Guard y, para devolver unos bytes, el atomico de la
  jaula (Lsp.Patch.EscribeBytes); nada de Lsp.Guard la usa a ella. }

interface

{ Tamano y fecha de escritura de un fichero SIN abrirlo (FindFirst): se leen
  aunque otro proceso lo tenga abierto sin compartir. False si no esta. La
  usan la foto de los escritores y la de la carpeta de un test. }
function HuellaDeFichero(const ARuta: string; out ATam: Int64;
  out AFecha: TDateTime): Boolean;

type
  { LA FOTO de unos ficheros ANTES de tocarlos, y su vuelta atras: el "todo
    o nada" de la tanda de edits, del commit de un changeset y de
    add-platform con sdk/perfil. Estaba escrita tres veces, solo una se
    protegia de una excepcion y ninguna de un deshacer que fallara (un
    fichero que otro proceso tiene abierto: el deshacer lanzaba y el
    changeset se quedaba colgado). Revision 27-sep-2026. }
  TFotoDeFicheros = record
  private
    FRutas: TArray<string>;
    FExistian: TArray<Boolean>;
    FBytes: TArray<TArray<Byte>>;
    // lo que dejo la operacion en cada ruta (Anota): lo UNICO que el deshacer
    // puede dar por suyo
    FAnotado: TArray<Boolean>;
    FExisteNuestro: TArray<Boolean>;
    FNuestros: TArray<TArray<Byte>>;
    // tamano y fecha de la foto: se leen aunque otro proceso tenga el fichero
    // abierto sin compartir, y dicen si cambio cuando los bytes no se pueden leer
    FTam: TArray<Int64>;
    FFecha: TArray<TDateTime>;
    // de una ruta que no existia: la primera carpeta que SI existia por
    // encima (lo que la operacion cree debajo, el deshacer lo quita si vacio)
    FAncestro: TArray<string>;
    // otro la cambio ENTRE dos pasos de la operacion (Vigila): el deshacer no
    // la toca, porque lleva trabajo ajeno mezclado
    FAjeno: TArray<Boolean>;
    // sus atributos en la foto: el deshacer devuelve el +R (un fichero
    // reescrito o que vuelve de un move lo perdia; decima revision)
    FAtrib: TArray<Cardinal>;
  public
    { Lee los bytes de cada ruta (la que no existe se apunta como tal). }
    procedure Toma(const ARutas: array of string);
    { Apunta como esta AHORA una ruta de la foto: lo que la operacion acaba de
      dejar en ella. Se llama tras cada paso hecho. Nunca lanza: si no puede
      leerla, la ruta queda sin apuntar (el deshacer la trata como siempre). }
    procedure Anota(const ARuta: string);
    { Antes de cada paso: si el disco ya no es lo ultimo que se sabe de la
      ruta (la foto, o lo que dejo el paso anterior), otro la cambio entre
      medias - otro proceso, que el cerrojo solo ordena a los de este - y el
      paso siguiente lo absorberia como propio. Se marca y el deshacer la deja
      y lo dice (quinta revision: 15 de 15 veces se perdia). Nunca lanza. }
    procedure Vigila(const ARuta: string);
    { Deja cada fichero como estaba en la foto, por la puerta de escritura:
      solo los que CAMBIARON, y el que no existia, fuera. Lo que otro cambio
      DESPUES de que la operacion lo escribiera (el disco ya no tiene lo
      apuntado) no se toca: se dice. Nunca lanza: lo que no volvio lo
      devuelve, uno por linea con su porque ('' = todo volvio). Perder una
      edicion ajena con OK es peor que un deshacer incompleto que lo dice
      (David, 27-sep-2026). }
    function Restaura: string;
    function Cuantos: Integer;
    { Cuantas rutas de la foto son HOY distintas de como estaban (existir
      o no, o sus bytes). Una que no se puede leer cuenta como distinta.
      Para decir UNCHANGED cuando una operacion no cambio nada. }
    function Cambiados: Integer;
  end;

type
  { Lo que se hace bajo FicherosTodoONada: un exito, o un fallo (EsFallo). }
  TAccionTodoONada = reference to function: string;

{ Una operacion sobre varios ficheros TODO O NADA: la foto de ARutas antes,
  y si AAccion lanza o devuelve un fallo, cada fichero vuelve como estaba (lo
  que no pudo volver se dice, con el motivo del fallo). Estaba escrita en
  ProyectoTodoONada para el .dpr y el .dproj; el form y su unidad de
  delphi_designer insert/delete eran la segunda copia (1.17.0). }
function FicherosTodoONada(const ARutas: array of string;
  const AAccion: TAccionTodoONada): string;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.StrUtils,
  System.IOUtils,
  Lsp.Texts,
  Lsp.Codificacion,     // BytesIguales, el comparador
  Lsp.Patch,            // EscribeBytes: el escritor atomico de la jaula, para devolver
  Lsp.Guard;            // las puertas de escritura y los escritores que deshacen

{ Tamano y fecha de escritura de un fichero SIN abrirlo (FindFirst): se leen
  aunque otro proceso lo tenga abierto sin compartir. False si no esta. }
function HuellaDeFichero(const ARuta: string; out ATam: Int64;
  out AFecha: TDateTime): Boolean;
var
  SR: TSearchRec;
begin
  ATam := -1;
  AFecha := 0;
  Result := FindFirst(ARuta, faAnyFile, SR) = 0;
  if Result then
    try
      ATam := SR.Size;
      AFecha := SR.TimeStamp;
    finally
      FindClose(SR);
    end;
end;

procedure TFotoDeFicheros.Toma(const ARutas: array of string);
var
  I: Integer;
begin
  SetLength(FRutas, Length(ARutas));
  SetLength(FExistian, Length(ARutas));
  SetLength(FBytes, Length(ARutas));
  SetLength(FAnotado, Length(ARutas));
  SetLength(FExisteNuestro, Length(ARutas));
  SetLength(FNuestros, Length(ARutas));
  SetLength(FTam, Length(ARutas));
  SetLength(FFecha, Length(ARutas));
  SetLength(FAncestro, Length(ARutas));
  SetLength(FAjeno, Length(ARutas));
  SetLength(FAtrib, Length(ARutas));
  // una foto a medias no es una foto: si una ruta no se deja leer (otro
  // proceso la tiene sin compartir), la foto queda VACIA y se lanza. Con la
  // mitad tomada, el deshacer borraba lo que no llego a leer (FExistian en
  // falso) y vaciaba lo que leyo a medias (28-sep-2026)
  try
    for I := 0 to High(ARutas) do
    begin
      FRutas[I] := ARutas[I];
      FAnotado[I] := False;
      FAjeno[I] := False;
      FExistian[I] := TFile.Exists(ARutas[I]);
      FAtrib[I] := GetFileAttributes(PChar(ARutas[I]));
      if FExistian[I] then
      begin
        FBytes[I] := TFile.ReadAllBytes(ARutas[I]);
        HuellaDeFichero(ARutas[I], FTam[I], FFecha[I]);
      end
      else
      begin
        FBytes[I] := nil;
        FAncestro[I] := PrimerAncestroQueExiste(ExtractFileDir(ARutas[I]));
      end;
    end;
  except
    SetLength(FRutas, 0);
    raise;
  end;
end;

procedure TFotoDeFicheros.Anota(const ARuta: string);
var
  I: Integer;
begin
  for I := 0 to High(FRutas) do
    if SameText(FRutas[I], ARuta) then
    try
      FAnotado[I] := False;
      FExisteNuestro[I] := TFile.Exists(FRutas[I]);
      if FExisteNuestro[I] then
        FNuestros[I] := TFile.ReadAllBytes(FRutas[I])
      else
        FNuestros[I] := nil;
      FAnotado[I] := True;
    except
      // sin apuntar: el deshacer la trata como siempre
    end;
end;

procedure TFotoDeFicheros.Vigila(const ARuta: string);
var
  I: Integer;
  Existe, Esperado: Boolean;
  Ahora, Sabido: TArray<Byte>;
begin
  for I := 0 to High(FRutas) do
    if SameText(FRutas[I], ARuta) and not FAjeno[I] then
    try
      // lo ultimo que se sabe de ella: lo que dejo el paso anterior, o la foto
      if FAnotado[I] then
      begin
        Esperado := FExisteNuestro[I];
        Sabido := FNuestros[I];
      end
      else
      begin
        Esperado := FExistian[I];
        Sabido := FBytes[I];
      end;
      Existe := TFile.Exists(FRutas[I]);
      Ahora := nil;
      if Existe then
        Ahora := TFile.ReadAllBytes(FRutas[I]);
      FAjeno[I] := (Existe <> Esperado) or (Existe and not BytesIguales(Ahora, Sabido));
    except
      // no se puede leer: el paso fallara o no; el deshacer lo mirara
    end;
end;

function TFotoDeFicheros.Restaura: string;

  function Iguales(const A, B: TArray<Byte>): Boolean;
  begin
    Result := BytesIguales(A, B);
  end;

var
  I: Integer;
  NoVolvio: Boolean;

  { Las carpetas que la operacion creo por encima de una ruta que no existia
    (un create en a\b\c.txt): se quitaban el fichero y quedaban a y b vacias.
    RemoveDir solo quita una carpeta VACIA; por la puerta de escritura. }
  procedure QuitaCarpetasNuevas(AIx: Integer);
  begin
    QuitaCarpetasCreadas(ExtractFileDir(FRutas[AIx]), FAncestro[AIx]);
  end;

  function MismaHuella(AIx: Integer): Boolean;
  var
    T: Int64;
    D: TDateTime;
  begin
    Result := HuellaDeFichero(FRutas[AIx], T, D) and (T = FTam[AIx]) and (D = FFecha[AIx]);
  end;

  { UNA ruta de la foto: '' si esta como en la foto (o volvio); si no, el
    motivo. Lo que no existia se borra, salvo si algo no volvio (NoVolvio). }
  function Devuelve(AIx: Integer): string;
  var
    Ahora: TArray<Byte>;
    Existe: Boolean;
    Veto, Ilegible: string;
  begin
    Result := '';
    Existe := TFile.Exists(FRutas[AIx]);
    Ahora := nil;
    Ilegible := '';
    if Existe then
      try
        Ahora := TFile.ReadAllBytes(FRutas[AIx]);
      except
        on E: Exception do
          Ilegible := E.Message;
      end;
    // No se puede LEER (otro proceso lo tiene sin compartir): si su tamano
    // y su fecha son los de la foto, no cambio y no hay nada que devolver.
    // Se contaba como "no volvio" un fichero intacto (verificacion de la
    // tercera ronda, medido: 38 de 44). Si cambio, ni se comprueba ni se
    // escribe: se dice.
    if Ilegible <> '' then
    begin
      if not (FExistian[AIx] and MismaHuella(AIx)) then
        Result := Ilegible;
      Exit;
    end;
    // lo que no cambio no se toca: un fichero que otro proceso tiene
    // abierto y nadie modifico no hace fallar el deshacer
    if (Existe = FExistian[AIx]) and (not Existe or Iguales(Ahora, FBytes[AIx])) then
    begin
      if not FExistian[AIx] then
        QuitaCarpetasNuevas(AIx);
      Exit;
    end;
    // deshacer tambien escribe: por la misma puerta. Un camino que dejo de
    // ser escribible no se restaura por el, y se DICE (se saltaba callado)
    Veto := EscrituraDenegada(FRutas[AIx]);
    if Veto <> '' then
      Exit(Veto);
    // otro la cambio ENTRE dos pasos: lleva su trabajo mezclado con el de
    // la operacion, y deshacer se lo llevaria (Vigila)
    if FAjeno[AIx] then
      Exit(MsgText(SF_FOTO_CAMBIADO_DURANTE));
    // lo que hay NO es lo que dejo la operacion: alguien lo cambio despues
    // (otro proceso, el IDE guardando). Se queda como esta y se dice; el
    // deshacer borraba o pisaba su trabajo contestando "todo volvio"
    // (verificacion de la tercera revision, 27-sep-2026, medido)
    if FAnotado[AIx] and ((Existe <> FExisteNuestro[AIx]) or
       (Existe and not Iguales(Ahora, FNuestros[AIx]))) then
      Exit(MsgText(SF_FOTO_CAMBIADO_POR_OTRO));
    // lo que la operacion dejo puede traer el +R de un original (un move,
    // una copia): se quita para borrarlo o reescribirlo, y el fichero
    // vuelve con el atributo de la foto (decima revision)
    if not FExistian[AIx] then
    begin
      // lo CREADO no se borra si algo que debia volver no volvio: puede ser la
      // UNICA copia - el destino de un move cuyo origen no se pudo devolver
      // (revisor de la noche, A-1: se borraba sin papelera y el contenido
      // solo quedaba en memoria)
      if NoVolvio then
        Exit(MsgText(SF_FOTO_LO_CREADO_SE_QUEDA));
      BorraLoNuestro(FRutas[AIx]);
      QuitaCarpetasNuevas(AIx);
      Exit;
    end;
    QuitaSoloLectura(FRutas[AIx]);
    try
      // entero o nada, por EL escritor de la jaula (el temporal al lado y el
      // renombre, con su puerta y su cerrojo): WriteAllBytes truncaba y
      // escribia encima, y un fallo a medias (disco lleno, otro proceso)
      // dejaba a medias justo el fichero que se queria devolver (P4 de la
      // 1.18.0). Una ruta que no cabe con su temporal (GUARD-028: anade 27
      // caracteres) se escribe directa, como antes: la operacion ya se llevo
      // el original, y no devolverlo es peor (revisor de la noche, A-1 y M-1);
      // la puerta ya la aprobo arriba (Veto)
      if RutaLargaDenegada(FRutas[AIx]) <> '' then
        TFile.WriteAllBytes(FRutas[AIx], FBytes[AIx])
      else
        EscribeBytes(FRutas[AIx], FBytes[AIx], ltJaula);
    finally
      // el +R de la foto vuelve tambien si la escritura fallo (B-10)
      var A := GetFileAttributes(PChar(FRutas[AIx]));
      if (A <> INVALID_FILE_ATTRIBUTES) and (FAtrib[AIx] <> INVALID_FILE_ATTRIBUTES) and
         ((FAtrib[AIx] and FILE_ATTRIBUTE_READONLY) <> 0) then
        SetFileAttributes(PChar(FRutas[AIx]), A or FILE_ATTRIBUTE_READONLY);
    end;
  end;

begin
  Result := '';
  NoVolvio := False;
  // primero lo que EXISTIA (se devuelve), despues lo que la operacion creo (se
  // borra): asi, si algo no volvio, lo creado se queda (A-1)
  for var Pasada := 0 to 1 do
    for I := 0 to High(FRutas) do
    begin
      if FExistian[I] <> (Pasada = 0) then
        Continue;
      var Motivo := '';
      try
        Motivo := Devuelve(I);
      except
        on E: Exception do
          Motivo := E.Message;
      end;
      if Motivo <> '' then
      begin
        Result := Result + IfThen(Result <> '', #10, '') + '  ' + FRutas[I] + ': ' + Motivo;
        if Pasada = 0 then
          NoVolvio := True;
      end;
    end;
end;

function TFotoDeFicheros.Cuantos: Integer;
begin
  Result := Length(FRutas);
end;

function TFotoDeFicheros.Cambiados: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(FRutas) do
    if FExistian[I] <> TFile.Exists(FRutas[I]) then
      Inc(Result)
    else if FExistian[I] then
      try
        if not BytesIguales(TFile.ReadAllBytes(FRutas[I]), FBytes[I]) then
          Inc(Result);
      except
        Inc(Result); // no se puede leer: no se da por igual
      end;
end;

function FicherosTodoONada(const ARutas: array of string;
  const AAccion: TAccionTodoONada): string;
var
  NoVolvio: string;
  Foto: TFotoDeFicheros;
begin
  Foto.Toma(ARutas);
  try
    Result := AAccion();
  except
    on E: Exception do
    begin
      NoVolvio := Foto.Restaura;
      if NoVolvio <> '' then
        raise Exception.Create(MsgFmt(SR_FOTO_NO_VOLVIO_FMT,
          [NoVolvio, MsgExcepcion(E.ClassName, E.Message)]));
      raise;
    end;
  end;
  if EsFallo(Result) then
  begin
    NoVolvio := Foto.Restaura;
    if NoVolvio <> '' then
      Result := MsgFmt(SR_FOTO_NO_VOLVIO_FMT, [NoVolvio, Result]);
  end;
end;

end.