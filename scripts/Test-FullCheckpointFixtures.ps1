[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
$tempBase = [System.IO.Path]::GetTempPath().TrimEnd('\')
$testRoot = Join-Path $tempBase ('full-checkpoint-' + [Guid]::NewGuid().ToString('N'))
$resolvedRoot = [System.IO.Path]::GetFullPath($testRoot)
$safePrefix = [System.IO.Path]::GetFullPath($tempBase).TrimEnd('\') + '\'
if (-not $resolvedRoot.StartsWith($safePrefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture root' }
New-Item -ItemType Directory -Path $resolvedRoot -Force | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$generator = Join-Path $Root 'scripts\New-AnalysisHandover.ps1'
$resumer = Join-Path $Root 'scripts\Resume-AnalysisHandover.ps1'

function Write-Json([string]$Path, $Value) { [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 30), $utf8) }
function Invoke-Resume([string]$RunPath) {
    $priorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $resumer -RunDirectory $RunPath 2>&1
        $exitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $priorPreference }
    [pscustomobject]@{ ExitCode = $exitCode; Output = ($output -join "`n") }
}

try {
    $fullRun = Join-Path $resolvedRoot 'full-run'
    New-Item -ItemType Directory -Path $fullRun | Out-Null
    $stageNames = @('deps','vars','erd','funcs','flow','rules','ui-verify','sd','api-contract','sa','vspec-mock','vspec-e2e','vspec-static','vspec-report','vspec-patch')
    $stages = @()
    foreach ($name in $stageNames) {
        $status = if ($name -eq 'deps') { 'done' } elseif ($name -eq 'vspec-mock') { 'skipped' } else { 'pending' }
        $gate = if ($name -eq 'deps') { 'passed' } elseif ($name -eq 'vspec-mock') { 'skipped' } else { $null }
        $stages += [ordered]@{ name=$name; status=$status; retry_count=0; score_attempts=0; quality_gate=$gate; doc_path=if($name -eq 'deps'){'docs/DEPENDENCIES.md'}else{$null} }
    }
    $state = [ordered]@{
        _schema_version='1.8'; run_id='fixture-full'; analysis_profile='full'; scope_confirmed=$true
        scope_card_path='docs/SCOPE.md'; checkpoint=$null; stages=$stages
    }
    Write-Json (Join-Path $fullRun 'state.json') $state
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $generator -RunDirectory $fullRun -CompletedUnit deps -NextUnit layer2 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Full checkpoint generator failed after deps' }
    $resume = Invoke-Resume $fullRun
    if ($resume.ExitCode -ne 0) { throw "Valid resume rejected: $($resume.Output)" }
    $resumeResult = $resume.Output | ConvertFrom-Json
    if ($resumeResult.next_unit -ne 'layer2') { throw 'Resume did not advance to Layer 2' }
    if (@($resumeResult.pending_stages) -join ',' -ne 'vars,erd,funcs') { throw 'Layer 2 pending stage set is incorrect' }
    if ('deps' -in @($resumeResult.pending_stages)) { throw 'Resume scheduled deps again' }

    $handoverPath = Join-Path $fullRun 'next-session.json'
    $validHandoverText = Get-Content -LiteralPath $handoverPath -Raw -Encoding UTF8
    $tampered = $validHandoverText | ConvertFrom-Json
    $tampered.revision = [int]$tampered.revision + 1
    Write-Json $handoverPath $tampered
    if ((Invoke-Resume $fullRun).ExitCode -eq 0) { throw 'Revision mismatch was accepted' }

    [System.IO.File]::WriteAllText($handoverPath, $validHandoverText, $utf8)
    $tampered = $validHandoverText | ConvertFrom-Json
    $tampered.resume_state_sha256 = ('0' * 64)
    Write-Json $handoverPath $tampered
    if ((Invoke-Resume $fullRun).ExitCode -eq 0) { throw 'Hash mismatch was accepted' }

    $fastRun = Join-Path $resolvedRoot 'fast-run'
    New-Item -ItemType Directory -Path $fastRun | Out-Null
    $fastState = [ordered]@{ _schema_version='1.8'; run_id='fixture-fast'; analysis_profile='fast'; scope_confirmed=$true; checkpoint=$null; stages=@() }
    Write-Json (Join-Path $fastRun 'state.json') $fastState
    $priorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $fastOutput = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $generator -RunDirectory $fastRun -CompletedUnit scope -NextUnit deps 2>&1
        $fastExitCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $priorPreference }
    if ($fastExitCode -eq 0) { throw 'Fast unexpectedly created a checkpoint' }
    if (Test-Path -LiteralPath (Join-Path $fastRun 'next-session.json')) { throw 'Fast created next-session.json' }

    [ordered]@{
        full_deps_checkpoint='pass'; resume_next_unit='layer2'; deps_rerun='prevented'
        revision_mismatch='rejected'; hash_mismatch='rejected'; fast_mode='single-session-unchanged'
    } | ConvertTo-Json
} finally {
    if (Test-Path -LiteralPath $resolvedRoot) { Remove-Item -LiteralPath $resolvedRoot -Recurse -Force }
}
