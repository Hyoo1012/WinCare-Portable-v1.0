# WinCare Portable v1.5 - Reglas de aplicaciones | Diseñado por DevPoderSEO
# Módulo de datos: nunca ejecuta desinstaladores ni cambia componentes Windows.
#requires -Version 5.1

$script:WCPolicyDefaultPath = Join-Path $PSScriptRoot 'Configuracion\recomendaciones.json'

function Test-WCPolicyEntry($Entry) {
    if ($null -eq $Entry) { throw 'Regla vacía.' }
    $type=[string]$Entry.Tipo
    $name=[string]$Entry.Nombre
    $publisher=[string]$Entry.Fabricante
    $choice=[string]$Entry.Recomendacion
    $reason=[string]$Entry.Motivo
    if ($type -notin @('Appx','Win32')) { throw 'Tipo inválido: solo Appx o Win32.' }
    if ([string]::IsNullOrWhiteSpace($name) -or $name.Trim().Length -gt 180 -or $name -match '[\x00-\x1f]') { throw 'Nombre inválido (1 a 180 caracteres, sin controles).' }
    if ($publisher.Length -gt 180 -or $publisher -match '[\x00-\x1f]') { throw 'Fabricante inválido.' }
    if ($choice -notin @('Conservar','Opcional')) { throw 'Recomendación inválida: Conservar u Opcional.' }
    if ($reason.Length -gt 360 -or $reason -match '[\x00-\x1f]') { throw 'Motivo inválido (máximo 360 caracteres).' }
    return [pscustomobject]@{
        Tipo=$type
        Nombre=$name.Trim()
        Fabricante=$publisher.Trim()
        Recomendacion=$choice
        Motivo=$reason.Trim()
    }
}

function Get-WCPolicyRules([string]$Path=$script:WCPolicyDefaultPath) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $document = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($null -eq $document -or [string]$document.Version -ne '1') { throw 'Archivo de recomendaciones con versión no compatible.' }
    if ($null -eq $document.Reglas) { return @() }
    $rules=@()
    foreach($entry in @($document.Reglas)) {
        $rules += (Test-WCPolicyEntry $entry)
    }
    return $rules
}

function Get-WCPolicyMatch(
    [object[]]$Rules,
    [string]$Type,
    [string]$Name,
    [string]$Publisher=''
) {
    if ($Type -notin @('Appx','Win32') -or [string]::IsNullOrWhiteSpace($Name)) { return $null }
    foreach($rule in @($Rules)) {
        if($null -eq $rule){continue}
        if([string]$rule.Tipo -ne $Type){continue}
        if(-not [string]::Equals(([string]$rule.Nombre).Trim(),$Name.Trim(),[StringComparison]::OrdinalIgnoreCase)){continue}
        # Appx se identifica por Name y Win32 por nombre + fabricante, sin coincidencias parciales.
        if($Type -eq 'Win32' -and -not [string]::Equals(([string]$rule.Fabricante).Trim(),$Publisher.Trim(),[StringComparison]::OrdinalIgnoreCase)){continue}
        return $rule
    }
    return $null
}

function Set-WCPolicyRule(
    [object[]]$Rules,
    [string]$Type,
    [string]$Name,
    [string]$Publisher,
    [string]$Recommendation,
    [string]$Reason
) {
    $new=Test-WCPolicyEntry ([pscustomobject]@{Tipo=$Type;Nombre=$Name;Fabricante=$Publisher;Recomendacion=$Recommendation;Motivo=$Reason})
    $out=@()
    foreach($rule in @($Rules)) {
        if($null -eq $rule){continue}
        $matches=Get-WCPolicyMatch -Rules @($new) -Type ([string]$rule.Tipo) -Name ([string]$rule.Nombre) -Publisher ([string]$rule.Fabricante)
        if($null -eq $matches){$out += (Test-WCPolicyEntry $rule)}
    }
    $out += $new
    return $out
}

function Remove-WCPolicyRule([object[]]$Rules,[string]$Type,[string]$Name,[string]$Publisher) {
    $out=@()
    foreach($rule in @($Rules)){
        if($null -eq $rule){continue}
        $match=Get-WCPolicyMatch -Rules @($rule) -Type $Type -Name $Name -Publisher $Publisher
        if($null -eq $match){$out += (Test-WCPolicyEntry $rule)}
    }
    return $out
}

function Save-WCPolicyRules([object[]]$Rules,[string]$Path=$script:WCPolicyDefaultPath) {
    $validated=@()
    $keys=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($rule in @($Rules)) {
        if($null -eq $rule){continue}
        $entry=Test-WCPolicyEntry $rule
        $key=$entry.Tipo+'|'+$entry.Nombre+'|'+$entry.Fabricante
        if(-not $keys.Add($key)){throw ('Regla duplicada: '+$entry.Nombre)}
        $validated += $entry
    }
    $folder=Split-Path -Parent $Path
    if(-not (Test-Path -LiteralPath $folder -PathType Container)){[void](New-Item -Path $folder -ItemType Directory -Force -ErrorAction Stop)}
    $json=ConvertTo-Json -InputObject ([ordered]@{Version=1;Actualizado=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss');Reglas=@($validated)}) -Depth 5
    $temporary=Join-Path $folder ('.wincare-'+[guid]::NewGuid().ToString('N')+'.json')
    try {
        [IO.File]::WriteAllText($temporary,$json,(New-Object System.Text.UTF8Encoding($true)))
        # Escribir primero el archivo temporal evita dejar JSON parcialmente escrito.
        if(Test-Path -LiteralPath $Path -PathType Leaf) {
            # La copia de respaldo permite recuperar reglas anteriores si falla la escritura.
            $backup=$Path+'.bak'
            Copy-Item -LiteralPath $Path -Destination $backup -Force -ErrorAction Stop
        }
        Move-Item -LiteralPath $temporary -Destination $Path -Force -ErrorAction Stop
    } finally {
        if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue}
    }
}
