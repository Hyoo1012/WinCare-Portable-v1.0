# WinCare Portable v2.0 - Autodiagnóstico de instalación
# Diseñado por DevPoderSEO. No hace cambios en Windows ni envía datos.
#requires -Version 5.1
param([object]$Owner,[switch]$SmokeTest)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:HRequired=@(
 'WinCare.ps1','AppRules.ps1','DesktopUninstall.ps1','SteamGames.ps1',
 'AppRecommendations.ps1','NetworkAudit.ps1','NetworkDiagnostics.ps1',
 'NetworkDiagnosticsCore.ps1','HardwareAudit.ps1','MaintenanceAudit.ps1',
 'TechToolkit.ps1','SupportTechnician.ps1','CCTVCore.ps1','CCTVAudit.ps1',
 'WinCareHealth.ps1','INICIAR_WINCARE.bat'
)
$script:HRows=New-Object System.Data.DataTable
foreach($n in @('Área','Verificación','Resultado','Observación')){[void]$script:HRows.Columns.Add($n,[string])}
$script:HReports=''
function Add-HResult([string]$Area,[string]$Name,[string]$Result,[string]$Detail){
 [void]$script:HRows.Rows.Add([object[]]@($Area,$Name,$Result,$Detail))
}
function Test-HWritable([string]$Folder){
 $probe=''
 try{
   if(-not (Test-Path -LiteralPath $Folder -PathType Container)){return $false}
   $probe=Join-Path $Folder ('.wincare-check-'+[guid]::NewGuid().ToString('N'))
   [IO.File]::WriteAllText($probe,'ok')
   return $true
 }catch{return $false}
 finally{if($probe -and (Test-Path -LiteralPath $probe -PathType Leaf)){Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue}}
}
function Get-HReports {
 foreach($path in @((Join-Path $PSScriptRoot 'Reportes'),(Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WinCarePortable\Reportes'))){
   try{
     if(-not (Test-Path -LiteralPath $path)){[void](New-Item -Path $path -ItemType Directory -Force)}
     if(Test-HWritable $path){return $path}
   }catch{}
 }
 return ''
}
function Read-HIntegrityChecks {
 $manifest=Join-Path $PSScriptRoot 'SHA256SUMS.txt'
 if(-not (Test-Path -LiteralPath $manifest -PathType Leaf)){
   Add-HResult 'Integridad' 'SHA256SUMS.txt' 'Información' 'No existe manifiesto SHA256: probablemente es una copia del código. Usa el ZIP generado en GitHub Actions.'
   return
 }
 $valid=0;$failed=0
 try{
   foreach($line in @(Get-Content -LiteralPath $manifest -Encoding UTF8 -ErrorAction Stop | Select-Object -First 256)){
     if($line -notmatch '^([0-9A-Fa-f]{64})  ([A-Za-z0-9_.\/-]+)$'){$failed++;continue}
     $expected=[string]$matches[1];$relative=[string]$matches[2]
     if($relative -match '(^|/)\.\.(/|$)' -or $relative -match '^/'){ $failed++;continue }
     $file=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot $relative.Replace('/','\')))
     $root=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')+'\'
     if(-not $file.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){$failed++;continue}
     if(-not (Test-Path -LiteralPath $file -PathType Leaf)){$failed++;continue}
     $actual=(Get-FileHash -LiteralPath $file -Algorithm SHA256 -ErrorAction Stop).Hash
     if($actual -eq $expected){$valid++}else{$failed++}
   }
   if($failed -eq 0 -and $valid -gt 0){
     Add-HResult 'Integridad' 'Archivos del paquete' 'Correcto' ('Coinciden los SHA256 de '+$valid+' archivos. No verifica autenticidad del editor.')
   }else{
     Add-HResult 'Integridad' 'Archivos del paquete' 'Revisar' ('Archivos correctos: '+$valid+'; diferentes, ilegibles o faltantes: '+$failed+'. Descarga un ZIP íntegro.')
   }
 }catch{Add-HResult 'Integridad' 'Archivos del paquete' 'Revisar' ('No se pudo revisar SHA256: '+$_.Exception.Message)}
}
function Read-HChecks {
 Read-HIntegrityChecks
 $script:HRows.Clear()
 $script:HReports=''
 foreach($file in $script:HRequired){
   $path=Join-Path $PSScriptRoot $file
   if(Test-Path -LiteralPath $path -PathType Leaf){
     Add-HResult 'Archivos' $file 'Correcto' 'El archivo requerido está presente.'
   }else{
     Add-HResult 'Archivos' $file 'Falta' 'Descarga el ZIP completo de WinCare y conserva todos los archivos juntos.'
   }
 }
 if($env:OS -eq 'Windows_NT'){
   Add-HResult 'Windows' 'Sistema operativo' 'Correcto' 'Windows detectado.'
 }else{
   Add-HResult 'Windows' 'Sistema operativo' 'Falta' 'WinCare solo se ejecuta dentro de Windows.'
 }
 if($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -ge 1){
   Add-HResult 'Windows' 'PowerShell 5.1' 'Correcto' ([string]$PSVersionTable.PSVersion)
 }else{
   Add-HResult 'Windows' 'PowerShell 5.1' 'Revisar' ('Versión actual: '+[string]$PSVersionTable.PSVersion+'. Ejecuta desde INICIAR_WINCARE.bat.')
 }
 if([Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA'){
   Add-HResult 'Windows' 'Interfaz STA' 'Correcto' 'Modo de interfaz correcto.'
 }else{
   Add-HResult 'Windows' 'Interfaz STA' 'Revisar' 'Ejecuta INICIAR_WINCARE.bat; usa -STA para formularios de Windows.'
 }
 try{
   $p=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
   if($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
     Add-HResult 'Permisos' 'Administrador' 'Correcto' 'Consultas de Windows que requieren elevación disponibles.'
   }else{
     Add-HResult 'Permisos' 'Administrador' 'Información' 'El inventario funciona parcialmente. Usa Solicitar permisos si lo necesitas.'
   }
 }catch{Add-HResult 'Permisos' 'Administrador' 'Revisar' $_.Exception.Message}
 if(Test-HWritable $PSScriptRoot){
   Add-HResult 'USB' 'Carpeta del programa' 'Correcto' 'Escribible. Se podrán guardar catálogos y reportes en el USB.'
 }else{
   Add-HResult 'USB' 'Carpeta del programa' 'Información' 'USB de solo lectura: los reportes se guardarán en Documentos cuando sea posible.'
 }
 $script:HReports=Get-HReports
 if($script:HReports){
   Add-HResult 'Reportes' 'Ruta de informes' 'Correcto' 'Existe una carpeta escribible para guardar reportes.'
 }else{
   Add-HResult 'Reportes' 'Ruta de informes' 'Revisar' 'No hay carpeta escribible en el USB ni Documentos.'
 }
 try{
   if(Test-Path -LiteralPath (Join-Path $PSScriptRoot 'AppRules.ps1')){
     . (Join-Path $PSScriptRoot 'AppRules.ps1')
     $rules=@(Get-WCPolicyRules)
     Add-HResult 'Protección' 'Recomendaciones' 'Correcto' ('Se pudieron leer las reglas. Cantidad: '+$rules.Count)
   }else{
     Add-HResult 'Protección' 'Recomendaciones' 'Falta' 'No puede verificarse la protección de programas.'
   }
 }catch{Add-HResult 'Protección' 'Recomendaciones' 'Revisar' ('Archivo de reglas ilegible; se deben bloquear desinstalaciones: '+$_.Exception.Message)}
 foreach($required in @('SteamGames.ps1','DesktopUninstall.ps1')){
   if(-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $required))){
     Add-HResult 'Steam' $required 'Falta' 'No se puede identificar o desinstalar juegos Steam con seguridad.'
   }
 }
 $problems=0
 foreach($r in $script:HRows.Rows){if([string]$r['Resultado'] -in @('Falta','Revisar')){$problems++}}
 if($problems){
   $script:HStatus.Text=('Se encontraron '+$problems+' elementos que debes revisar antes de utilizar todos los módulos.')
 }else{
   $script:HStatus.Text='Sin fallos de instalación detectados. Esto no sustituye pruebas con hardware y redes reales.'
 }
}
function Export-HReport {
 if(-not $script:HReports){$script:HReports=Get-HReports}
 if(-not $script:HReports){
   [void][Windows.Forms.MessageBox]::Show('No hay carpeta de reportes escribible.','Exportar autodiagnóstico','OK','Warning')
   return
 }
 try{
   $path=Join-Path $script:HReports ('autodiagnostico-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.csv')
   $items=@(foreach($r in $script:HRows.Rows){
     [pscustomobject]@{Area=[string]$r['Área'];Verificacion=[string]$r['Verificación'];Resultado=[string]$r['Resultado'];Observacion=[string]$r['Observación']}
   })
   $items|Export-Csv -LiteralPath $path -Encoding UTF8 -NoTypeInformation
   [void][Windows.Forms.MessageBox]::Show(('Archivo guardado en '+$path+'. No se envió por Internet.'),'Autodiagnóstico','OK','Information')
 }catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Error al exportar','OK','Warning')}
}
$script:HForm=New-Object Windows.Forms.Form
$script:HForm.Text='WinCare Portable v2.0 | Verificar instalación | DevPoderSEO'
$script:HForm.StartPosition='CenterParent'
$script:HForm.Size=New-Object Drawing.Size(1070,765)
$script:HForm.MinimumSize=New-Object Drawing.Size(880,620)
$script:HForm.BackColor=[Drawing.Color]::FromArgb(16,24,36)
$script:HForm.ForeColor=[Drawing.Color]::FromArgb(237,243,251)
$script:HForm.Font=New-Object Drawing.Font('Segoe UI',9)
$title=New-Object Windows.Forms.Label
$title.Text='Verificación integral de WinCare'
$title.Location=New-Object Drawing.Point(22,19)
$title.Size=New-Object Drawing.Size(760,36)
$title.Font=New-Object Drawing.Font('Segoe UI Semibold',18,[Drawing.FontStyle]::Bold)
$script:HForm.Controls.Add($title)
$brand=New-Object Windows.Forms.Label
$brand.Text='Diseñado por DevPoderSEO'
$brand.Location=New-Object Drawing.Point(770,25)
$brand.Size=New-Object Drawing.Size(267,24)
$brand.Anchor='Top,Right'
$brand.ForeColor=[Drawing.Color]::FromArgb(78,160,236)
$brand.TextAlign='MiddleRight'
$script:HForm.Controls.Add($brand)
$desc=New-Object Windows.Forms.Label
$desc.Text='Comprueba módulos, PowerShell, permisos, reglas y capacidad de guardar reportes. No limpia ni desinstala.'
$desc.Location=New-Object Drawing.Point(24,66)
$desc.Size=New-Object Drawing.Size(980,29)
$desc.ForeColor=[Drawing.Color]::FromArgb(180,194,211)
$script:HForm.Controls.Add($desc)
$bar=New-Object Windows.Forms.FlowLayoutPanel
$bar.Location=New-Object Drawing.Point(18,103)
$bar.Size=New-Object Drawing.Size(1010,45)
$bar.Anchor='Top,Left,Right'
$script:HForm.Controls.Add($bar)
$scan=New-Object Windows.Forms.Button
$scan.Text='Verificar de nuevo'
$scan.Size=New-Object Drawing.Size(200,35)
$scan.BackColor=[Drawing.Color]::FromArgb(40,133,216)
$scan.ForeColor=[Drawing.Color]::White
$scan.FlatStyle='Flat'
$scan.Add_Click({Read-HChecks})
$bar.Controls.Add($scan)
$export=New-Object Windows.Forms.Button
$export.Text='Guardar informe CSV'
$export.Size=New-Object Drawing.Size(220,35)
$export.Add_Click({Export-HReport})
$bar.Controls.Add($export)
$script:HGrid=New-Object Windows.Forms.DataGridView
$script:HGrid.Location=New-Object Drawing.Point(19,154)
$script:HGrid.Size=New-Object Drawing.Size(1000,500)
$script:HGrid.Anchor='Top,Bottom,Left,Right'
$script:HGrid.ReadOnly=$true
$script:HGrid.RowHeadersVisible=$false
$script:HGrid.AllowUserToAddRows=$false
$script:HGrid.AllowUserToDeleteRows=$false
$script:HGrid.AutoGenerateColumns=$false
$script:HGrid.AutoSizeColumnsMode='Fill'
$script:HGrid.BackgroundColor=[Drawing.Color]::FromArgb(28,41,59)
$script:HGrid.EnableHeadersVisualStyles=$false
$script:HGrid.ColumnHeadersDefaultCellStyle.BackColor=[Drawing.Color]::FromArgb(45,61,81)
$script:HGrid.ColumnHeadersDefaultCellStyle.ForeColor=$script:HForm.ForeColor
$script:HGrid.DefaultCellStyle.BackColor=[Drawing.Color]::FromArgb(28,41,59)
$script:HGrid.DefaultCellStyle.ForeColor=$script:HForm.ForeColor
$script:HGrid.DefaultCellStyle.SelectionBackColor=[Drawing.Color]::FromArgb(46,109,174)
$script:HGrid.DefaultCellStyle.SelectionForeColor=[Drawing.Color]::White
foreach($column in $script:HRows.Columns){
   $name=[string]$column.ColumnName
   $c=New-Object Windows.Forms.DataGridViewTextBoxColumn
   $c.Name=$name;$c.DataPropertyName=$name;$c.HeaderText=$name
   if($name -eq 'Observación'){$c.FillWeight=320}
   elseif($name -eq 'Verificación'){$c.FillWeight=140}
   else{$c.FillWeight=90}
   [void]$script:HGrid.Columns.Add($c)
}
$script:HGrid.DataSource=$script:HRows.DefaultView
$script:HForm.Controls.Add($script:HGrid)
$script:HStatus=New-Object Windows.Forms.Label
$script:HStatus.Text='Ninguna comprobación realizada.'
$script:HStatus.Location=New-Object Drawing.Point(22,669)
$script:HStatus.Size=New-Object Drawing.Size(995,32)
$script:HStatus.Anchor='Bottom,Left,Right'
$script:HStatus.ForeColor=[Drawing.Color]::FromArgb(250,194,119)
$script:HForm.Controls.Add($script:HStatus)
if($SmokeTest){
 if($script:HGrid.Columns.Count -ne 4 -or $script:HRequired.Count -lt 14){throw 'Módulo de salud incompleto.'}
 Write-Host 'OK: autodiagnóstico sin ejecutar cambios ni pruebas externas.'
 $script:HForm.Dispose()
 return
}
$script:HForm.Add_Shown({Read-HChecks})
try{
 if($Owner -is [Windows.Forms.IWin32Window]){[void]$script:HForm.ShowDialog($Owner)}
 else{[void]$script:HForm.ShowDialog()}
}finally{$script:HForm.Dispose()}
