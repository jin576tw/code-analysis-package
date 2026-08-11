[CmdletBinding()]
param([string]$Root)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
$tempBase = [System.IO.Path]::GetTempPath().TrimEnd('\')
$testRoot = Join-Path $tempBase ('fast-contract-' + [Guid]::NewGuid().ToString('N'))
$resolvedRoot = [System.IO.Path]::GetFullPath($testRoot)
$safePrefix = [System.IO.Path]::GetFullPath($tempBase).TrimEnd('\') + '\'
if (-not $resolvedRoot.StartsWith($safePrefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture root' }
New-Item -ItemType Directory -Path $resolvedRoot -Force | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$validator = Join-Path $Root 'scripts\Test-FastAnalysisContract.ps1'
$classifier = Join-Path $Root 'scripts\Get-UiRiskDecision.ps1'

function Write-Json([string]$Path, $Value) { [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 15), $utf8) }
function Copy-Object($Value) { return ($Value | ConvertTo-Json -Depth 15 | ConvertFrom-Json) }
function Invoke-Contract([string]$Evidence, [string]$Review, [string]$Contract, [string]$Plugin, [string]$Market) {
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $validator -EvidencePath $Evidence -ReviewPath $Review -OutputContractPath $Contract -PluginManifestPath $Plugin -MarketplacePath $Market 2>&1
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
}

try {
    $targetPath = Join-Path $resolvedRoot 'ANALYSIS.md'
    [System.IO.File]::WriteAllText($targetPath, '# Scope`r`n# Behavior', $utf8)
    $contractPath = Join-Path $resolvedRoot 'output-contract.json'
    $evidencePath = Join-Path $resolvedRoot 'fast-evidence.json'
    $reviewPath = Join-Path $resolvedRoot 'fast-review.json'
    $pluginPath = Join-Path $resolvedRoot 'plugin.json'
    $marketPath = Join-Path $resolvedRoot 'marketplace.json'
    Write-Json $pluginPath ([ordered]@{ version = '0.12.0' })
    Write-Json $marketPath ([ordered]@{ plugins = @([ordered]@{ version = '0.12.0' }) })

    $contract = [ordered]@{
        contract_schema = 1; contract_id = 'fixture:summary:v1'
        target_document = [ordered]@{ path = 'ANALYSIS.md'; role = 'fixture-summary'; required_sections = @('scope','behavior') }
        evidence_requirements = @(
            [ordered]@{ id = 'scope'; description = 'scope'; required = $true; allowed_not_applicable = $false; collectors = @('dependencies'); target_sections = @('scope') },
            [ordered]@{ id = 'behavior'; description = 'behavior'; required = $true; allowed_not_applicable = $false; collectors = @('functions','execution_flow'); target_sections = @('behavior') }
        )
    }
    Write-Json $contractPath $contract
    $contractHash = (Get-FileHash $contractPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $baseEvidence = [ordered]@{
        fast_schema = 3; analysis_profile = 'fast'; artifact_class = 'fast-v3'; run_id = 'fixture'
        contract_id = 'fixture:summary:v1'; output_contract_sha256 = $contractHash
        target_document_path = 'ANALYSIS.md'; delivery_ready = $false
        coverage = [ordered]@{ covered_sections = @('scope','behavior') }
        collector_runs = @(
            [ordered]@{ collector = 'dependencies'; status = 'complete'; materialized_document = $false; supports = @('scope') },
            [ordered]@{ collector = 'functions'; status = 'complete'; materialized_document = $false; supports = @('behavior') },
            [ordered]@{ collector = 'execution_flow'; status = 'complete'; materialized_document = $false; supports = @('behavior') }
        )
        evidence_requirements = @(
            [ordered]@{ id = 'scope'; status = 'covered'; not_applicable_reason = $null; items = @([ordered]@{ source = 'src/entry'; locator = 'L1'; fact_type = 'observed' }) },
            [ordered]@{ id = 'behavior'; status = 'covered'; not_applicable_reason = $null; items = @([ordered]@{ source = 'src/service'; locator = 'L10'; fact_type = 'observed' }) }
        )
        ui_risk = [ordered]@{ decision = 'static_pass'; signals = @(); evidence_kind = 'static'; runtime_confirmed = $false }
    }
    Write-Json $evidencePath $baseEvidence
    $baseReview = [ordered]@{
        fast_schema = 3; classification = 'fast-v3'; verdict = 'PASS'
        target_document_sha256 = (Get-FileHash $targetPath -Algorithm SHA256).Hash.ToLowerInvariant()
        evidence_sha256 = (Get-FileHash $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
        output_contract_sha256 = $contractHash; reviewed_at = [DateTime]::UtcNow.ToString('o')
        review_round = 1; diff_rate = 0.05; coverage_complete = $true; collectors_verified = $true
        ui_risk_accepted = $true; findings = @(); delivery_ready = $true
    }
    Write-Json $reviewPath $baseReview
    $valid = Invoke-Contract $evidencePath $reviewPath $contractPath $pluginPath $marketPath
    if ($valid.ExitCode -ne 0) { throw "Valid project contract rejected: $($valid.Output)" }

    $missingSection = Copy-Object $baseEvidence
    $missingSection.coverage.covered_sections = @('scope')
    Write-Json $evidencePath $missingSection
    $review = Copy-Object $baseReview; $review.evidence_sha256 = (Get-FileHash $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant(); Write-Json $reviewPath $review
    if ((Invoke-Contract $evidencePath $reviewPath $contractPath $pluginPath $marketPath).ExitCode -eq 0) { throw 'Missing required target section was accepted' }

    $missingEvidence = Copy-Object $baseEvidence
    $missingEvidence.evidence_requirements = @($missingEvidence.evidence_requirements | Where-Object { $_.id -ne 'behavior' })
    Write-Json $evidencePath $missingEvidence
    $review.evidence_sha256 = (Get-FileHash $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant(); Write-Json $reviewPath $review
    if ((Invoke-Contract $evidencePath $reviewPath $contractPath $pluginPath $marketPath).ExitCode -eq 0) { throw 'Missing project evidence requirement was accepted' }

    Write-Json $evidencePath $baseEvidence
    $review = Copy-Object $baseReview; $review.evidence_sha256 = (Get-FileHash $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant(); $review.diff_rate = 0.11; Write-Json $reviewPath $review
    if ((Invoke-Contract $evidencePath $reviewPath $contractPath $pluginPath $marketPath).ExitCode -eq 0) { throw 'diff_rate > 0.10 was accepted' }

    $review = Copy-Object $baseReview; $review.target_document_sha256 = ('0' * 64); Write-Json $reviewPath $review
    if ((Invoke-Contract $evidencePath $reviewPath $contractPath $pluginPath $marketPath).ExitCode -eq 0) { throw 'Stale reviewer fingerprint was accepted' }

    $legacy = Copy-Object $baseEvidence; $legacy.fast_schema = 2; $legacy.artifact_class = 'fast-v2'; Write-Json $evidencePath $legacy
    $review = Copy-Object $baseReview; $review.fast_schema = 2; $review.classification = 'fast-v2'; $review.evidence_sha256 = (Get-FileHash $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant(); Write-Json $reviewPath $review
    if ((Invoke-Contract $evidencePath $reviewPath $contractPath $pluginPath $marketPath).ExitCode -eq 0) { throw 'fast_schema 2 was delivery-ready' }

    Write-Json $evidencePath $baseEvidence
    Write-Json $reviewPath $baseReview
    Write-Json $marketPath ([ordered]@{ plugins = @([ordered]@{ version = '0.11.0' }) })
    if ((Invoke-Contract $evidencePath $reviewPath $contractPath $pluginPath $marketPath).ExitCode -eq 0) { throw 'Version mismatch was accepted' }
    Write-Json $marketPath ([ordered]@{ plugins = @([ordered]@{ version = '0.12.0' }) })

    $alternateTarget = Join-Path $resolvedRoot 'INVENTORY.md'
    [System.IO.File]::WriteAllText($alternateTarget, '# Inventory', $utf8)
    $alternateContract = [ordered]@{
        contract_schema = 1; contract_id = 'fixture:inventory:v1'
        target_document = [ordered]@{ path = 'INVENTORY.md'; role = 'inventory'; required_sections = @('inventory') }
        evidence_requirements = @([ordered]@{ id = 'entities'; description = 'entities'; required = $true; allowed_not_applicable = $false; collectors = @('data_model'); target_sections = @('inventory') })
    }
    Write-Json $contractPath $alternateContract
    $alternateContractHash = (Get-FileHash $contractPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $alternateEvidence = [ordered]@{
        fast_schema = 3; analysis_profile = 'fast'; artifact_class = 'fast-v3'; run_id = 'alternate'
        contract_id = 'fixture:inventory:v1'; output_contract_sha256 = $alternateContractHash
        target_document_path = 'INVENTORY.md'; delivery_ready = $false
        coverage = [ordered]@{ covered_sections = @('inventory') }
        collector_runs = @([ordered]@{ collector = 'data_model'; status = 'complete'; materialized_document = $false; supports = @('entities') })
        evidence_requirements = @([ordered]@{ id = 'entities'; status = 'covered'; items = @([ordered]@{ source = 'src/entity'; locator = 'L1'; fact_type = 'observed' }) })
        ui_risk = [ordered]@{ decision = 'not_applicable'; signals = @(); evidence_kind = 'none'; runtime_confirmed = $false }
    }
    Write-Json $evidencePath $alternateEvidence
    $alternateReview = [ordered]@{
        fast_schema = 3; classification = 'fast-v3'; verdict = 'PASS'
        target_document_sha256 = (Get-FileHash $alternateTarget -Algorithm SHA256).Hash.ToLowerInvariant()
        evidence_sha256 = (Get-FileHash $evidencePath -Algorithm SHA256).Hash.ToLowerInvariant()
        output_contract_sha256 = $alternateContractHash; reviewed_at = [DateTime]::UtcNow.ToString('o')
        review_round = 1; diff_rate = 0.02; coverage_complete = $true; collectors_verified = $true
        ui_risk_accepted = $true; findings = @(); delivery_ready = $true
    }
    Write-Json $reviewPath $alternateReview
    if ((Invoke-Contract $evidencePath $reviewPath $contractPath $pluginPath $marketPath).ExitCode -ne 0) { throw 'Alternate project output contract was rejected' }

    $server = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $classifier -EntryType ui -SourceText '<form method="post">server rendered</form>' -EvidenceKind static | ConvertFrom-Json
    if ($server.decision -ne 'static_pass') { throw 'Server-rendered UI did not static-pass' }
    foreach ($signalText in @('<script src="a.js"></script>','fetch("/api")','Content-Disposition: attachment','position: sticky')) {
        $risk = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $classifier -EntryType ui -SourceText $signalText -RuntimeAvailable -EvidenceKind live | ConvertFrom-Json
        if ($risk.decision -ne 'playwright_required') { throw "Risk signal did not require Playwright: $signalText" }
    }
    $blocked = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $classifier -EntryType ui -SourceText 'runtime-only dialog' -CriticalRuntime -EvidenceKind none | ConvertFrom-Json
    if ($blocked.decision -ne 'blocked_runtime_evidence') { throw 'Missing critical runtime environment was not blocked' }
    $mock = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $classifier -EntryType ui -SourceText 'ajax' -RuntimeAvailable -EvidenceKind simulation | ConvertFrom-Json
    if ($mock.runtime_confirmed -or -not $mock.simulation_only) { throw 'Mock was treated as runtime-confirmed' }

    [ordered]@{
        project_contract_pass = 'pass'; alternate_contract_pass = 'pass'; missing_section = 'rejected'
        missing_evidence = 'rejected'; diff_rate_gt_010 = 'rejected'; stale_fingerprint = 'rejected'
        schema_2 = 'legacy-not-delivery-ready'; version_mismatch = 'rejected'; ui_server_static = 'static_pass'
        ui_risks = 'playwright_required'; runtime_missing = 'blocked'; mock = 'simulation-only'
    } | ConvertTo-Json
} finally {
    if (Test-Path -LiteralPath $resolvedRoot) { Remove-Item -LiteralPath $resolvedRoot -Recurse -Force }
}
