[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunDirectory,
    [Parameter(Mandatory)][ValidateSet('scope','deps','layer2','flow','rules','ui-verify','sd','api-contract','sa','verify-evidence')][string]$CompletedUnit,
    [Parameter(Mandatory)][ValidateSet('deps','layer2','flow','rules','ui-verify','sd','api-contract','sa','verify-evidence','report-patch-finalize')][string]$NextUnit,
    [string[]]$ReadPath,
    [string]$ResumeCommand
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$resolvedRun = [System.IO.Path]::GetFullPath($RunDirectory)
$statePath = Join-Path $resolvedRun 'state.json'
if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw "Missing run state: $statePath" }

function Get-PropertyValue($Object, [string]$Name, $Default = $null) {
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $Default }
    return $property.Value
}

function Set-PropertyValue($Object, [string]$Name, $Value) {
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
    else { $property.Value = $Value }
}

function Get-UnitStageNames([string]$Unit) {
    switch ($Unit) {
        'deps' { return @('deps') }
        'layer2' { return @('vars','erd','funcs') }
        'flow' { return @('flow') }
        'rules' { return @('rules') }
        'ui-verify' { return @('ui-verify') }
        'sd' { return @('sd') }
        'api-contract' { return @('api-contract') }
        'sa' { return @('sa') }
        'verify-evidence' { return @('vspec-mock','vspec-e2e','vspec-static') }
        'report-patch-finalize' { return @('vspec-report','vspec-patch') }
        default { return @() }
    }
}

function Assert-UnitComplete($State, [string]$Unit) {
    if ($Unit -eq 'scope') {
        if ((Get-PropertyValue $State 'scope_confirmed' $false) -ne $true) { throw 'Scope is not confirmed' }
        return
    }
    $acceptedGates = @('passed','tech_debt_accepted','accepted_risk','skipped')
    foreach ($stageName in (Get-UnitStageNames $Unit)) {
        $stage = @($State.stages | Where-Object { $_.name -eq $stageName })[0]
        if ($null -eq $stage) { throw "Missing stage in state: $stageName" }
        if ($stage.status -notin @('done','skipped')) { throw "Stage is not complete: $stageName ($($stage.status))" }
        if ($stageName -in @('deps','vars','erd','funcs','flow','rules','ui-verify','sd','api-contract','sa')) {
            if ((Get-PropertyValue $stage 'quality_gate') -notin $acceptedGates) {
                throw "Quality gate is not terminal for stage: $stageName"
            }
        }
    }
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

function Write-AtomicUtf8([string]$Path, [string]$Content) {
    $tempPath = "$Path.tmp"
    [System.IO.File]::WriteAllText($tempPath, $Content, $utf8)
    Move-Item -LiteralPath $tempPath -Destination $Path -Force
}

$state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($state.analysis_profile -ne 'full') { throw 'CHECKPOINT_NOT_APPLICABLE: Fast remains a single-session workflow' }
Assert-UnitComplete $state $CompletedUnit

$existing = Get-PropertyValue $state 'checkpoint'
$sameBoundary = $null -ne $existing -and $existing.completed_unit -eq $CompletedUnit -and $existing.next_unit -eq $NextUnit -and $existing.status -eq 'awaiting_resume'
if ($sameBoundary) { $revision = [int]$existing.revision }
else { $revision = [int](Get-PropertyValue $existing 'revision' 0) + 1 }

$projection = Get-ResumeProjection $state $revision $CompletedUnit $NextUnit
$resumeHash = Get-Sha256 $projection
$relativeJson = 'next-session.json'
$relativeMarkdown = 'next-session.md'
$checkpoint = [pscustomobject][ordered]@{
    schema_version = 1
    revision = $revision
    status = 'awaiting_resume'
    completed_unit = $CompletedUnit
    next_unit = $NextUnit
    resume_state_sha256 = $resumeHash
    next_session_json = $relativeJson
    next_session_markdown = $relativeMarkdown
}
Set-PropertyValue $state 'checkpoint' $checkpoint

if ([string]::IsNullOrWhiteSpace($ResumeCommand)) { $ResumeCommand = "/start-analysis --resume $($state.run_id)" }
$defaultReads = @('.analysis-profile.md', 'state.json')
if (-not [string]::IsNullOrWhiteSpace([string]$state.scope_card_path)) { $defaultReads += [string]$state.scope_card_path }
foreach ($stage in @($state.stages | Where-Object { $_.status -in @('done','skipped') })) {
    if (-not [string]::IsNullOrWhiteSpace([string]$stage.doc_path)) { $defaultReads += [string]$stage.doc_path }
}
$reads = @($defaultReads + @($ReadPath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
$pendingStages = @(Get-UnitStageNames $NextUnit)

$handover = [ordered]@{
    resume_schema = 1
    run_id = [string]$state.run_id
    analysis_profile = 'full'
    revision = $revision
    completed_unit = $CompletedUnit
    next_unit = $NextUnit
    resume_state_sha256 = $resumeHash
    state_path = 'state.json'
    read_paths = $reads
    pending_stages = $pendingStages
    resume_command = $ResumeCommand
}

$stateJson = $state | ConvertTo-Json -Depth 30
$handoverJson = $handover | ConvertTo-Json -Depth 20
$readLines = @($reads | ForEach-Object { "- ``$_``" }) -join "`r`n"
$pendingText = if ($pendingStages.Count) { ($pendingStages -join ', ') } else { 'none' }
$markdown = @"
# Next analysis session

- Run: ``$($state.run_id)``
- Checkpoint revision: ``$revision``
- Completed unit: ``$CompletedUnit``
- Next unit: ``$NextUnit``
- Resume-state SHA-256: ``$resumeHash``

## Read first

$readLines

## Resume

``$ResumeCommand``

The resume validator must pass before dispatch. Dispatch only the pending stages for this unit: $pendingText. Do not rerun completed stages. Complete quality repair and rescore inside this same session, then write the next checkpoint and stop.
"@

Write-AtomicUtf8 $statePath $stateJson
Write-AtomicUtf8 (Join-Path $resolvedRun $relativeJson) $handoverJson
Write-AtomicUtf8 (Join-Path $resolvedRun $relativeMarkdown) $markdown
$handover | ConvertTo-Json -Depth 20
