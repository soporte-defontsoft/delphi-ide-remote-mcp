program McpDesktopNode;

{$APPTYPE CONSOLE}

{ UN NODO, DOS ESCRITORIOS. El mismo programa y las MISMAS ordenes sirven en
  Linux y en Windows; lo que cambia es con quien habla por debajo:
    Linux   -> portal XDG + libei + X11, cargados en caliente ([Mld.DBus],
               [Mld.Eis], [Mld.X11]). Hoy GNOME.
    Windows -> GDI y SendInput, que ya vienen con el sistema ([Mld.Win]).
  El escritor de PNG y el contrato de salida (CAPTURE=<ruta>) son comunes. }

uses
  System.SysUtils,
  System.IOUtils,
  System.StrUtils,
  System.Classes,
  Mld.Textos in 'Mld.Textos.pas', // EL catalogo de mensajes del nodo
{$IFDEF MSWINDOWS}
  Winapi.Windows,
  Mld.Captura in 'Mld.Captura.pas',
  Mld.Win in 'Mld.Win.pas';
{$ELSE}
  Mld.Dyn in 'Mld.Dyn.pas',
  Mld.DBus in 'Mld.DBus.pas',
  Mld.Teclado in 'Mld.Teclado.pas',
  Mld.Eis in 'Mld.Eis.pas',
  Mld.X11 in 'Mld.X11.pas',
  Mld.Sesion in 'Mld.Sesion.pas';
{$ENDIF}

const
{$I NodeKey.inc}
{$I NodeProtocolo.inc}

{ Los argumentos van DESPLAZADOS uno: el primero es la clave que prueba que
  llama el servidor MCP, y las ordenes empiezan detras. Todo el reparto de
  abajo habla por estas dos funciones y no se entera. }
function Arg(AIndice: Integer): string;
begin
  Result := ParamStr(AIndice + 1);
end;

function Args: Integer;
begin
  Result := ParamCount - 1;
  if Result < 0 then
    Result := 0;
end;

{ El pestillo: sin la clave del servidor, el nodo no mira ni toca nada.
  Ver NodeKey.inc para lo que esto protege de verdad (y lo que no). }
function LlamaElServidor: Boolean;
begin
  Result := ParamStr(1) = NODE_KEY;
end;

{$IFDEF MSWINDOWS}
{ ------------------------------------------------------------- WINDOWS --- }
procedure EjecutarWindows;
var
  Escritorio: TEscritorioWin;
  Ruta, Orden, Frase: string;
  ObjX, ObjY, I: Integer;
  Tecla: Word;
  Hizo: Boolean;

  procedure Instantanea;
  var
    Lista: TArray<TVentanaWin>;
    V: TVentanaWin;
  begin
    if Escritorio.Capturar(Ruta) then
    begin
      Writeln(NODO_CAPTURA, Ruta);
      { El camino normal (BitBlt del escritorio) fallo y la captura salio por
        el de respaldo: se dice, porque le faltan el cursor y el fondo. }
      if Escritorio.Respaldo <> '' then
        Writeln(MsgFmt(SN_NODE_RESPALDO_FMT, [Escritorio.Respaldo]));
      { La lista de ventanas viaja CON cada captura (David, 24-sep), en
        pixeles de la imagen. PROTEGIDA: si falla, falla la lista y se
        dice; la captura ya esta escrita y no se pierde por esto. }
      try
        Lista := Escritorio.Ventanas;
        Writeln(Format('  %d ' + NODO_VENTANAS, [Length(Lista)]));
        for V in Lista do
          Writeln(Format('  ' + NODO_VENTANA + '%d %d %d %d %s',
            [V.X, V.Y, V.Ancho, V.Alto, V.Titulo]));
      except
        on E: Exception do
          Writeln(MsgFmt(SN_NODE_VENTANAS_FALLO_LISTA_FMT, [E.Message]));
      end;
    end
    else
      Writeln('  ', NODO_NO_PUDE, ' ', Escritorio.Error);
  end;

begin
  { La salida va a un fichero que el servidor lee como UTF-8 estricto o, si
    no lo es, como CP1252: en ANSI un titulo con acento salia bien solo por
    ese respaldo. En UTF-8, como el nodo Linux, no depende de adivinar. }
  SetTextCodePage(Output, CP_UTF8);
  Ruta := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'captura.png');
  Escritorio := TEscritorioWin.Create;
  try
    Writeln(MsgText(SN_NODE_CONTROL_ESCRITORIO_WINDOWS));
    Writeln('  ', TOSVersion.ToString);
    Writeln(MsgFmt(SN_NODE_ESCRITORIO_PIXELES_ESCALA_FMT,
      [Escritorio.Ancho, Escritorio.Alto, FormatFloat('0.00', Escritorio.Escala)]));
    { Siempre, no solo al fallar: la captura del DC de pantalla se niega a
      ratos sin causa conocida (2026-09-22) y hay que poder comparar el
      estado de los casos buenos con el de los malos. }
    Writeln(MsgFmt(SF_NODE_ESTADO_FMT, [EstadoDelEscritorio]));
    Writeln;

    { Mismas ordenes que en Linux y mismas coordenadas: las de LA CAPTURA. }
    Orden := LowerCase(Arg(1));
    Hizo := False;
    if Orden = 'ventanas' then
    begin
      { En Windows no hace falta pedirle al escritorio que las ensene: la
        lista con titulo y sitio va CON CADA captura (24-sep), asi que esta
        orden solo vuelve a capturar, y con ella la lista al dia. }
      Writeln(MsgText(SN_NODE_VENTANAS_LISTA_CAPTURA));
      Hizo := True;
    end
    else if (Orden = 'escribe') and (Args >= 4) then
    begin
      ObjX := StrToIntDef(Arg(2), -1);
      ObjY := StrToIntDef(Arg(3), -1);
      Frase := '';
      for I := 4 to Args do
        Frase := Frase + IfThen(Frase = '', '', ' ') + Arg(I);
      Hizo := Escritorio.Pulsar(ObjX, ObjY);
      if not Hizo then
        Writeln(MsgFmt(SN_NODE_NO_PUDE_PULSAR_CAMPO_FMT, [Escritorio.Error]))
      else
      begin
        Sleep(250);
        Hizo := Escritorio.Escribir(Frase);
        if Hizo then
          Writeln(MsgFmt(SK_NODE_ESCRITO_EN_PIXEL_FMT, [Frase, ObjX, ObjY]))
        else
          Writeln(MsgFmt(SN_NODE_PULSE_BIEN_NO_ESCRIBIR_FMT, [Escritorio.Error]));
      end;
    end
    else if (Orden = 'texto') and (Args >= 2) then
    begin
      Frase := '';
      for I := 2 to Args do
        Frase := Frase + IfThen(Frase = '', '', ' ') + Arg(I);
      Hizo := Escritorio.Escribir(Frase);
      if Hizo then
        Writeln(MsgFmt(SK_NODE_ESCRITO_TECLEADO_FMT, [Frase]))
      else
        Writeln(MsgFmt(SN_NODE_NO_PUDE_ESCRIBIR_FMT, [Escritorio.Error]));
    end
    else if (Orden = 'tecla') and (Args >= 2) then
    begin
      { Por NOMBRE ('escape', 'enter'), que es lo mismo en los dos sistemas;
        un numero se toma como codigo virtual de Windows. VARIAS = una
        combinacion: se pulsan en orden y se sueltan al reves, asi que los
        modificadores van delante (tecla ctrl k = Ctrl+K). }
      var Teclas: TArray<Word> := nil;
      Tecla := 1;
      for I := 2 to Args do
      begin
        Tecla := TeclaPorNombre(Arg(I));
        if Tecla = 0 then
          Tecla := Word(StrToIntDef(Arg(I), 0));
        if Tecla = 0 then
          Break;
        Teclas := Teclas + [Tecla];
      end;
      if Tecla = 0 then
        Writeln(MsgFmt(SN_NODE_NO_CONOZCO_TECLA_FMT, [Arg(I)]))
      else
      begin
        Hizo := Escritorio.Combinacion(Teclas);
        if Hizo then
          Writeln(MsgFmt(SK_NODE_TECLA_ENVIADA_FMT, [Arg(Args),
            IfThen(Args > 2, MsgFmt(SF_NODE_CON_MODIFICADORES_FMT, [Args - 2]), '')]))
        else
          Writeln(MsgFmt(SN_NODE_NO_ENVIAR_TECLA_FMT, [Escritorio.Error]));
      end;
    end
    else if Orden = 'altab' then
    begin
      Hizo := Escritorio.Combinacion([TeclaPorNombre('alt'), TeclaPorNombre('tab')]);
      if Hizo then
        Writeln(MsgText(SK_NODE_ALT_TAB_ENVIADO))
      else
        Writeln(MsgFmt(SN_NODE_NO_ENVIAR_ALT_TAB_FMT, [Escritorio.Error]));
    end
    else if Args >= 2 then
    begin
      ObjX := StrToIntDef(Arg(1), -1);
      ObjY := StrToIntDef(Arg(2), -1);
      if (ObjX >= 0) and (ObjY >= 0) then
      begin
        Hizo := Escritorio.Pulsar(ObjX, ObjY);
        if Hizo then
          Writeln(MsgFmt(SK_NODE_CLIC_EN_PIXEL_FMT, [ObjX, ObjY]))
        else
          Writeln(MsgFmt(SN_NODE_NO_PUDE_PULSAR_FMT, [Escritorio.Error]));
      end;
    end
    else
    begin
      Writeln(MsgText(SN_NODE_USO_ENUMERA_VENTANAS));
    end;

    if Hizo then
      Sleep(400);
    Instantanea;
    Writeln;
    Writeln(MsgText(SN_NODE_NODO_LISTO));
  finally
    Escritorio.Free;
  end;
end;
{$ENDIF}

{$IFDEF LINUX}
function RecogerCaptura(const AOrigen: string): string;
begin
  { El portal escribe en ~/Imagenes del operador. El nodo se la lleva a SU
    carpeta (dentro del area de PAServer, de donde el servidor puede
    traersela) y borra la original: ni ensucia las carpetas del usuario ni
    deja copias sueltas. }
  Result := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'captura.png');
  try
    TFile.Copy(AOrigen, Result, True);
    TFile.Delete(AOrigen);
  except
    on E: Exception do
    begin
      Writeln(MsgFmt(SN_NODE_NO_RECOGER_CAPTURA_FMT, [E.Message]));
      Result := AOrigen;
    end;
  end;
end;

{ Ancho y alto de un PNG, de su IHDR (bytes 16..23, big-endian): lo que
  mide la captura, para convertir a sus pixeles lo que X11 cuenta. }
function TamanoPng(const ARuta: string; out AAncho, AAlto: Integer): Boolean;
var
  B: TBytes;
begin
  AAncho := 0;
  AAlto := 0;
  Result := False;
  try
    B := TFile.ReadAllBytes(ARuta);
  except
    Exit;
  end;
  if (Length(B) < 24) or (B[1] <> Ord('P')) or (B[2] <> Ord('N')) or (B[3] <> Ord('G')) then
    Exit;
  AAncho := (B[16] shl 24) or (B[17] shl 16) or (B[18] shl 8) or B[19];
  AAlto := (B[20] shl 24) or (B[21] shl 16) or (B[22] shl 8) or B[23];
  Result := (AAncho > 0) and (AAlto > 0);
end;

{ Sonda: abre una libreria del sistema y resuelve una muestra de simbolos.
  Es la prueba de que el nodo puede hablar con el escritorio sin enlazar
  nada en compilacion ni instalar nada en la maquina destino. }
procedure Sondear(const ALib: string; const ASimbolos: array of string);
var
  L: TLibreria;
  S: string;
  P: Pointer;
  Buenos, Total: Integer;
begin
  L := TLibreria.Create;
  try
    if not L.Abrir(ALib) then
    begin
      Writeln(MsgFmt(SN_NODE_NO_SE_PUDO_ABRIR_FMT, [ALib, L.Error]));
      Exit;
    end;
    Buenos := 0;
    Total := 0;
    for S in ASimbolos do
    begin
      Inc(Total);
      if L.Simbolo(S, P) then
        Inc(Buenos)
      else
        Writeln(MsgFmt(SF_NODE_AUSENTE_FMT, [S, L.Error]));
    end;
    Writeln(MsgFmt(SN_NODE_ABIERTA_SIMBOLOS_FMT, [ALib, Buenos, Total]));
  finally
    L.Free;
  end;
end;

{ --------------------------------------------------------------- LINUX --- }
procedure EjecutarLinux;
var
  Bus: TConexionBus;
  Manos: TManos;
  Pantallas: TArray<TPantalla>;
  Escala: Double;
  Captura, RutaSesion, RutaSc, Stream: string;
  Descriptor, ObjX, ObjY: Integer;
  Orden, Frase: string;
  Sesion: TSesionGrafica;
  I: Integer;
  Hizo: Boolean;
  Ojos: TOjos;
  SinOjos: Boolean;

  { La lista de ventanas que viaja CON la captura (David, 24-sep): detras de
    cada CAPTURE=, en el mismo formato que el nodo Windows y en pixeles de
    la imagen. Son los ojos X11: bajo Wayland ven lo que corre por Xwayland
    (toda aplicacion FMX), no las ventanas nativas Wayland. PROTEGIDA: si
    los ojos fallan, falla la lista y se dice; la captura ya esta escrita y
    no se pierde por esto. }
  procedure ListarVentanas(const ACaptura: string);
  var
    Lista: TArray<TVentana>;
    V: TVentana;
    RaizW, RaizH, CapW, CapH: Integer;
    FX, FY: Double;
  begin
    if SinOjos then
      Exit;
    try
      if Ojos = nil then
      begin
        Ojos := TOjos.Create;
        if not Ojos.Abrir then
        begin
          Writeln(MsgFmt(SN_NODE_VENTANAS_SIN_OJOS_FMT, [Ojos.Error]));
          SinOjos := True;
          Exit;
        end;
      end;
      if not Ojos.Principales(Lista) or not Ojos.TamanoRaiz(RaizW, RaizH) then
      begin
        Writeln(MsgFmt(SN_NODE_VENTANAS_NO_ENUMERARLAS_FMT, [Ojos.Error]));
        Exit;
      end;
      FX := 1;
      FY := 1;
      if TamanoPng(ACaptura, CapW, CapH) then
      begin
        FX := CapW / RaizW;
        FY := CapH / RaizH;
      end
      else
        Writeln(MsgText(SN_NODE_VENTANAS_SIN_CONVERTIR));
      Writeln(Format('  %d ' + NODO_VENTANAS, [Length(Lista)]));
      Writeln(MsgText(SN_NODE_NATIVAS_WAYLAND_NO_SALEN));
      for V in Lista do
        Writeln(Format('  ' + NODO_VENTANA + '%d %d %d %d %s',
          [Round(V.X * FX), Round(V.Y * FY), Round(V.Ancho * FX), Round(V.Alto * FY), V.Titulo]));
    except
      on E: Exception do
        Writeln(MsgFmt(SN_NODE_VENTANAS_FALLO_LISTA_CLASE_FMT, [E.ClassName, E.Message]));
    end;
  end;

begin
    Ojos := nil;
    SinOjos := False;
    Writeln(MsgText(SN_NODE_CONTROL_ESCRITORIO_LINUX));
    Writeln;

    Writeln(MsgText(SN_NODE_LIBRERIAS_DEL_SISTEMA));
    Sondear('libdbus-1.so.3', ['dbus_bus_get', 'dbus_error_init',
      'dbus_message_new_method_call', 'dbus_connection_send_with_reply_and_block',
      'dbus_message_iter_init', 'dbus_bus_get_unique_name']);
    Sondear('libei.so.1', ['ei_new_sender', 'ei_setup_backend_fd',
      'ei_configure_name', 'ei_dispatch', 'ei_get_fd', 'ei_get_event']);
    { Con que IDENTIDAD corre el nodo: el portal deduce la app-id de una
      aplicacion sin sandbox del nombre de su cgroup (app-...-<id>-....scope)
      y a ese nombre apunta el permiso de captura. Se dice para poder medirlo
      (decision 5, 24-sep-2026). }
    try
      // /proc declara tamano 0: ReadAllText devuelve vacio; se lee por flujo.
      if TFile.Exists('/proc/self/cgroup') then
        with TStreamReader.Create('/proc/self/cgroup') do
        try
          Writeln('  cgroup: ', ReadToEnd.Trim.Replace(#10, ' | '));
        finally
          Free;
        end;
    except
      // sin /proc no hay dato, y no es motivo para parar
    end;
    Writeln;

    { Sin sesion grafica de ESTE usuario el portal no contesta y el nodo se
      quedaba 20 s esperandole antes de decir nada (medido en Zorin el
      26-sep-2026). Se mira antes y se dice ya, con la linea que el
      servidor lee como motivo (Lsp.RemoteRun.MotivoSinCaptura). }
    Sesion := SesionGrafica;
    if not Sesion.Hay then
    begin
      Writeln('  ', NODO_NO_PUDE, ' ', Sesion.Motivo);
      Exit;
    end;
    Bus := TConexionBus.Create;
    try
      if not Bus.Conectar then
      begin
        Writeln(MsgFmt(SN_NODE_NO_HAY_ESCRITORIO_FMT, [Bus.Error]));
        Exit;
      end;

      Writeln(MsgText(SN_NODE_PANTALLA_ESCALA_CAPTURA));
      Escala := 1.0;
      if Bus.LeerPantallas(Pantallas) and (Length(Pantallas) > 0) then
      begin
        Escala := Pantallas[0].Escala;
        Writeln(MsgFmt(SN_NODE_ESCRITORIO_DICE_ESCALA_FMT, [FormatFloat('0.00', Escala)]));
      end
      else
        Writeln(MsgFmt(SN_NODE_NO_LEER_ESCALA_FMT, [Bus.Error]));
      if Bus.CapturarEscritorio(Captura, 20000) then
      begin
        Captura := RecogerCaptura(Captura);
        Writeln(NODO_CAPTURA, Captura);
        ListarVentanas(Captura);
      end
      else
      begin
        Writeln('  ', NODO_NO_PUDE, ' ', Bus.Error);
        Exit;
      end;
      Writeln;

      Writeln(MsgText(SN_NODE_LAS_MANOS));
      if not Bus.PrepararCanal(RutaSesion, RutaSc, Stream) then
      begin
        Writeln(MsgFmt(SN_NODE_NO_PREPARAR_CANAL_FMT, [Bus.Error]));
        Exit;
      end;
      try
        if not Bus.AbrirCanal(RutaSesion, Descriptor) then
        begin
          Writeln(MsgFmt(SN_NODE_NO_ABRIR_CANAL_FMT, [Bus.Error]));
          Exit;
        end;
        Manos := TManos.Create;
        try
          Manos.Escala := Escala;
          if not Manos.Abrir(Descriptor, 'mcp-linux-desktop', 6000) then
          begin
            Writeln(MsgFmt(SN_NODE_CANAL_NO_LISTO_FMT, [Manos.Error]));
            Exit;
          end;
          Writeln(MsgFmt(SN_NODE_LISTAS_PANTALLA_LOGICA_FMT,
            [Manos.Region.Ancho, Manos.Region.Alto, FormatFloat('0.00', Manos.Escala)]));
          { Las coordenadas son las de la CAPTURA: quien llama mide sobre la
            imagen y ya esta. La escala la aplica el nodo. }
          Orden := LowerCase(Arg(1));
          Hizo := False;
          if Orden = 'ventanas' then
          begin
            { Cuando varias ventanas se tapan, no vale con pulsar: hay que
              pedirle al escritorio que las ensene TODAS. La tecla Super abre
              la vista de actividades con cada ventana en miniatura, y
              entonces vuelve a ser un clic sobre algo visible. }
            Hizo := Manos.Combinacion([125]);
            if Hizo then
              Writeln(MsgText(SK_NODE_SUPER_ENVIADO))
            else
              Writeln(MsgFmt(SN_NODE_NO_ABRIR_VISTA_FMT, [Manos.Error]));
          end
          else if (Orden = 'escribe') and (Args >= 4) then
          begin
            { Un solo viaje: pulsa para dar el foco y teclea. Es el gesto
              real -"escribe esto ahi"- y paga el arranque UNA vez. }
            ObjX := StrToIntDef(Arg(2), -1);
            ObjY := StrToIntDef(Arg(3), -1);
            Frase := '';
            for I := 4 to Args do
              Frase := Frase + IfThen(Frase = '', '', ' ') + Arg(I);
            Hizo := Manos.Pulsar(ObjX, ObjY);
            if not Hizo then
              Writeln(MsgFmt(SN_NODE_NO_PUDE_PULSAR_CAMPO_FMT, [Manos.Error]))
            else
            begin
              Sleep(250);
              Hizo := Manos.Escribir(Frase);
              if Hizo then
                Writeln(MsgFmt(SK_NODE_ESCRITO_PIXEL_MAPA_FMT,
                  [Frase, ObjX, ObjY, Manos.MapaNota]))
              else
                Writeln(MsgFmt(SN_NODE_PULSE_BIEN_NO_ESCRIBIR_FMT, [Manos.Error]));
            end;
          end
          else if (Orden = 'texto') and (Args >= 2) then
          begin
            { Todo lo que venga detras es el texto, espacios incluidos. }
            Frase := '';
            for ObjX := 2 to Args do
              Frase := Frase + IfThen(Frase = '', '', ' ') + Arg(ObjX);
            Hizo := Manos.Escribir(Frase);
            if Hizo then
              Writeln(MsgFmt(SK_NODE_ESCRITO_TECLEADO_MAPA_FMT, [Frase, Manos.MapaNota]))
            else
              Writeln(MsgFmt(SN_NODE_NO_PUDE_ESCRIBIR_FMT, [Manos.Error]));
          end
          else if (Orden = 'tecla') and (Args >= 2) then
          begin
            { Teclas en codigo evdev: Escape 1, Tab 15, Enter 28. VARIAS =
              una combinacion, pulsadas en orden y soltadas al reves: los
              modificadores delante (tecla 29 37 = Ctrl+K). }
            var Codigos: TArray<Cardinal> := nil;
            for ObjX := 2 to Args do
              if StrToIntDef(Arg(ObjX), 0) > 0 then
                Codigos := Codigos + [Cardinal(StrToIntDef(Arg(ObjX), 0))];
            if Length(Codigos) < Args - 1 then
              Hizo := False
            else
              Hizo := Manos.Combinacion(Codigos);
            if Hizo then
              Writeln(MsgFmt(SK_NODE_TECLA_ENVIADA_FMT, [Arg(Args),
                IfThen(Args > 2, MsgFmt(SF_NODE_CON_MODIFICADORES_FMT, [Args - 2]), '')]))
            else
              Writeln(MsgFmt(SN_NODE_NO_ENVIAR_TECLA_FMT, [Manos.Error]));
          end
          else if Orden = 'altab' then
          begin
            { Alt+Tab: la via de teclado para cambiar de ventana. }
            Hizo := Manos.Combinacion([56, 15]);
            if Hizo then
              Writeln(MsgText(SK_NODE_ALT_TAB_ENVIADO))
            else
              Writeln(MsgFmt(SN_NODE_NO_ENVIAR_ALT_TAB_FMT, [Manos.Error]));
          end
          else if Args >= 2 then
          begin
            ObjX := StrToIntDef(Arg(1), -1);
            ObjY := StrToIntDef(Arg(2), -1);
            if (ObjX >= 0) and (ObjY >= 0) then
            begin
              Hizo := Manos.Pulsar(ObjX, ObjY);
              if Hizo then
                Writeln(MsgFmt(SK_NODE_CLIC_EN_PIXEL_FMT, [ObjX, ObjY]))
              else
                Writeln(MsgFmt(SN_NODE_NO_PUDE_PULSAR_FMT, [Manos.Error]));
            end;
          end
          else
          begin
            Writeln(MsgText(SN_NODE_USO_TECLA_EVDEV));
          end;
          if Hizo then
          begin
            Sleep(800);
            if Bus.CapturarEscritorio(Captura, 20000) then
            begin
              Captura := RecogerCaptura(Captura);
              Writeln(NODO_CAPTURA, Captura);
              ListarVentanas(Captura);
            end;
          end;
        finally
          Manos.Free;
        end;
      finally
        Bus.CerrarSesion(RutaSesion);
      end;
    finally
      Bus.Free;
      Ojos.Free;
    end;

    Writeln;
    Writeln(MsgText(SN_NODE_NODO_LISTO));
end;
{$ENDIF}

{ El nodo elige manos segun el sistema con el que se compilo. Anadir macOS
  (o cualquier otro) es escribir su unidad y su Ejecutar<Sistema>, y colgarlo
  de este mismo reparto: el protocolo de ordenes no cambia. }
begin
  try
    if not LlamaElServidor then
    begin
      Writeln(MsgText(SN_NODE_NO_SE_USA_MANO));
      Exit;
    end;
{$IF DEFINED(MSWINDOWS)}
    EjecutarWindows;
{$ELSEIF DEFINED(LINUX)}
    EjecutarLinux;
{$ELSE}
    Writeln(MsgText(SN_NODE_TODAVIA_NO_TIENE_MANOS));
{$ENDIF}
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
