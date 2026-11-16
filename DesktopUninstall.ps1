# WinCare Portable - Selector seguro de desinstalación de escritorio
# Diseñado por DevPoderSEO | PowerShell 5.1
# Solo construye planes, nunca ejecuta cadenas arbitrarias desde el registro.
#requires -Version 5.1

function Get-WCDesktopUninstallPlan(
    [string]$Name,
    [string]$Key,
    [string]$UninstallString,
    [string]$WindowsInstaller
) {
    $msiGuid='^\{[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}$'
    if ($WindowsInstaller -eq '1' -and $Key -match $msiGuid) {
        return [pscustomobject]@{
            Method='MSI'; Display='MSI'; Id=$Key; Exe=''; Details='Paquete MSI validado. Windows Installer solicitará confirmación y podría requerir administrador.'
        }
    }

    # Los juegos de Steam usan una clave "Steam App N" y pueden contener
    # steam://uninstall/N en el registro. Ignorar totalmente los demás
    # argumentos de UninstallString y construir un URI nuevo solo con N.
    if ($Key -match '^Steam App ([1-9][0-9]{0,9})$') {
        $appId=[string]$matches[1]
        if($UninstallString -match '(?i)steam://uninstall/([1-9][0-9]{0,9})(?![0-9])') {
            if([string]$matches[1] -eq $appId) {
                return [pscustomobject]@{
                    Method='Steam'; Display='Steam'; Id=$appId; Exe=''; Details='Se abrirá Steam para confirmar la desinstalación de este juego. No se elimina Steam ni otros juegos.'
                }
            }
        }
    }

    # Solo ejecutables de desinstalación CONOCIDOS, SIN parámetros,
    # situados en Program Files / carpeta Programs del usuario.
    # No ejecutar nunca cmd, PowerShell, mshta, rundll32, scripts
    # ni cadenas con parámetros de instalación silenciosa.
    $command=([string]$UninstallString).Trim()
    $exe=''
    if ($command -match '^"([A-Za-z]:\\[^"]+\.exe)"$') {
        $exe=[string]$matches[1]
    } elseif ($command -match '^([A-Za-z]:\\.+\.exe)$') {
        $exe=[string]$matches[1]
    }
    if ($exe -and (Test-WCAllowedUninstallerLocation $exe)) {
        return [pscustomobject]@{
            Method='Uninstaller'; Display='Desinstalador'; Id=''; Exe=$exe; Details='Se iniciará el asistente de desinstalación sin parámetros ocultos. Revisa sus opciones antes de aceptar.'
        }
    }

    return [pscustomobject]@{
        Method='Windows'; Display='Abrir Windows'; Id=''; Exe=''; Details='Se abrirá Aplicaciones instaladas de Windows para completar la desinstalación. WinCare no ejecutará cadenas desconocidas.'
    }
}

function Test-WCAllowedUninstallerLocation([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z]:\\') {return $false}
    if ([IO.Path]::GetFileName($Path) -notmatch '^(?i:unins[0-9]*|uninstall|uninstaller|uninst|remove)\.exe$'){return $false}
    try {
        $full=[IO.Path]::GetFullPath($Path)
        if($full -ne $Path -and -not [string]::Equals($full,$Path,[StringComparison]::OrdinalIgnoreCase)){return $false}
        $allowed=@(
            [Environment]::GetFolderPath('ProgramFiles'),
            [Environment]::GetEnvironmentVariable('ProgramFiles(x86)'),
            (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Programs')
        ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        foreach($root in $allowed){
            $canon=[IO.Path]::GetFullPath($root).TrimEnd('\')
            if($full.StartsWith(($canon+'\'),[StringComparison]::OrdinalIgnoreCase)){return $true}
        }
    }catch{}
    return $false
}

function Get-WCSteamExecutable {
    $candidates=New-Object 'System.Collections.Generic.List[string]'
    try {
        $reg=Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam' -ErrorAction Stop
        if($reg.SteamExe){[void]$candidates.Add([string]$reg.SteamExe)}
        if($reg.SteamPath){[void]$candidates.Add((Join-Path ([string]$reg.SteamPath) 'steam.exe'))}
    }catch{}
    foreach($key in @('HKLM:\SOFTWARE\WOW6432Node\Valve\Steam','HKLM:\SOFTWARE\Valve\Steam')){
        try {
            $reg=Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            if($reg.InstallPath){[void]$candidates.Add((Join-Path ([string]$reg.InstallPath) 'steam.exe'))}
        }catch{}
    }
    foreach($base in @([Environment]::GetEnvironmentVariable('ProgramFiles(x86)'),[Environment]::GetFolderPath('ProgramFiles'))){
        if($base){[void]$candidates.Add((Join-Path $base 'Steam\steam.exe'))}
    }
    foreach($value in $candidates){
        try {
            $path=[IO.Path]::GetFullPath(([string]$value).Replace('/','\'))
            if([IO.Path]::GetFileName($path) -ne 'steam.exe'){continue}
            if($path -notmatch '(?i)\\Steam\\steam\.exe$'){continue}
            if($path.StartsWith(([IO.Path]::GetFullPath($env:WINDIR).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){continue}
            if($path -match '(?i)\\(temp|downloads|desktop|startup)\\'){continue}
            $item=Get-Item -LiteralPath $path -Force -ErrorAction Stop
            if($item -isnot [IO.FileInfo] -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){continue}
            return $path
        }catch{}
    }
    return ''
}

function Assert-WCTrustedSteamExecutable([string]$Path) {
    if([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)){
        throw 'No se encontró el ejecutable de Steam.'
    }
    try{
        $signature=Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
        if([string]$signature.Status -ne 'Valid' -or $null -eq $signature.SignerCertificate -or
            [string]$signature.SignerCertificate.Subject -notmatch '(?i)Valve'){
            throw 'El ejecutable no tiene una firma válida de Valve.'
        }
    }catch{
        throw 'No se pudo confirmar la firma de Steam. WinCare no abrirá este ejecutable; usa la Biblioteca de Steam manualmente. Detalle: '+$_.Exception.Message
    }
}
function Start-WCSteamUninstall([string]$AppId) {
    if($AppId -notmatch '^[1-9][0-9]{0,9}$'){throw 'ID de juego Steam inválido.'}
    $client=Get-WCSteamExecutable
    if(-not $client){throw 'No se encontró el ejecutable de Steam instalado. Abre Steam manualmente y desinstala el juego desde Biblioteca > Administrar > Desinstalar.'}
    Assert-WCTrustedSteamExecutable $client
    [void](Start-Process -FilePath $client -ArgumentList ('steam://uninstall/'+$AppId) -ErrorAction Stop)
}
function Open-WCSteamClient {
    $client=Get-WCSteamExecutable
    if(-not $client){throw 'No se encontró Steam instalado. Puedes abrirlo manualmente desde Windows.'}
    Assert-WCTrustedSteamExecutable $client
    [void](Start-Process -FilePath $client -ErrorAction Stop)
}

function Start-WCInteractiveUninstaller([string]$Path) {
    if(-not (Test-WCAllowedUninstallerLocation $Path)){throw 'Ruta de desinstalador no permitida. Usa la configuración de Windows.'}
    $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if($item -isnot [IO.FileInfo] -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'El desinstalador no es un archivo normal o es un enlace. Usa Windows.'}
    # No se emplean parámetros, ShellExecute ni cmd /c.
    [void](Start-Process -FilePath $item.FullName -ErrorAction Stop)
}
