@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem Issue 184 regression harness. Usage: test_issue184.cmd PACKAGE_CONTENTS_DIR
rem Offline, non-admin. uv/uvx are replaced by stub .exe files built with in-box csc.exe.
if "%~1"=="" (echo usage: %~nx0 PACKAGE_CONTENTS_DIR& exit /b 2)
set "SRC=%~f1\update.bat"
if not exist "%SRC%" (echo SETUP: missing update.bat& exit /b 2)
set "WORK=%TEMP%\issue184_%RANDOM%%RANDOM%"
mkdir "%WORK%\stubs" || exit /b 2
set "CSC=%WINDIR%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%WINDIR%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" (echo SETUP: csc.exe not found& exit /b 2)

>"%WORK%\uv.cs" echo class P{static int Main(){System.Console.WriteLine("uv 0.0.0 (stub)");return 0;}}
>"%WORK%\uvx.cs" echo class P{static int Main(){string r=System.Environment.GetEnvironmentVariable("STUB_UVX_RC");if(r!=null){System.Console.Error.WriteLine("stub uvx failure");return int.Parse(r);}System.Console.WriteLine("2026-10-12");return 0;}}
"%CSC%" /nologo /out:"%WORK%\stubs\uv.exe" "%WORK%\uv.cs" >nul || (echo SETUP: csc uv failed& exit /b 2)
"%CSC%" /nologo /out:"%WORK%\stubs\uvx.exe" "%WORK%\uvx.cs" >nul || (echo SETUP: csc uvx failed& exit /b 2)
set "PATH=%WORK%\stubs;%PATH%"
set "STUB_UVX_RC="
uv --version | findstr /c:"(stub)" >nul || (echo SETUP: uv stub is not first on PATH& exit /b 2)
set FAILS=0

rem A: writable folder -> success, timestamp written
call :prep writable
call :run writable
call :expect_rc writable 0
call :expect_log writable "INFO: Update done." 1
call :expect_ts writable 2026-10-12

rem B: update_timestamp.txt is a directory -> redirection fails, uvx never runs
call :prep dirblock
mkdir "%CASEDIR%\update_timestamp.txt"
call :run dirblock
call :expect_rc dirblock 1
call :expect_log dirblock "ERROR: Could not create timestamp" 1
call :expect_log dirblock "INFO: Update done." 0

rem C: existing read-only timestamp file -> redirection fails, old value kept
call :prep readonly
>"%CASEDIR%\update_timestamp.txt" echo 2000-01-01
attrib +r "%CASEDIR%\update_timestamp.txt"
call :run readonly
call :expect_rc readonly 1
call :expect_log readonly "ERROR: Could not create timestamp" 1
call :expect_log readonly "INFO: Update done." 0
call :expect_ts readonly 2000-01-01
attrib -r "%CASEDIR%\update_timestamp.txt"

rem D: uvx itself fails in a writable folder -> pre-existing error path preserved
call :prep uvxfail
set "STUB_UVX_RC=1"
call :run uvxfail
set "STUB_UVX_RC="
call :expect_rc uvxfail 1
call :expect_log uvxfail "ERROR: Could not create timestamp" 1
call :expect_log uvxfail "INFO: Update done." 0

if %FAILS% EQU 0 (
    echo ALL PASS
    rmdir /s /q "%WORK%"
    exit /b 0
)
echo %FAILS% check(s) failed; logs kept in %WORK%
exit /b 1

:prep
set "CASEDIR=%WORK%\%~1"
mkdir "%CASEDIR%"
copy /y "%SRC%" "%CASEDIR%\update.bat" >nul
exit /b 0

:run
pushd "%CASEDIR%"
cmd /d /c update.bat <nul >"%WORK%\%~1.log" 2>&1
set "RC=%ERRORLEVEL%"
popd
exit /b 0

:expect_rc
if "%RC%"=="%~2" (echo ok   %~1 exit=%RC%) else (echo FAIL %~1 exit=%RC% expected %~2& set /a FAILS+=1)
exit /b 0

:expect_log
findstr /l /c:"%~2" "%WORK%\%~1.log" >nul
if errorlevel 1 (set "HIT=0") else set "HIT=1"
if "%HIT%"=="%~3" (echo ok   %~1 log[%~2]=%HIT%) else (echo FAIL %~1 log[%~2]=%HIT% expected %~3& set /a FAILS+=1)
exit /b 0

:expect_ts
set "TS="
set /p TS=<"%CASEDIR%\update_timestamp.txt"
if "%TS%"=="%~2" (echo ok   %~1 timestamp=%TS%) else (echo FAIL %~1 timestamp=[%TS%] expected %~2& set /a FAILS+=1)
exit /b 0

