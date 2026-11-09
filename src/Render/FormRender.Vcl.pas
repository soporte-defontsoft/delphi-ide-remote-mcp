unit FormRender.Vcl;

{ DelphiFormRenderVcl: un .dfm -> un PNG de lo que ensena el designer VCL.
  La form se crea en modo diseno sin aparecer en el escritorio, con las
  clases estandar registradas desde este uses (como hace el IDE) y, si el
  dfm trae clases de terceros, con los paquetes de diseno del IDE cargados
  fuera del IDE. Dos captores, elegidos solos (FIDELITY= lo declara):

    window  la ventana EN pantalla pero invisible al ojo y al raton (por
            capas, alfa 1, al fondo, sin activar) y BitBlt de su DC: la
            pintada REAL de cada control, igual al designer. Necesita DWM,
            o sea una sesion interactiva.
    print   la ventana fuera de pantalla y WM_PRINT a cada control en su
            orden Z, recortado a su padre; EDIT/COMBOBOX callan su texto si
            la ventana no es visible (sesion 0) y lo dibuja el impresor.
            Vale desde un servicio; los controles que se pintan a su manera
            salen con aspecto nativo.

  Medidas del 6-oct-2026 en el vault (renderform-sonda-2026-10-06). }

interface

function Main: Integer;

implementation

uses
  FormRender.Comun, FormRender.Textos,
  Winapi.Windows, Winapi.Messages, Winapi.CommCtrl, Winapi.DwmApi,
  System.SysUtils, System.Classes, System.Diagnostics, System.IOUtils, System.Types,
  Vcl.Forms, Vcl.Controls, Vcl.Graphics, Vcl.Themes, Vcl.Styles,
  Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.StdCtrls, Vcl.Buttons, Vcl.Mask, Vcl.Grids, Vcl.Menus,
  Vcl.ActnList, Vcl.Dialogs, Vcl.ExtDlgs, Vcl.CheckLst, Vcl.ValEdit, Vcl.ToolWin, Vcl.Tabs,
  Vcl.ActnMan, Vcl.ActnCtrls, Vcl.ActnMenus, Vcl.CategoryButtons, Vcl.ButtonGroup,
  Vcl.WinXCtrls, Vcl.WinXPanels, Vcl.WinXPickers, Vcl.WinXCalendars, Vcl.NumberBox,
  Vcl.TitleBarCtrls, Vcl.ControlList, Vcl.VirtualImageList, Vcl.ImageCollection,
  Vcl.Samples.Spin,
  Vcl.Imaging.pngimage, Vcl.Imaging.jpeg, Vcl.Imaging.GIFImg;

type
  { Un panel con el nombre de la clase que no existe en ningun paquete }
  TSustituto = class(TPanel)
  end;

  { Una form que NUNCA aparece: el cambio de Showing se traga aqui; la
    ventana y las de sus hijos existen y se ensenan a mano donde conviene }
  TFormOculta = class(TForm)
  private
    FPpiDeLasUnidades: Integer;
  protected
    procedure CMShowingChanged(var Message: TMessage); message CM_SHOWINGCHANGED;
    procedure Loaded; override;
  public
    { El PPI en el que lo leido esta en unidades del fichero: el PixelsPerInch que
      escribe el fichero de un form (el lector lo pone antes de que Loaded lo lleve
      al de la pantalla: en ejecucion uno a 120 queda a 96), o el de esta form
      vacia si lo leido es un frame (que la VCL no escala al leerlo: medido). Lo pone
      quien la crea, y Loaded si se lee en ella (C2 de la 1.29) }
    property PpiDeLasUnidades: Integer read FPpiDeLasUnidades write FPpiDeLasUnidades;
  end;

  TCrackCombo = class(TCustomComboBox);

  TCargadorVcl = class(TCargador)
  protected
    function ClaseSustituto: TComponentClass; override;
    function CreaSustituto(AOwner: TComponent; const AClase: string): TComponent; override;
    function ClaseFrame: TComponentClass; override;
  end;

  { Application.OnException sin cuadro: una excepcion que llegue al bucle de
    mensajes (desde un WM_PRINT, por ejemplo) se apunta y no sale al escritorio }
  TSinCuadro = class
    procedure Excepcion(Sender: TObject; E: Exception);
  end;

procedure TFormOculta.CMShowingChanged(var Message: TMessage);
begin
  // a proposito: ni ShowWindow ni activacion
end;

procedure TFormOculta.Loaded;
begin
  // antes de que TCustomForm.Loaded (ScaleForCurrentDPI) lo lleve al de la pantalla
  FPpiDeLasUnidades := PixelsPerInch;
  inherited;
end;

var
  // la escala del png respecto al fichero (SCALE=, EnPixeles): la de lo que la VCL no
  // escala, el sitio de un no visual (C2 de la 1.29)
  GPixeles: Integer = 1;
  GUnidades: Integer = 1;

{ Una medida del fichero (el Left/Top de un no visual) en pixeles del png }
function EnPixeles(A: Integer): Integer;
begin
  Result := MulDiv(A, GPixeles, GUnidades);
end;

procedure TSinCuadro.Excepcion(Sender: TObject; E: Exception);
begin
  Aviso(MsgFmt(SN_RENDER_EXCEPCION_BUCLE_FMT, [E.ClassName, E.Message]));
end;

{ TCargadorVcl }

function TCargadorVcl.ClaseSustituto: TComponentClass;
begin
  Result := TSustituto;
end;

function TCargadorVcl.CreaSustituto(AOwner: TComponent; const AClase: string): TComponent;
begin
  Result := TSustituto.Create(AOwner);
  with TSustituto(Result) do
  begin
    Caption := AClase;
    Color := $00C0C0FF;
    BevelOuter := bvRaised;
    ParentBackground := False;
    ShowCaption := True;
  end;
end;

function TCargadorVcl.ClaseFrame: TComponentClass;
begin
  Result := TFrame;
end;

{ Las clases estandar las registra el renderizador desde su uses, como hace
  el IDE con la form que crea; los paquetes quedan para los terceros. }
procedure RegistraEstandar;
begin
  Apunta([TLabel, TEdit, TMemo, TButton, TCheckBox, TRadioButton, TListBox,
    TComboBox, TScrollBar, TGroupBox, TRadioGroup, TPanel, TMainMenu, TPopupMenu, TMenuItem,
    TActionList, TAction, TImageList, TFrame,
    TBitBtn, TSpeedButton, TMaskEdit, TStringGrid, TDrawGrid, TImage,
    TShape, TBevel, TScrollBox, TSplitter, TStaticText, TLabeledEdit, TButtonedEdit,
    TTimer, TPaintBox, TLinkLabel, TCategoryPanelGroup, TCategoryPanel, TGridPanel, TFlowPanel,
    TColorBox, TColorListBox, TControlBar, TTrayIcon, TRadioGroup, TValueListEditor,
    TCheckListBox, TTabSet, TControlList,
    TPageControl, TTabSheet, TTabControl, TToolBar, TToolButton, TStatusBar,
    TTrackBar, TProgressBar, TDateTimePicker, TTreeView, TListView, TRichEdit, TUpDown,
    TMonthCalendar, THotKey, TAnimate, TCoolBar, THeaderControl, TPageScroller, TComboBoxEx,
    TSplitView, TRelativePanel, TToggleSwitch, TActivityIndicator, TSearchBox,
    TCardPanel, TCard, TDatePicker, TTimePicker, TCalendarView, TCalendarPicker, TNumberBox,
    TTitleBarPanel, TVirtualImageList, TImageCollection,
    TActionManager, TActionMainMenuBar, TActionToolBar,
    TCategoryButtons, TButtonGroup, TSpinEdit, TSpinButton,
    TOpenDialog, TSaveDialog, TOpenTextFileDialog, TSaveTextFileDialog, TOpenPictureDialog,
    TSavePictureDialog, TFontDialog, TColorDialog, TPrintDialog, TPrinterSetupDialog,
    TFindDialog, TReplaceDialog, TPageSetupDialog, TTaskDialog, TFileOpenDialog, TFileSaveDialog]);
end;

{ Sesion 0: la ventana nunca "es visible" (IsWindowVisible False con
  WS_VISIBLE puesto) y el EDIT y el COMBOBOX nativos callan su texto en
  WM_PRINTCLIENT. El impresor lo dibuja con la fuente del control en el
  rectangulo donde lo pintaria Windows. Vacio, su texto de ayuda (TextHint),
  en gris, como Windows: callaba tambien y el preview del servicio ensenaba
  en blanco el edit y el combo que el IDE ensena con su pista (C9 de la 1.29,
  medido en el servicio). Un memo no: Windows no pone pista a un edit de
  varias lineas (y TMemo no la publica). }
procedure DibujaTextoCallado(AControl: TWinControl; DC: HDC);
var
  R: TRect;
  Info: TComboBoxInfo;
  Texto: string;
  HF: HFONT;
  Viejo: HGDIOBJ;
  Margen: Integer;
  Flags: UINT;
  Pista: string;
  Color: TColor;
begin
  Pista := '';
  if IsWindowVisible(AControl.Handle) then
    Exit;
  if AControl is TCustomEdit then
  begin
    Texto := TCustomEdit(AControl).Text;
    if not (AControl is TCustomMemo) then
      Pista := TCustomEdit(AControl).TextHint;
    GetClientRect(AControl.Handle, R);
    OffsetRect(R, (AControl.Width - R.Width) div 2, (AControl.Height - R.Height) div 2);
    Margen := LoWord(SendMessage(AControl.Handle, EM_GETMARGINS, 0, 0));
    Inc(R.Left, Margen + 1);
    if AControl is TCustomMemo then
      Flags := DT_LEFT or DT_TOP or DT_WORDBREAK or DT_NOPREFIX or DT_EDITCONTROL
    else
      Flags := DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX;
  end
  else if AControl is TCustomComboBox then
  begin
    Texto := TCrackCombo(AControl).Text;
    Pista := TCustomComboBox(AControl).TextHint;
    FillChar(Info, SizeOf(Info), 0);
    Info.cbSize := SizeOf(Info);
    if not GetComboBoxInfo(AControl.Handle, Info) then
      Exit;
    R := Info.rcItem;
    OffsetRect(R, (AControl.Width - AControl.ClientWidth) div 2, (AControl.Height - AControl.ClientHeight) div 2);
    Inc(R.Left, 3);
    Flags := DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX;
  end
  else
    Exit;
  Color := clWindowText;
  if Texto = '' then
  begin
    Texto := Pista;
    Color := clGrayText;
  end;
  if Texto = '' then
    Exit;
  HF := HFONT(SendMessage(AControl.Handle, WM_GETFONT, 0, 0));
  Viejo := 0;
  if HF <> 0 then
    Viejo := SelectObject(DC, HF);
  SetBkMode(DC, TRANSPARENT);
  SetTextColor(DC, ColorToRGB(Color));
  DrawText(DC, PChar(Texto), Length(Texto), R, Flags);
  if Viejo <> 0 then
    SelectObject(DC, Viejo);
end;

{ WM_PRINT a cada ventana SIN PRF_CHILDREN, en el orden Z de la VCL, con el
  origen del DC en su posicion respecto al cliente de la form y el recorte a
  su rectangulo (DefWindowProc con PRF_CHILDREN imprime cada hijo entero sin
  recortarlo al padre). Los graficos (TLabel, TSpeedButton) los pinta su
  padre en WM_PRINTCLIENT. }
procedure ImprimeArbol(AForm: TForm; AControl: TWinControl; DC: HDC);
var
  WR: TRect;
  P: TPoint;
  Save: Integer;
begin
  if not AControl.HandleAllocated then
    Exit;
  GetWindowRect(AControl.Handle, WR);
  P := AForm.ScreenToClient(WR.TopLeft);
  Save := SaveDC(DC);
  try
    SetWindowOrgEx(DC, -P.X, -P.Y, nil);
    IntersectClipRect(DC, 0, 0, WR.Width, WR.Height);
    SendMessage(AControl.Handle, WM_PRINT, DC, PRF_CLIENT or PRF_NONCLIENT or PRF_ERASEBKGND);
    DibujaTextoCallado(AControl, DC);
    // los que la VCL MUESTRA (Showing, de UpdateShowing): en diseno tambien los de
    // Visible = False, como el disenador del IDE y como los pinta window. Por Visible
    // print se saltaba un panel oculto que window pintaba (Hermes, dirigido de la 1.29;
    // medido: rojo en window, blanco en print)
    for var I := 0 to AControl.ControlCount - 1 do
      if (AControl.Controls[I] is TWinControl) and TWinControl(AControl.Controls[I]).Showing then
        ImprimeArbol(AForm, TWinControl(AControl.Controls[I]), DC);
  finally
    RestoreDC(DC, Save);
  end;
end;

function HayDwm: Boolean;
var
  B: BOOL;
begin
  Result := Succeeded(DwmIsCompositionEnabled(B)) and B;
end;

{ Visible := True crea las ventanas hijas (UpdateShowing; con Visible=False
  no existen y nada las enumera). Luego la ventana se ensena sin activar:
  por capas EN pantalla (window) o fuera de pantalla como tool window (print). }
procedure Muestra(AForm: TForm; AWindow: Boolean);
var
  Ex: NativeInt;
begin
  AForm.HandleNeeded;
  Ex := GetWindowLong(AForm.Handle, GWL_EXSTYLE) or WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE;
  if AWindow then
    Ex := Ex or WS_EX_LAYERED or WS_EX_TRANSPARENT;
  SetWindowLong(AForm.Handle, GWL_EXSTYLE, Ex);
  if AWindow then
  begin
    SetLayeredWindowAttributes(AForm.Handle, 0, 1, LWA_ALPHA);
    SetWindowPos(AForm.Handle, HWND_BOTTOM, 0, 0, 0, 0, SWP_NOSIZE or SWP_NOACTIVATE);
  end
  else
    SetWindowPos(AForm.Handle, 0, -32000, -32000, 0, 0, SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE);
  AForm.Visible := True;
  ShowWindow(AForm.Handle, SW_SHOWNOACTIVATE);
  if not IsWindowVisible(AForm.Handle) then
    SetWindowPos(AForm.Handle, 0, 0, 0, 0, 0,
      SWP_NOMOVE or SWP_NOSIZE or SWP_NOZORDER or SWP_NOACTIVATE or SWP_SHOWWINDOW);
end;

procedure Repinta(AForm: TForm);
begin
  RedrawWindow(AForm.Handle, nil, 0, RDW_INVALIDATE or RDW_ERASE or RDW_UPDATENOW or RDW_ALLCHILDREN);
end;

{ La ventana, a mano, como Muestra la ensena; la VCL no: no esconde un hijo
  MDI sin padre (TCustomForm.VisibleChanging lanza 'Cannot hide an MDI Child
  Form' sin mirar csDesigning; ni su BeforeDestruction lo intenta), y el render
  entero fallaba con la imagen ya hecha - DSGN-061 tambien por el servidor (C9
  de la 1.29: los hijos MDI de los Samples). }
procedure Esconde(AForm: TForm);
begin
  ShowWindow(AForm.Handle, SW_HIDE);
end;

{ El bitmap del cliente de la form con uno de los dos captores. Devuelve el
  captor que de verdad se uso (window puede caer a print). }
function Captura(AForm: TForm; const ACaptor: string; out AUsado: string): TBitmap;
var
  DC: HDC;
  Bien: Boolean;
begin
  AUsado := ACaptor;
  Result := TBitmap.Create;
  Result.PixelFormat := pf24bit;
  Result.SetSize(AForm.ClientWidth, AForm.ClientHeight);
  // como GetFormImage: el DC de un TBitmap se recicla si no esta bloqueado
  Result.Canvas.Lock;
  try
    Result.Canvas.Brush.Color := AForm.Color;
    Result.Canvas.FillRect(Rect(0, 0, Result.Width, Result.Height));
    Bien := False;
    if ACaptor = FR_FIDELIDAD_WINDOW then
    begin
      DC := GetDC(AForm.Handle);
      try
        Bien := BitBlt(Result.Canvas.Handle, 0, 0, Result.Width, Result.Height, DC, 0, 0, SRCCOPY);
        if not Bien then
          Aviso(MsgFmt(SN_RENDER_PINTADA_NO_COPIADA_FMT, [SysErrorMessage(GetLastError)]));
      finally
        ReleaseDC(AForm.Handle, DC);
      end;
    end;
    if not Bien then
    begin
      AUsado := FR_FIDELIDAD_PRINT;
      ImprimeArbol(AForm, AForm, Result.Canvas.Handle);
    end;
  finally
    Result.Canvas.Unlock;
  end;
end;

{ Los no visuales como los ensena el designer: su icono en un recuadro en el
  Left/Top que guarda el dfm y el nombre debajo. Cuenta los dibujados. }
function DibujaNoVisuales(ARaiz: TComponent; ABmp: TBitmap): Integer;
const
  LADO = LADO_DE_NO_VISUAL;
var
  Png: TBytes;
  Imagen: TPngImage;
  P: TPoint;
  M: TMemoryStream;
  R: TRect;
begin
  Result := 0;
  ABmp.Canvas.Lock;
  try
    ABmp.Canvas.Font.Name := 'Segoe UI';
    ABmp.Canvas.Font.Size := 7;
    ABmp.Canvas.Font.Height := EnPixeles(ABmp.Canvas.Font.Height);
    for var C in NoVisualesDe(ARaiz, TControl) do
    begin
      P := PosicionDeNoVisual(C);
      R := Rect(EnPixeles(P.X), EnPixeles(P.Y), EnPixeles(P.X + LADO), EnPixeles(P.Y + LADO));
      ABmp.Canvas.Brush.Color := clWindow;
      ABmp.Canvas.Pen.Color := clGray;
      ABmp.Canvas.Rectangle(R);
      if IconoPngDeClase(C.ClassName, Png) then
      begin
        Imagen := TPngImage.Create;
        M := TMemoryStream.Create;
        try
          M.WriteBuffer(Png[0], Length(Png));
          M.Position := 0;
          Imagen.LoadFromStream(M);
          ABmp.Canvas.StretchDraw(Rect(R.Left + 2, R.Top + 2, R.Right - 2, R.Bottom - 2), Imagen);
        finally
          M.Free;
          Imagen.Free;
        end;
      end
      else
      begin
        // sin icono en ningun paquete: las iniciales de la clase
        ABmp.Canvas.Brush.Style := bsClear;
        var Ini := C.ClassName.Substring(1, 3);
        ABmp.Canvas.TextOut(R.Left + (R.Width - ABmp.Canvas.TextWidth(Ini)) div 2,
          R.Top + (R.Height - ABmp.Canvas.TextHeight(Ini)) div 2, Ini);
        ABmp.Canvas.Brush.Style := bsSolid;
      end;
      ABmp.Canvas.Brush.Style := bsClear;
      ABmp.Canvas.TextOut(R.Left + (R.Width - ABmp.Canvas.TextWidth(C.Name)) div 2, R.Bottom + 1, C.Name);
      ABmp.Canvas.Brush.Style := bsSolid;
      Inc(Result);
    end;
  finally
    ABmp.Canvas.Unlock;
  end;
end;

{ El rectangulo de un componente en el PNG (el cliente de la form). El
  nombre como lee la RTL una referencia (FindNestedComponent): Marco1.LblAviso
  es uno de dentro de un frame inline (revision de la 1.17.0: DSGN-066) }
function RectDe(AForm: TForm; ARaiz: TComponent; const ANombre: string; out R: TRect): Boolean;
var
  C: TComponent;
  P: TPoint;
begin
  Result := False;
  C := ComponenteDeRuta(ARaiz, ANombre);
  if C = nil then
    C := ComponenteDeRuta(AForm, ANombre);
  if C = nil then
    Exit;
  if C is TControl then
  begin
    R := TControl(C).BoundsRect;
    if (TControl(C).Parent <> nil) and (TControl(C).Parent <> AForm) then
    begin
      P := TControl(C).Parent.ClientToParent(R.TopLeft, AForm);
      R := Rect(P.X, P.Y, P.X + R.Width, P.Y + R.Height);
    end;
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
          R := Rect(EnPixeles(P.X), EnPixeles(P.Y), EnPixeles(P.X + LADO_DE_NO_VISUAL),
            EnPixeles(P.Y + LADO_DE_NO_VISUAL + 12));
          Exit(True);
        end;
end;

{ Donde queda cada control del form ya mostrado, en coordenadas del cliente de la form:
  lo que resuelve la VCL, no lo que dice el texto (V24 de la 1.24). }
procedure RespondeCajas(AForm: TForm; ARaiz: TComponent; ACargador: TCargador);

  procedure De(APadre: TWinControl);
  begin
    for var I := 0 to APadre.ControlCount - 1 do
    begin
      var C := APadre.Controls[I];
      var P := C.BoundsRect.TopLeft;
      if APadre <> AForm then
        P := APadre.ClientToParent(P, AForm);
      var Ruta := RutaDeComponente(ARaiz, C);
      if Ruta <> '' then
      begin
        // y donde esta escrito: el de dentro de un frame, en el fichero del frame
        var EnFichero: string;
        var Fichero := ACargador.EscritoEn(C, EnFichero);
        RespondeCaja(Ruta, ACargador.ClaseEscrita(C, ARaiz),
          (if (APadre = AForm) or (APadre = ARaiz) then '' else RutaDeComponente(ARaiz, APadre)),
          P.X, P.Y, C.Width, C.Height, C.Visible, '', Fichero, EnFichero, '');
      end;
      if C is TWinControl then
        De(TWinControl(C));
    end;
  end;

begin
  if ARaiz is TWinControl then
    De(TWinControl(ARaiz));
end;

procedure GuardaPng(ABmp: TBitmap; const APng: string);
var
  Png: TPngImage;
begin
  Png := TPngImage.Create;
  try
    Png.Assign(ABmp);
    Png.SaveToFile(APng);
  finally
    Png.Free;
  end;
end;

{ Crea la form y lee el fichero (form o frame) en ella. En modo diseno, como
  el designer, salvo con un estilo .vsf: el motor de estilos de la VCL no
  viste a un control con csDesigning (por eso el designer VCL pinta sin
  estilo; medido con Carbon.vsf), asi que con --style la form va sin el. }
function CreaYLee(ACargador: TCargador; ADesigning: Boolean; out ARaiz: TComponent): TForm;
var
  Frame: TFrame;
  Cab: TCabecera;
begin
  // el grupo de clases de la VCL, como lo activa el designer VCL del IDE: cada
  // unidad FMX de un paquete cargado activa el suyo al inicializarse
  // (RegisterFmxClasses, FMX.Types), y GetClass solo busca en el activo - un
  // TCalendar o un TMediaPlayer salian los de FMX (corpus, 18-oct-2026)
  ActivateClassGroup(Vcl.Controls.TControl);
  Cab := Cabecera(GPeticion.Path);
  Result := TFormOculta.CreateNew(nil);
  // el de la form vacia; si se lee un form en ella, su Loaded pone el del fichero
  TFormOculta(Result).PpiDeLasUnidades := Result.PixelsPerInch;
  try
    if ADesigning then
      PonEnDiseno(Result);
    if EsFrame(GPeticion.Path, Cab.Clase, TFrame) then // el que se crea aqui abajo
    begin
      Frame := TFrame.Create(Result);
      if ADesigning then
        PonEnDiseno(Frame);
      ARaiz := Frame;
      ACargador.LeeRaiz(GPeticion.Path, Cab.Nombre, Frame);
      Result.ClientWidth := Frame.Width;
      Result.ClientHeight := Frame.Height;
      Frame.Parent := Result;
      Frame.Left := 0;
      Frame.Top := 0;
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

function Main: Integer;
var
  Captor, Usado: string;
  Cargador: TCargador;
  F: TForm;
  Raiz: TComponent;
  Bmp: TBitmap;
  Reloj: TStopwatch;
  MsCarga, MsPintado, Cargados, Conocidos, N: Integer;
  SinCuadro: TSinCuadro;
  R: TRect;
  Designing: Boolean;
  // mientras lee el form (lo que falle ahi y sea del lector es el fichero:
  // NOTLOADED=) y si lo leido ya se dijo (RespondeFallo, DSGN-061 de la 1.20)
  Cargando, YaLeido: Boolean;
begin
  Cargando := False;
  YaLeido := False;
  if not ArrancaAyudante(Result) then
    Exit;
  SinCuadro := TSinCuadro.Create;
  Cargador := TCargadorVcl.Create;
  F := nil;
  Bmp := nil;
  try
    try
      Responde(FR_DPI, IntToStr(DeclaraAjenoAlDpi));
      ArrancaGuardaDeVentanas; // ningun cuadro, ninguna activacion (Comun; FireDAC, 19-oct-2026)
      Responde(FR_SESSION, IntToStr(SesionActual));
      Application.OnException := SinCuadro.Excepcion;
      Application.ShowHint := False;
      RegistraEstandar;
      Cargados := 0;
      Conocidos := 0;
      if GPeticion.Paquetes = FR_PAQUETES_TODOS then
        CargaPaquetesDelIde(Cargados, Conocidos);
      // estilo VCL: .vsf por TStyleManager, el mecanismo global de la VCL
      if (GPeticion.Estilo <> '') and not SameText(GPeticion.Estilo, FR_ESTILO_NINGUNO) then
      begin
        if not TFile.Exists(GPeticion.Estilo) then
          raise ERender.Create(MsgFmt(SR_RENDER_NO_EXISTE_FMT, [MsgFmt(SF_RENDER_FICHERO_DE_ESTILO_FMT,
            [GPeticion.Estilo])]));
        TStyleManager.SetStyle(TStyleManager.LoadFromFile(GPeticion.Estilo));
        Designing := False;
        Responde(FR_STYLE, MsgFmt(SF_RENDER_ESTILO_VCL_FMT, [TStyleManager.ActiveStyle.Name, ExtractFileName(GPeticion.Estilo)]));
      end
      else
      begin
        Designing := True;
        Responde(FR_STYLE, MsgText(SF_RENDER_SIN_ESTILO_VCL));
      end;
      Reloj := TStopwatch.StartNew;
      Cargando := True;
      F := TForm(LeeConLosPaquetes(Cargador,
        function: TCargador
        begin
          Result := TCargadorVcl.Create;
        end,
        function(ACargador: TCargador; out ARaiz: TComponent): TComponent
        begin
          Result := CreaYLee(ACargador, Designing, ARaiz);
        end, Raiz, Cargados, Conocidos));
      Cargando := False;
      MsCarga := Reloj.ElapsedMilliseconds;
      RespondeLoCargado(Cargador, Raiz, Raiz is TFrame, Cargados, Conocidos, TControl, YaLeido);
      // el juez de lo que guarda el IDE (3.11): escrito por TWriter, sin pintar
      if GPeticion.Escribe then
      begin
        // lo que puso el agente, sobre el form YA cargado, como el Inspector del
        // IDE: su clase hace lo suyo fuera de la lectura (B2 de la 1.28, como FMX)
        for var S in GPeticion.Puestas do
          AplicaEstado(Cargador, Raiz, S);
        // el SOLTADO, el ultimo del tabulador de su padre, lo que hace soltarlo en el
        // disenador (--dropped). Un control lo es ya al leerlo, pero un frame inline
        // salia con 0, repetido, porque se crea antes de tener padre (1-nov-2026)
        if GPeticion.Soltado <> '' then
        begin
          var Soltado := ComponenteDeRuta(Raiz, GPeticion.Soltado);
          if Soltado is TWinControl then
            TWinControl(Soltado).TabOrder := High(TTabOrder);
        end;
        EscribeComoElIde(Raiz);
        Exit;
      end;
      // captor: la pintada real si hay DWM (sesion interactiva); si no, impresion
      Captor := GPeticion.Fidelidad;
      if Captor = FR_AUTO then
        if (SesionActual <> 0) and HayDwm then
          Captor := FR_FIDELIDAD_WINDOW
        else
          Captor := FR_FIDELIDAD_PRINT;
      Reloj := TStopwatch.StartNew;
      // la escala de pantalla pedida (C2 de la 1.29): lo que hace la VCL con un form que pasa
      // a un monitor de ese DPI (WMDpiChanged -> ScaleForPPIRect), y nada si dice
      // Scaled = False. ANTES de mostrarlo, ya cargado: el orden de una aplicacion que escala
      // sus forms (tras crear el form y antes de Show; David: "el orden importa"). Medido el
      // 7-nov-2026 con una variante que escala despues: aqui da lo mismo (anclados abajo a la
      // derecha, a lo ancho, alBottom: las mismas cajas), porque es UN escalado desde lo
      // cargado; se sigue el de la aplicacion. Lo leido ya esta en el DPI de
      // la pantalla de este proceso (ejecucion) o en el de su fichero (diseno, como el IDE).
      // Un frame va en esta form, que lo escala con ella
      if GPeticion.Escala > 0 then
      begin
        F.ScaleForPPI(MulDiv(Screen.DefaultPixelsPerInch, GPeticion.Escala, 100));
        if not F.Scaled then
          Aviso(MsgFmt(SN_RENDER_SIN_ESCALAR_FMT, [Raiz.Name]));
      end;
      // cuantos pixeles por unidad del fichero: el PPI de la form al pintarla, que la VCL
      // pone en cada escalado (CurrentPPI no: en un proceso ajeno al DPI dice el de la
      // ventana, 96), y aquel en el que lo leido estaba en unidades del fichero
      GPixeles := F.PixelsPerInch;
      GUnidades := TFormOculta(F).PpiDeLasUnidades;
      RespondeEscala(GPixeles, GUnidades);
      Muestra(F, Captor = FR_FIDELIDAD_WINDOW);
      // el estado de vista va DESPUES de mostrar: un ActivePage puesto antes
      // llega al control nativo con la seleccion vieja
      for var S in GPeticion.Estados do
        AplicaEstado(Cargador, Raiz, S); // sus mensajes, con la clase que escribe el fichero
      Repinta(F);
      Bmp := Captura(F, Captor, Usado);
      Esconde(F);
      if GPeticion.NoVisuales then
      begin
        N := DibujaNoVisuales(Raiz, Bmp);
        Responde(FR_NONVISUAL, IntToStr(N));
      end;
      if GPeticion.Componente <> '' then
        if RectDe(F, Raiz, GPeticion.Componente, R) then
          RespondeRect(GPeticion.Componente, R.Left, R.Top, R.Width, R.Height)
        else
          Aviso(MsgFmt(SN_RENDER_SIN_COMPONENTE_FMT, [GPeticion.Componente, Raiz.Name]));
      if GPeticion.Cajas then
        RespondeCajas(F, Raiz, Cargador)
      else
        GuardaPng(Bmp, GPeticion.Salida);
      MsPintado := Reloj.ElapsedMilliseconds;
      RespondeElPintado(Usado, Bmp.Width, Bmp.Height, MsCarga, MsPintado);
    except
      on E: Exception do
        Result := RespondeFallo(E, Cargador, Cargando, YaLeido);
    end;
  finally
    Bmp.Free;
    F.Free;
    Cargador.Free;
    SinCuadro.Free;
    ParaVigia;
    ParaGuardaDeVentanas;
  end;
end;

end.
