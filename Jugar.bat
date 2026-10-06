@echo off
rem Lanza Taskbar Pokemon con el Godot del Escritorio (sin ventana de consola).
set "GODOT=%USERPROFILE%\Desktop\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
  echo No encuentro %GODOT%
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0"
