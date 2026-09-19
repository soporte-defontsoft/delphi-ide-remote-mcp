@echo off
REM ============================================================================
REM  BuildGroup.bat - compila el GRUPO entero (MCP-delphi.groupproj):
REM  el servidor (DelphiLspMcp), DelphiStyleConvert, LspCoreTest y el nodo
REM  de escritorio. Cada proyecto compila en SU plataforma por defecto
REM  (Win64 los tres primeros, Linux64 el nodo) y ADEMAS, en Release, el
REM  nodo se compila TAMBIEN para Win64: un mismo codigo, dos escritorios.
REM
REM  USO:  BuildGroup.bat [quiet^|normal^|verbose] [make^|build] [Debug^|Release]
REM        (sin parametros = quiet make Debug)
REM
REM  NOTAS (medidas, no teoricas):
REM    - El nodo Linux necesita /p:PlatformSDK=Linux64.sdk o el linker muere
REM      con "cannot find -lgcc_s". Pasarlo no molesta a los proyectos
REM      Windows, asi que va siempre.
REM    - Con Release, el binario recien compilado del nodo se copia a
REM      node\McpLinuxDesktop (lo que viaja en la release y lo que el server
REM      autodespliega por sello node.ver): un solo comando deja TODO listo.
REM    - Requiere el SDK Linux64 aprovisionado una vez (delphi_paserver
REM      command=get-sdk, o el SDK Manager del IDE).
REM ============================================================================

setlocal
set RSVARS=C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat
set GRUPO=%~dp0MCP-delphi.groupproj

set MODE=%~1
if "%MODE%"=="" set MODE=quiet
set BTARGET=%~2
if "%BTARGET%"=="" set BTARGET=make
set BCONFIG=%~3
if "%BCONFIG%"=="" set BCONFIG=Debug

set MSBTARGET=
if /I "%BTARGET%"=="make" set MSBTARGET=Make
if /I "%BTARGET%"=="build" set MSBTARGET=Build
if "%MSBTARGET%"=="" (
  echo [BuildGroup] Target no reconocido: %BTARGET%
  echo Uso: BuildGroup.bat [quiet^|normal^|verbose] [make^|build] [Debug^|Release]
  exit /b 1
)

if /I not "%BCONFIG%"=="Debug" if /I not "%BCONFIG%"=="Release" (
  echo [BuildGroup] Config no reconocida: %BCONFIG%
  echo Uso: BuildGroup.bat [quiet^|normal^|verbose] [make^|build] [Debug^|Release]
  exit /b 1
)

set VERBOSITY=
if /I "%MODE%"=="quiet"   set VERBOSITY=/v:quiet /clp:ErrorsOnly;Summary;NoItemAndPropertyList /nologo
if /I "%MODE%"=="normal"  set VERBOSITY=/v:minimal /nologo
if /I "%MODE%"=="verbose" set VERBOSITY=/v:detailed
if "%VERBOSITY%"=="" (
  echo [BuildGroup] Modo no reconocido: %MODE%
  echo Uso: BuildGroup.bat [quiet^|normal^|verbose] [make^|build] [Debug^|Release]
  exit /b 1
)

call "%RSVARS%"
if errorlevel 1 (
  echo [BuildGroup] ERROR: no se pudo cargar rsvars.bat
  exit /b 1
)

echo [BuildGroup] Compilando el grupo (%BCONFIG%, %MSBTARGET%)...
msbuild "%GRUPO%" /t:%MSBTARGET% /p:Config=%BCONFIG% /p:PlatformSDK=Linux64.sdk %VERBOSITY%
if errorlevel 1 exit /b 1

if /I "%BCONFIG%"=="Release" (
  copy /Y "%~dp0src_linux_desktop_node\Linux64\Release\McpLinuxDesktop" "%~dp0node\McpLinuxDesktop" >nul
  if errorlevel 1 (
    echo [BuildGroup] AVISO: no pude copiar el nodo Release a node\McpLinuxDesktop
    exit /b 1
  )
  echo [BuildGroup] node\McpLinuxDesktop actualizado desde el build Release.

  REM El grupo compila cada proyecto en su plataforma por defecto, asi que
  REM la version Windows del nodo se pide aparte. Mismo .dpr, mismas ordenes:
  REM lo que cambia es con quien habla por debajo (GDI+SendInput en vez de
  REM portal+libei), elegido con IFDEF en tiempo de compilacion.
  echo [BuildGroup] Compilando el nodo tambien para Win64...
  msbuild "%~dp0src_linux_desktop_node\McpLinuxDesktop.dproj" /t:%MSBTARGET% /p:Config=Release /p:Platform=Win64 %VERBOSITY%
  if errorlevel 1 (
    echo [BuildGroup] AVISO: el nodo no compilo para Win64
    exit /b 1
  )
  copy /Y "%~dp0src_linux_desktop_node\Win64\Release\McpLinuxDesktop.exe" "%~dp0node\McpWinDesktop.exe" >nul
  if errorlevel 1 (
    echo [BuildGroup] AVISO: no pude copiar el nodo Windows a node\McpWinDesktop.exe
    exit /b 1
  )
  echo [BuildGroup] node\McpWinDesktop.exe actualizado desde el build Release.
)

echo [BuildGroup] Grupo completo OK.
endlocal
exit /b 0
