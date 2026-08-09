[CmdletBinding()]
param(
    [string]$Root = 'C:\AGROINPACO_ERP_EMPRESARIAL_2_0\FUENTE_TRABAJO\W',
    [string]$BackupPath,
    [string]$PackageRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$ConfirmarReversion
)

Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$script:ExitCode=1
$timestamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$resultRoot=Join-Path $PackageRoot ("RESULTADOS_REVERSION_M03_P02_REV1A_{0}" -f $timestamp)
$resultFile=Join-Path $resultRoot 'RESULTADO_REVERSION.txt'
$logFile=Join-Path $resultRoot 'EJECUCION_REVERSION.log'
function Write-Log{param([string]$Message)$line='[{0}] {1}' -f(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),$Message;Write-Host $line;Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8}
function Copy-Atomic{param([string]$Source,[string]$Destination)$parent=Split-Path -Parent $Destination;New-Item -ItemType Directory -Path $parent -Force|Out-Null;$temp="$Destination.m03p02.rollback.tmp";Copy-Item -LiteralPath $Source -Destination $temp -Force;Move-Item -LiteralPath $temp -Destination $Destination -Force}
try{
    New-Item -ItemType Directory -Path $resultRoot -Force|Out-Null;Set-Content -LiteralPath $logFile -Value '' -Encoding UTF8
    if(-not $ConfirmarReversion){throw 'Reversion bloqueada: use -ConfirmarReversion.'}
    if([string]::IsNullOrWhiteSpace($BackupPath)){$parent=Join-Path $Root 'RESPALDOS_M03_P02_REV1A';$latest=Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue|Sort-Object Name -Descending|Select-Object -First 1;if($null -eq $latest){throw 'No existe un respaldo M03-P02 REV1A para revertir.'};$BackupPath=$latest.FullName}
    if(-not (Test-Path -LiteralPath $BackupPath -PathType Container)){throw "No existe el respaldo: $BackupPath"}
    $manifestPath=Join-Path $BackupPath 'MANIFIESTO_RESPALDO.tsv';if(-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)){throw 'El respaldo no contiene MANIFIESTO_RESPALDO.tsv.'}
    $manifest=@(Import-Csv -LiteralPath $manifestPath -Delimiter "`t");if($manifest.Count -ne 11){throw "Respaldo incompleto: $($manifest.Count) archivos."}
    foreach($row in $manifest){$relative=[string]$row.Ruta;$source=Join-Path $BackupPath $relative;$actual=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash;if(-not [string]::Equals($actual,[string]$row.SHA256,[System.StringComparison]::OrdinalIgnoreCase)){throw "Huella invalida en respaldo: $relative"};Copy-Atomic -Source $source -Destination (Join-Path $Root $relative);$restored=(Get-FileHash -LiteralPath (Join-Path $Root $relative) -Algorithm SHA256).Hash;if(-not [string]::Equals($restored,[string]$row.SHA256,[System.StringComparison]::OrdinalIgnoreCase)){throw "No se verifico la restauracion: $relative"};Write-Log ("RESTAURADO={0}" -f $relative)}
    @('CODIGO_FINAL=0','ESTADO=REVERSION_APROBADA',('RESPALDO_USADO={0}' -f $BackupPath),('ARCHIVOS_RESTAURADOS={0}' -f $manifest.Count),'SQL_EJECUTADO=NO','CAMBIOS_DATOS=0')|Set-Content -LiteralPath $resultFile -Encoding UTF8
    Write-Log 'CODIGO_FINAL=0';$script:ExitCode=0
}catch{New-Item -ItemType Directory -Path $resultRoot -Force|Out-Null;@('CODIGO_FINAL=1','ESTADO=REVERSION_FALLIDA',('ERROR={0}' -f $_.Exception.Message),'SQL_EJECUTADO=NO','CAMBIOS_DATOS=0')|Set-Content -LiteralPath $resultFile -Encoding UTF8;try{Write-Log ("ERROR={0}" -f $_.Exception.Message)}catch{Write-Host $_.Exception.Message};Write-Error $_.Exception.Message;$script:ExitCode=1}
exit $script:ExitCode
