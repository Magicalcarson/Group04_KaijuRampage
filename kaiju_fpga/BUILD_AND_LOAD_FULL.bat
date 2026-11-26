@echo off
rem Kaiju Rampage FULL GAME : rebuild bit/kaiju_top.bit from rtl/ (~5 min) then load it into the Nexys A7 over USB (JTAG).
setlocal
set "HERE=%~dp0"
cd /d "%HERE%bit"
call :find_vivado
if not defined VIV goto no_vivado
echo Vivado : %VIV%
echo [1/2] Building the full game (about 5 minutes) ...
echo BUILDING > "%HERE%bit\full_status.txt"
call "%VIV%" -mode batch -nojournal -log "%HERE%bit\build_full_now.log" -source "%HERE%build.tcl"
if errorlevel 1 goto build_failed
if not exist "%HERE%bit\kaiju_top.bit" goto build_failed
echo [2/2] Loading kaiju_top.bit into the board ...
echo PROGRAMMING > "%HERE%bit\full_status.txt"
call "%VIV%" -mode batch -nojournal -log "%HERE%bit\program_full_now.log" -source "%HERE%program_full_jtag.tcl"
if errorlevel 1 goto prog_failed
echo OK > "%HERE%bit\full_status.txt"
echo.
echo ===== OK : the FULL GAME is running on the board =====
pause
exit /b 0

:build_failed
echo BUILD_FAILED > "%HERE%bit\full_status.txt"
echo ===== BUILD FAILED : see bit\build_full_now.log =====
pause
exit /b 1

:prog_failed
echo PROGRAM_FAILED > "%HERE%bit\full_status.txt"
echo ===== LOAD FAILED : check the USB cable, the power switch, and close Vivado Hardware Manager =====
pause
exit /b 1

:no_vivado
echo NO_VIVADO > "%HERE%bit\full_status.txt"
echo Vivado not found.
pause
exit /b 1

:find_vivado
set "VIV="
for /d %%D in ("C:\Xilinx\Vivado\*") do if exist "%%D\bin\vivado.bat" set "VIV=%%D\bin\vivado.bat"
if defined VIV exit /b 0
for /d %%D in ("C:\AMDDesignTools\*") do if exist "%%D\Vivado\bin\vivado.bat" set "VIV=%%D\Vivado\bin\vivado.bat"
if defined VIV exit /b 0
for /f "delims=" %%P in ('where vivado.bat 2^>nul') do if not defined VIV set "VIV=%%P"
exit /b 0
