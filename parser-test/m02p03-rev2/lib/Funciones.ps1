function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    if (Test-Path -LiteralPath $Out) {
        Add-Content -LiteralPath $Log -Value $line -Encoding UTF8
    }
}

function Add-Finding {
    param(
        [string]$Id, [string]$Severity, [string]$Area, [string]$Title,
        [string]$Evidence, [string]$Risk, [string]$Recommendation
    )
    [void]$Findings.Add([pscustomobject]@{
        Id = $Id
        Severidad = $Severity
        Area = $Area
        Titulo = $Title
        Evidencia = $Evidence
        Riesgo = $Risk
        Recomendacion = $Recommendation
    })
}

function Get-RelPath {
    param([string]$Base, [string]$Full)
    $basePath = [System.IO.Path]::GetFullPath($Base).TrimEnd('\', '/')
    $fullPath = [System.IO.Path]::GetFullPath($Full)
    $baseUri = New-Object System.Uri(($basePath + [System.IO.Path]::DirectorySeparatorChar))
    $fullUri = New-Object System.Uri($fullPath)
    [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($fullUri).ToString()).Replace('/', '\')
}

function New-Snapshot {
    param([string]$Base, [string]$Path)
    $scan = @((Join-Path $Base 'src'), (Join-Path $Base 'SQL'))
    $items = foreach ($dir in $scan) {
        if (Test-Path -LiteralPath $dir -PathType Container) {
            Get-ChildItem -LiteralPath $dir -File -Recurse
        }
    }
    $rows = foreach ($item in @($items | Sort-Object FullName -Unique)) {
        [pscustomobject]@{
            Ruta = Get-RelPath -Base $Base -Full $item.FullName
            Longitud = $item.Length
            SHA256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
        }
    }
    @($rows) | Export-Csv -LiteralPath $Path -Delimiter "`t" -NoTypeInformation -Encoding UTF8
    @($rows)
}

function Read-Source {
    param([string]$Relative)
    $full = Join-Path $Root $Relative
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $null }
    Get-Content -LiteralPath $full -Raw
}

function Save-Matches {
    param([string]$Relative, [string[]]$Patterns)
    $full = Join-Path $Root $Relative
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return }
    foreach ($pattern in $Patterns) {
        Select-String -LiteralPath $full -Pattern $pattern -AllMatches | ForEach-Object {
            '{0}:{1}: {2}' -f $Relative, $_.LineNumber, $_.Line.Trim()
        }
    }
}

function Compare-Snapshots {
    param([object[]]$SnapshotBefore, [object[]]$SnapshotAfter)
    $b = @{}
    foreach ($x in @($SnapshotBefore)) { $b[$x.Ruta] = $x.SHA256 }
    $a = @{}
    foreach ($x in @($SnapshotAfter)) { $a[$x.Ruta] = $x.SHA256 }
    @(
        ($b.Keys + $a.Keys | Sort-Object -Unique) |
        Where-Object {
            -not $b.ContainsKey($_) -or
            -not $a.ContainsKey($_) -or
            $b[$_] -ne $a[$_]
        }
    )
}

function Assert-ReadOnlyQuery {
    param([string]$Name, [string]$Query)
    $blocked = '(?im)\b(INSERT|UPDATE|DELETE|MERGE|CREATE|ALTER|DROP|TRUNCATE|GRANT|REVOKE|DENY|BACKUP|RESTORE|DBCC|EXEC(?:UTE)?|BULK)\b'
    if ([regex]::IsMatch($Query, $blocked)) {
        throw "Consulta no permitida por la guarda de solo lectura: $Name"
    }
    if (-not [regex]::IsMatch($Query, '(?im)^\s*(SELECT|WITH)\b')) {
        throw "La consulta no inicia con SELECT o WITH: $Name"
    }
}

function Invoke-ReadOnlySql {
    param(
        [System.Data.SqlClient.SqlConnection]$Connection,
        [string]$Name,
        [string]$Query
    )
    Assert-ReadOnlyQuery -Name $Name -Query $Query
    $cmd = $Connection.CreateCommand()
    $cmd.CommandTimeout = 60
    $cmd.CommandText = $Query
    $da = New-Object System.Data.SqlClient.SqlDataAdapter($cmd)
    $dt = New-Object System.Data.DataTable($Name)
    [void]$da.Fill($dt)

    $rows = foreach ($r in $dt.Rows) {
        $o = [ordered]@{}
        foreach ($c in $dt.Columns) {
            $o[$c.ColumnName] = if ($r[$c] -eq [DBNull]::Value) { $null } else { $r[$c] }
        }
        [pscustomobject]$o
    }
    @($rows) | Export-Csv -LiteralPath (Join-Path $Out ("SQL_" + $Name + '.csv')) -NoTypeInformation -Encoding UTF8

    # Contrato deliberadamente escalar: evita que PowerShell enumere DataTable como DataRow.
    return [int]$dt.Rows.Count
}

function Invoke-SafeReadOnlySql {
    param(
        [System.Data.SqlClient.SqlConnection]$Connection,
        [string]$Name,
        [string]$Query,
        [bool]$Required = $true
    )
    try {
        $rowCount = [int](Invoke-ReadOnlySql -Connection $Connection -Name $Name -Query $Query)
        [void]$SqlChecks.Add([pscustomobject]@{
            Consulta = $Name
            Obligatoria = $Required
            Estado = 'OK'
            Filas = $rowCount
            Error = $null
        })
        Write-Log ("SQL {0}: OK ({1} filas)." -f $Name, $rowCount)
        return $rowCount
    }
    catch {
        $message = $_.Exception.Message
        [void]$SqlChecks.Add([pscustomobject]@{
            Consulta = $Name
            Obligatoria = $Required
            Estado = 'ERROR'
            Filas = 0
            Error = $message
        })
        Write-Log ("SQL {0}: ERROR: {1}" -f $Name, $message) 'WARN'
        return $null
    }
}
