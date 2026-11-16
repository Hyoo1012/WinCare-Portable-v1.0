# WinCare Portable v1.9 | Diseñado por DevPoderSEO
# Pruebas puras sin procesos externos ni desinstalaciones reales.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'DesktopUninstall.ps1')
$guid='{11111111-1111-1111-1111-111111111111}'
$msi=Get-WCDesktopUninstallPlan -Name 'Programa MSI prueba' -Key $guid -WindowsInstaller '1' -UninstallString 'msiexec.exe /x {11111111-1111-1111-1111-111111111111}'
if($msi.Method -ne 'MSI'){throw 'No reconoció MSI por GUID.'}
$steam=Get-WCDesktopUninstallPlan -Name 'Dota 2' -Key 'Steam App 570' -UninstallString '"C:\Program Files (x86)\Steam\steam.exe" steam://uninstall/570' -WindowsInstaller '0'
if($steam.Method -ne 'Steam' -or $steam.Id -ne '570'){throw 'No reconoció Dota 2 / Steam App 570.'}
$malicious=Get-WCDesktopUninstallPlan -Name 'Juego prueba' -Key 'Steam App 570' -UninstallString '"C:\Malware\steam.exe" steam://uninstall/999' -WindowsInstaller '0'
if($malicious.Method -eq 'Steam'){throw 'Aceptó URI Steam con ID diferente al registro.'}
$untrusted=Get-WCDesktopUninstallPlan -Name 'Programa prueba' -Key 'Uninstaller' -UninstallString 'powershell.exe -command Remove-Item C:\*' -WindowsInstaller '0'
if($untrusted.Method -ne 'Windows'){throw 'Aceptó ejecutar PowerShell del registro.'}
$cmd=Get-WCDesktopUninstallPlan -Name 'Programa prueba' -Key 'Uninstaller' -UninstallString 'cmd.exe /c del C:\*' -WindowsInstaller '0'
if($cmd.Method -ne 'Windows'){throw 'Aceptó ejecutar cmd del registro.'}
$quiet=Get-WCDesktopUninstallPlan -Name 'Programa prueba' -Key 'Program' -UninstallString '"C:\Program Files\Programa\uninstall.exe" /S' -WindowsInstaller '0'
if($quiet.Method -ne 'Windows'){throw 'Aceptó argumentos silenciosos no autorizados.'}
$plain=Get-WCDesktopUninstallPlan -Name 'Programa prueba' -Key 'Program' -UninstallString '"C:\Program Files\Programa\uninstall.exe"' -WindowsInstaller '0'
if($plain.Method -ne 'Uninstaller'){throw 'No reconoció asistente interactivo sin argumentos.'}
$internal=Get-WCDesktopUninstallPlan -Name 'Programa prueba' -Key 'Program' -UninstallString '"C:\Windows\System32\uninstall.exe"' -WindowsInstaller '0'
if($internal.Method -ne 'Windows'){throw 'Permitió ejecutar archivo de sistema.'}
$temp=Get-WCDesktopUninstallPlan -Name 'Programa prueba' -Key 'Program' -UninstallString '"C:\Users\User\AppData\Local\Temp\uninstall.exe"' -WindowsInstaller '0'
if($temp.Method -ne 'Windows'){throw 'Permitió desinstalador en carpeta temporal.'}
$windows=Get-WCDesktopUninstallPlan -Name 'Programa prueba' -Key 'Program' -UninstallString '' -WindowsInstaller '0'
if($windows.Method -ne 'Windows'){throw 'No aplicó fallback a Windows.'}
Write-Host 'OK: Dota 2 via Steam, MSI, instalador firmado pendiente, comandos peligrosos bloqueados, fallback Windows.'
