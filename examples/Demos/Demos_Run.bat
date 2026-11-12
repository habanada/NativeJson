@echo off
rem ---------------------------------------------------------------
rem  Runs all built demos one after another and evaluates the
rem  exit code: 0 = all checks passed.
rem  Usage:  Demos_Run.bat [Win32|Win64] [Debug|Release]
rem ---------------------------------------------------------------
setlocal enabledelayedexpansion

set PLATFORM=%~1
if "%PLATFORM%"=="" set PLATFORM=Win32

set CONFIG=%~2
if "%CONFIG%"=="" set CONFIG=Release

set BINROOT=%~dp0..\..\bin

set TOTAL=0
set RED=0
set MISSING=0

for %%F in ("%~dp0Demo*.dpr") do (
  set EXE=%BINROOT%\%%~nF\%PLATFORM%\%CONFIG%\%%~nF.exe
  if not exist "!EXE!" (
    echo MISSING: !EXE!
    set /a MISSING+=1
  ) else (
    echo.
    echo ============================================================
    echo   %%~nF
    echo ============================================================
    "!EXE!" auto
    set RC=!errorlevel!
    set /a TOTAL+=1
    if not "!RC!"=="0" (
      set /a RED+=1
      echo ^>^>^> %%~nF reports errors ^(exit code !RC!^)
    )
  )
)

echo.
echo ============================================================
echo   %TOTAL% demos ran, %RED% of them with errors, %MISSING% not built
echo ============================================================
if not "%RED%"=="0" exit /b 1
if not "%MISSING%"=="0" exit /b 1

endlocal
