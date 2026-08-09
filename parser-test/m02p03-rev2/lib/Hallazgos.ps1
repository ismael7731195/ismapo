function Invoke-CodeDiagnostics {
    $ui = 'src\AgroInpaco.Web\Components\Pages\Documentos\Operacion.razor'
    $doc = 'src\Legacy\AgroEmpaques.Application\Services\DocumentosService.vb'
    $store = 'src\Legacy\AgroEmpaques.Infrastructure\Services\AlmacenDocumentalService.vb'
    $reader = 'src\Legacy\AgroEmpaques.Infrastructure\Services\ArchivoCargaMasivaReader.vb'
    $loads = 'src\Legacy\AgroEmpaques.Application\Services\CargaMasivaService.vb'
    $third = 'src\AgroInpaco.Web\Components\Pages\Terceros\Edit.razor'

    $uiText = Read-Source $ui
    $docText = Read-Source $doc
    $storeText = Read-Source $store
    $readerText = Read-Source $reader
    $loadText = Read-Source $loads
    $thirdText = Read-Source $third

    $evidence = @()
    $evidence += Save-Matches $ui @('MaxUploadBytes','SaveTempAsync','_templateId','ModuloOrigen','EntidadOrigen','IdRegistroOrigen','/erp/auditoria','/erp/informes')
    $evidence += Save-Matches $doc @('TamanoMaximoMB','BuscarTipoArchivo','GuardarArchivo','IdCategoriaDocumental','IdCarpetaDocumental')
    $evidence += Save-Matches $store @('documentos_agroempaques.ini','File.Copy','CalcularHash','RutaArchivo')
    $evidence += Save-Matches $reader @('Path.GetExtension','ZipFile.OpenRead','File.ReadAllLines','XDocument.Load','CalcularHash','GenerarPlantilla')
    $evidence += Save-Matches $loads @('Hash','CrearLote','Procesar','Validar','PermiteProcesar')
    $evidence | Set-Content -LiteralPath (Join-Path $Out 'EVIDENCIAS_CODIGO.txt') -Encoding UTF8

    Save-Matches $third @('@bind','Responsabilidad','Contacto','Direccion','Rol','Clasificacion','TipoPersona','TipoIdentificacion','NumeroIdentificacion','DigitoVerificacion') |
        Set-Content -LiteralPath (Join-Path $Out 'EVIDENCIAS_TERCEROS_UI.txt') -Encoding UTF8

    if ($uiText -match '50L?\s*\*\s*1024L?\s*\*\s*1024L?') {
        Add-Finding 'M02-P03-OBS-054' 'MEDIA' 'Archivos' 'Limite web fijo de 50 MiB' 'El componente usa un maximo global de 50 MiB.' 'El limite no se informa ni diferencia por proceso.' 'Mostrar el limite y aplicar reglas por tipo documental.'
    }
    if ($uiText -match 'SaveTempAsync') {
        Add-Finding 'M02-P03-OBS-055' 'ALTA' 'Archivos' 'Copia temporal previa a validacion profunda' 'La interfaz guarda primero en temporal.' 'Un archivo no confiable alcanza disco antes de cuarentena visible.' 'Usar cuarentena, firma magica y analisis antimalware.'
    }
    if (($docText -match 'Path\.GetExtension') -or ($docText -match 'Extension')) {
        Add-Finding 'M02-P03-OBS-056' 'ALTA' 'Documentos' 'Tipo de archivo guiado por extension' 'La admision se apoya en extension o catalogo.' 'Una extension no demuestra el contenido real.' 'Validar MIME, firma binaria y contenido.'
    }
    if ($storeText -match 'CalcularHash') {
        Add-Finding 'M02-P03-OBS-057' 'POSITIVA' 'Integridad' 'Huella digital implementada' 'El almacenamiento calcula hash.' 'Debe verificarse algoritmo, persistencia y revalidacion.' 'Mantener SHA-256 y comprobarlo en descarga y versionado.'
    }
    if ($storeText -match 'documentos_agroempaques\.ini') {
        Add-Finding 'M02-P03-OBS-058' 'MEDIA' 'Almacenamiento' 'Ruta fisica configurable por archivo INI' 'La ubicacion documental puede depender de configuracion externa.' 'Una ruta mal configurada puede dispersar o exponer archivos.' 'Administrar configuracion, permisos y prueba de escritura controlada.'
    }
    if (($uiText -match 'ModuloOrigen') -and ($uiText -match 'EntidadOrigen')) {
        Add-Finding 'M02-P03-OBS-059' 'ALTA' 'Integracion' 'Origen transversal editable' 'Los campos de origen estan expuestos en el formulario.' 'Se permiten referencias arbitrarias y perdida de trazabilidad.' 'Resolver el origen desde registros reales y bloquear edicion libre.'
    }
    if (($uiText -match 'IdCategoriaDocumental') -and ($uiText -match 'IdCarpetaDocumental')) {
        Add-Finding 'M02-P03-OBS-060' 'ALTA' 'Clasificacion' 'Categoria y carpeta son campos independientes' 'La interfaz administra ambos identificadores por separado.' 'Permite combinaciones incoherentes confirmadas visualmente.' 'Mapear categoria y carpetas, y validar compatibilidad.'
    }
    if ($uiText -match '_templateId\s*=\s*_templates\.FirstOrDefault') {
        Add-Finding 'M02-P03-OBS-061' 'MEDIA' 'Cargas' 'Plantilla predeterminada automatica' 'Se selecciona la primera plantilla al cargar.' 'Aumenta el riesgo de leer un archivo con plantilla equivocada.' 'Iniciar sin seleccion y exigir una decision explicita.'
    }
    if (($readerText -match 'XDocument\.Load') -and ($readerText -match 'ZipFile\.OpenRead')) {
        Add-Finding 'M02-P03-OBS-062' 'ALTA' 'Excel' 'Lectura directa de XML dentro de XLSX' 'El lector abre ZIP y XML.' 'Debe controlar zip bombs, XML externo y tamanos internos.' 'Deshabilitar DTD y limitar entradas, compresion y expansion.'
    }
    if ($readerText -match 'File\.ReadAllLines') {
        Add-Finding 'M02-P03-OBS-063' 'MEDIA' 'CSV/TXT' 'Lectura completa en memoria' 'El lector usa ReadAllLines.' 'Archivos grandes pueden agotar memoria.' 'Procesar por streaming y limitar filas y longitudes.'
    }
    if (($readerText -match 'CalcularHash') -or ($loadText -match 'Hash')) {
        Add-Finding 'M02-P03-OBS-064' 'POSITIVA' 'Cargas' 'Huella digital de archivo de carga' 'Existe calculo o manejo de hash.' 'Debe confirmarse deduplicacion e inmutabilidad.' 'Persistir SHA-256 y bloquear reprocesos duplicados.'
    }

    $groups = @('Responsabilidad','Contacto','Direccion','Rol','Clasificacion')
    $covered = @($groups | Where-Object { $thirdText -match $_ })
    Add-Finding 'M02-P03-OBS-065' 'CRITICA' 'Plantilla TERCEROS' 'Compatibilidad con M02-P01/P02 pendiente' ("El formulario vigente contiene grupos: " + ($covered -join ', ') + '.') 'La plantilla historica puede omitir relaciones fiscales, contactos y direcciones multiples.' 'No habilitar carga real hasta comparar el catalogo vivo y el contrato vigente.'
}
