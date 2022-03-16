@echo off
set "FirefoxFolder="
Title Firefox Updater
curl --silent -o "%TEMP%\firefoxdl.txt" "https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US"
powershell -command "(Get-Content "%TEMP%\firefoxdl.txt") | ForEach-Object { $_ -replace '^.*releases.([0-9][0-9]).*$','$1' } | Set-Content "%TEMP%\firefoxdl.txt""
set /p FirefoxVersion=<"%TEMP%\firefoxdl.txt"
del "%TEMP%\firefoxdl.txt"
Echo The Latest Release of Firefox is version %FirefoxVersion%.

rem Get path of installed Firefox directly from Windows registry.
for /F "skip=2 tokens=1,2*" %%A in ('%SystemRoot%\System32\reg.exe query "HKLM\Software\Microsoft\Windows\CurrentVersion\App Paths\firefox.exe" /v Path 2^>nul') do (
    if /I "%%A" == "Path" (
        set "FirefoxFolder=%%C"
        if defined FirefoxFolder goto CheckFirefox
    )
)

:InstallFirefox

:UpdateFireFox
Echo Downloading Firefox Version %FirefoxVersion%...
curl --silent -L -o "%TEMP%\firefoxcurrent.exe" "https://download.mozilla.org/?product=firefox-latest-ssl&os=win64&lang=en-US"
Echo Installing Firefox Version %FirefoxVersion%, please wait...
tasklist /fi "imagename eq firefox.exe" |find ":" > nul
if errorlevel 1 taskkill /f /im "firefox.exe" >nul 2>&1
start "" /wait "%TEMP%\firefoxcurrent.exe" -ms
Echo Cleaning Up!
del "%TEMP%\firefoxcurrent.exe"
goto :EOF

:CheckFirefox
if not exist "%FirefoxFolder%\firefox.exe" goto InstallFirefox

rem Check if version of Mozilla Firefox starts with defined number.
rem The space at beginning makes sure to find the major version number.
"%FirefoxFolder%\firefox.exe" -v | %SystemRoot%\System32\more | %SystemRoot%\System32\find.exe " %FirefoxVersion%" >nul
if errorlevel 1 (
    echo Updating Firefox to version %FirefoxVersion% ...
    goto UpdateFireFox
)

echo However, Firefox version %FirefoxVersion% is already installed.