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
REM    - El SDK de Linux NO se pasa a ciegas: si el proyecto declara su
REM      PlatformSDK manda EL PROYECTO; si no, el activo del SDK Manager
REM      (Default_Linux64); y en ultimo caso, el primer .sdk de Linux64.
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
REM  1) Si el PROYECTO ya declara su SDK (PlatformSDK: lo que pone el IDE en
REM     Project Options y lo que escribe delphi_config set-sdk), NO se le pisa.
REM     Una propiedad en la linea de msbuild GANA a la del .dproj, asi que
REM     pasarla aqui anulaba la eleccion del proyecto (medido 2026-09-20: el
REM     proyecto decia zorin18 y este script compilaba con fedora44).
set SDKPROYECTO=
if "%SDKLINUX%"=="" findstr /I /C:"<PlatformSDK>" "%~dp0src_desktop_node\McpDesktopNode.dproj" >nul 2>&1 && set SDKPROYECTO=1
REM  2) Si el proyecto no dice nada, manda el ACTIVO del SDK Manager
REM     (Default_Linux64), que es lo que hace el IDE y lo que hace delphi_build.
if "%SDKLINUX%"=="" if not defined SDKPROYECTO (
  for /f "tokens=2,*" %%A in ('reg query "HKCU\Software\Embarcadero\BDS\%DELPHIVER%\PlatformSDKs" /v Default_Linux64 2^>nul ^| findstr /I "Default_Linux64"') do set SDKLINUX=%%B
)
REM  3) Y como ultimo recurso, el primer .sdk registrado que sea de Linux64.
if "%SDKLINUX%"=="" if not defined SDKPROYECTO (
  for %%F in ("%APPDATA%\Embarcadero\BDS\%DELPHIVER%\*.sdk") do (
    if "!SDKLINUX!"=="" (
      findstr /I /C:"<Profile_platform>Linux64<" "%%F" >nul 2>&1 && set SDKLINUX=%%~nxF
    )
  )
)
set ARGSDK=
if not "%SDKLINUX%"=="" set ARGSDK=/p:PlatformSDK=%SDKLINUX%
if "%SDKLINUX%"=="" if not defined SDKPROYECTO echo [BuildGroup] AVISO: no hay ningun SDK de Linux64 registrado; el nodo Linux no enlazara. Traelo con delphi_paserver command=get-sdk.

if defined SDKPROYECTO echo [BuildGroup] Compilando el grupo (%BCONFIG%, %MSBTARGET%); el SDK de Linux lo manda el proyecto (PlatformSDK).
if not defined SDKPROYECTO echo [BuildGroup] Compilando el grupo (%BCONFIG%, %MSBTARGET%) con SDK Linux "%SDKLINUX%"...
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

  REM El lanzador para destinos WINDOWS (PAServer alli no ejecuta guiones):
  REM viaja en node\ junto a los dos nodos y el servidor lo sube por trabajo.
  echo [BuildGroup] Compilando el lanzador McpRunJob (Win64)...
  msbuild "%~dp0src_run_job\McpRunJob.dproj" /t:%MSBTARGET% /p:Config=Release /p:Platform=Win64 %VERBOSITY%
  if errorlevel 1 (
    echo [BuildGroup] AVISO: el lanzador McpRunJob no compilo
    exit /b 1
  )
  copy /Y "%~dp0src_run_job\Win64\Release\McpRunJob.exe" "%~dp0node\McpRunJob.exe" >nul
  if errorlevel 1 (
    echo [BuildGroup] AVISO: no pude copiar el lanzador a node\McpRunJob.exe
    exit /b 1
  )
  echo [BuildGroup] node\McpRunJob.exe actualizado desde el build Release.
)

echo [BuildGroup] Grupo completo OK.
endlocal
exit /b 0
