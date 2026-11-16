# WinCare Portable v2.0 - Pruebas de juegos Steam en bibliotecas
# Diseñado por DevPoderSEO. Sin conexión ni desinstalaciones.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'SteamGames.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('WinCareSteam-'+[guid]::NewGuid().ToString('N'))
try{
    $steamapps=Join-Path $temp 'steamapps'
    [void](New-Item -ItemType Directory -Path $steamapps -Force)
    $path=Join-Path $steamapps 'appmanifest_570.acf'
    $vdf=@'
"AppState"
{
    "appid" "570"
    "Universe" "1"
    "name" "Dota 2"
    "installdir" "dota 2 beta"
}
'@
    Set-Content -LiteralPath $path -Encoding UTF8 -Value $vdf
    $g=Get-WCSteamGameFromManifest $path
    if($null -eq $g -or $g.AppId -ne '570' -or $g.Name -ne 'Dota 2'){throw 'No se leyó Dota 2 de un appmanifest válido.'}
    $games=@(Get-WCSteamGamesFromLibraries -Libraries @($temp))
    if($games.Count -ne 1 -or $games[0].AppId -ne '570'){throw 'La biblioteca Steam no descubrió Dota 2.'}
    $bad=Join-Path $steamapps 'appmanifest_571.acf'
    Set-Content -LiteralPath $bad -Encoding UTF8 -Value $vdf
    if($null -ne (Get-WCSteamGameFromManifest $bad)){throw 'Se aceptó manifiesto con AppId diferente al nombre.'}
    $outside=Join-Path $temp 'appmanifest_570.acf'
    Set-Content -LiteralPath $outside -Encoding UTF8 -Value $vdf
    if($null -ne (Get-WCSteamGameFromManifest $outside)){throw 'Se aceptó archivo que no está en steamapps.'}
    $new=Join-Path $steamapps 'appmanifest_440.acf'
    Set-Content -LiteralPath $new -Encoding UTF8 -Value $vdf.Replace('"570"','"440"').Replace('"Dota 2"','"Team Fortress 2"')
    $all=@(Get-WCSteamGamesFromLibraries -Libraries @($temp,$temp))
    if($all.Count -ne 2){throw 'No se deduplicaron bibliotecas o se perdieron juegos.'}
    Write-Host 'OK: biblioteca Steam sin registro, Dota 2 570, múltiples juegos, duplicados y manifiestos inválidos bloqueados.'
}finally{
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
