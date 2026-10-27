unit FormRender.Fmx;

{ DelphiFormRenderFmx: un .fmx (form o frame) -> un PNG de lo que ensena el
  designer FMX. La form se crea en modo diseno y pinta su arbol sobre un
  bitmap (TCustomForm.PaintTo): sin ventana, sin DWM, tambien desde un
  servicio (en sesion 0 FMX cae solo de Direct2D a GDI+). El estilo se aplica
  como lo aplica una aplicacion: un TStyleBook EN la form (nunca el global de
  TStyleManager, que pierde los glyphs; medido), y en modo diseno con el
  gancho de plataforma del designer, que acepta cualquier plataforma.

    --style ''            lo que traiga el .fmx (= el designer)
    --style none          sin StyleBook: el estilo por defecto de Windows
    --style f.style       ese fichero en un TStyleBook de la form
    --style android|ios|ios-dark|osx|linux|gnome|win7|win8|win10|win11|mobile
                          el "Style" del desplegable del designer: los RCDATA
                          de fmx370.bpl / fmxdesigner370.bpl, abiertos como datos

  Nada sale al escritorio del servidor: los servicios de dialogo de FMX se
  retiran al arrancar (FMX.Forms.SetStyleBook lanzaba un ShowMessage y se
  quedaba esperando el Aceptar; medido 6-oct-2026). }

interface

function Main: Integer;

implementation

uses
  FormRender.Comun, FormRender.Textos,
  Winapi.Windows, System.SysUtils, System.Classes, System.Types, System.UITypes,
  System.Diagnostics, System.IOUtils,
  FMX.Types, FMX.Forms, FMX.Controls, FMX.Graphics, FMX.Styles, FMX.Objects,
  FMX.StdCtrls, FMX.Layouts, FMX.Edit, FMX.Memo, FMX.ListBox, FMX.ComboEdit,
  FMX.TabControl, FMX.ListView, FMX.Grid, FMX.ImgList, FMX.Ani, FMX.Effects,
  FMX.Menus, FMX.ScrollBox, FMX.SpinBox, FMX.NumberBox, FMX.TreeView, FMX.Colors,
  FMX.MultiView, FMX.ActnList, FMX.DateTimeCtrls, FMX.Controls.Presentation,
  FMX.ExtCtrls, FMX.Calendar, FMX.EditBox, FMX.SearchBox, FMX.Platform, FMX.Filter.Effects,
  FMX.MediaLibrary.Actions, FMX.StdActns, FMX.WebBrowser, FMX.Media, FMX.Gestures,
  FMX.Controls.Model, FMX.Presentation.Style, FMX.Dialogs, FMX.DialogService,
  FMX.Platform.Win;

type
  { Un rectangulo con el nombre de la clase que no existe en ningun paquete }
  TSustituto = class(TRectangle)
  end;

  // Realign y GetTabStopController son protegidos: los del juez son los de FMX
  TFormCrack = class(TCustomForm);
  TControlCrack = class(TControl);

  TCargadorFmx = class(TCargador)
  protected
    function ClaseSustituto: TComponentClass; override;
    function CreaSustituto(AOwner: TComponent; const AClase: string): TComponent; override;
    function ClaseFrame: TComponentClass; override;
  end;

{ TCargadorFmx }

function TCargadorFmx.ClaseSustituto: TComponentClass;
begin
  Result := TSustituto;
end;

function TCargadorFmx.CreaSustituto(AOwner: TComponent; const AClase: string): TComponent;
var
  T: TText;
begin
  Result := TSustituto.Create(AOwner);
  with TSustituto(Result) do
  begin
    Fill.Color := $FFFFC0C0;
    Stroke.Color := TAlphaColors.Red;
    T := TText.Create(Result);
    T.Parent := TSustituto(Result);
    T.Align := TAlignLayout.Client;
    T.Text := AClase;
    T.HitTest := False;
  end;
end;

function TCargadorFmx.ClaseFrame: TComponentClass;
begin
  Result := TFrame;
end;

{ Las clases estandar de FMX, desde el uses }
procedure RegistraEstandar;
begin
  Apunta([TLabel, TButton, TSpeedButton, TCheckBox, TRadioButton, TGroupBox,
    TPanel, TEdit, TMemo, TListBox, TListBoxItem, TListBoxGroupHeader, TListBoxHeader,
    TComboBox, TComboEdit, TTrackBar, TSwitch,
    TProgressBar, TAniIndicator, TArcDial, TExpander, TScrollBar, TSmallScrollBar, TSizeGrip,
    TStatusBar, TToolBar, TLayout, TScaledLayout, TGridLayout, TGridPanelLayout, TFlowLayout,
    TScrollBox, TVertScrollBox, THorzScrollBox, TFramedScrollBox, TFramedVertScrollBox, TSplitter,
    TTabControl, TTabItem, TListView, TGrid, TStringGrid, TTreeView, TTreeViewItem,
    TImageList, TGlyph, TPopupMenu, TMainMenu, TMenuItem, TMenuBar, TActionList, TAction,
    TMultiView, TStyleBook, TCalendar, TDateEdit, TTimeEdit, TSpinBox, TNumberBox, TSearchBox,
    TColorBox, TColorPanel, TColorPicker, TComboColorBox, TColorListBox, TColorComboBox,
    TPopupBox, TClearingEdit, TPathLabel, TTrackBar, TCornerButton, TPopup, TFrame,
    TRectangle, TRoundRect, TEllipse, TCircle, TArc, TPie, TLine, TPath,
    TText, TImage, TCalloutRectangle, TCalloutPanel, TPaintBox, TSelection, TSelectionPoint,
    TImageControl, TDropTarget, TPlotGrid, TImageViewer,
    TFloatAnimation, TColorAnimation, TGradientAnimation, TRectAnimation,
    TBitmapAnimation, TBitmapListAnimation, TPathAnimation, TFloatKeyAnimation, TColorKeyAnimation,
    TShadowEffect, TBlurEffect, TGlowEffect, TInnerGlowEffect, TBevelEffect, TReflectionEffect,
    TTimer, TGestureManager, TWebBrowser, TMediaPlayer, TMediaPlayerControl,
    TOpenDialog, TSaveDialog,
    TStringColumn, TIntegerColumn, TFloatColumn, TCurrencyColumn, TDateColumn, TTimeColumn,
    TDateTimeColumn, TCheckColumn, TProgressColumn, TPopupColumn, TImageColumn, TGlyphColumn,
    TTimeColumn, TColumn]);
end;

{ En ejecucion FMX rechaza un estilo cuyo PlatformTarget no lleve [MSWINDOWS]
  y cae al defecto; el designer instala un gancho que lo acepta
  (CheckPlatformTargetAtDesignTime en FMX.Controls). Igual aqui. }
function AceptaCualquierPlataforma(const PlatformTarget: string): Boolean;
begin
  Result := True;
end;

{ El "Style" del desplegable del designer -> recurso RCDATA y su BPL. UNA tabla. }
function RecursoDePlataforma(const ANombre: string; out ABpl, ARecurso: string): Boolean;
const
  TABLA: array[0..10, 0..2] of string = (
    ('win7', 'fmx370.bpl', 'WIN7STYLE'), ('win8', 'fmx370.bpl', 'WIN8STYLE'),
    ('win10', 'fmx370.bpl', 'WIN10STYLE'), ('win11', 'fmx370.bpl', 'WIN11STYLE'),
    ('mobile', 'fmx370.bpl', 'MOBILEPREVIEWSTYLE'),
    ('android', 'fmxdesigner370.bpl', 'ANDROIDSTYLE'), ('ios', 'fmxdesigner370.bpl', 'IOSSTYLE'),
    ('ios-dark', 'fmxdesigner370.bpl', 'IOS15DARKSTYLE'), ('osx', 'fmxdesigner370.bpl', 'OSXSTYLE'),
    ('linux', 'fmxdesigner370.bpl', 'UBUNTUSTYLE'), ('gnome', 'fmxdesigner370.bpl', 'GNOMESTYLE'));
begin
  for var I := Low(TABLA) to High(TABLA) do
    if SameText(TABLA[I, 0], ANombre) then
    begin
      ABpl := TABLA[I, 1].Replace('370', GPeticion.Bds.Replace('.', ''));
      ARecurso := TABLA[I, 2];
      Exit(True);
    end;
  Result := False;
end;

function NombresDePlataforma: string;
begin
  Result := 'windows|win7|win8|win10|win11|mobile|android|ios|ios-dark|osx|linux|gnome';
end;

{ Cuantos items del StyleBook llevan un estilo: uno vacio (Styles = < item
  end>) cuenta en Styles.Count y no pinta nada. Lo dice el propio item
  (TStyleCollectionItem.IsEmpty). }
function EstilosConContenido(ASB: TStyleBook): Integer;
begin
  Result := 0;
  for var I := 0 to ASB.Styles.Count - 1 do
    if not ASB.Styles[I].IsEmpty then
      Inc(Result);
end;

{ Lo que lleva la form ella misma (lo que vera la app), para la coletilla
  de un style= de la peticion }
function LoQueLlevaLaForm(AForm: TForm): string;
begin
  if AForm.StyleBook = nil then
    Exit(MsgText(SF_RENDER_LLEVA_NADA));
  var N := EstilosConContenido(AForm.StyleBook);
  if N = 0 then
    Exit(MsgFmt(SF_RENDER_LLEVA_VACIO_FMT, [AForm.StyleBook.Name]));
  Result := MsgFmt(SF_RENDER_LLEVA_ESTILOS_FMT, [AForm.StyleBook.Name, N]);
end;

{ Aplica --style a la form: '' = lo suyo; none = sin StyleBook; fichero;
  plataforma del designer. Devuelve la descripcion para STYLE=; con un
  --style, termina diciendo lo que lleva la form (solo esta imagen lo usa). }
function AplicaEstilo(AForm: TForm): string;
var
  SB: TStyleBook;
  Bpl, Recurso, Lleva: string;
  Modulo: HMODULE;
  Res: TResourceStream;
begin
  if GPeticion.Estilo = '' then
  begin
    if AForm.StyleBook = nil then
      Exit('none (the form has no StyleBook: Windows default, as the designer)');
    if EstilosConContenido(AForm.StyleBook) = 0 then
      Exit(MsgFmt(SF_RENDER_ESTILO_PROPIO_VACIO_FMT, [AForm.StyleBook.Name, AForm.StyleBook.Styles.Count]));
    Exit(MsgFmt(SF_RENDER_ESTILO_PROPIO_FMT, [AForm.StyleBook.Name, AForm.StyleBook.Styles.Count]));
  end;
  Lleva := LoQueLlevaLaForm(AForm);
  if SameText(GPeticion.Estilo, 'none') or SameText(GPeticion.Estilo, 'windows') then
  begin
    AForm.StyleBook := nil;
    Exit(MsgFmt(SF_RENDER_ESTILO_SOLO_ESTA_IMAGEN_FMT, ['none (Windows default, as the designer)', Lleva]));
  end;
  if TFile.Exists(GPeticion.Estilo) then
  begin
    SB := TStyleBook.Create(AForm);
    SB.LoadFromFile(GPeticion.Estilo);
    AForm.StyleBook := SB;
    Exit(MsgFmt(SF_RENDER_ESTILO_SOLO_ESTA_IMAGEN_FMT, ['file ' + ExtractFileName(GPeticion.Estilo), Lleva]));
  end;
  if not RecursoDePlataforma(GPeticion.Estilo, Bpl, Recurso) then
    raise ERender.Create(MsgFmt(SR_RENDER_ESTILO_DESCONOCIDO_FMT, [GPeticion.Estilo, NombresDePlataforma]));
  Bpl := RaizDelIde(GPeticion.Bds) + 'bin\' + Bpl;
  // el BPL se abre como DATOS: nada suyo se ejecuta
  Modulo := LoadLibraryEx(PChar(Bpl), 0, LOAD_LIBRARY_AS_DATAFILE);
  if Modulo = 0 then
    raise ERender.Create(MsgFmt(SR_RENDER_ESTILO_NO_ABRE_FMT, [Bpl]));
  Res := TResourceStream.Create(Modulo, Recurso, RT_RCDATA);
  try
    SB := TStyleBook.Create(AForm);
    SB.LoadFromStream(Res);
    AForm.StyleBook := SB;
  finally
    Res.Free;
  end;
  Result := MsgFmt(SF_RENDER_ESTILO_SOLO_ESTA_IMAGEN_FMT, [Format('designer platform style %s (%s of %s)',
    [GPeticion.Estilo.ToLower, Recurso, ExtractFileName(Bpl)]), Lleva]);
end;

{ Los no visuales como los ensena el designer: icono en su Left/Top y el nombre debajo }
function DibujaNoVisuales(ARaiz: TComponent; ABmp: TBitmap): Integer;
const
  LADO = 28;
var
  Png: TBytes;
  Icono: TBitmap;
  M: TMemoryStream;
  P: TPoint;
  R: TRectF;
begin
  Result := 0;
  if not ABmp.Canvas.BeginScene then
    Exit;
  try
    ABmp.Canvas.Font.Family := 'Segoe UI';
    ABmp.Canvas.Font.Size := 9;
    ABmp.Canvas.Stroke.Kind := TBrushKind.Solid;
    ABmp.Canvas.Stroke.Color := TAlphaColors.Gray;
    for var C in NoVisualesDe(ARaiz, TControl) do
    begin
      P := PosicionDeNoVisual(C);
      R := TRectF.Create(P.X, P.Y, P.X + LADO, P.Y + LADO);
      ABmp.Canvas.Fill.Color := TAlphaColors.White;
      ABmp.Canvas.FillRect(R, 0, 0, [], 1);
      ABmp.Canvas.DrawRect(R, 0, 0, [], 1);
      if IconoPngDeClase(C.ClassName, Png) then
      begin
        Icono := TBitmap.Create;
        M := TMemoryStream.Create;
        try
          M.WriteBuffer(Png[0], Length(Png));
          M.Position := 0;
          Icono.LoadFromStream(M);
          ABmp.Canvas.DrawBitmap(Icono, TRectF.Create(0, 0, Icono.Width, Icono.Height),
            TRectF.Create(P.X + 2, P.Y + 2, P.X + LADO - 2, P.Y + LADO - 2), 1);
        finally
          M.Free;
          Icono.Free;
        end;
      end
      else
      begin
        ABmp.Canvas.Fill.Color := TAlphaColors.Black;
        ABmp.Canvas.FillText(R, C.ClassName.Substring(1, 3), False, 1, [], TTextAlign.Center, TTextAlign.Center);
      end;
      ABmp.Canvas.Fill.Color := TAlphaColors.Black;
      ABmp.Canvas.FillText(TRectF.Create(P.X - 40, P.Y + LADO, P.X + LADO + 40, P.Y + LADO + 14), C.Name,
        False, 1, [], TTextAlign.Center, TTextAlign.Leading);
      Inc(Result);
    end;
  finally
    ABmp.Canvas.EndScene;
  end;
end;

{ El nombre como lee la RTL una referencia (FindNestedComponent): uno de
  dentro de un frame inline va como Marco1.LblAviso (revision de la 1.17.0) }
function RectDe(AForm: TForm; ARaiz: TComponent; const ANombre: string; out R: TRect): Boolean;
var
  C: TComponent;
  P: TPoint;
  RF: TRectF;
begin
  Result := False;
  C := ComponenteDeRuta(ARaiz, ANombre);
  if C = nil then
    C := ComponenteDeRuta(AForm, ANombre);
  if C = nil then
    Exit;
  if C is TControl then
  begin
    RF := TControl(C).AbsoluteRect;
    R := Rect(Round(RF.Left), Round(RF.Top), Round(RF.Right), Round(RF.Bottom));
    Result := True;
  end
  else
    // un no visual esta en la imagen solo si se dibujan (nonvisual=true) y es
    // de la raiz, como en el designer: el de un frame metido no se ensena, y
    // su "rect" era un trozo de form cualquiera (segunda revision de la 1.17.0)
    if GPeticion.NoVisuales then
      for var N in NoVisualesDe(ARaiz, TControl) do
        if N = C then
        begin
          P := PosicionDeNoVisual(C);
          R := Rect(P.X, P.Y, P.X + 28, P.Y + 28 + 14);
          Exit(True);
        end;
end;

{ Crea la form de diseno y lee el fichero (form o frame) en ella }
function CreaYLee(ACargador: TCargador; out ARaiz: TComponent): TForm;
var
  Frame: TFrame;
  Cab: TCabecera;
begin
  // el grupo de clases de FMX, como lo activa el designer FMX del IDE: un
  // paquete VCL cargado activa el suyo (Vcl.Controls, Vcl.ActnList...) y
  // GetClass solo busca en el activo (corpus, 18-oct-2026)
  ActivateClassGroup(TFmxObject);
  Cab := Cabecera(GPeticion.Path);
  Result := TForm.CreateNew(nil);
  try
    PonEnDiseno(Result);
    if EsFrame(GPeticion.Path, Cab.Clase, TFrame) then // el que se crea aqui abajo
    begin
      Frame := TFrame.Create(Result);
      PonEnDiseno(Frame);
      ARaiz := Frame;
      ACargador.LeeRaiz(GPeticion.Path, Cab.Nombre, Frame);
      Result.ClientWidth := Round(Frame.Width);
      Result.ClientHeight := Round(Frame.Height);
      Frame.Parent := Result;
      Frame.Position.Point := PointF(0, 0);
    end
    else
    begin
      ARaiz := Result;
      ACargador.LeeRaiz(GPeticion.Path, Cab.Nombre, Result);
    end;
  except
    // la que no se pudo leer no se queda: con --packages auto se lee otra
    Result.Free;
    raise;
  end;
end;

{ El form leido como lo tiene el disenador, antes de que lo escriba su
  TWriter:
  - ALINEADO: la VCL alinea al cargar; FMX no alinea lo que cuelga del form
    hasta que algo lo realinea (la preview, al pintar), y un TPanel
    Align=Bottom se escribia en 10,10 sin su tamano y al cargar se estiraba
    (V68). TCustomForm.Realign da lo que pinta la preview y lo que escribe el
    IDE (Mobile Tasks, FormMain.fmx:94-99; medido el 27-oct-2026). Lo de
    dentro de un control ya lo alinea el suyo al cargar.
  - el SOLTADO (--dropped: insert, set parent=) EN EL TABULADOR de su padre:
    FMX solo mete un hijo en esa lista fuera de la lectura
    (TControl.DoAddObject, not csReading), y el servidor lo pregunta sin su
    linea TabOrder (SinSuTabOrder) para que el IDE le de la suya: sin lista no
    habia TabOrder que escribir y valia el respaldo, que no ve los hermanos de
    un ancestro - 0 junto al 0 heredado (V72). Lo que hace soltarlo en el
    disenador: TabList.Add, el ultimo. Solo el soltado: uno que ya estaba sin
    TabOrder (un form escrito a mano) lo sigue guardando sin el, como el IDE. }
procedure ComoLoTieneElDisenador(AForm: TForm; ARaiz: TComponent);
var
  Controlador: ITabStopController;
begin
  TFormCrack(AForm).Realign;
  if GPeticion.Soltado = '' then
    Exit;
  var C := ComponenteDeRuta(ARaiz, GPeticion.Soltado);
  if not (C is TControl) then
    Exit;
  Controlador := TControlCrack(C).GetTabStopController;
  if (Controlador <> nil) and (Controlador.TabList.GetTabOrder(TControl(C)) < 0) then
    Controlador.TabList.Add(TControl(C));
end;

function Main: Integer;
var
  Uso, Error: string;
  Cargador: TCargador;
  F: TForm;
  Raiz: TComponent;
  Bmp: TBitmap;
  Reloj: TStopwatch;
  MsCarga, MsPintado, Cargados, Conocidos: Integer;
  R: TRect;
  // mientras lee el form (lo que falle ahi y sea del lector es el fichero:
  // NOTLOADED=) y si lo leido ya se dijo (RespondeFallo, DSGN-061 de la 1.20)
  Cargando, YaLeido: Boolean;
begin
  Cargando := False;
  YaLeido := False;
  Error := ParseaArgumentos(Uso);
  if Error <> '' then
  begin
    Responde(FR_ERROR, Error);
    Writeln(ErrOutput, Uso);
    Exit(FR_RC_USAGE);
  end;
  Result := FR_RC_OK;
  ArrancaVigia(GPeticion.TiempoMs);
  Cargador := TCargadorFmx.Create;
  F := nil;
  Bmp := nil;
  try
    try
      Responde(FR_DPI, IntToStr(DeclaraAjenoAlDpi));
      // nada en la barra de tareas: la ventana de aplicacion de FMX es la
      // nuestra, oculta (VentanaDeAplicacionOculta), antes de cargar paquetes
      RegisterApplicationHWNDProc(VentanaDeAplicacionOculta); // la copia estatica de FMX; la de los paquetes, Comun
      ArrancaGuardaDeVentanas; // ningun cuadro, ninguna activacion (Comun)
      Responde(FR_SESSION, IntToStr(SesionActual));
      // nada al escritorio: sin servicio de dialogos, TDialogService no tiene a quien llamar
      TPlatformServices.Current.RemovePlatformService(IFMXDialogService);
      TPlatformServices.Current.RemovePlatformService(IFMXDialogServiceSync);
      TStyleStreaming.SetSupportedPlatformHook(AceptaCualquierPlataforma);
      RegistraEstandar;
      Cargados := 0;
      Conocidos := 0;
      if GPeticion.Paquetes = 'all' then
        CargaPaquetesDelIde(GPeticion.Bds, Cargados, Conocidos);
      Reloj := TStopwatch.StartNew;
      Cargando := True;
      F := TForm(LeeConLosPaquetes(Cargador,
        function: TCargador
        begin
          Result := TCargadorFmx.Create;
        end,
        function(ACargador: TCargador; out ARaiz: TComponent): TComponent
        begin
          Result := CreaYLee(ACargador, ARaiz);
        end, Raiz, Cargados, Conocidos));
      Cargando := False;
      MsCarga := Reloj.ElapsedMilliseconds;
      Responde(FR_ROOT, Format('%s:%s:%s', [Raiz.Name, Cabecera(GPeticion.Path).Clase,
        (if Raiz is TFrame then 'frame' else 'form')]));
      Responde(FR_PACKAGES, Format('%d/%d', [Cargados, Conocidos]));
      Responde(FR_COMPONENTS, IntToStr(Raiz.ComponentCount));
      RespondeLoLeido(Cargador);
      YaLeido := True;
      // los no visuales, SIEMPRE: se dibujen o no, el agente sabe que estan
      Responde(FR_NONVISUALS, ListaDeNoVisuales(NoVisualesDe(Raiz, TControl)));
      // el juez de lo que guarda el IDE (3.11): escrito por TWriter, sin pintar,
      // con el form como lo tiene el disenador (V68, V72)
      if GPeticion.Escribe then
      begin
        ComoLoTieneElDisenador(F, Raiz);
        EscribeComoElIde(Raiz);
        Exit;
      end;
      Responde(FR_STYLE, AplicaEstilo(F));
      for var S in GPeticion.Estados do
        AplicaEstado(Cargador, Raiz, S); // sus mensajes, con la clase que escribe el fichero
      Reloj := TStopwatch.StartNew;
      Bmp := TBitmap.Create(Round(F.ClientWidth), Round(F.ClientHeight));
      if Bmp.Canvas.BeginScene then
      try
        Bmp.Canvas.Clear(TAlphaColors.White);
        F.PaintTo(Bmp.Canvas);
      finally
        Bmp.Canvas.EndScene;
      end
      else
        raise ERender.Create(MsgFmt(SR_RENDER_SIN_ESCENA_FMT, [Bmp.Canvas.ClassName]));
      if GPeticion.NoVisuales then
        Responde(FR_NONVISUAL, IntToStr(DibujaNoVisuales(Raiz, Bmp)));
      if GPeticion.Componente <> '' then
        if RectDe(F, Raiz, GPeticion.Componente, R) then
          Responde(FR_RECT, Format('%s=%d,%d,%d,%d', [GPeticion.Componente, R.Left, R.Top, R.Width, R.Height]))
        else
          Aviso(MsgFmt(SN_RENDER_SIN_COMPONENTE_FMT, [GPeticion.Componente, Raiz.Name]));
      Bmp.SaveToFile(GPeticion.Salida);
      MsPintado := Reloj.ElapsedMilliseconds;
      Responde(FR_FIDELITY, 'canvas (' + Bmp.Canvas.ClassName + ')');
      Responde(FR_SIZE, Format('%dx%d', [Bmp.Width, Bmp.Height]));
      Responde(FR_CAPTURE, GPeticion.Salida);
      Responde(FR_MS, Format('%d,%d', [MsCarga, MsPintado]));
    except
      on E: Exception do
        Result := RespondeFallo(E, Cargador, Cargando, YaLeido);
    end;
  finally
    Bmp.Free;
    F.Free;
    Cargador.Free;
    ParaVigia;
    ParaGuardaDeVentanas;
  end;
end;

end.
