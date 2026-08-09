[CmdletBinding()]
param(
    [string]$Root = "C:\AGROINPACO_ERP_EMPRESARIAL_2_0\FUENTE_TRABAJO\W",
    [string]$SqlServer = "ISMAEL\SQLEXPRESS",
    [string]$Database = "AGROEMPAQUES_WEB_PRUEBAS",
    [switch]$OmitirSql
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$PackageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $PackageRoot 'lib\Funciones.ps1')
. (Join-Path $PackageRoot 'lib\Hallazgos.ps1')
. (Join-Path $PackageRoot 'lib\Sql.ps1')

$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$Out = Join-Path $PackageRoot ("RESULTADOS_M02_P03_D01_REV1_" + $Stamp)
$Log = Join-Path $Out 'EJECUCION.log'
$Findings = New-Object System.Collections.Generic.List[object]
$SqlChecks = New-Object System.Collections.Generic.List[object]
$FinalCode = 1
$SqlState = 'NO_INICIADO'
$Integrity = 'NO_VERIFICADA'
$Changed = @()
$Before = @()
$RootError = $null

try{
    New-Item -ItemType Directory -Path $Out -Force | Out-Null
    Write-Log 'Inicio diagnóstico técnico M02-P03 D01 REV1 de solo lectura.'

    if(-not (Test-Path -LiteralPath $Root -PathType Container)){
        throw "No existe la línea base: $Root"
    }

    $required = @(
        'src\AgroInpaco.Web\Components\Pages\Documentos\Operacion.razor',
        'src\Legacy\AgroEmpaques.Application\Services\DocumentosService.vb',
        'src\Legacy\AgroEmpaques.Infrastructure\Services\AlmacenDocumentalService.vb',
        'src\Legacy\AgroEmpaques.Infrastructure\Services\ArchivoCargaMasivaReader.vb',
        'src\Legacy\AgroEmpaques.Application\Services\CargaMasivaService.vb',
        'src\AgroInpaco.Web\Components\Pages\Terceros\Edit.razor'
    )
    $missing = @($required | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $Root $_) -PathType Leaf)
    })
    if($missing.Count -gt 0){
        $missing | Set-Content -LiteralPath (Join-Path $Out 'ARCHIVOS_FALTANTES.txt') -Encoding UTF8
        throw 'Faltan archivos esenciales de la línea base.'
    }

    $Before = New-Snapshot -Base $Root -Path (Join-Path $Out 'HASHES_ANTES.tsv')
    Invoke-CodeDiagnostics

    if($OmitirSql){
        $SqlState = 'OMITIDO'
        Write-Log 'SQL omitido por parámetro.'
    }
    else{
        $SqlState = Invoke-DatabaseDiagnostics -Server $SqlServer -DatabaseName $Database
    }

    $Findings | Export-Csv -LiteralPath (Join-Path $Out 'HALLAZGOS.csv') -NoTypeInformation -Encoding UTF8
    $SqlChecks | Export-Csv -LiteralPath (Join-Path $Out 'SQL_ESTADO.csv') -NoTypeInformation -Encoding UTF8

    $After = New-Snapshot -Base $Root -Path (Join-Path $Out 'HASHES_DESPUES.tsv')
    $Changed = Compare-Snapshots -SnapshotBefore $Before -SnapshotAfter $After
    $Integrity = if($Changed.Count -eq 0){ 'FUENTE_INTACTA' } else { 'FUENTE_MODIFICADA' }
    @('ESTADO=' + $Integrity,'ARCHIVOS_CAMBIADOS=' + $Changed.Count) + $Changed |
        Set-Content -LiteralPath (Join-Path $Out 'INTEGRIDAD.txt') -Encoding UTF8

    if($Integrity -ne 'FUENTE_INTACTA'){
        $FinalCode = 2
    }
    elseif((-not $OmitirSql) -and $SqlState -ne 'EJECUTADO_SOLO_LECTURA_COMPLETO'){
        $FinalCode = 3
    }
    else{
        $FinalCode = 0
    }
}
catch{
    $RootError = $_.Exception.ToString()
    Write-Log ('ERROR_RAIZ=' + $RootError) 'ERROR'
    $FinalCode = 1
}
finally{
    try{
        if(-not (Test-Path -LiteralPath $Out)){
            New-Item -ItemType Directory -Path $Out -Force | Out-Null
        }
        if(-not (Test-Path -LiteralPath (Join-Path $Out 'HALLAZGOS.csv'))){
            $Findings | Export-Csv -LiteralPath (Join-Path $Out 'HALLAZGOS.csv') -NoTypeInformation -Encoding UTF8
        }
        if(-not (Test-Path -LiteralPath (Join-Path $Out 'SQL_ESTADO.csv'))){
            $SqlChecks | Export-Csv -LiteralPath (Join-Path $Out 'SQL_ESTADO.csv') -NoTypeInformation -Encoding UTF8
        }

        $conclusion = if($FinalCode -eq 0){
            'Diagnóstico completado; no habilitar cargas reales hasta evaluar los hallazgos y la compatibilidad de TERCEROS.'
        } else {
            'Diagnóstico incompleto; revisar ERROR_RAIZ y SQL_ESTADO antes de continuar.'
        }
        $errorText = if($null -eq $RootError){ '' } else { $RootError }
        @(
            'AGROINPACO ERP - M02-P03 D01 REV1',
            'DIAGNOSTICO_TECNICO=SOLO_LECTURA',
            'SQL=' + $SqlState,
            'CAMBIOS_DATOS=0',
            'INTEGRIDAD=' + $Integrity,
            'HALLAZGOS=' + $Findings.Count,
            'CODIGO_FINAL=' + $FinalCode,
            'ERROR_RAIZ=' + $errorText,
            'CONCLUSION=' + $conclusion
        ) | Set-Content -LiteralPath (Join-Path $Out 'RESULTADO.txt') -Encoding UTF8

        $level = if($FinalCode -eq 0){ 'INFO' } else { 'ERROR' }
        Write-Log ('Fin del diagnóstico. CODIGO_FINAL=' + $FinalCode) $level

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = Join-Path $PackageRoot ("RESULTADOS_M02_P03_D01_REV1_" + $Stamp + '.zip')
        if(Test-Path -LiteralPath $zip){ Remove-Item -LiteralPath $zip -Force }
        [System.IO.Compression.ZipFile]::CreateFromDirectory($Out,$zip)
        Write-Host ('RESULTADO_ZIP=' + $zip)
    }
    catch{
        Write-Host ('ERROR_EMPAQUETADO=' + $_.Exception.ToString())
        if($FinalCode -eq 0){ $FinalCode = 4 }
    }
}

exit $FinalCode
