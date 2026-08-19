@echo off
REM ============================================================================
REM  BuildWithParams.bat - Build parametrizable del proyecto (plantilla estandar)
REM  (optimizado para agentes de IA y sesiones con contexto limitado)
REM
REM  INSTALACION EN UN PROYECTO NUEVO (2 pasos, la plantilla estandar.
REM  patterns/delphi-build-msbuild.md):
REM    1. Copiar este fichero como BuildWithParams.bat a la carpeta del .dproj.
REM    2. Rellenar las DOS lineas de CONFIGURACION DEL PROYECTO de abajo.
REM  Si el proyecto no compila para Android, no pasa nada: simplemente no usar
REM  esas plataformas (o borrar sus ramas si molestan).
REM ============================================================================
REM
REM  USO:  BuildWithParams.bat [quiet^|normal^|verbose] [Win32^|Win64^|Android^|Android64^|AllWin^|All] [make^|build] [Debug^|Release]
REM
REM  MODOS DE OUTPUT:
REM    quiet    (DEFAULT) solo errores + Build succeeded/FAILED + tiempo.
REM                       ~5 lineas de output. Minimo gasto de contexto.
REM    normal             warnings + hitos msbuild. ~30-80 lineas.
REM    verbose            output detallado por unit, paths, flags. 200+ lineas.
REM
REM  DECISION PARA AGENTES DE IA:
REM    - Verificar que un cambio compila: "quiet Win64 make Debug" (= sin params).
REM    - Cambio que toca codigo especifico Android (JNI, permisos, lifecycle,
REM      rutas de ficheros): anadir "Android64" o "All".
REM    - Si quiet da error poco claro -> repetir en verbose la MISMA plataforma.
REM    - Al CAMBIAR de plataforma (Win32<->Win64) con .dcu compartidos: usar
REM      "build", nunca "make" (F2048 Bad unit format si no).
REM    - Atribucion de warnings: compilar en "normal" ANTES de editar para tener
REM      la lista base, y comparar tras editar. Un warning que no estaba = tuyo.
REM
REM  NOTAS:
REM    - Sin parametros equivale a: BuildWithParams.bat quiet Win64 make Debug
REM    - Exit code: 0 = OK, 1 = parametro invalido o error de rsvars o build
REM    - Android: este bat NO despliega (/t:Deploy va aparte y en Android debe
REM      ser SIEMPRE /t:Build;Deploy).
REM ============================================================================

setlocal

REM ----------------- CONFIGURACION DEL PROYECTO (rellenar) --------------------
set PROYECTO=%~dp0DelphiLspMcp.dproj
set RSVARS=C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat
REM ----------------------------------------------------------------------------

set MODE=%~1
if "%MODE%"=="" set MODE=quiet

set BPLAT=%~2
if "%BPLAT%"=="" set BPLAT=Win64

set BTARGET=%~3
if "%BTARGET%"=="" set BTARGET=make

set BCONFIG=%~4
if "%BCONFIG%"=="" set BCONFIG=Debug

REM --- Validar BTARGET ---
set MSBTARGET=
if /I "%BTARGET%"=="make" (
  set MSBTARGET=Make
) else if /I "%BTARGET%"=="build" (
  set MSBTARGET=Build
) else (
  echo [BuildWithParams] Target no reconocido: %BTARGET%
  echo Uso: BuildWithParams.bat [quiet^|normal^|verbose] [Win32^|Win64^|Android^|Android64^|AllWin^|All] [make^|build] [Debug^|Release]
  exit /b 1
)

REM --- Validar BCONFIG ---
if /I not "%BCONFIG%"=="Debug" if /I not "%BCONFIG%"=="Release" (
  echo [BuildWithParams] Config no reconocida: %BCONFIG%
  echo Uso: BuildWithParams.bat [quiet^|normal^|verbose] [Win32^|Win64^|Android^|Android64^|AllWin^|All] [make^|build] [Debug^|Release]
  exit /b 1
)

call "%RSVARS%"
if errorlevel 1 (
  echo [BuildWithParams] ERROR: no se pudo cargar rsvars.bat
  exit /b 1
)

REM --- Validar MODE ---
set VERBOSITY=
if /I "%MODE%"=="quiet" (
  set VERBOSITY=/v:quiet /clp:ErrorsOnly;Summary;NoItemAndPropertyList /nologo
) else if /I "%MODE%"=="normal" (
  set VERBOSITY=/v:minimal /nologo
) else if /I "%MODE%"=="verbose" (
  set VERBOSITY=/v:detailed
) else (
  echo [BuildWithParams] Modo no reconocido: %MODE%
  echo Uso: BuildWithParams.bat [quiet^|normal^|verbose] [Win32^|Win64^|Android^|Android64^|AllWin^|All] [make^|build] [Debug^|Release]
  exit /b 1
)

REM --- Validar BPLAT ---
if /I "%BPLAT%"=="Win32"     ( call :BUILD_ONE Win32 & goto CHECK )
if /I "%BPLAT%"=="Win64"     ( call :BUILD_ONE Win64 & goto CHECK )
if /I "%BPLAT%"=="Android"   ( call :BUILD_ONE Android & goto CHECK )
if /I "%BPLAT%"=="Android64" ( call :BUILD_ONE Android64 & goto CHECK )
if /I "%BPLAT%"=="AllWin"    ( call :BUILD_ALLWIN & goto CHECK )
if /I "%BPLAT%"=="All"       ( call :BUILD_ALL & goto CHECK )

echo [BuildWithParams] Plataforma no reconocida: %BPLAT%
echo Uso: BuildWithParams.bat [quiet^|normal^|verbose] [Win32^|Win64^|Android^|Android64^|AllWin^|All] [make^|build] [Debug^|Release]
exit /b 1

:CHECK
if errorlevel 1 exit /b 1
goto END

:BUILD_ONE
echo [BuildWithParams] Compilando %~1 (%BCONFIG%)...
msbuild "%PROYECTO%" /t:%MSBTARGET% /p:Config=%BCONFIG% /p:Platform=%~1 %VERBOSITY%
if errorlevel 1 exit /b 1
exit /b 0

:BUILD_ALLWIN
call :BUILD_ONE Win32
if errorlevel 1 exit /b 1
call :BUILD_ONE Win64
if errorlevel 1 exit /b 1
exit /b 0

:BUILD_ALL
call :BUILD_ONE Win32
if errorlevel 1 exit /b 1
call :BUILD_ONE Win64
if errorlevel 1 exit /b 1
call :BUILD_ONE Android
if errorlevel 1 exit /b 1
call :BUILD_ONE Android64
if errorlevel 1 exit /b 1
exit /b 0

:END
endlocal
exit /b 0
