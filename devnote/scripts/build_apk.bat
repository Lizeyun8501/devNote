@echo off
REM ============================================================
REM  DevNote APK Build Launcher (CMD entry point)
REM  Forwards all arguments to scripts\build_apk.ps1
REM ============================================================
REM
REM  IMPORTANT: Do NOT use 2>&1 to merge stderr here.
REM  Reason: When parent PowerShell invokes a .bat with 2>&1, every
REM  stderr line from the child PowerShell is wrapped as an
REM  ErrorRecord, polluting the error stream. The build_apk.ps1
REM  script uses System.Diagnostics.Process internally so child
REM  stdout/stderr inherit the console handle directly - no merge
REM  is needed at this level.
REM
REM  Use -File (not -Command) to avoid parameter parsing differences.
REM  Use -NonInteractive to prevent hanging on interactive prompts.

setlocal
set "SCRIPT_DIR=%~dp0"
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%SCRIPT_DIR%build_apk.ps1" %*
set "EXITCODE=%ERRORLEVEL%"
exit /b %EXITCODE%
