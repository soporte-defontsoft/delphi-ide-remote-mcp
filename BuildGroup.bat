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
REM      node\McpDesktopNode (lo que viaja en la release y lo que el server
REM      autodespliega por sello node.ver): un solo comando deja TODO listo.
REM    - Requiere el SDK Linux64 aprovisionado una vez (delphi_paserver
REM      command=get-sdk, o el SDK Manager del IDE).
REM ============================================================================

setlocal enabledelayedexpansion
REM  La version con la que compila ESTE grupo. Una maquina puede tener dos o
REM  tres Delphi instalados: si hace falta otra, se cambia aqui (o con
REM  set DELPHIVER=38.0 antes de llamar) y todo lo de abajo la sigue.
if "%DELPHIVER%"=="" set DELPHIVER=37.0
set RSVARS=C:\Program Files (x86)\Embarcadero\Studio\%DELPHIVER%\bin\rsvars.bat
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

REM  El SDK de Linux NO se clava por nombre: desde 2026-09-20 cada maquina
REM  destino tiene el suyo (zorin18.sdk, fedora44.sdk...) y "Linux64.sdk" puede
REM  no existir. Se coge el primer .sdk del IDE cuya plataforma sea Linux64.
REM  Se puede imponer uno con  set MCP_LINUX_SDK=zorin18.sdk  antes de llamar,
REM  y con varios conviene: el bueno es el de la glibc MAS VIEJA del parque
REM  (un binario enlazado con glibc vieja corre en las distros nuevas; al
REM  reves muere con "GLIBC_2.xx not found"). Comprobacion de un vistazo:
REM     grep -aoE "GLIBC_[0-9]+\.[0-9]+" node\McpDesktopNode | sort -uV | tail -1
set SDKLINUX=%MCP_LINUX_SDK%
if "%SDKLINUX%"=="" (
  for %%F in ("%APPDATA%\Embarcadero\BDS\%DELPHIVER%\*.sdk") do (
    if "!SDKLINUX!"=="" (
      findstr /I /C:"<Profile_platform>Linux64<" "%%F" >nul 2>&1 && set SDKLINUX=%%~nxF
    )
  )
)
set ARGSDK=
if not "%SDKLINUX%"=="" set ARGSDK=/p:PlatformSDK=%SDKLINUX%
if "%SDKLINUX%"=="" echo [BuildGroup] AVISO: no hay ningun SDK de Linux64 registrado; el nodo Linux no enlazara. Traelo con delphi_paserver command=get-sdk.

echo [BuildGroup] Compilando el grupo (%BCONFIG%, %MSBTARGET%) con SDK Linux "%SDKLINUX%"...
msbuild "%GRUPO%" /t:%MSBTARGET% /p:Config=%BCONFIG% %ARGSDK% %VERBOSITY%
if errorlevel 1 exit /b 1

if /I "%BCONFIG%"=="Release" (
  copy /Y "%~dp0src_desktop_node\Linux64\Release\McpDesktopNode" "%~dp0node\McpDesktopNode" >nul
  if errorlevel 1 (
    echo [BuildGroup] AVISO: no pude copiar el nodo Release a node\McpDesktopNode
    exit /b 1
  )
  echo [BuildGroup] node\McpDesktopNode actualizado desde el build Release.

  REM El grupo compila cada proyecto en su plataforma por defecto, asi que
  REM la version Windows del nodo se pide aparte. Mismo .dpr, mismas ordenes:
  REM lo que cambia es con quien habla por debajo (GDI+SendInput en vez de
  REM portal+libei), elegido con IFDEF en tiempo de compilacion.
  echo [BuildGroup] Compilando el nodo tambien para Win64...
  msbuild "%~dp0src_desktop_node\McpDesktopNode.dproj" /t:%MSBTARGET% /p:Config=Release /p:Platform=Win64 %VERBOSITY%
  if errorlevel 1 (
    echo [BuildGroup] AVISO: el nodo no compilo para Win64
    exit /b 1
  )
  copy /Y "%~dp0src_desktop_node\Win64\Release\McpDesktopNode.exe" "%~dp0node\McpDesktopNode.exe" >nul
  if errorlevel 1 (
    echo [BuildGroup] AVISO: no pude copiar el nodo Windows a node\McpDesktopNode.exe
    exit /b 1
  )
  echo [BuildGroup] node\McpDesktopNode.exe actualizado desde el build Release.
)

echo [BuildGroup] Grupo completo OK.
endlocal
exit /b 0
