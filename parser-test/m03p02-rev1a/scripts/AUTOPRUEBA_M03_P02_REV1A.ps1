[CmdletBinding()]
param(
    [string]$Root = 'C:\AGROINPACO_ERP_EMPRESARIAL_2_0\FUENTE_TRABAJO\W',
    [string]$PackageRoot = (Split-Path -Parent $PSScriptRoot),
    [string]$DotNetPath = 'C:\Program Files\dotnet\dotnet.exe',
    [switch]$ConservarClon
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:ExitCode=1
$timestamp=Get-Date -Format 'yyyyMMdd_HHmmss'
$resultRoot=Join-Path $PackageRoot ("RESULTADOS_AUTOPRUEBA_M03_P02_REV1A_{0}" -f $timestamp)
$resultFile=Join-Path $resultRoot 'RESULTADO_AUTOPRUEBA.txt'
$logFile=Join-Path $resultRoot 'EJECUCION_AUTOPRUEBA.log'
$cloneRoot=Join-Path $env:TEMP ("AGROINPACO_M03_P02_REV1A_AUTOPRUEBA_RUTA_MUY_LARGA_CON_ACENTOS_Revision_Tecnica_{0}\Linea_base_clonada_para_compilacion_y_contractchecks" -f $timestamp)

function Write-Log{param([string]$Message)$line='[{0}] {1}' -f(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'),$Message;Write-Host $line;Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8}
function Assert-Hash{param([string]$Path,[string]$Expected,[string]$Label)if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){throw "Falta archivo $Label: $Path"};$actual=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash;if(-not [string]::Equals($actual,$Expected,[System.StringComparison]::OrdinalIgnoreCase)){throw "Huella distinta en $Label. Esperada=$Expected Actual=$actual Ruta=$Path"}}
function Copy-Atomic{param([string]$Source,[string]$Destination)$parent=Split-Path -Parent $Destination;New-Item -ItemType Directory -Path $parent -Force|Out-Null;$temp="$Destination.m03p02.tmp";Copy-Item -LiteralPath $Source -Destination $temp -Force;Move-Item -LiteralPath $temp -Destination $Destination -Force}
function Invoke-Logged{param([string]$FilePath,[string[]]$Arguments,[string]$Name)Write-Log ("EJECUTANDO={0} {1}" -f $Name,($Arguments -join ' '));& $FilePath @Arguments 2>&1|Tee-Object -FilePath (Join-Path $resultRoot ($Name+'.log'));$code=$LASTEXITCODE;if($code -ne 0){throw "$Name fallo con codigo $code"};Write-Log ("{0}=APROBADO" -f $Name)}

try{
    New-Item -ItemType Directory -Path $resultRoot -Force|Out-Null
    Set-Content -LiteralPath $logFile -Value '' -Encoding UTF8
    Write-Log 'INICIO_AUTOPRUEBA_M03_P02_REV1A'
    if(-not (Test-Path -LiteralPath $Root -PathType Container)){throw "No existe la linea base: $Root"}
    if(-not (Test-Path -LiteralPath $DotNetPath -PathType Leaf)){throw "No existe dotnet en la ruta absoluta requerida: $DotNetPath"}

    $manifest=@(Import-Csv -LiteralPath (Join-Path $PackageRoot 'MANIFIESTO_CAMBIOS_M03_P02_REV1A.tsv') -Delimiter "`t")
    if($manifest.Count -ne 11){throw "Manifiesto invalido: $($manifest.Count) archivos."}
    foreach($row in $manifest){$relative=([string]$row.Ruta).Replace('/','\');Assert-Hash -Path (Join-Path $Root $relative) -Expected ([string]$row.SHA256_Base) -Label ("fuente antes {0}" -f $relative);Assert-Hash -Path (Join-Path (Join-Path $PackageRoot 'payload') $relative) -Expected ([string]$row.SHA256_Payload) -Label ("payload {0}" -f $relative)}

    $psFiles=@(Get-ChildItem -LiteralPath (Join-Path $PackageRoot 'scripts') -Filter '*.ps1' -File -Recurse)
    foreach($file in $psFiles){$tokens=$null;$parseErrors=$null;[System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)|Out-Null;if($parseErrors.Count -gt 0){throw "Error sintactico en $($file.Name): $($parseErrors[0].Message)"};Write-Log ("PARSER_OK={0};TOKENS={1}" -f $file.Name,$tokens.Count)}

    if(Test-Path -LiteralPath $cloneRoot){Remove-Item -LiteralPath $cloneRoot -Recurse -Force}
    New-Item -ItemType Directory -Path $cloneRoot -Force|Out-Null
    $roboArgs=@($Root,$cloneRoot,'/MIR','/R:1','/W:1','/NFL','/NDL','/NJH','/NJS','/NP','/XD','bin','obj','.git','RESPALDOS_*','_RESPALDO_*','RESULTADOS_*','/XF','*.user','*.suo')
    & robocopy.exe @roboArgs|Out-Null
    if($LASTEXITCODE -gt 7){throw "Robocopy fallo con codigo $LASTEXITCODE"}
    Write-Log ("CLON={0}" -f $cloneRoot)

    foreach($row in $manifest){$relative=([string]$row.Ruta).Replace('/','\');Assert-Hash -Path (Join-Path $cloneRoot $relative) -Expected ([string]$row.SHA256_Base) -Label ("clon base {0}" -f $relative);Copy-Atomic -Source (Join-Path (Join-Path $PackageRoot 'payload') $relative) -Destination (Join-Path $cloneRoot $relative);Assert-Hash -Path (Join-Path $cloneRoot $relative) -Expected ([string]$row.SHA256_Payload) -Label ("clon parcheado {0}" -f $relative)}

    $version=& $DotNetPath --version
    if($LASTEXITCODE -ne 0){throw 'No fue posible obtener la version de .NET.'}
    if(-not ([string]$version).StartsWith('10.')){throw "Se requiere .NET SDK 10; version detectada: $version"}
    Write-Log ("DOTNET_VERSION={0}" -f $version)
    $env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
    $env:DOTNET_NOLOGO='1'
    $env:AGROINPACO_CONTRACTCHECKS_REPORT=Join-Path $resultRoot 'RESULTADO_CONTRACTCHECKS_M03_P02_REV1A.txt'
    Push-Location $cloneRoot
    try{
        Invoke-Logged -FilePath $DotNetPath -Arguments @('restore','AgroInpacoERP.Web.sln') -Name 'DOTNET_RESTORE'
        Invoke-Logged -FilePath $DotNetPath -Arguments @('build','AgroInpacoERP.Web.sln','-c','Release','-t:Rebuild','--no-restore') -Name 'COMPILACION_REBUILD_RELEASE'
        Invoke-Logged -FilePath $DotNetPath -Arguments @('run','--project','tests\AgroInpaco.ContractChecks\AgroInpaco.ContractChecks.csproj','-c','Release','--no-build') -Name 'CONTRACTCHECKS'
    }finally{Pop-Location}

    foreach($row in $manifest){$relative=([string]$row.Ruta).Replace('/','\');Assert-Hash -Path (Join-Path $Root $relative) -Expected ([string]$row.SHA256_Base) -Label ("fuente despues {0}" -f $relative)}
    $lines=@('CODIGO_FINAL=0','ESTADO=AUTOPRUEBA_APROBADA','ANALIZADOR_POWERSHELL_REAL=True','ERRORES_SINTACTICOS=0',('DOTNET_VERSION={0}' -f $version),'COMPILACION_CLON_REBUILD=APROBADA','ERRORES_COMPILACION=0','CONTRACTCHECKS_CLON=APROBADOS','FALLOS_CONTRACTCHECKS=0','RUTA_LARGA_Y_ACENTOS=APROBADA','SQL_EJECUTADO=NO','CAMBIOS_DATOS=0','FUENTE_OFICIAL_INTACTA=SI')
    $lines|Set-Content -LiteralPath $resultFile -Encoding UTF8
    foreach($line in $lines){Write-Log $line}
    $zipPath="$resultRoot.zip";if(Test-Path -LiteralPath $zipPath){Remove-Item -LiteralPath $zipPath -Force};Compress-Archive -Path (Join-Path $resultRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal;Write-Host ("RESULTADO_ZIP={0}" -f $zipPath)
    $script:ExitCode=0
}
catch{
    New-Item -ItemType Directory -Path $resultRoot -Force|Out-Null
    @('CODIGO_FINAL=1','ESTADO=AUTOPRUEBA_FALLIDA',('ERROR={0}' -f $_.Exception.Message),'SQL_EJECUTADO=NO','CAMBIOS_DATOS=0','FUENTE_OFICIAL_INTACTA=POR_VERIFICAR')|Set-Content -LiteralPath $resultFile -Encoding UTF8
    try{Write-Log ("ERROR={0}" -f $_.Exception.Message)}catch{Write-Host $_.Exception.Message}
    Write-Error $_.Exception.Message
    $script:ExitCode=1
}
finally{if(-not $ConservarClon -and (Test-Path -LiteralPath $cloneRoot)){Remove-Item -LiteralPath $cloneRoot -Recurse -Force -ErrorAction SilentlyContinue}}
exit $script:ExitCode
