# WinCare Portable - Editor de recomendaciones | Diseñado por DevPoderSEO
# Gestiona clasificaciones locales, no desinstala aplicaciones ni altera Windows.
#requires -Version 5.1
param(
    [object]$Owner,
    [string]$SuggestedType='Appx',
    [string]$SuggestedName='',
    [string]$SuggestedPublisher='',
    [switch]$SmokeTest
)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'AppRules.ps1')

$script:REditRules=@()
$script:RColors=@{
    Bg=[Drawing.Color]::FromArgb(16,23,34)
    Panel=[Drawing.Color]::FromArgb(28,39,54)
    Accent=[Drawing.Color]::FromArgb(32,129,214)
    Text=[Drawing.Color]::FromArgb(244,247,252)
    Muted=[Drawing.Color]::FromArgb(174,191,207)
}
$script:RTable=New-Object System.Data.DataTable
foreach($name in @('Tipo','Nombre','Fabricante','Recomendacion','Motivo')){[void]$script:RTable.Columns.Add($name,[string])}
function Update-RList {
    $script:RTable.Clear()
    foreach($rule in @($script:REditRules)){
        [void]$script:RTable.Rows.Add([object[]]@([string]$rule.Tipo,[string]$rule.Nombre,[string]$rule.Fabricante,[string]$rule.Recomendacion,[string]$rule.Motivo))
    }
    $script:RCount.Text=('{0} reglas personalizadas | Guardadas en Configuracion\recomendaciones.json' -f $script:REditRules.Count)
}
function Read-RList {
    $script:REditRules=@(Get-WCPolicyRules)
    Update-RList
}
function Fill-REditor {
    if($script:RGrid.SelectedRows.Count -ne 1){return}
    $row=$script:RGrid.SelectedRows[0]
    if($row.IsNewRow){return}
    $script:RType.SelectedItem=[string]$row.Cells['Tipo'].Value
    $script:RName.Text=[string]$row.Cells['Nombre'].Value
    $script:RPublisher.Text=[string]$row.Cells['Fabricante'].Value
    $script:RChoice.SelectedItem=[string]$row.Cells['Recomendacion'].Value
    $script:RReason.Text=[string]$row.Cells['Motivo'].Value
}
function Save-RSelected {
    $type=[string]$script:RType.SelectedItem
    $name=[string]$script:RName.Text
    $publisher=[string]$script:RPublisher.Text
    $choice=[string]$script:RChoice.SelectedItem
    $reason=[string]$script:RReason.Text
    try {
        $updated=@(Set-WCPolicyRule -Rules $script:REditRules -Type $type -Name $name -Publisher $publisher -Recommendation $choice -Reason $reason)
        Save-WCPolicyRules -Rules $updated
        $script:REditRules=$updated
        Update-RList
        [void][Windows.Forms.MessageBox]::Show('Recomendación guardada. Al volver a WinCare se actualizará el inventario. Marcar como Opcional NO permite desinstalar componentes protegidos.','Regla guardada','OK','Information')
    }catch{
        [void][Windows.Forms.MessageBox]::Show(('No se pudieron guardar las recomendaciones: '+$_.Exception.Message+'. Revisa permisos de escritura en el USB.'),'Error','OK','Warning')
    }
}
function Remove-RSelected {
    if($script:RGrid.SelectedRows.Count -ne 1){return}
    $row=$script:RGrid.SelectedRows[0]
    $type=[string]$row.Cells['Tipo'].Value
    $name=[string]$row.Cells['Nombre'].Value
    $publisher=[string]$row.Cells['Fabricante'].Value
    $question=('¿Eliminar tu recomendación personalizada de '+$name+'?'+[Environment]::NewLine+'Esto no desinstala ni modifica el programa. Se aplicarán las reglas predeterminadas de WinCare.')
    if([Windows.Forms.MessageBox]::Show($question,'Eliminar recomendación','YesNo','Warning','Button2') -ne [Windows.Forms.DialogResult]::Yes){return}
    try{
        $updated=@(Remove-WCPolicyRule -Rules $script:REditRules -Type $type -Name $name -Publisher $publisher)
        Save-WCPolicyRules -Rules $updated
        $script:REditRules=$updated
        Update-RList
    }catch{
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'No se pudo eliminar la regla','OK','Error')
    }
}
function Export-RRules {
    if($script:REditRules.Count -eq 0){
        [void][Windows.Forms.MessageBox]::Show('No hay reglas para exportar.','Exportar','OK','Information')
        return
    }
    $dialog=New-Object Windows.Forms.SaveFileDialog
    $dialog.Title='Exportar reglas de clasificación'
    $dialog.Filter='CSV (*.csv)|*.csv'
    $dialog.FileName='WinCare-recomendaciones.csv'
    if($dialog.ShowDialog($script:RForm) -ne [Windows.Forms.DialogResult]::OK){return}
    try{
        $script:REditRules | Export-Csv -LiteralPath $dialog.FileName -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
        [void][Windows.Forms.MessageBox]::Show('CSV exportado. El archivo original de reglas permanece en la carpeta Configuracion.','Exportado','OK','Information')
    }catch{[void][Windows.Forms.MessageBox]::Show($_.Exception.Message,'Error al exportar','OK','Error')}
}

$script:RForm=New-Object Windows.Forms.Form
$script:RForm.Text='WinCare | Recomendaciones de programas | DevPoderSEO'
$script:RForm.StartPosition='CenterParent'
$script:RForm.Size=New-Object Drawing.Size(1110,790)
$script:RForm.MinimumSize=New-Object Drawing.Size(960,710)
$script:RForm.BackColor=$script:RColors.Bg
$script:RForm.ForeColor=$script:RColors.Text
$script:RForm.Font=New-Object Drawing.Font('Segoe UI',9)

$heading=New-Object Windows.Forms.Label
$heading.Text='Catálogo personal de aplicaciones'
$heading.Location=New-Object Drawing.Point(22,14)
$heading.Size=New-Object Drawing.Size(780,37)
$heading.Font=New-Object Drawing.Font('Segoe UI Semibold',18,[Drawing.FontStyle]::Bold)
$script:RForm.Controls.Add($heading)
$brand=New-Object Windows.Forms.Label
$brand.Text='Diseñado por DevPoderSEO'
$brand.Location=New-Object Drawing.Point(799,22)
$brand.Size=New-Object Drawing.Size(275,26)
$brand.Anchor='Top,Right'
$brand.TextAlign='MiddleRight'
$brand.ForeColor=$script:RColors.Accent
$script:RForm.Controls.Add($brand)

$notice=New-Object Windows.Forms.Label
$notice.Text='CONSERVAR bloquea la desinstalación en WinCare. OPCIONAL solo recomienda revisar: jamás elimina ni desbloquea componentes esenciales.'
$notice.Location=New-Object Drawing.Point(22,60)
$notice.Size=New-Object Drawing.Size(1045,32)
$notice.Anchor='Top,Left,Right'
$notice.ForeColor=$script:RColors.Muted
$script:RForm.Controls.Add($notice)

$script:RGrid=New-Object Windows.Forms.DataGridView
$script:RGrid.Location=New-Object Drawing.Point(22,103)
$script:RGrid.Size=New-Object Drawing.Size(1044,350)
$script:RGrid.Anchor='Top,Left,Right,Bottom'
$script:RGrid.AutoGenerateColumns=$false
$script:RGrid.AllowUserToAddRows=$false
$script:RGrid.AllowUserToDeleteRows=$false
$script:RGrid.RowHeadersVisible=$false
$script:RGrid.SelectionMode='FullRowSelect'
$script:RGrid.MultiSelect=$false
$script:RGrid.ReadOnly=$true
$script:RGrid.AutoSizeColumnsMode='Fill'
$script:RGrid.BackgroundColor=$script:RColors.Panel
$script:RGrid.EnableHeadersVisualStyles=$false
$script:RGrid.ColumnHeadersDefaultCellStyle.BackColor=[Drawing.Color]::FromArgb(42,57,76)
$script:RGrid.ColumnHeadersDefaultCellStyle.ForeColor=$script:RColors.Text
$script:RGrid.DefaultCellStyle.BackColor=$script:RColors.Panel
$script:RGrid.DefaultCellStyle.ForeColor=$script:RColors.Text
$script:RGrid.DefaultCellStyle.SelectionBackColor=[Drawing.Color]::FromArgb(32,101,166)
$script:RGrid.DefaultCellStyle.SelectionForeColor=[Drawing.Color]::White
$weights=@{Tipo=75;Nombre=210;Fabricante=140;Recomendacion=110;Motivo=290}
foreach($name in @('Tipo','Nombre','Fabricante','Recomendacion','Motivo')){
    $column=New-Object Windows.Forms.DataGridViewTextBoxColumn
    $column.Name=$name
    $column.HeaderText=$(if($name -eq 'Recomendacion'){'Recomendación'}else{$name})
    $column.DataPropertyName=$name
    $column.FillWeight=[single]$weights[$name]
    [void]$script:RGrid.Columns.Add($column)
}
$script:RGrid.DataSource=$script:RTable.DefaultView
$script:RGrid.Add_SelectionChanged({ Fill-REditor })
$script:RGrid.Add_CellFormatting({
    param($sender,$eventArgs)
    if($eventArgs.RowIndex -lt 0 -or $eventArgs.ColumnIndex -lt 0){return}
    if([string]$sender.Columns[$eventArgs.ColumnIndex].Name -ne 'Recomendacion'){return}
    if([string]$eventArgs.Value -eq 'Conservar'){$eventArgs.CellStyle.ForeColor=[Drawing.Color]::FromArgb(135,222,183)}
    elseif([string]$eventArgs.Value -eq 'Opcional'){$eventArgs.CellStyle.ForeColor=[Drawing.Color]::FromArgb(115,197,253)}
})
$script:RForm.Controls.Add($script:RGrid)

$panel=New-Object Windows.Forms.Panel
$panel.Location=New-Object Drawing.Point(22,462)
$panel.Size=New-Object Drawing.Size(1044,226)
$panel.Anchor='Bottom,Left,Right'
$panel.BackColor=$script:RColors.Panel
$script:RForm.Controls.Add($panel)
$editLabel=New-Object Windows.Forms.Label
$editLabel.Text='Editar o agregar una recomendación'
$editLabel.Font=New-Object Drawing.Font('Segoe UI Semibold',11,[Drawing.FontStyle]::Bold)
$editLabel.Location=New-Object Drawing.Point(14,9)
$editLabel.Size=New-Object Drawing.Size(500,26)
$panel.Controls.Add($editLabel)
$labels=@(
    @('Tipo',14,125),
    @('Nombre exacto',149,390),
    @('Fabricante',560,280),
    @('Recomendación',850,170),
    @('Motivo de la decisión',14,530)
)
foreach($entry in $labels){
    $caption=New-Object Windows.Forms.Label
    $caption.Text=[string]$entry[0]
    $caption.Location=New-Object Drawing.Point([int]$entry[1],$(if([string]$entry[0] -eq 'Motivo de la decisión'){96}else{43}))
    $caption.Size=New-Object Drawing.Size([int]$entry[2],18)
    $caption.ForeColor=$script:RColors.Muted
    $panel.Controls.Add($caption)
}
$script:RType=New-Object Windows.Forms.ComboBox
$script:RType.DropDownStyle='DropDownList'
$script:RType.Items.AddRange([object[]]@('Appx','Win32'))
$script:RType.Location=New-Object Drawing.Point(14,65)
$script:RType.Size=New-Object Drawing.Size(125,28)
$script:RType.SelectedIndex=0
$panel.Controls.Add($script:RType)
$script:RName=New-Object Windows.Forms.TextBox
$script:RName.Location=New-Object Drawing.Point(149,65)
$script:RName.Size=New-Object Drawing.Size(400,28)
$script:RName.Anchor='Top,Left,Right'
$panel.Controls.Add($script:RName)
$script:RPublisher=New-Object Windows.Forms.TextBox
$script:RPublisher.Location=New-Object Drawing.Point(560,65)
$script:RPublisher.Size=New-Object Drawing.Size(280,28)
$script:RPublisher.Anchor='Top,Right'
$panel.Controls.Add($script:RPublisher)
$script:RChoice=New-Object Windows.Forms.ComboBox
$script:RChoice.DropDownStyle='DropDownList'
$script:RChoice.Items.AddRange([object[]]@('Conservar','Opcional'))
$script:RChoice.Location=New-Object Drawing.Point(850,65)
$script:RChoice.Size=New-Object Drawing.Size(170,28)
$script:RChoice.Anchor='Top,Right'
$script:RChoice.SelectedIndex=0
$panel.Controls.Add($script:RChoice)
$script:RReason=New-Object Windows.Forms.TextBox
$script:RReason.Location=New-Object Drawing.Point(14,117)
$script:RReason.Size=New-Object Drawing.Size(1006,38)
$script:RReason.Anchor='Top,Left,Right'
$script:RReason.Multiline=$true
$script:RReason.Text='Indica por qué conservarlo o por qué es opcional.'
$panel.Controls.Add($script:RReason)
$script:RSave=New-Object Windows.Forms.Button
$script:RSave.Text='Guardar recomendación'
$script:RSave.Location=New-Object Drawing.Point(14,173)
$script:RSave.Size=New-Object Drawing.Size(224,41)
$script:RSave.BackColor=$script:RColors.Accent
$script:RSave.ForeColor=[Drawing.Color]::White
$script:RSave.FlatStyle='Flat'
$script:RSave.Add_Click({ Save-RSelected })
$panel.Controls.Add($script:RSave)
$script:RRemove=New-Object Windows.Forms.Button
$script:RRemove.Text='Quitar regla'
$script:RRemove.Location=New-Object Drawing.Point(250,173)
$script:RRemove.Size=New-Object Drawing.Size(160,41)
$script:RRemove.Add_Click({ Remove-RSelected })
$panel.Controls.Add($script:RRemove)
$script:RExport=New-Object Windows.Forms.Button
$script:RExport.Text='Exportar CSV'
$script:RExport.Location=New-Object Drawing.Point(420,173)
$script:RExport.Size=New-Object Drawing.Size(160,41)
$script:RExport.Add_Click({ Export-RRules })
$panel.Controls.Add($script:RExport)
$script:RCount=New-Object Windows.Forms.Label
$script:RCount.Text='Sin reglas guardadas.'
$script:RCount.Location=New-Object Drawing.Point(22,709)
$script:RCount.Size=New-Object Drawing.Size(1044,28)
$script:RCount.Anchor='Bottom,Left,Right'
$script:RCount.ForeColor=$script:RColors.Muted
$script:RForm.Controls.Add($script:RCount)
if($SmokeTest){
    if($script:RGrid.Columns.Count -ne 5){throw 'Editor: columnas incompletas.'}
    if($script:RSave.Text -ne 'Guardar recomendación'){throw 'Editor sin acción de guardado.'}
    Write-Host 'OK: editor de reglas construido; ninguna regla guardada.'
    $script:RForm.Dispose()
    return
}
$script:RForm.Add_Shown({
    try{
        Read-RList
        if($SuggestedType -in @('Appx','Win32')){$script:RType.SelectedItem=$SuggestedType}
        if($SuggestedName){$script:RName.Text=$SuggestedName}
        if($SuggestedPublisher){$script:RPublisher.Text=$SuggestedPublisher}
        $script:RChoice.SelectedItem='Conservar'
    } catch {
        $script:RSave.Enabled=$false
        $script:RRemove.Enabled=$false
        [void][Windows.Forms.MessageBox]::Show(('No se pudo leer la configuración. Se bloquearon los cambios para no sobrescribirla: '+$_.Exception.Message),'Configuración no disponible','OK','Warning')
    }
})
try{
    if($Owner -is [Windows.Forms.IWin32Window]){[void]$script:RForm.ShowDialog($Owner)}
    else{[void]$script:RForm.ShowDialog()}
}finally{$script:RForm.Dispose()}
