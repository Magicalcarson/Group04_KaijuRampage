@echo off
rem Kaiju Rampage FULL GAME : write the full game into the Nexys A7 QSPI flash (boots by itself at power-on, JP1 = QSPI)
rem and leave the full game running on the board. Uses the already-built bit\kaiju_top_flash.mcs (no rebuild).
setlocal
set "HERE=%~dp0"
cd /d "%HERE%bit"
call :find_vivado
if not defined VIV goto no_vivado
echo Vivado : %VIV%
echo Writing the FULL GAME into the QSPI flash (about 1-3 minutes) ...
echo FLASHING > "%HERE%bit\flash_full_status.txt"
call "%VIV%" -mode batch -nojournal -log "%HERE%bit\flash_full_now.log" -source "%HERE%program_full_flash.tcl"
if errorlevel 1 goto failed
echo OK > "%HERE%bit\flash_full_status.txt"
echo.
echo ===== OK : FULL GAME written to flash and running on the board =====
pause
exit /b 0

:failed
echo FAILED > "%HERE%bit\flash_full_status.txt"
echo ===== FAILED : see bit\flash_full_now.log (USB cable, power switch, close Vivado Hardware Manager) =====
pause
exit /b 1

:no_vivado
echo NO_VIVADO > "%HERE%bit\flash_full_status.txt"
echo Vivado not found.
pause
exit /b 1

:find_vivado
set "VIV="
for /d %%D in ("C:\Xilinx\Vivado\*") do if exist "%%D\bin\vivado.bat" set "VIV=%%D\bin\vivado.bat"
if defined VIV exit /b 0
for /d %%D in ("C:\AMDDesignTools\*") do if exist "%%D\Vivado\bin\vivado.bat" set "VIV=%%D\Vivado\bin\vivado.bat"
if defined VIV exit /b 0
for /d %%D in ("C:\Xilinx\Vivado_Lab\*") do if exist "%%D\bin\vivado_lab.bat" set "VIV=%%D\bin\vivado_lab.bat"
if defined VIV exit /b 0
for /f "delims=" %%P in ('where vivado.bat 2^>nul') do if not defined VIV set "VIV=%%P"
exit /b 0
