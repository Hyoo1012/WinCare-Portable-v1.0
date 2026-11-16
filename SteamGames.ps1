# WinCare Portable - Inventario de bibliotecas Steam
# Diseñado por DevPoderSEO. Solo lee manifiestos locales .acf; nunca borra datos.
#requires -Version 5.1

function Get-WCSteamGamesFromLibraries([string[]]$Libraries) {
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $found=New-Object 'System.Collections.Generic.List[object]'
    foreach($library in @($Libraries | Select-Object -First 32)){
        if([string]::IsNullOrWhiteSpace($library)){continue}
        try{
            $root=[IO.Path]::GetFullPath($library)
            if($root -notmatch '^[A-Za-z]:\\'){continue}
            $rootItem=Get-Item -LiteralPath $root -Force -ErrorAction Stop
            if($rootItem -isnot [IO.DirectoryInfo] -or ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){continue}
            $steamapps=Join-Path $root 'steamapps'
            $folder=Get-Item -LiteralPath $steamapps -Force -ErrorAction Stop
            if($folder -isnot [IO.DirectoryInfo] -or ($folder.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){continue}
            foreach($manifest in @(Get-ChildItem -LiteralPath $steamapps -File -Filter 'appmanifest_*.acf' -ErrorAction Stop | Select-Object -First 800)){
                $game=Get-WCSteamGameFromManifest -Path $manifest.FullName
                if($null -eq $game){continue}
                if($seen.Add($game.AppId)){
                    [void]$found.Add($game)
                    if($found.Count -ge 800){break}
                }
            }
            if($found.Count -ge 800){break}
        }catch{
            # Un USB o disco desconectado no impide leer las demás bibliotecas.
            continue
        }
    }
    return @($found.ToArray())
}
function Get-WCSteamGameFromManifest([string]$Path) {
    try{
        if([string]::IsNullOrWhiteSpace($Path)){return $null}
        $full=[IO.Path]::GetFullPath($Path)
        if($full -notmatch '^[A-Za-z]:\\'){return $null}
        $file=Get-Item -LiteralPath $full -Force -ErrorAction Stop
        if($file -isnot [IO.FileInfo] -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $null}
        if($file.Length -gt 1048576){return $null}
        if($file.Name -notmatch '^appmanifest_([1-9][0-9]{0,9})\.acf$'){return $null}
        $appId=[string]$matches[1]
        $parent=Split-Path -Parent $file.FullName
        if((Split-Path -Leaf $parent) -ne 'steamapps'){return $null}
        $root=Split-Path -Parent $parent
        $text=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop
        if($text -notmatch '(?im)^\s*"appid"\s+"([1-9][0-9]{0,9})"\s*$'){return $null}
        if([string]$matches[1] -ne $appId){return $null}
        $name='Juego Steam '+$appId
        if($text -match '(?im)^\s*"name"\s+"([^"\r\n]{1,160})"\s*$'){
            $name=([string]$matches[1]).Trim()
        }
        if([string]::IsNullOrWhiteSpace($name)){return $null}
        return [pscustomobject]@{
            AppId=$appId
            Name=$name
            ManifestPath=$file.FullName
            LibraryPath=$root
        }
    }catch{return $null}
}
function Get-WCSteamLibraries {
    $candidates=New-Object 'System.Collections.Generic.List[string]'
    $steamExe=''
    if(Get-Command Get-WCSteamExecutable -ErrorAction SilentlyContinue){$steamExe=Get-WCSteamExecutable}
    if($steamExe){[void]$candidates.Add((Split-Path -Parent $steamExe))}
    foreach($base in @([Environment]::GetEnvironmentVariable('ProgramFiles(x86)'),[Environment]::GetFolderPath('ProgramFiles'))){
        if($base){[void]$candidates.Add((Join-Path $base 'Steam'))}
    }
    foreach($key in @('HKCU:\Software\Valve\Steam','HKLM:\SOFTWARE\WOW6432Node\Valve\Steam','HKLM:\SOFTWARE\Valve\Steam')){
        try{
            $reg=Get-ItemProperty -LiteralPath $key -ErrorAction Stop
            foreach($prop in @('SteamPath','InstallPath')){
                if($reg.$prop){[void]$candidates.Add(([string]$reg.$prop).Replace('/','\'))}
            }
        }catch{}
    }
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $result=New-Object 'System.Collections.Generic.List[string]'
    foreach($base in @($candidates)){
        try{
            $root=[IO.Path]::GetFullPath([string]$base).TrimEnd('\')
            if($root -notmatch '^[A-Za-z]:\\' -or -not $seen.Add($root)){continue}
            $dir=Get-Item -LiteralPath $root -Force -ErrorAction Stop
            if($dir -isnot [IO.DirectoryInfo] -or ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){continue}
            if(Test-Path -LiteralPath (Join-Path $root 'steamapps') -PathType Container){[void]$result.Add($root)}
            $config=Join-Path $root 'steamapps\libraryfolders.vdf'
            if(-not (Test-Path -LiteralPath $config -PathType Leaf)){continue}
            $item=Get-Item -LiteralPath $config -ErrorAction Stop
            if($item.Length -gt 1048576){continue}
            $vdf=Get-Content -LiteralPath $config -Raw -Encoding UTF8 -ErrorAction Stop
            foreach($m in [regex]::Matches($vdf,'(?im)^\s*"(?:path|\d+)"\s+"([^"\r\n]+)"')){
                $candidate=([string]$m.Groups[1].Value).Replace('\\','\')
                if($candidate -notmatch '^[A-Za-z]:\\'){continue}
                $folder=[IO.Path]::GetFullPath($candidate).TrimEnd('\')
                if($seen.Add($folder) -and (Test-Path -LiteralPath (Join-Path $folder 'steamapps') -PathType Container)){
                    [void]$result.Add($folder)
                }
                if($result.Count -ge 32){break}
            }
        }catch{}
        if($result.Count -ge 32){break}
    }
    return @($result.ToArray())
}
