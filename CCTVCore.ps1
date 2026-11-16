# WinCare Portable v1.8 - Catalogo seguro de CCTV
# Diseñado por DevPoderSEO. No realiza conexiones ni usa credenciales.
#requires -Version 5.1

$script:CCTVAllowedRoles=@('Cámara IP','NVR','DVR','Switch PoE','Router','Otro')
$script:CCTVAllowedPorts=@(80,443,554,8000,8080,8899)
function Test-CCTVValue([string]$Text,[int]$MaxLength) {
    if($null -eq $Text){return $false}
    if($Text.Length -gt $MaxLength -or $Text -match '[\x00-\x08\x0B\x0C\x0E-\x1F]'){return $false}
    return $true
}
function Assert-CCTVDevice($Device) {
    if($null -eq $Device){throw 'El dispositivo no puede estar vacío.'}
    $name=([string]$Device.Nombre).Trim()
    $ip=([string]$Device.IP).Trim()
    $role=[string]$Device.Tipo
    $site=([string]$Device.Ubicacion).Trim()
    $notes=([string]$Device.Notas).Trim()
    $id=[string]$Device.Id
    $port=0
    if(-not [int]::TryParse([string]$Device.Puerto,[ref]$port) -or $port -notin $script:CCTVAllowedPorts){throw 'El puerto debe estar en la lista autorizada.'}
    if([string]::IsNullOrWhiteSpace($name) -or -not (Test-CCTVValue $name 100)){throw 'Nombre inválido (1-100 caracteres).'}
    if((Get-WCIPv4Scope $ip) -ne 'Privada'){throw 'Solo se permiten direcciones IPv4 privadas, sin abreviaturas.'}
    if($role -notin $script:CCTVAllowedRoles){throw 'Tipo de equipo no permitido.'}
    if(-not (Test-CCTVValue $site 120) -or -not (Test-CCTVValue $notes 320)){throw 'Ubicación o nota demasiado extensa.'}
    if($notes -match '(?i)(password|contraseña|passphrase|secret|token|clave)\s*[:=]'){throw 'No guardes contraseñas ni tokens en las notas.'}
    $parsed=[guid]::Empty
    if([string]::IsNullOrWhiteSpace($id)){$id=[guid]::NewGuid().ToString('N')}
    elseif(-not [guid]::TryParse($id,[ref]$parsed)){throw 'Identificador de dispositivo inválido.'}
    return [pscustomobject]@{Id=$id;Nombre=$name;IP=$ip;Tipo=$role;Puerto=$port;Ubicacion=$site;Notas=$notes}
}
function Get-CCTVConfigPath([string]$ProjectRoot,[switch]$PreferWritable) {
    $near=Join-Path $ProjectRoot 'Configuracion\cctv-dispositivos.json'
    if(-not $PreferWritable) {
        if(Test-Path -LiteralPath $near -PathType Leaf){return $near}
        $docs=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WinCarePortable\Configuracion\cctv-dispositivos.json'
        if(Test-Path -LiteralPath $docs -PathType Leaf){return $docs}
        return $near
    }
    $parent=Split-Path -Parent $near
    try {
        if(-not (Test-Path -LiteralPath $parent)){[void](New-Item -Path $parent -ItemType Directory -Force -ErrorAction Stop)}
        $probe=Join-Path $parent ('.wincare-'+[guid]::NewGuid().ToString('N')+'.tmp')
        [IO.File]::WriteAllText($probe,'test')
        Remove-Item -LiteralPath $probe -Force -ErrorAction Stop
        return $near
    }catch{
        $parent=Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WinCarePortable\Configuracion'
        if(-not (Test-Path -LiteralPath $parent)){[void](New-Item -Path $parent -ItemType Directory -Force -ErrorAction Stop)}
        return (Join-Path $parent 'cctv-dispositivos.json')
    }
}
function Read-CCTVDevices([string]$Path){
    if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){return @()}
    $doc=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if([string]$doc.Version -ne '1'){throw 'Versión de catálogo CCTV no compatible. No se sobrescribirá.'}
    $list=@()
    $keys=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($item in @($doc.Dispositivos)){
        if($null -eq $item){continue}
        $validated=Assert-CCTVDevice $item
        if(-not $keys.Add($validated.Id)){throw 'Dispositivos duplicados en el catálogo.'}
        $list+=$validated
    }
    return $list
}
function Save-CCTVDevices([object[]]$Devices,[string]$Path){
    if(@($Devices).Count -gt 100){throw 'Máximo 100 equipos por catálogo.'}
    $validated=@()
    $keys=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($device in @($Devices)){
        if($null -eq $device){continue}
        $item=Assert-CCTVDevice $device
        if(-not $keys.Add($item.Id)){throw 'Identificador duplicado.'}
        $validated+=$item
    }
    $folder=Split-Path -Parent $Path
    if(-not (Test-Path -LiteralPath $folder)){[void](New-Item -Path $folder -ItemType Directory -Force)}
    $temp=Join-Path $folder ('.cctv-'+[guid]::NewGuid().ToString('N')+'.json')
    try{
        $json=ConvertTo-Json -InputObject ([ordered]@{Version=1;Actualizado=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss');Dispositivos=@($validated)}) -Depth 6
        [IO.File]::WriteAllText($temp,$json,(New-Object Text.UTF8Encoding($true)))
        if(Test-Path -LiteralPath $Path -PathType Leaf){Copy-Item -LiteralPath $Path -Destination ($Path+'.bak') -Force -ErrorAction Stop}
        Move-Item -LiteralPath $temp -Destination $Path -Force -ErrorAction Stop
    }finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue}}
}
function Test-CCTVTarget($Device,$Interface){
    if($null -eq $Device -or $null -eq $Interface){return $false}
    try{
        $item=Assert-CCTVDevice $Device
        return (Test-WCLanTargetAllowed ([string]$item.IP) $Interface)
    }catch{return $false}
}
