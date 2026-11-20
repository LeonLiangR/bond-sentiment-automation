$ErrorActionPreference = 'Stop'
function Copy-ReleaseFile([string]$Root, [string]$Destination, [string]$Relative) {
    $target = Join-Path $Destination $Relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $Root $Relative) -Destination $target
}
function Copy-CleanTemplate([string]$Root, [string]$Destination, [string]$Relative) {
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $source = Join-Path $Root $Relative
    # The development folder may retain the vendor blank template under this name.
    if ($Relative -eq 'templates/dq-upload.xlsx' -and (Test-Path -LiteralPath (Join-Path $Root 'templates/dq-share.xlsx'))) {
        $source = Join-Path $Root 'templates/dq-share.xlsx'
    }
    $target = Join-Path $Destination $Relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target
    $archive = [IO.Compression.ZipFile]::Open($target, [IO.Compression.ZipArchiveMode]::Update)
    try {
        $entry = $archive.GetEntry('docProps/core.xml')
        if ($entry) {
            $reader = New-Object IO.StreamReader($entry.Open())
            try { $document = New-Object Xml.XmlDocument; $document.PreserveWhitespace = $true; $document.LoadXml($reader.ReadToEnd()) } finally { $reader.Dispose() }
            foreach ($node in $document.SelectNodes('//*[local-name()="creator" or local-name()="lastModifiedBy"]')) { $node.InnerText = 'BondSentimentAutomation' }
            $entry.Delete()
            $replacement = $archive.CreateEntry('docProps/core.xml')
            $writer = New-Object IO.StreamWriter($replacement.Open(), ([Text.UTF8Encoding]::new($false)))
            try { $writer.Write($document.OuterXml) } finally { $writer.Dispose() }
        }
    } finally { $archive.Dispose() }
}
function New-EmptyReleaseDirectory([string]$Destination) {
    if ((Test-Path -LiteralPath $Destination) -and @(Get-ChildItem -LiteralPath $Destination -Force).Count) {
        throw '发布目录必须为空，避免混入旧数据。请指定新的目录。'
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
}
