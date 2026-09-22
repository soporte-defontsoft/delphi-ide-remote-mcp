program McpDesktopNode;

{$APPTYPE CONSOLE}

{ UN NODO, DOS ESCRITORIOS. El mismo programa y las MISMAS ordenes sirven en
  Linux y en Windows; lo que cambia es con quien habla por debajo:
    Linux   -> portal XDG + libei + X11, cargados en caliente ([Mld.DBus],
               [Mld.Eis], [Mld.X11]). Hoy GNOME.
    Windows -> GDI y SendInput, que ya vienen con el sistema ([Mld.Win]).
  El escritor de PNG y el contrato de salida (CAPTURA=<ruta>) son comunes. }

uses
  System.SysUtils,
  System.IOUtils,
  System.StrUtils,
{$IFDEF MSWINDOWS}
  Mld.Captura in 'Mld.Captura.pas',
  Mld.Win in 'Mld.Win.pas';
{$ELSE}
  Mld.Dyn in 'Mld.Dyn.pas',
  Mld.DBus in 'Mld.DBus.pas',
  Mld.Teclado in 'Mld.Teclado.pas',
  Mld.Eis in 'Mld.Eis.pas';
{$ENDIF}

const
{$I NodeKey.inc}

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
  Lista: TArray<TVentanaWin>;
  V: TVentanaWin;

  procedure Instantanea;
  begin
    if Escritorio.Capturar(Ruta) then
    begin
      Writeln('CAPTURA=', Ruta);
      { El camino normal (BitBlt del escritorio) fallo y la captura salio por
        el de respaldo: se dice, porque le faltan el cursor y el fondo. }
      if Escritorio.Respaldo <> '' then
        Writeln('  RESPALDO: ', Escritorio.Respaldo);
    end
    else
      Writeln('  NO pude capturar: ', Escritorio.Error);
  end;

begin
  Ruta := TPath.Combine(TPath.GetDirectoryName(ParamStr(0)), 'captura.png');
  Escritorio := TEscritorioWin.Create;
  try
    Writeln('McpDesktop - nodo de control del escritorio Windows');
    Writeln('  ', TOSVersion.ToString);
    Writeln(Format('  escritorio %dx%d pixeles, escala %.2f',
      [Escritorio.Ancho, Escritorio.Alto, Escritorio.Escala]));
    Writeln;

    { Mismas ordenes que en Linux y mismas coordenadas: las de LA CAPTURA. }
    Orden := LowerCase(Arg(1));
    Hizo := False;
    if Orden = 'ventanas' then
    begin
      { En Windows no hace falta pedirle al escritorio que las ensene: se
        pueden enumerar con titulo y sitio, que es mas util que una vista
        de miniaturas. Quien llama ya sabe donde pulsar. }
      Lista := Escritorio.Ventanas;
      Writeln(Format('  %d ventanas visibles:', [Length(Lista)]));
      for V in Lista do
        Writeln(Format('  VENTANA %d %d %d %d %s',
          [V.X, V.Y, V.Ancho, V.Alto, V.Titulo]));
      Hizo := Length(Lista) > 0;
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
        Writeln('  no pude pulsar en el campo: ', Escritorio.Error)
      else
      begin
        Sleep(250);
        Hizo := Escritorio.Escribir(Frase);
        if Hizo then
          Writeln(Format('  ESCRITO "%s" en el pixel (%d,%d)', [Frase, ObjX, ObjY]))
        else
          Writeln('  pulse bien pero no pude escribir: ', Escritorio.Error);
      end;
    end
    else if (Orden = 'texto') and (Args >= 2) then
    begin
      Frase := '';
      for I := 2 to Args do
        Frase := Frase + IfThen(Frase = '', '', ' ') + Arg(I);
      Hizo := Escritorio.Escribir(Frase);
      if Hizo then
        Writeln('  ESCRITO: ', Frase)
      else
        Writeln('  no pude escribir: ', Escritorio.Error);
    end
    else if (Orden = 'tecla') and (Args >= 2) then
    begin
      { Por NOMBRE ('escape', 'enter'), que es lo mismo en los dos sistemas;
        un numero se toma como codigo virtual de Windows. }
      Tecla := TeclaPorNombre(Arg(2));
      if Tecla = 0 then
        Tecla := Word(StrToIntDef(Arg(2), 0));
      if Tecla = 0 then
        Writeln('  no conozco la tecla ', Arg(2))
      else
      begin
        Hizo := Escritorio.Combinacion([Tecla]);
        if Hizo then
          Writeln('  TECLA ', Arg(2), ' enviada')
        else
          Writeln('  no pude enviar la tecla: ', Escritorio.Error);
      end;
    end
    else if Orden = 'altab' then
    begin
      Hizo := Escritorio.Combinacion([TeclaPorNombre('alt'), TeclaPorNombre('tab')]);
      if Hizo then
        Writeln('  ALT+TAB enviado')
      else
        Writeln('  no pude enviar Alt+Tab: ', Escritorio.Error);
    end
    else if Args >= 2 then
    begin
      ObjX := StrToIntDef(Arg(1), -1);
      ObjY := StrToIntDef(Arg(2), -1);
      if (ObjX >= 0) and (ObjY >= 0) then
      begin
        Hizo := Escritorio.Pulsar(ObjX, ObjY);
        if Hizo then
          Writeln(Format('  CLIC en el pixel (%d,%d) de la captura', [ObjX, ObjY]))
        else
          Writeln('  no pude pulsar: ', Escritorio.Error);
      end;
    end
    else
    begin
      Writeln('  uso: <x> <y>   pulsa en ese pixel de la captura');
      Writeln('       altab     cambia de ventana con el teclado');
      Writeln('       tecla <t> pulsa una tecla (escape, enter, tab, super...)');
      Writeln('       texto <t> escribe ese texto donde este el foco');
      Writeln('       escribe <x> <y> <t>  pulsa ahi Y escribe: un solo viaje');
      Writeln('       ventanas  enumera las ventanas visibles con su sitio');
    end;

    if Hizo then
      Sleep(400);
    Instantanea;
    Writeln;
    Writeln('nodo listo');
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
      Writeln('  aviso: no pude recoger la captura (', E.Message, ')');
      Result := AOrigen;
    end;
  end;
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
      Writeln(Format('  %-16s NO SE PUDO ABRIR: %s', [ALib, L.Error]));
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
        Writeln(Format('     AUSENTE %s (%s)', [S, L.Error]));
    end;
    Writeln(Format('  %-16s abierta, simbolos %d/%d', [ALib, Buenos, Total]));
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
  I: Integer;
  Hizo: Boolean;
begin
    Writeln('McpDesktop - nodo de control del escritorio Linux');
    Writeln;

    Writeln('-- 1. librerias del sistema (nada que instalar) --');
    Sondear('libdbus-1.so.3', ['dbus_bus_get', 'dbus_error_init',
      'dbus_message_new_method_call', 'dbus_connection_send_with_reply_and_block',
      'dbus_message_iter_init', 'dbus_bus_get_unique_name']);
    Sondear('libei.so.1', ['ei_new_sender', 'ei_setup_backend_fd',
      'ei_configure_name', 'ei_dispatch', 'ei_get_fd', 'ei_get_event']);
    Writeln;

    Bus := TConexionBus.Create;
    try
      if not Bus.Conectar then
      begin
        Writeln('NO hay escritorio al que hablar: ', Bus.Error);
        Exit;
      end;

      Writeln('-- 2. la pantalla: escala y captura --');
      Escala := 1.0;
      if Bus.LeerPantallas(Pantallas) and (Length(Pantallas) > 0) then
      begin
        Escala := Pantallas[0].Escala;
        Writeln(Format('  el escritorio dice que su escala es %.2f', [Escala]));
      end
      else
        Writeln('  no pude leer la escala, asumo 1,00: ', Bus.Error);
      if Bus.CapturarEscritorio(Captura, 20000) then
      begin
        Captura := RecogerCaptura(Captura);
        Writeln('CAPTURA=', Captura);
      end
      else
      begin
        Writeln('  NO pude capturar: ', Bus.Error);
        Exit;
      end;
      Writeln;

      Writeln('-- 3. las manos --');
      if not Bus.PrepararCanal(RutaSesion, RutaSc, Stream) then
      begin
        Writeln('  no pude preparar el canal: ', Bus.Error);
        Exit;
      end;
      try
        if not Bus.AbrirCanal(RutaSesion, Descriptor) then
        begin
          Writeln('  no pude abrir el canal: ', Bus.Error);
          Exit;
        end;
        Manos := TManos.Create;
        try
          Manos.Escala := Escala;
          if not Manos.Abrir(Descriptor, 'mcp-linux-desktop', 6000) then
          begin
            Writeln('  el canal no llego a estar listo: ', Manos.Error);
            Exit;
          end;
          Writeln(Format('  listas. pantalla logica %dx%d, escala %.2f',
            [Manos.Region.Ancho, Manos.Region.Alto, Manos.Escala]));
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
              Writeln('  SUPER enviado: vista de todas las ventanas')
            else
              Writeln('  no pude abrir la vista: ', Manos.Error);
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
              Writeln('  no pude pulsar en el campo: ', Manos.Error)
            else
            begin
              Sleep(250);
              Hizo := Manos.Escribir(Frase);
              if Hizo then
                Writeln(Format('  ESCRITO "%s" en el pixel (%d,%d)  [%s]',
                  [Frase, ObjX, ObjY, Manos.MapaNota]))
              else
                Writeln('  pulse bien pero no pude escribir: ', Manos.Error);
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
              Writeln('  ESCRITO: ', Frase, '  [', Manos.MapaNota, ']')
            else
              Writeln('  no pude escribir: ', Manos.Error);
          end
          else if (Orden = 'tecla') and (Args >= 2) then
          begin
            { Una tecla suelta, en codigo evdev: Escape 1, Tab 15, Enter 28. }
            Hizo := Manos.Combinacion([StrToIntDef(Arg(2), 0)]);
            if Hizo then
              Writeln('  TECLA ', Arg(2), ' enviada')
            else
              Writeln('  no pude enviar la tecla: ', Manos.Error);
          end
          else if Orden = 'altab' then
          begin
            { Alt+Tab: la via de teclado para cambiar de ventana. }
            Hizo := Manos.Combinacion([56, 15]);
            if Hizo then
              Writeln('  ALT+TAB enviado')
            else
              Writeln('  no pude enviar Alt+Tab: ', Manos.Error);
          end
          else if Args >= 2 then
          begin
            ObjX := StrToIntDef(Arg(1), -1);
            ObjY := StrToIntDef(Arg(2), -1);
            if (ObjX >= 0) and (ObjY >= 0) then
            begin
              Hizo := Manos.Pulsar(ObjX, ObjY);
              if Hizo then
                Writeln(Format('  CLIC en el pixel (%d,%d) de la captura', [ObjX, ObjY]))
              else
                Writeln('  no pude pulsar: ', Manos.Error);
            end;
          end
          else
          begin
            Writeln('  uso: <x> <y>   pulsa en ese pixel de la captura');
            Writeln('       altab     cambia de ventana con el teclado');
            Writeln('       tecla <n> pulsa una tecla (evdev: Escape 1, Enter 28)');
            Writeln('       texto <t> escribe ese texto donde este el foco');
            Writeln('       escribe <x> <y> <t>  pulsa ahi Y escribe: un solo viaje');
            Writeln('       ventanas  ensena TODAS las ventanas (tecla Super),');
            Writeln('                 para cuando se tapan entre ellas');
            Writeln('  (para dar el foco a una ventana, pulsa en su barra de titulo)');
          end;
          if Hizo then
          begin
            Sleep(800);
            if Bus.CapturarEscritorio(Captura, 20000) then
            begin
              Captura := RecogerCaptura(Captura);
              Writeln('CAPTURA=', Captura);
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
    end;

    Writeln;
    Writeln('nodo listo');
end;
{$ENDIF}

{ El nodo elige manos segun el sistema con el que se compilo. Anadir macOS
  (o cualquier otro) es escribir su unidad y su Ejecutar<Sistema>, y colgarlo
  de este mismo reparto: el protocolo de ordenes no cambia. }
begin
  try
    if not LlamaElServidor then
    begin
      Writeln('McpDesktopNode - nodo de escritorio del Delphi IDE Remote MCP.');
      Writeln('  Este programa no se usa a mano: lo lanza el servidor MCP, que');
      Writeln('  es quien decide (por workspace) si un agente puede ver y tocar');
      Writeln('  este escritorio. Sin esa llamada no hace nada.');
      Exit;
    end;
{$IF DEFINED(MSWINDOWS)}
    EjecutarWindows;
{$ELSEIF DEFINED(LINUX)}
    EjecutarLinux;
{$ELSE}
    Writeln('McpDesktop - este sistema todavia no tiene manos en el nodo');
    Writeln('  (hoy: Linux con GNOME y Windows; macOS seria el siguiente)');
{$ENDIF}
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
