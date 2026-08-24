[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunDirectory,
    [string]$ExpectedRunId
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$resolvedRun = [System.IO.Path]::GetFullPath($RunDirectory)
$statePath = Join-Path $resolvedRun 'state.json'
$handoverPath = Join-Path $resolvedRun 'next-session.json'
foreach ($path in @($statePath, $handoverPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "RESUME_REJECTED: missing $path" }
}

function Get-PropertyValue($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Get-ResumeProjection($State, [int]$Revision, [string]$Completed, [string]$Next) {
    $stageRows = @()
    foreach ($stage in @($State.stages)) {
        $stageRows += [ordered]@{
            name = [string](Get-PropertyValue $stage 'name')
            status = [string](Get-PropertyValue $stage 'status')
            quality_gate = Get-PropertyValue $stage 'quality_gate'
            retry_count = [int](Get-PropertyValue $stage 'retry_count' 0)
            score_attempts = [int](Get-PropertyValue $stage 'score_attempts' 0)
            doc_path = Get-PropertyValue $stage 'doc_path'
        }
    }
    return [ordered]@{
        resume_schema = 1
        run_id = [string]$State.run_id
        analysis_profile = [string]$State.analysis_profile
        state_schema_version = [string]$State._schema_version
        revision = $Revision
        completed_unit = $Completed
        next_unit = $Next
        scope_confirmed = [bool](Get-PropertyValue $State 'scope_confirmed' $false)
        stages = $stageRows
    }
}

function Get-Sha256($Value) {
    $json = $Value | ConvertTo-Json -Depth 20 -Compress
    $bytes = $utf8.GetBytes($json)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

$state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
$handover = Get-Content -LiteralPath $handoverPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($state.analysis_profile -ne 'full' -or $handover.analysis_profile -ne 'full') { throw 'RESUME_REJECTED: Fast is single-session only' }
if (-not [string]::IsNullOrWhiteSpace($ExpectedRunId) -and $state.run_id -ne $ExpectedRunId) { throw 'RESUME_REJECTED: unexpected run_id' }
if ($handover.run_id -ne $state.run_id) { throw 'RESUME_REJECTED: run_id mismatch' }
$checkpoint = Get-PropertyValue $state 'checkpoint'
if ($null -eq $checkpoint -or $checkpoint.status -ne 'awaiting_resume') { throw 'RESUME_REJECTED: state is not awaiting resume' }
if ([int]$handover.revision -ne [int]$checkpoint.revision) { throw 'RESUME_REJECTED: checkpoint revision mismatch' }
if ($handover.completed_unit -ne $checkpoint.completed_unit -or $handover.next_unit -ne $checkpoint.next_unit) { throw 'RESUME_REJECTED: checkpoint boundary mismatch' }
if ($handover.resume_state_sha256 -ne $checkpoint.resume_state_sha256) { throw 'RESUME_REJECTED: handover hash mismatch' }
$projection = Get-ResumeProjection $state ([int]$checkpoint.revision) ([string]$checkpoint.completed_unit) ([string]$checkpoint.next_unit)
$actualHash = Get-Sha256 $projection
if ($actualHash -ne $checkpoint.resume_state_sha256) { throw 'RESUME_REJECTED: state changed after checkpoint' }

$completedStageNames = @($state.stages | Where-Object { $_.status -in @('done','skipped') } | ForEach-Object { $_.name })
$overlap = @($handover.pending_stages | Where-Object { $_ -in $completedStageNames })
if ($overlap.Count) { throw "RESUME_REJECTED: completed stage scheduled again: $($overlap -join ', ')" }

[ordered]@{
    resume_valid = $true
    run_id = [string]$state.run_id
    revision = [int]$checkpoint.revision
    next_unit = [string]$checkpoint.next_unit
    pending_stages = @($handover.pending_stages)
    completed_stages = $completedStageNames
    read_paths = @($handover.read_paths)
} | ConvertTo-Json -Depth 10
