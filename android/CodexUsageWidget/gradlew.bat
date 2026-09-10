@echo off
setlocal
set "APP_HOME=%~dp0"
set "JAR=%APP_HOME%gradle\wrapper\gradle-wrapper.jar"
set "URL=https://raw.githubusercontent.com/gradle/gradle/v9.3.1/gradle/wrapper/gradle-wrapper.jar"
set "SHA=b3a875ddc1f044746e1b1a55f645584505f4a10438c1afea9f15e92a7c42ec13"

if not exist "%JAR%" (
  echo Downloading Gradle wrapper...
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; Invoke-WebRequest -UseBasicParsing -Uri '%URL%' -OutFile '%JAR%'"
  if errorlevel 1 exit /b 1
)

for /f "usebackq delims=" %%H in (`powershell.exe -NoProfile -Command "(Get-FileHash -Algorithm SHA256 -LiteralPath '%JAR%').Hash.ToLowerInvariant()"`) do set "ACTUAL=%%H"
if /i not "%ACTUAL%"=="%SHA%" (
  echo Gradle wrapper checksum mismatch.
  del /q "%JAR%" >nul 2>nul
  exit /b 1
)

java.exe -classpath "%JAR%" org.gradle.wrapper.GradleWrapperMain %*
