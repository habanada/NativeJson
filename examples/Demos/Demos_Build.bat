@echo off
rem ---------------------------------------------------------------
rem  Builds all demo programs with MSBuild.
rem  Usage:  Demos_Build.bat [Win32|Win64] [Debug|Release]
rem ---------------------------------------------------------------
setlocal

set PLATFORM=%~1
if "%PLATFORM%"=="" set PLATFORM=Win32

set CONFIG=%~2
if "%CONFIG%"=="" set CONFIG=Release

if "%BDS%"=="" (
  if exist "%ProgramFiles(x86)%\Embarcadero\Studio\23.0\bin\rsvars.bat" (
    call "%ProgramFiles(x86)%\Embarcadero\Studio\23.0\bin\rsvars.bat"
  ) else (
    echo ERROR: RAD Studio not found. Please call rsvars.bat first.
    exit /b 1
  )
)

set FAILED=0
for %%F in ("%~dp0Demo*.dproj") do (
  echo.
  echo === Building %%~nF [%PLATFORM% ^| %CONFIG%] ===
  msbuild "%%~fF" /t:Build /p:Config=%CONFIG% /p:Platform=%PLATFORM% /nologo /verbosity:minimal
  if errorlevel 1 set FAILED=1
)

echo.
if "%FAILED%"=="1" (
  echo RESULT: At least one demo failed to compile.
  exit /b 1
) else (
  echo RESULT: All demos were compiled.
  echo Output: %~dp0..\..\bin\^<Project^>\%PLATFORM%\%CONFIG%
)

endlocal
