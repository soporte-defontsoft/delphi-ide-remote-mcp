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
  protected
    procedure CMShowingChanged(var Message: TMessage); message CM_SHOWINGCHANGED;
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

const
  PW_CLIENTONLY = 1;

{ Sesion 0: la ventana nunca "es visible" (IsWindowVisible False con
  WS_VISIBLE puesto) y el EDIT y el COMBOBOX nativos callan su texto en
  WM_PRINTCLIENT. El impresor lo dibuja con la fuente del control en el
  rectangulo donde lo pintaria Windows. }
procedure DibujaTextoCallado(AControl: TWinControl; DC: HDC);
var
  R: TRect;
  Info: TComboBoxInfo;
  Texto: string;
  HF: HFONT;
  Viejo: HGDIOBJ;
  Margen: Integer;
  Flags: UINT;
begin
  if IsWindowVisible(AControl.Handle) then
    Exit;
  if AControl is TCustomEdit then
  begin
    Texto := TCustomEdit(AControl).Text;
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
  if Texto = '' then
    Exit;
  HF := HFONT(SendMessage(AControl.Handle, WM_GETFONT, 0, 0));
  Viejo := 0;
  if HF <> 0 then
    Viejo := SelectObject(DC, HF);
  SetBkMode(DC, TRANSPARENT);
  SetTextColor(DC, ColorToRGB(clWindowText));
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
    for var I := 0 to AControl.ControlCount - 1 do
      if (AControl.Controls[I] is TWinControl) and AControl.Controls[I].Visible then
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

procedure Esconde(AForm: TForm);
begin
  ShowWindow(AForm.Handle, SW_HIDE);
  AForm.Visible := False;
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
    if ACaptor = 'window' then
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
      AUsado := 'print';
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
  LADO = 28;
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
    for var C in NoVisualesDe(ARaiz, TControl) do
    begin
      P := PosicionDeNoVisual(C);
      R := Rect(P.X, P.Y, P.X + LADO, P.Y + LADO);
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
          ABmp.Canvas.StretchDraw(Rect(P.X + 2, P.Y + 2, P.X + LADO - 2, P.Y + LADO - 2), Imagen);
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
        ABmp.Canvas.TextOut(P.X + (LADO - ABmp.Canvas.TextWidth(Ini)) div 2,
          P.Y + (LADO - ABmp.Canvas.TextHeight(Ini)) div 2, Ini);
        ABmp.Canvas.Brush.Style := bsSolid;
      end;
      ABmp.Canvas.Brush.Style := bsClear;
      ABmp.Canvas.TextOut(P.X + (LADO - ABmp.Canvas.TextWidth(C.Name)) div 2, P.Y + LADO + 1, C.Name);
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
          R := Rect(P.X, P.Y, P.X + 28, P.Y + 28 + 12);
          Exit(True);
        end;
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
  Cab := Cabecera(GPeticion.Path);
  Result := TFormOculta.CreateNew(nil);
  if ADesigning then
    PonEnDiseno(Result);
  if EsFrame(GPeticion.Path, Cab.Clase) then
  begin
    Frame := TFrame.Create(Result);
    if ADesigning then
      PonEnDiseno(Frame);
    ARaiz := Frame;
    ACargador.Lee(GPeticion.Path, Frame);
    if Cab.Nombre <> '' then
      Frame.Name := Cab.Nombre;
    Result.ClientWidth := Frame.Width;
    Result.ClientHeight := Frame.Height;
    Frame.Parent := Result;
    Frame.Left := 0;
    Frame.Top := 0;
  end
  else
  begin
    ARaiz := Result;
    ACargador.Lee(GPeticion.Path, Result);
    if Cab.Nombre <> '' then
      Result.Name := Cab.Nombre;
  end;
end;

function Main: Integer;
var
  Uso, Error, Captor, Usado: string;
  Cargador: TCargadorVcl;
  F: TForm;
  Raiz: TComponent;
  Bmp: TBitmap;
  Reloj: TStopwatch;
  MsCarga, MsPintado, Cargados, Conocidos, N: Integer;
  SinCuadro: TSinCuadro;
  R: TRect;
  Designing: Boolean;
begin
  Error := ParseaArgumentos(Uso);
  if Error <> '' then
  begin
    Responde(FR_ERROR, Error);
    Writeln(ErrOutput, Uso);
    Exit(FR_RC_USAGE);
  end;
  Result := FR_RC_OK;
  ArrancaVigia(GPeticion.TiempoMs);
  SinCuadro := TSinCuadro.Create;
  Cargador := TCargadorVcl.Create;
  F := nil;
  Bmp := nil;
  try
    try
      Responde(FR_DPI, IntToStr(DeclaraAjenoAlDpi));
      Responde(FR_SESSION, IntToStr(SesionActual));
      Application.OnException := SinCuadro.Excepcion;
      Application.ShowHint := False;
      RegistraEstandar;
      Cargados := 0;
      Conocidos := 0;
      if GPeticion.Paquetes = 'all' then
        CargaPaquetesDelIde(GPeticion.Bds, Cargados, Conocidos);
      // estilo VCL: .vsf por TStyleManager, el mecanismo global de la VCL
      if (GPeticion.Estilo <> '') and not SameText(GPeticion.Estilo, 'none') then
      begin
        if not TFile.Exists(GPeticion.Estilo) then
          raise ERender.Create(MsgFmt(SR_RENDER_NO_EXISTE_FMT, ['style ' + GPeticion.Estilo]));
        TStyleManager.SetStyle(TStyleManager.LoadFromFile(GPeticion.Estilo));
        Designing := False;
        Responde(FR_STYLE, TStyleManager.ActiveStyle.Name + ' (' + ExtractFileName(GPeticion.Estilo) +
          '; the form is not in design mode: VCL styles do not apply to designed controls)');
      end
      else
      begin
        Designing := True;
        Responde(FR_STYLE, 'none (as the VCL designer)');
      end;
      Reloj := TStopwatch.StartNew;
      F := CreaYLee(Cargador, Designing, Raiz);
      if (GPeticion.Paquetes = 'auto') and (Cargador.Sustituidas.Count > 0) then
      begin
        // clases que no son estandar: los paquetes de diseno del IDE, y otra vez
        Traza('clases sin registrar: ' + string.Join(',', Cargador.Sustituidas.ToStringArray) + ' -> paquetes del IDE');
        FreeAndNil(F);
        Cargador.Free;
        Cargador := TCargadorVcl.Create;
        CargaPaquetesDelIde(GPeticion.Bds, Cargados, Conocidos);
        F := CreaYLee(Cargador, Designing, Raiz);
      end;
      MsCarga := Reloj.ElapsedMilliseconds;
      Responde(FR_ROOT, Format('%s:%s:%s', [Raiz.Name, Cabecera(GPeticion.Path).Clase,
        (if Raiz is TFrame then 'frame' else 'form')]));
      Responde(FR_PACKAGES, Format('%d/%d', [Cargados, Conocidos]));
      Responde(FR_COMPONENTS, IntToStr(Raiz.ComponentCount));
      RespondeLoLeido(Cargador);
      // los no visuales, SIEMPRE: se dibujen o no, el agente sabe que estan
      Responde(FR_NONVISUALS, ListaDeNoVisuales(NoVisualesDe(Raiz, TControl)));
      // el juez de lo que guarda el IDE (3.11): escrito por TWriter, sin pintar
      if GPeticion.Escribe then
      begin
        EscribeComoElIde(Raiz);
        Exit;
      end;
      // captor: la pintada real si hay DWM (sesion interactiva); si no, impresion
      Captor := GPeticion.Fidelidad;
      if Captor = 'auto' then
        if (SesionActual <> 0) and HayDwm then
          Captor := 'window'
        else
          Captor := 'print';
      Reloj := TStopwatch.StartNew;
      Muestra(F, Captor = 'window');
      // el estado de vista va DESPUES de mostrar: un ActivePage puesto antes
      // llega al control nativo con la seleccion vieja
      for var S in GPeticion.Estados do
        AplicaEstado(Raiz, S);
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
          Responde(FR_RECT, Format('%s=%d,%d,%d,%d', [GPeticion.Componente, R.Left, R.Top, R.Width, R.Height]))
        else
          Aviso(MsgFmt(SN_RENDER_SIN_COMPONENTE_FMT, [GPeticion.Componente, Raiz.Name]));
      GuardaPng(Bmp, GPeticion.Salida);
      MsPintado := Reloj.ElapsedMilliseconds;
      Responde(FR_FIDELITY, Usado);
      Responde(FR_SIZE, Format('%dx%d', [Bmp.Width, Bmp.Height]));
      Responde(FR_CAPTURE, GPeticion.Salida);
      Responde(FR_MS, Format('%d,%d', [MsCarga, MsPintado]));
    except
      on E: ERender do
      begin
        Responde(FR_ERROR, E.Message); // ya lleva su etiqueta
        Result := FR_RC_ERROR;
      end;
      on E: Exception do
      begin
        Responde(FR_ERROR, E.ClassName + ': ' + E.Message);
        Result := FR_RC_ERROR;
      end;
    end;
  finally
    Bmp.Free;
    F.Free;
    Cargador.Free;
    SinCuadro.Free;
    ParaVigia;
  end;
end;

end.
