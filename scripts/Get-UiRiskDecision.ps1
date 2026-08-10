[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('ui','ws-api','rest-api','batch','cli')][string]$EntryType,
    [string]$SourceText = '',
    [switch]$RuntimeAvailable,
    [switch]$CriticalRuntime,
    [ValidateSet('none','static','live','simulation')][string]$EvidenceKind = 'none'
)

$signals = New-Object System.Collections.Generic.List[string]
$patterns = [ordered]@{
    javascript = '(?i)(<script|\.js\b|javascript:|addEventListener|onclick\s*=)'
    ajax = '(?i)(ajax|fetch\s*\(|XMLHttpRequest|partial[- ]?submit)'
    download = '(?i)(download|Content-Disposition|attachment|Blob\s*\(|createObjectURL)'
    layout = '(?i)(responsive|media\s*\(|layout|position:\s*(fixed|sticky)|overflow|dialog|modal)'
    runtime = '(?i)(websocket|timer|setTimeout|setInterval|runtime[- ]only)'
}
foreach ($item in $patterns.GetEnumerator()) {
    if ($SourceText -match $item.Value) { $signals.Add($item.Key) }
}

if ($EntryType -ne 'ui') {
    $decision = 'not_applicable'
} elseif ($signals.Count -eq 0) {
    $decision = 'static_pass'
} elseif ($CriticalRuntime -and -not $RuntimeAvailable) {
    $decision = 'blocked_runtime_evidence'
} elseif ($RuntimeAvailable) {
    $decision = 'playwright_required'
} else {
    $decision = 'blocked_runtime_evidence'
}

$runtimeConfirmed = ($EvidenceKind -eq 'live' -and $RuntimeAvailable)
[ordered]@{
    decision = $decision
    signals = @($signals)
    evidence_kind = $EvidenceKind
    runtime_confirmed = $runtimeConfirmed
    simulation_only = ($EvidenceKind -eq 'simulation')
} | ConvertTo-Json -Depth 4
