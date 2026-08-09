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
$Stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$Out = Join-Path $PackageRoot ("RESULTADOS_M02_P03_D01_" + $Stamp)
$Log = Join-Path $Out 'EJECUCION.log'
$Findings = New-Object System.Collections.Generic.List[object]

function Write-Log {
    param([string]$Message,[string]$Level='INFO')
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Level,$Message
    Write-Host $line
    Add-Content -LiteralPath $Log -Value $line -Encoding UTF8
}

function Add-Finding {
    param([string]$Id,[string]$Severity,[string]$Area,[string]$Title,[string]$Evidence,[string]$Risk,[string]$Recommendation)
    $Findings.Add([pscustomobject]@{
        Id=$Id; Severidad=$Severity; Area=$Area; Titulo=$Title;
        Evidencia=$Evidence; Riesgo=$Risk; Recomendacion=$Recommendation
    })
}

function Get-RelPath {
    param([string]$Base,[string]$Full)
    $b = New-Object System.Uri(($Base.TrimEnd('\') + '\'))
    $f = New-Object System.Uri($Full)
    [System.Uri]::UnescapeDataString($b.MakeRelativeUri($f).ToString()).Replace('/','\')
}

function New-Snapshot {
    param([string]$Base,[string]$Path)
    $scan = @((Join-Path $Base 'src'),(Join-Path $Base 'SQL'))
    $items = foreach($dir in $scan){
        if(Test-Path -LiteralPath $dir){ Get-ChildItem -LiteralPath $dir -File -Recurse }
    }
    $rows = foreach($item in ($items | Sort-Object FullName -Unique)){
        [pscustomobject]@{
            Ruta=Get-RelPath -Base $Base -Full $item.FullName
            Longitud=$item.Length
            SHA256=(Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
        }
    }
    @($rows) | Export-Csv -LiteralPath $Path -Delimiter "`t" -NoTypeInformation -Encoding UTF8
    @($rows)
}

function Read-Source {
    param([string]$Relative)
    $full = Join-Path $Root $Relative
    if(-not (Test-Path -LiteralPath $full)){ return $null }
    Get-Content -LiteralPath $full -Raw
}

function Save-Matches {
    param([string]$Relative,[string[]]$Patterns)
    $full = Join-Path $Root $Relative
    if(-not (Test-Path -LiteralPath $full)){ return }
    foreach($pattern in $Patterns){
        Select-String -LiteralPath $full -Pattern $pattern -AllMatches | ForEach-Object {
            '{0}:{1}: {2}' -f $Relative,$_.LineNumber,$_.Line.Trim()
        }
    }
}

function Invoke-ReadOnlySql {
    param([System.Data.SqlClient.SqlConnection]$Connection,[string]$Name,[string]$Query)
    $blocked = '(?im)\b(INSERT|UPDATE|DELETE|MERGE|CREATE|ALTER|DROP|TRUNCATE|GRANT|REVOKE|DENY|BACKUP|RESTORE|DBCC|EXEC(?:UTE)?|BULK)\b'
    if([regex]::IsMatch($Query,$blocked)){ throw "Consulta no permitida: $Name" }
    $cmd=$Connection.CreateCommand(); $cmd.CommandTimeout=60; $cmd.CommandText=$Query
    $da=New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
    $dt=New-Object System.Data.DataTable($Name)
    [void]$da.Fill($dt)
    $rows=foreach($r in $dt.Rows){
        $o=[ordered]@{}
        foreach($c in $dt.Columns){ $o[$c.ColumnName]=if($r[$c] -eq [DBNull]::Value){$null}else{$r[$c]} }
        [pscustomobject]$o
    }
    @($rows) | Export-Csv -LiteralPath (Join-Path $Out ("SQL_"+$Name+'.csv')) -NoTypeInformation -Encoding UTF8
    $dt
}

try {
    New-Item -ItemType Directory -Path $Out -Force | Out-Null
    Write-Log 'Inicio diagnóstico técnico M02-P03 D01 de solo lectura.'
    if(-not (Test-Path -LiteralPath $Root -PathType Container)){ throw "No existe la línea base: $Root" }

    $required=@(
        'src\AgroInpaco.Web\Components\Pages\Documentos\Operacion.razor',
        'src\Legacy\AgroEmpaques.Application\Services\DocumentosService.vb',
        'src\Legacy\AgroEmpaques.Infrastructure\Services\AlmacenDocumentalService.vb',
        'src\Legacy\AgroEmpaques.Infrastructure\Services\ArchivoCargaMasivaReader.vb',
        'src\Legacy\AgroEmpaques.Application\Services\CargaMasivaService.vb',
        'src\AgroInpaco.Web\Components\Pages\Terceros\Edit.razor'
    )
    $missing=@($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Root $_)) })
    if($missing.Count -gt 0){
        $missing | Set-Content -LiteralPath (Join-Path $Out 'ARCHIVOS_FALTANTES.txt') -Encoding UTF8
        throw 'Faltan archivos esenciales.'
    }

    $before=New-Snapshot -Base $Root -Path (Join-Path $Out 'HASHES_ANTES.tsv')

    $ui='src\AgroInpaco.Web\Components\Pages\Documentos\Operacion.razor'
    $doc='src\Legacy\AgroEmpaques.Application\Services\DocumentosService.vb'
    $store='src\Legacy\AgroEmpaques.Infrastructure\Services\AlmacenDocumentalService.vb'
    $reader='src\Legacy\AgroEmpaques.Infrastructure\Services\ArchivoCargaMasivaReader.vb'
    $loads='src\Legacy\AgroEmpaques.Application\Services\CargaMasivaService.vb'
    $third='src\AgroInpaco.Web\Components\Pages\Terceros\Edit.razor'

    $uiText=Read-Source $ui; $docText=Read-Source $doc; $storeText=Read-Source $store
    $readerText=Read-Source $reader; $loadText=Read-Source $loads; $thirdText=Read-Source $third

    $evidence=@()
    $evidence += Save-Matches $ui @('MaxUploadBytes','SaveTempAsync','_templateId','ModuloOrigen','EntidadOrigen','IdRegistroOrigen','/erp/auditoria','/erp/informes')
    $evidence += Save-Matches $doc @('TamanoMaximoMB','BuscarTipoArchivo','GuardarArchivo','IdCategoriaDocumental','IdCarpetaDocumental')
    $evidence += Save-Matches $store @('documentos_agroempaques.ini','File.Copy','CalcularHash','RutaArchivo')
    $evidence += Save-Matches $reader @('Path.GetExtension','ZipFile.OpenRead','File.ReadAllLines','XDocument.Load','CalcularHash','GenerarPlantilla')
    $evidence | Set-Content -LiteralPath (Join-Path $Out 'EVIDENCIAS_CODIGO.txt') -Encoding UTF8

    if($uiText -match '50\s*\*\s*1024\s*\*\s*1024'){
        Add-Finding 'M02-P03-OBS-054' 'MEDIA' 'Archivos' 'Límite web fijo de 50 MiB' 'El componente usa un máximo global de 50 MiB.' 'El límite no se informa ni diferencia por proceso.' 'Mostrar límite y aplicar reglas por tipo documental.'
    }
    if($uiText -match 'SaveTempAsync'){
        Add-Finding 'M02-P03-OBS-055' 'ALTA' 'Archivos' 'Copia temporal previa a validación profunda' 'La interfaz guarda primero en temporal.' 'Un archivo no confiable alcanza disco antes de cuarentena visible.' 'Usar cuarentena, firma mágica y análisis antimalware.'
    }
    if(($docText -match 'Path\.GetExtension') -or ($docText -match 'Extension')){
        Add-Finding 'M02-P03-OBS-056' 'ALTA' 'Documentos' 'Tipo de archivo guiado por extensión' 'La admisión se apoya en extensión/catálogo.' 'Una extensión no demuestra el contenido real.' 'Validar MIME, firma binaria y contenido.'
    }
    if($storeText -match 'CalcularHash'){
        Add-Finding 'M02-P03-OBS-057' 'POSITIVA' 'Integridad' 'Huella digital implementada' 'El almacenamiento calcula hash.' 'Debe verificarse algoritmo, persistencia y revalidación.' 'Mantener SHA-256 y comprobarlo en descarga/versionado.'
    }
    if($storeText -match 'documentos_agroempaques\.ini'){
        Add-Finding 'M02-P03-OBS-058' 'MEDIA' 'Almacenamiento' 'Ruta física configurable por archivo INI' 'La ubicación documental puede depender de configuración externa.' 'Una ruta mal configurada puede dispersar o exponer archivos.' 'Administrar configuración, permisos y prueba de escritura controlada.'
    }
    if(($uiText -match 'ModuloOrigen') -and ($uiText -match 'EntidadOrigen')){
        Add-Finding 'M02-P03-OBS-059' 'ALTA' 'Integración' 'Origen transversal editable' 'Los campos de origen están expuestos en el formulario.' 'Se permiten referencias arbitrarias y pérdida de trazabilidad.' 'Resolver origen desde registros reales y bloquear edición libre.'
    }
    if(($uiText -match 'IdCategoriaDocumental') -and ($uiText -match 'IdCarpetaDocumental')){
        Add-Finding 'M02-P03-OBS-060' 'ALTA' 'Clasificación' 'Categoría y carpeta son campos independientes' 'La interfaz administra ambos identificadores por separado.' 'Permite combinaciones incoherentes confirmadas visualmente.' 'Mapear categoría-carpetas y validar compatibilidad.'
    }
    if($uiText -match '_templateId\s*=\s*_templates\.FirstOrDefault'){
        Add-Finding 'M02-P03-OBS-061' 'MEDIA' 'Cargas' 'Plantilla predeterminada automática' 'Se selecciona la primera plantilla al cargar.' 'Aumenta el riesgo de leer un archivo con plantilla equivocada.' 'Iniciar sin selección obligatoria.'
    }
    if(($readerText -match 'XDocument\.Load') -and ($readerText -match 'ZipFile\.OpenRead')){
        Add-Finding 'M02-P03-OBS-062' 'ALTA' 'Excel' 'Lectura directa de XML dentro de XLSX' 'El lector abre ZIP/XML.' 'Debe controlar zip bombs, XML externo y tamaños internos.' 'Deshabilitar DTD, limitar entradas y expansión.'
    }
    if($readerText -match 'File\.ReadAllLines'){
        Add-Finding 'M02-P03-OBS-063' 'MEDIA' 'CSV/TXT' 'Lectura completa en memoria' 'El lector usa ReadAllLines.' 'Archivos grandes pueden agotar memoria.' 'Procesar por streaming y limitar filas/longitudes.'
    }
    if(($readerText -match 'CalcularHash') -or ($loadText -match 'Hash')){
        Add-Finding 'M02-P03-OBS-064' 'POSITIVA' 'Cargas' 'Huella digital de archivo de carga' 'Existe cálculo o manejo de hash.' 'Debe confirmar deduplicación e inmutabilidad.' 'Persistir SHA-256 y bloquear reprocesos duplicados.'
    }

    $groups=@('Responsabilidad','Contacto','Direccion','Rol','Clasificacion')
    $covered=@($groups | Where-Object { $thirdText -match $_ })
    Add-Finding 'M02-P03-OBS-065' 'CRITICA' 'Plantilla TERCEROS' 'Compatibilidad con M02-P01/P02 pendiente' ("El formulario vigente contiene grupos: "+($covered -join ', ')+'.') 'La plantilla histórica puede omitir relaciones fiscales, contactos y direcciones múltiples.' 'No habilitar carga real hasta comparar catálogo live y contrato vigente.'

    $sqlState='OMITIDO'
    if(-not $OmitirSql){
        try{
            $cs='Server={0};Database={1};Integrated Security=True;Application Name=AGROINPACO_M02_P03_D01;Encrypt=False;TrustServerCertificate=True;ApplicationIntent=ReadOnly' -f $SqlServer,$Database
            $cn=New-Object System.Data.SqlClient.SqlConnection($cs); $cn.Open()
            try{
                [void](Invoke-ReadOnlySql $cn 'OBJETOS' @"
SELECT s.name AS Esquema,o.name AS Objeto,o.type_desc AS Tipo
FROM sys.objects o INNER JOIN sys.schemas s ON s.schema_id=o.schema_id
WHERE s.name IN ('doc','imp')
ORDER BY s.name,o.name;
"@)
                [void](Invoke-ReadOnlySql $cn 'PLANTILLAS' @"
SELECT IdPlantillaCarga,Codigo,Nombre,ModuloDestino,FormatosPermitidos,ModoAplicacion,PermiteProcesar,Activo,OrdenVisual
FROM imp.PlantillasCargaMasiva
ORDER BY OrdenVisual,Codigo;
"@)
                [void](Invoke-ReadOnlySql $cn 'COLUMNAS_TERCEROS' @"
SELECT P.Codigo AS Plantilla,C.CodigoColumna,C.NombreColumna,C.OrdenColumna,C.Obligatoria,C.TipoDato,C.LongitudMaxima,C.ValorEjemplo,C.Descripcion,C.EsClaveNegocio
FROM imp.PlantillasCargaMasiva P
INNER JOIN imp.ColumnasPlantillaCarga C ON C.IdPlantillaCarga=P.IdPlantillaCarga
WHERE P.Codigo='TERCEROS'
ORDER BY C.OrdenColumna;
"@)
                [void](Invoke-ReadOnlySql $cn 'TIPOS_ARCHIVO' @"
SELECT * FROM doc.TiposArchivoPermitidos ORDER BY Extension;
"@)
                [void](Invoke-ReadOnlySql $cn 'CATEGORIAS_CARPETAS' @"
SELECT C.Codigo AS CategoriaCodigo,C.Nombre AS CategoriaNombre,C.RequiereAprobacion,C.EsConfidencialDefault,
       F.Codigo AS CarpetaCodigo,F.Nombre AS CarpetaNombre,F.RutaRelativa,F.Activo AS CarpetaActiva
FROM doc.CategoriasDocumentales C
LEFT JOIN doc.CarpetasDocumentales F ON F.IdCategoriaDocumental=C.IdCategoriaDocumental
ORDER BY C.Codigo,F.Codigo;
"@)
                $sqlState='EJECUTADO_SOLO_LECTURA'
            } finally { $cn.Close(); $cn.Dispose() }
        } catch {
            $sqlState='NO_EJECUTADO: '+$_.Exception.Message
            Write-Log $sqlState 'WARN'
        }
    }

    $Findings | Export-Csv -LiteralPath (Join-Path $Out 'HALLAZGOS.csv') -NoTypeInformation -Encoding UTF8
    $after=New-Snapshot -Base $Root -Path (Join-Path $Out 'HASHES_DESPUES.tsv')
    $b=@{}; foreach($x in $before){$b[$x.Ruta]=$x.SHA256}
    $a=@{}; foreach($x in $after){$a[$x.Ruta]=$x.SHA256}
    $changed=@(($b.Keys+$a.Keys | Sort-Object -Unique) | Where-Object { -not $b.ContainsKey($_) -or -not $a.ContainsKey($_) -or $b[$_] -ne $a[$_] })
    $integrity=if($changed.Count -eq 0){'FUENTE_INTACTA'}else{'FUENTE_MODIFICADA'}
    @('ESTADO='+$integrity,'ARCHIVOS_CAMBIADOS='+$changed.Count)+$changed | Set-Content -LiteralPath (Join-Path $Out 'INTEGRIDAD.txt') -Encoding UTF8

    @(
        'AGROINPACO ERP - M02-P03 D01',
        'DIAGNOSTICO_TECNICO=SOLO_LECTURA',
        'SQL='+$sqlState,
        'CAMBIOS_DATOS=0',
        'INTEGRIDAD='+$integrity,
        'HALLAZGOS='+$Findings.Count,
        'CONCLUSION=No habilitar cargas reales hasta cerrar seguridad de archivos, versionado y compatibilidad de TERCEROS.'
    ) | Set-Content -LiteralPath (Join-Path $Out 'RESULTADO.txt') -Encoding UTF8

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=Join-Path $PackageRoot ("RESULTADOS_M02_P03_D01_"+$Stamp+'.zip')
    [System.IO.Compression.ZipFile]::CreateFromDirectory($Out,$zip)
    if($changed.Count -gt 0){ Write-Log 'La fuente cambió durante el diagnóstico.' 'ERROR'; exit 2 }
    Write-Log 'Diagnóstico completado. CODIGO_FINAL=0'
    exit 0
}
catch{
    try{ Write-Log ('ERROR_RAIZ='+$_.Exception.ToString()) 'ERROR' }catch{ Write-Host $_.Exception.ToString() }
    exit 1
}
