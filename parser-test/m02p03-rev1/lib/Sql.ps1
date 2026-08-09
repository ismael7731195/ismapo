function Invoke-DatabaseDiagnostics {
    param([string]$Server,[string]$DatabaseName)

    $cs='Server={0};Database={1};Integrated Security=True;Application Name=AGROINPACO_M02_P03_D01_REV1;Encrypt=False;TrustServerCertificate=True;ApplicationIntent=ReadOnly' -f $Server,$DatabaseName
    $cn=New-Object System.Data.SqlClient.SqlConnection($cs)
    $cn.Open()
    try{
        $queries=[ordered]@{
            OBJETOS=@"
SELECT s.name AS Esquema,o.name AS Objeto,o.type_desc AS Tipo
FROM sys.objects o INNER JOIN sys.schemas s ON s.schema_id=o.schema_id
WHERE s.name IN ('doc','imp') ORDER BY s.name,o.name;
"@
            ESTRUCTURA_TABLAS=@"
SELECT s.name AS Esquema,t.name AS Tabla,c.column_id AS OrdenFisico,
 c.name AS Columna,ty.name AS TipoDato,c.max_length AS LongitudBytes,
 c.precision AS Precision,c.scale AS Escala,c.is_nullable AS PermiteNulo,
 c.is_identity AS EsIdentidad
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id=t.schema_id
JOIN sys.columns c ON c.object_id=t.object_id
JOIN sys.types ty ON ty.user_type_id=c.user_type_id
WHERE (s.name='doc' AND t.name IN ('Documentos','DocumentosVersiones',
 'DocumentoAprobaciones','DocumentoRelaciones','TiposArchivoPermitidos',
 'CategoriasDocumentales','CarpetasDocumentales'))
 OR (s.name='imp' AND t.name IN ('PlantillasCargaMasiva','ColumnasPlantillaCarga',
 'LotesCargaMasiva','FilasCargaMasiva','CeldasCargaMasiva',
 'ErroresCargaMasiva','AuditoriaCargasMasivas'))
ORDER BY s.name,t.name,c.column_id;
"@
            PLANTILLAS=@"
SELECT * FROM imp.PlantillasCargaMasiva ORDER BY Codigo;
"@
            COLUMNAS_TERCEROS=@"
SELECT P.Codigo AS Plantilla,C.*
FROM imp.PlantillasCargaMasiva P
JOIN imp.ColumnasPlantillaCarga C ON C.IdPlantillaCarga=P.IdPlantillaCarga
WHERE P.Codigo='TERCEROS';
"@
            TIPOS_ARCHIVO=@"
SELECT * FROM doc.TiposArchivoPermitidos;
"@
            CATEGORIAS=@"
SELECT * FROM doc.CategoriasDocumentales;
"@
            CARPETAS=@"
SELECT * FROM doc.CarpetasDocumentales;
"@
            CONTEOS=@"
SELECT 'doc.Documentos' AS Objeto,COUNT_BIG(*) AS Filas FROM doc.Documentos
UNION ALL SELECT 'doc.DocumentosVersiones',COUNT_BIG(*) FROM doc.DocumentosVersiones
UNION ALL SELECT 'doc.DocumentoAprobaciones',COUNT_BIG(*) FROM doc.DocumentoAprobaciones
UNION ALL SELECT 'doc.DocumentoRelaciones',COUNT_BIG(*) FROM doc.DocumentoRelaciones
UNION ALL SELECT 'imp.LotesCargaMasiva',COUNT_BIG(*) FROM imp.LotesCargaMasiva
UNION ALL SELECT 'imp.FilasCargaMasiva',COUNT_BIG(*) FROM imp.FilasCargaMasiva
UNION ALL SELECT 'imp.ErroresCargaMasiva',COUNT_BIG(*) FROM imp.ErroresCargaMasiva;
"@
        }
        foreach($entry in $queries.GetEnumerator()){
            [void](Invoke-SafeReadOnlySql -Connection $cn -Name $entry.Key -Query $entry.Value -Required $true)
        }
    }
    finally{
        $cn.Close()
        $cn.Dispose()
    }

    $errors=@($SqlChecks | Where-Object { $_.Obligatoria -and $_.Estado -ne 'OK' })
    if($errors.Count -eq 0){ 'EJECUTADO_SOLO_LECTURA_COMPLETO' }
    else{ 'INCOMPLETO_CON_ERRORES=' + $errors.Count }
}
