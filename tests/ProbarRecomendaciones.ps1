# WinCare Portable | Diseñado por DevPoderSEO
# Solo usa archivos de prueba aislados en TEMP. Nunca desinstala programas.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'AppRules.ps1')
$tempDir=Join-Path ([IO.Path]::GetTempPath()) ('WinCare-Reglas-Test-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -Path $tempDir -ItemType Directory -Force)
try{
    $path=Join-Path $tempDir 'recomendaciones.json'
    $entries=@(Set-WCPolicyRule -Rules @() -Type 'Appx' -Name 'Clipchamp.Clipchamp' -Publisher '' -Recommendation 'Conservar' -Reason 'Cliente usa esta herramienta.')
    $entries=@(Set-WCPolicyRule -Rules $entries -Type 'Win32' -Name 'Programa de prueba' -Publisher 'Fabricante A' -Recommendation 'Opcional' -Reason 'No es esencial para el usuario.')
    if($entries.Count -ne 2){throw 'No se agregaron ambas recomendaciones.'}
    Save-WCPolicyRules -Rules $entries -Path $path
    $loaded=@(Get-WCPolicyRules -Path $path)
    if($loaded.Count -ne 2){throw 'Lectura JSON incompleta.'}
    $protected=Get-WCPolicyMatch -Rules $loaded -Type 'Appx' -Name 'clipchamp.clipchamp' -Publisher 'Cualquier fabricante'
    if($null -eq $protected -or $protected.Recomendacion -ne 'Conservar'){throw 'Regla Conservar no coincide.'}
    $unrelated=Get-WCPolicyMatch -Rules $loaded -Type 'Win32' -Name 'Programa de prueba' -Publisher 'Fabricante B'
    if($null -ne $unrelated){throw 'Regla Win32 coincidió con fabricante equivocado.'}
    $entries=@(Remove-WCPolicyRule -Rules $loaded -Type 'Appx' -Name 'Clipchamp.Clipchamp' -Publisher '')
    if($entries.Count -ne 1){throw 'Eliminar una regla afectó otra regla.'}
    $errorCaught=$false
    try{[void](Test-WCPolicyEntry ([pscustomobject]@{Tipo='Win32';Nombre='';Fabricante='';Recomendacion='Opcional';Motivo=''}))}catch{$errorCaught=$true}
    if(-not $errorCaught){throw 'El programa aceptó una regla sin nombre.'}
    Write-Host 'OK: reglas exactas, protección Conservar, fabricante, persistencia JSON, eliminación y validación.'
}finally{
    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
}
