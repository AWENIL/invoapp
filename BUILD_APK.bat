@echo off
chcp 65001 >nul
cd /d "%~dp0"

if "%ANDROID_HOME%"=="" if "%ANDROID_SDK_ROOT%"=="" (
  echo ANDROID_HOME не задан. Установите Android Studio ^(SDK^) и задайте переменную, например:
  echo   set ANDROID_HOME=%%LOCALAPPDATA%%\Android\Sdk
  echo Затем снова запустите этот файл.
  exit /b 1
)

flutter pub get
if errorlevel 1 exit /b 1

flutter build apk --release
if errorlevel 1 exit /b 1

echo.
echo Готово: build\app\outputs\flutter-apk\app-release.apk
explorer /select,"%CD%\build\app\outputs\flutter-apk\app-release.apk"
