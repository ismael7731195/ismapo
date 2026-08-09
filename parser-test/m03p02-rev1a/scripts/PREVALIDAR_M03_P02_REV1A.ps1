[CmdletBinding()]
param(
    [string]$Root = 'C:\AGROINPACO_ERP_EMPRESARIAL_2_0\FUENTE_TRABAJO\W',
    [string]$PackageRoot = (Split-Path -Parent $PSScriptRoot),
    [switch]$NoEmpaquetarResultado
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:ExitCode = 1
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$resultRoot = Join-Path $PackageRoot ("RESULTADOS_PREVALIDACION_M03_P02_REV1A_{0}" -f $timestamp)
$resultFile = Join-Path $resultRoot 'RESULTADO_PREVALIDACION.txt'
$logFile = Join-Path $resultRoot 'EJECUCION_PREVALIDACION.log'

function Write-Log {
    param([string]$Message)
    $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message
    Write-Host $line
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}

function Get-RelativePath {
    param([string]$BasePath,[string]$FullPath)
    $baseUri = New-Object System.Uri((Resolve-Path -LiteralPath $BasePath).Path.TrimEnd('\') + '\')
    $fullUri = New-Object System.Uri((Resolve-Path -LiteralPath $FullPath).Path)
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($fullUri).ToString()).Replace('/','\')
}

function Assert-Hash {
    param([string]$Path,[string]$Expected,[string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Falta archivo $Label: $Path" }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if (-not [string]::Equals($actual,$Expected,[System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Huella distinta en $Label. Esperada=$Expected Actual=$actual Ruta=$Path"
    }
}

try {
    New-Item -ItemType Directory -Path $resultRoot -Force | Out-Null
    Set-Content -LiteralPath $logFile -Value '' -Encoding UTF8
    Write-Log 'INICIO_PREVALIDACION_M03_P02_REV1A'
    Write-Log ("ROOT={0}" -f $Root)
    Write-Log ("PACKAGE_ROOT={0}" -f $PackageRoot)

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { throw "No existe la linea base: $Root" }
    if (-not (Test-Path -LiteralPath (Join-Path $Root 'AgroInpacoERP.Web.sln') -PathType Leaf)) { throw 'La carpeta indicada no contiene AgroInpacoERP.Web.sln.' }

    $manifestPath = Join-Path $PackageRoot 'MANIFIESTO_CAMBIOS_M03_P02_REV1A.tsv'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Falta el manifiesto de cambios.' }
    $manifest = @(Import-Csv -LiteralPath $manifestPath -Delimiter "`t")
    if ($manifest.Count -ne 11) { throw "Se esperaban 11 archivos en el manifiesto y se encontraron $($manifest.Count)." }

    $psFiles = @(Get-ChildItem -LiteralPath (Join-Path $PackageRoot 'scripts') -Filter '*.ps1' -File -Recurse | Sort-Object FullName)
    if ($psFiles.Count -ne 4) { throw "Se esperaban 4 scripts PowerShell y se encontraron $($psFiles.Count)." }
    foreach ($file in $psFiles) {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors) | Out-Null
        if ($parseErrors.Count -gt 0) {
            $detail = ($parseErrors | ForEach-Object { '{0}:{1}:{2}: {3}' -f $file.Name,$_.Extent.StartLineNumber,$_.Extent.StartColumnNumber,$_.Message }) -join [Environment]::NewLine
            throw "Analizador sintactico rechazo $($file.Name):$([Environment]::NewLine)$detail"
        }
        Write-Log ("PARSER_OK={0};TOKENS={1}" -f $file.Name,$tokens.Count)
    }
    Write-Log ("POWERSHELL_VERSION={0}" -f $PSVersionTable.PSVersion)
    Write-Log 'ANALIZADOR=System.Management.Automation.Language.Parser.ParseFile'

    $sqlFiles = @(Get-ChildItem -LiteralPath $PackageRoot -Filter '*.sql' -File -Recurse)
    if ($sqlFiles.Count -ne 0) { throw 'El paquete correctivo de codigo no puede contener archivos SQL.' }

    foreach ($row in $manifest) {
        $relative = ([string]$row.Ruta).Replace('/','\')
        Assert-Hash -Path (Join-Path (Join-Path $PackageRoot 'payload') $relative) -Expected ([string]$row.SHA256_Payload) -Label ("payload {0}" -f $relative)
        Assert-Hash -Path (Join-Path $Root $relative) -Expected ([string]$row.SHA256_Base) -Label ("linea base {0}" -f $relative)
    }
    Write-Log 'HUELLAS_PAYLOAD=APROBADAS'
    Write-Log 'HUELLAS_LINEA_BASE=APROBADAS'

    $cmdFiles = @(Get-ChildItem -LiteralPath $PackageRoot -Filter '*.cmd' -File)
    if ($cmdFiles.Count -ne 4) { throw "Se esperaban 4 lanzadores CMD y se encontraron $($cmdFiles.Count)." }
    foreach ($cmd in $cmdFiles) {
        $bytes = [System.IO.File]::ReadAllBytes($cmd.FullName)
        if ($bytes.Length -lt 9) { throw "CMD demasiado corto: $($cmd.Name)" }
        if (($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) -or ($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE)) { throw "El CMD contiene BOM: $($cmd.Name)" }
        if ([System.Text.Encoding]::ASCII.GetString($bytes,0,9) -ne '@echo off') { throw "Inicio CMD invalido: $($cmd.Name)" }
    }
    Write-Log 'CMD_SIN_BOM=APROBADO'

    $lines = @(
        'CODIGO_FINAL=0',
        'ESTADO=PREVALIDACION_APROBADA',
        'ANALIZADOR_POWERSHELL_REAL=True',
        'MOTOR_ANALIZADOR=System.Management.Automation.Language.Parser.ParseFile',
        ("VERSION_POWERSHELL={0}" -f $PSVersionTable.PSVersion),
        ("ARCHIVOS_PS1={0}" -f $psFiles.Count),
        'ERRORES_SINTACTICOS=0',
        ("ARCHIVOS_PAYLOAD={0}" -f $manifest.Count),
        'HUELLAS_PAYLOAD=APROBADAS',
        'HUELLAS_LINEA_BASE=APROBADAS',
        'SQL_EJECUTADO=NO',
        'CAMBIOS_DATOS=0',
        'FUENTE_MODIFICADA=NO'
    )
    $lines | Set-Content -LiteralPath $resultFile -Encoding UTF8
    foreach ($line in $lines) { Write-Log $line }
    $script:ExitCode = 0

    if (-not $NoEmpaquetarResultado) {
        $zipPath = "$resultRoot.zip"
        if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
        Compress-Archive -Path (Join-Path $resultRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal
        Write-Host ("RESULTADO_ZIP={0}" -f $zipPath)
    }
}
catch {
    New-Item -ItemType Directory -Path $resultRoot -Force | Out-Null
    $failure = @('CODIGO_FINAL=1','ESTADO=PREVALIDACION_FALLIDA',('ERROR={0}' -f $_.Exception.Message),'SQL_EJECUTADO=NO','CAMBIOS_DATOS=0','FUENTE_MODIFICADA=NO')
    $failure | Set-Content -LiteralPath $resultFile -Encoding UTF8
    try { Write-Log ("ERROR={0}" -f $_.Exception.Message) } catch { Write-Host $_.Exception.Message }
    Write-Error $_.Exception.Message
    $script:ExitCode = 1
}
exit $script:ExitCode
