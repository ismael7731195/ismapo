[CmdletBinding()]
param(
    [string]$Root = 'C:\AGROINPACO_ERP_EMPRESARIAL_2_0\FUENTE_TRABAJO\W',
    [string]$PackageRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$ConfirmarAplicacion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:ExitCode = 1
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$resultRoot = Join-Path $PackageRoot ("RESULTADOS_APLICACION_M03_P02_REV1A_{0}" -f $timestamp)
$resultFile = Join-Path $resultRoot 'RESULTADO_APLICACION.txt'
$logFile = Join-Path $resultRoot 'EJECUCION_APLICACION.log'
$backupRoot = Join-Path $Root ("RESPALDOS_M03_P02_REV1A\{0}" -f $timestamp)
$applied = New-Object System.Collections.Generic.List[string]

function Write-Log { param([string]$Message) $line='[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),$Message; Write-Host $line; Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 }
function Assert-Hash { param([string]$Path,[string]$Expected,[string]$Label) if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){throw "Falta archivo ${Label}: $Path"};$actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash;if(-not [string]::Equals($actual,$Expected,[System.StringComparison]::OrdinalIgnoreCase)){throw "Huella distinta en $Label. Esperada=$Expected Actual=$actual Ruta=$Path"} }
function Copy-Atomic { param([string]$Source,[string]$Destination) $parent=Split-Path -Parent $Destination;New-Item -ItemType Directory -Path $parent -Force|Out-Null;$temp="$Destination.m03p02.tmp";Copy-Item -LiteralPath $Source -Destination $temp -Force;Move-Item -LiteralPath $temp -Destination $Destination -Force }

try {
    New-Item -ItemType Directory -Path $resultRoot -Force | Out-Null
    Set-Content -LiteralPath $logFile -Value '' -Encoding UTF8
    Write-Log 'INICIO_APLICACION_M03_P02_REV1A'
    if (-not $ConfirmarAplicacion) { throw 'Aplicacion bloqueada: use -ConfirmarAplicacion despues de aprobar la autoprueba.' }
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "No existe la linea base: $Root" }

    $prevalidation = Join-Path $PSScriptRoot 'PREVALIDAR_M03_P02_REV1A.ps1'
    $engine = (Get-Process -Id $PID).Path
    $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$prevalidation,'-Root',$Root,'-PackageRoot',$PackageRoot,'-NoEmpaquetarResultado')
    $process = Start-Process -FilePath $engine -ArgumentList $arguments -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -ne 0) { throw "La prevalidacion obligatoria fallo con codigo $($process.ExitCode)." }

    $manifestPath = Join-Path $PackageRoot 'MANIFIESTO_CAMBIOS_M03_P02_REV1A.tsv'
    $manifest = @(Import-Csv -LiteralPath $manifestPath -Delimiter "`t")
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
    Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $backupRoot 'MANIFIESTO_CAMBIOS_M03_P02_REV1A.tsv') -Force

    $backupRows = New-Object System.Collections.Generic.List[object]
    foreach ($row in $manifest) {
        $relative = ([string]$row.Ruta).Replace('/','\')
        $sourceFile = Join-Path $Root $relative
        $backupFile = Join-Path $backupRoot $relative
        New-Item -ItemType Directory -Path (Split-Path -Parent $backupFile) -Force | Out-Null
        Copy-Item -LiteralPath $sourceFile -Destination $backupFile -Force
        Assert-Hash -Path $backupFile -Expected ([string]$row.SHA256_Base) -Label ("respaldo {0}" -f $relative)
        $backupRows.Add([pscustomobject]@{Ruta=$relative;SHA256=([string]$row.SHA256_Base)})
    }
    $backupRows | Export-Csv -LiteralPath (Join-Path $backupRoot 'MANIFIESTO_RESPALDO.tsv') -Delimiter "`t" -NoTypeInformation -Encoding UTF8
    Write-Log ("RESPALDO={0}" -f $backupRoot)

    foreach ($row in $manifest) {
        $relative = ([string]$row.Ruta).Replace('/','\')
        $payloadFile = Join-Path (Join-Path $PackageRoot 'payload') $relative
        $destination = Join-Path $Root $relative
        Copy-Atomic -Source $payloadFile -Destination $destination
        Assert-Hash -Path $destination -Expected ([string]$row.SHA256_Payload) -Label ("aplicado {0}" -f $relative)
        $applied.Add($relative)
        Write-Log ("APLICADO={0}" -f $relative)
    }

    $lines=@('CODIGO_FINAL=0','ESTADO=APLICADO_Y_VALIDADO',('RESPALDO={0}' -f $backupRoot),('ARCHIVOS_APLICADOS={0}' -f $applied.Count),'SQL_EJECUTADO=NO','CAMBIOS_DATOS=0','ROLLBACK_DISPONIBLE=SI')
    $lines|Set-Content -LiteralPath $resultFile -Encoding UTF8
    foreach($line in $lines){Write-Log $line}
    $script:ExitCode=0
}
catch {
    $rollbackState='NO_REQUERIDO'
    if ($applied.Count -gt 0 -and (Test-Path -LiteralPath $backupRoot -PathType Container)) {
        $rollbackState='INICIADO'
        foreach ($relative in $applied) {
            $backupFile=Join-Path $backupRoot $relative
            $destination=Join-Path $Root $relative
            if(Test-Path -LiteralPath $backupFile -PathType Leaf){Copy-Atomic -Source $backupFile -Destination $destination}
        }
        $rollbackState='COMPLETADO'
    }
    New-Item -ItemType Directory -Path $resultRoot -Force|Out-Null
    @('CODIGO_FINAL=1','ESTADO=APLICACION_FALLIDA',('ERROR={0}' -f $_.Exception.Message),('ROLLBACK={0}' -f $rollbackState),'SQL_EJECUTADO=NO','CAMBIOS_DATOS=0')|Set-Content -LiteralPath $resultFile -Encoding UTF8
    try{Write-Log ("ERROR={0};ROLLBACK={1}" -f $_.Exception.Message,$rollbackState)}catch{Write-Host $_.Exception.Message}
    Write-Error $_.Exception.Message
    $script:ExitCode=1
}
exit $script:ExitCode
