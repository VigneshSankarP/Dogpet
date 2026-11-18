@echo off
echo Checking DogPet.ps1 for mistakes...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$e=$null; $null=[System.Management.Automation.Language.Parser]::ParseFile('%~dp0DogPet.ps1',[ref]$null,[ref]$e); if($e){$e|%%{'LINE '+$_.Extent.StartLineNumber+': '+$_.Message}}else{'No mistakes found in the file.'}"
echo.
echo Now starting the dog. Leave this window open...
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -NoExit -File "%~dp0DogPet.ps1"
pause
