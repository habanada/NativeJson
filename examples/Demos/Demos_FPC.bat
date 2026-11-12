@echo off
setlocal enabledelayedexpansion

set FPC=%~1
if "%FPC%"=="" set FPC=C:\fpcupdeluxe\fpc\bin\x86_64-win64\fpc.exe
if not exist "%FPC%" (
  echo ERROR: %FPC% not found. Usage: Demos_FPC.bat [path\fpc.exe]
  exit /b 1
)

pushd "%~dp0..\.."
set ROOT=%CD%
set SRCDIR=%ROOT%\src
set DEMODIR=%ROOT%\examples\Demos
set BINDIR=%ROOT%\bin\FPC
set UNITDIR=%ROOT%\build\FPC
if not exist "%BINDIR%" mkdir "%BINDIR%"

set TOTAL=0
set RED=0

for %%F in ("%DEMODIR%\Demo*.dpr" "%ROOT%\Tests\Package2\Test2_*.dpr") do (
  echo.
  echo ============================================================
  echo   %%~nF
  echo ============================================================
  if exist "%UNITDIR%" rmdir /s /q "%UNITDIR%"
  mkdir "%UNITDIR%"
  "%FPC%" -B -vew -FU"%UNITDIR%" -FE"%BINDIR%" -Fu"%SRCDIR%" -Fu"%DEMODIR%" -Fi"%SRCDIR%" "%%~fF" > "%BINDIR%\%%~nF.log" 2>&1
  set RC=!errorlevel!
  set /a TOTAL+=1
  if not "!RC!"=="0" (
    set /a RED+=1
    echo ^>^>^> %%~nF does not compile, see %BINDIR%\%%~nF.log
  ) else (
    "%BINDIR%\%%~nF.exe" auto
    if not "!errorlevel!"=="0" (
      set /a RED+=1
      echo ^>^>^> %%~nF reports errors
    )
  )
)

popd
echo.
if "%RED%"=="0" (
  echo RESULT: All %TOTAL% programs built with FPC and passed.
) else (
  echo RESULT: %RED% of %TOTAL% programs with errors.
  exit /b 1
)

endlocal
