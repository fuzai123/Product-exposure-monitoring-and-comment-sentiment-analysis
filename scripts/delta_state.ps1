param(
    [ValidateSet('Init', 'Diff', 'Commit', 'Cleanup')]
    [string]$Mode = 'Init',
    [string]$SnapshotPath,
    [string]$DeltaPath,
    [string]$StatePath = (Join-Path $PSScriptRoot 'state.json'),
    [string]$RunsRoot = $PSScriptRoot,
    [int]$SuccessfulRetentionDays = 7,
    [int]$FailedRetentionHours = 48,
    [int]$MaxSizeMB = 500,
    [switch]$Apply
)

$ErrorActionPreference = 'Stop'

function Resolve-SafePath {
    param([string]$Path, [string]$Root)
    $resolvedRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $resolvedPath = [IO.Path]::GetFullPath($Path)
    if (-not $resolvedPath.StartsWith($resolvedRoot + '\', [StringComparison]::OrdinalIgnoreCase) -and $resolvedPath -ne $resolvedRoot) {
        throw "Path escapes monitoring root: $resolvedPath"
    }
    return $resolvedPath
}

function ConvertTo-Hashtable {
    param($InputObject)
    $table = @{}
    if ($null -eq $InputObject) { return $table }
    foreach ($property in $InputObject.PSObject.Properties) { $table[$property.Name] = $property.Value }
    return $table
}

function Get-CanonicalUrl {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $null }
    try { $uri = [Uri]$Url.Trim() } catch { return $Url.Trim() }
    $urlHost = $uri.Host.ToLowerInvariant()
    $path = $uri.AbsolutePath
    $videoId = $null
    if ($urlHost -eq 'youtu.be') {
        $videoId = $path.Trim('/').Split('/')[0]
    } elseif ($urlHost -match '(^|\.)youtube\.com$') {
        if ($path -match '^/shorts/([^/?]+)') { $videoId = $Matches[1] }
        elseif ($path -eq '/watch') {
            foreach ($pair in $uri.Query.TrimStart('?').Split('&')) {
                $parts = $pair.Split('=', 2)
                if ($parts[0] -eq 'v' -and $parts.Count -eq 2) { $videoId = [Uri]::UnescapeDataString($parts[1]); break }
            }
        }
    }
    if ($videoId) { return "https://www.youtube.com/watch?v=$videoId" }
    $drop = @('fbclid', 'gclid', 'igshid', 'si', 'feature', 'ref', 'from')
    $kept = New-Object Collections.Generic.List[string]
    foreach ($pair in $uri.Query.TrimStart('?').Split('&')) {
        if ([string]::IsNullOrWhiteSpace($pair)) { continue }
        $key = [Uri]::UnescapeDataString($pair.Split('=', 2)[0]).ToLowerInvariant()
        if ($key.StartsWith('utm_') -or $drop -contains $key) { continue }
        $kept.Add($pair)
    }
    $query = (($kept | Sort-Object) -join '&')
    $normalizedPath = if ($path -eq '/') { '/' } else { $path.TrimEnd('/') }
    $result = "https://$urlHost$normalizedPath"
    if ($query) { $result += "?$query" }
    return $result
}

function New-State {
    return [ordered]@{ version = 1; updated_at = $null; last_successful_run = $null; platform_cursors = @{}; items = @{} }
}

function Read-State {
    if (-not (Test-Path -LiteralPath $StatePath)) { return (New-State) }
    return (Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json)
}

function Write-JsonFile {
    param($Object, [string]$Path, [int]$Depth = 20)
    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    $Object | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-SnapshotItems {
    if (-not $SnapshotPath) { throw 'SnapshotPath is required.' }
    $snapshot = Get-Content -LiteralPath $SnapshotPath -Raw | ConvertFrom-Json
    if ($snapshot.PSObject.Properties.Name -contains 'items') { return @($snapshot.items) }
    return @($snapshot)
}

function Get-MetricValue {
    param($Item, [string]$Name)
    if ($null -ne $Item.metrics -and $Item.metrics.PSObject.Properties.Name -contains $Name) { return $Item.metrics.$Name }
    if ($Item.PSObject.Properties.Name -contains $Name) { return $Item.$Name }
    return $null
}

if ($Mode -eq 'Init') {
    if (-not (Test-Path -LiteralPath $StatePath)) { Write-JsonFile (New-State) $StatePath }
    [pscustomobject]@{ mode = 'init'; state = $StatePath; exists = $true } | ConvertTo-Json -Compress
    exit 0
}

if ($Mode -eq 'Diff' -or $Mode -eq 'Commit') {
    $state = Read-State
    $stateItems = ConvertTo-Hashtable $state.items
    $snapshotItems = Read-SnapshotItems
}

if ($Mode -eq 'Diff') {
    $delta = [ordered]@{
        generated_at = (Get-Date).ToString('o')
        new_items = New-Object Collections.Generic.List[object]
        metric_changes = New-Object Collections.Generic.List[object]
        comment_changes = New-Object Collections.Generic.List[object]
        transcript_rechecks = New-Object Collections.Generic.List[object]
        unchanged_urls = New-Object Collections.Generic.List[string]
        rejected_missing_url = New-Object Collections.Generic.List[object]
    }
    foreach ($item in $snapshotItems) {
        $url = Get-CanonicalUrl $item.url
        if (-not $url) { $delta.rejected_missing_url.Add($item); continue }
        $old = $stateItems[$url]
        if ($null -eq $old) {
            $item | Add-Member -NotePropertyName canonical_url -NotePropertyValue $url -Force
            $delta.new_items.Add($item)
            $delta.transcript_rechecks.Add([pscustomobject]@{ url = $url; reason = 'new_item' })
            continue
        }
        $changedMetrics = [ordered]@{}
        foreach ($metric in @('views', 'likes', 'comments')) {
            $newValue = Get-MetricValue $item $metric
            $oldValue = Get-MetricValue $old $metric
            if ($null -ne $newValue -and "$newValue" -ne "$oldValue") { $changedMetrics[$metric] = [ordered]@{ old = $oldValue; new = $newValue } }
        }
        if ($changedMetrics.Count -gt 0) { $delta.metric_changes.Add([pscustomobject]@{ url = $url; changes = $changedMetrics }) }
        $oldCount = Get-MetricValue $old 'comments'
        $newCount = Get-MetricValue $item 'comments'
        $oldIds = @($old.comment_ids)
        $newIds = @($item.comment_ids)
        $newCommentIds = @($newIds | Where-Object { $_ -and $_ -notin $oldIds })
        if (($null -ne $newCount -and "$newCount" -ne "$oldCount") -or $newCommentIds.Count -gt 0) {
            $delta.comment_changes.Add([pscustomobject]@{
                url = $url; old_count = $oldCount; new_count = $newCount; new_comment_ids = $newCommentIds
                requires_full_audit = ($null -ne $oldCount -and $null -ne $newCount -and [int64]$newCount -lt [int64]$oldCount)
            })
        }
        $oldFingerprint = $old.transcript_fingerprint
        $newFingerprint = $item.transcript_fingerprint
        $oldStatus = $old.transcript_status
        if ($oldStatus -eq 'gap' -or (-not $oldFingerprint) -or ($newFingerprint -and $newFingerprint -ne $oldFingerprint)) {
            $reason = if ($oldStatus -eq 'gap') { 'previous_gap' } elseif (-not $oldFingerprint) { 'missing_fingerprint' } else { 'fingerprint_changed' }
            $delta.transcript_rechecks.Add([pscustomobject]@{ url = $url; reason = $reason })
        }
        if ($changedMetrics.Count -eq 0 -and $newCommentIds.Count -eq 0 -and "$newCount" -eq "$oldCount" -and $oldStatus -ne 'gap' -and $oldFingerprint -and (-not $newFingerprint -or $newFingerprint -eq $oldFingerprint)) {
            $delta.unchanged_urls.Add($url)
        }
    }
    $delta.summary = [ordered]@{ scanned = @($snapshotItems).Count; new = $delta.new_items.Count; metric_changed = $delta.metric_changes.Count; comments_changed = $delta.comment_changes.Count; transcript_recheck = $delta.transcript_rechecks.Count; unchanged = $delta.unchanged_urls.Count }
    if ($DeltaPath) { Write-JsonFile $delta $DeltaPath }
    $delta | ConvertTo-Json -Depth 20
    exit 0
}

if ($Mode -eq 'Commit') {
    $now = (Get-Date).ToString('o')
    foreach ($item in $snapshotItems) {
        $url = Get-CanonicalUrl $item.url
        if (-not $url) { continue }
        $item | Add-Member -NotePropertyName canonical_url -NotePropertyValue $url -Force
        $item | Add-Member -NotePropertyName last_checked -NotePropertyValue $now -Force
        $stateItems[$url] = $item
    }
    $newState = [ordered]@{ version = 1; updated_at = $now; last_successful_run = $now; platform_cursors = if ($state.platform_cursors) { $state.platform_cursors } else { @{} }; items = $stateItems }
    Write-JsonFile $newState $StatePath
    [pscustomobject]@{ mode = 'commit'; items = $stateItems.Count; state = $StatePath } | ConvertTo-Json -Compress
    exit 0
}

if ($Mode -eq 'Cleanup') {
    $root = Resolve-SafePath $RunsRoot $RunsRoot
    $now = Get-Date
    $actions = New-Object Collections.Generic.List[object]
    $runDirs = Get-ChildItem -LiteralPath $root -Recurse -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like 'run-*' }
    foreach ($dir in $runDirs) {
        $safeDir = Resolve-SafePath $dir.FullName $root
        $summaryPath = Join-Path $safeDir 'run-summary.json'
        $summaryText = if (Test-Path -LiteralPath $summaryPath) { Get-Content -LiteralPath $summaryPath -Raw } else { '' }
        $explicitFailure = $summaryText -match '"result"\s*:\s*"(partial|blocked|blocked_without_mutation)"|"feishu_verified"\s*:\s*false|"feishu_updated"\s*:\s*false'
        $success = -not $explicitFailure -and ($summaryText -match '"site_deployment"\s*:\s*"succeeded"|"result"\s*:\s*"(success|completed)"|"status"\s*:\s*"(success|completed)"|"itemsRechecked"\s*:')
        $cutoff = if ($success) { $now.AddDays(-$SuccessfulRetentionDays) } else { $now.AddHours(-$FailedRetentionHours) }
        if ($dir.LastWriteTime -lt $cutoff) {
            $actions.Add([pscustomobject]@{ action = 'remove_run'; path = $safeDir; reason = if ($success) { 'successful_retention' } else { 'failed_retention' } })
        } elseif ($success) {
            foreach ($child in Get-ChildItem -LiteralPath $safeDir -Force -ErrorAction SilentlyContinue) {
                if ($child.Name -notin @('manifest.json', 'run-summary.json')) { $actions.Add([pscustomobject]@{ action = 'remove_intermediate'; path = (Resolve-SafePath $child.FullName $root); reason = 'successful_run_compaction' }) }
            }
        }
    }
    if ($Apply) {
        foreach ($entry in $actions) { if (Test-Path -LiteralPath $entry.path) { Remove-Item -LiteralPath $entry.path -Recurse -Force } }
    }
    $remainingBytes = (Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
    [pscustomobject]@{ mode = 'cleanup'; applied = [bool]$Apply; planned_actions = $actions; remaining_mb = [math]::Round(($remainingBytes / 1MB), 2); cap_mb = $MaxSizeMB; cap_exceeded = ($remainingBytes -gt ($MaxSizeMB * 1MB)) } | ConvertTo-Json -Depth 10
}
