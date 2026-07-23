param(
    [Parameter(Mandatory = $true)]
    [string]$Target,

    [string]$OutputRoot = "",
    [string]$ProjectKey = "software-design-governance",
    [string]$Background = "",
    [string]$From = "",
    [string]$To = "",
    [string]$Commit = "",
    [switch]$SkipCodebase,
    [switch]$SkipAudit,
    [switch]$SkipOCR,
    [switch]$SkipLocalEvidence
)

$ErrorActionPreference = "Stop"

function Invoke-Captured {
    param(
        [string]$Name,
        [string]$Command,
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [string]$StdoutPath,
        [string]$StderrPath
    )

    $oldLocation = Get-Location
    try {
        Set-Location -LiteralPath $WorkingDirectory
        & $Command @Arguments > $StdoutPath 2> $StderrPath
        $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
        return [ordered]@{
            name = $Name
            command = $Command
            arguments = $Arguments
            exit_code = $exitCode
            stdout = $StdoutPath
            stderr = $StderrPath
        }
    } catch {
        $_ | Out-String | Set-Content -LiteralPath $StderrPath -Encoding UTF8
        return [ordered]@{
            name = $Name
            command = $Command
            arguments = $Arguments
            exit_code = 1
            stdout = $StdoutPath
            stderr = $StderrPath
            error = $_.Exception.Message
        }
    } finally {
        Set-Location $oldLocation
    }
}

function Resolve-ToolFromCheck {
    param(
        [object]$ToolCheck,
        [string]$Name
    )

    foreach ($tool in $ToolCheck.tools) {
        if ($tool.name -eq $Name -and $tool.found) {
            return $tool.path
        }
    }
    return $null
}

$targetRoot = (Resolve-Path -LiteralPath $Target).Path
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$skillRoot = Split-Path -Parent $scriptRoot
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

if ($OutputRoot) {
    $outputBase = $OutputRoot
} else {
    $outputBase = Join-Path $targetRoot ".governance"
}
$runDir = Join-Path $outputBase $timestamp
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$toolCheckPath = Join-Path $runDir "tool-check.json"
$checkToolsScript = Join-Path $scriptRoot "check_tools.ps1"
& powershell -NoProfile -ExecutionPolicy Bypass -File $checkToolsScript -Target $targetRoot -AsJson |
    Set-Content -LiteralPath $toolCheckPath -Encoding UTF8
$toolCheck = Get-Content -LiteralPath $toolCheckPath -Raw | ConvertFrom-Json

$steps = @()
$warnings = @()

if (-not $SkipLocalEvidence) {
    $python = "python"
    $baseRevision = if ($From) { $From } else { "HEAD" }

    $steps += Invoke-Captured `
        -Name "collect_diff" `
        -Command $python `
        -Arguments @((Join-Path $scriptRoot "collect_diff.py"), "--repo", $targetRoot, "--base", $baseRevision) `
        -WorkingDirectory $targetRoot `
        -StdoutPath (Join-Path $runDir "collect-diff.json") `
        -StderrPath (Join-Path $runDir "collect-diff.err.txt")

    $steps += Invoke-Captured `
        -Name "analyze_imports" `
        -Command $python `
        -Arguments @((Join-Path $scriptRoot "analyze_imports.py"), "--repo", $targetRoot) `
        -WorkingDirectory $targetRoot `
        -StdoutPath (Join-Path $runDir "analyze-imports.json") `
        -StderrPath (Join-Path $runDir "analyze-imports.err.txt")

    $steps += Invoke-Captured `
        -Name "detect_extension_cost" `
        -Command $python `
        -Arguments @((Join-Path $scriptRoot "detect_extension_cost.py"), "--repo", $targetRoot, "--base", $baseRevision) `
        -WorkingDirectory $targetRoot `
        -StdoutPath (Join-Path $runDir "extension-cost.json") `
        -StderrPath (Join-Path $runDir "extension-cost.err.txt")
}

if (-not $SkipCodebase) {
    $cbm = Resolve-ToolFromCheck -ToolCheck $toolCheck -Name "codebase-memory-mcp"
    if ($cbm) {
        $cbmOut = Join-Path $runDir "codebase-memory-index.json"
        $cbmErr = Join-Path $runDir "codebase-memory-index.err.txt"
        $payload = "{`"repo_path`":`"$($targetRoot.Replace('\','/'))`"}"
        $steps += Invoke-Captured `
            -Name "codebase_memory_index" `
            -Command $cbm `
            -Arguments @("cli", "index_repository", $payload) `
            -WorkingDirectory $targetRoot `
            -StdoutPath $cbmOut `
            -StderrPath $cbmErr
    } else {
        $warnings += "codebase-memory-mcp not found; use MCP index_repository inside Codex or install the CLI."
    }
}

if (-not $SkipAudit) {
    $audit = Resolve-ToolFromCheck -ToolCheck $toolCheck -Name "code-quality-audit"
    if ($audit) {
        $auditRoot = Join-Path $runDir "code-quality-audit"
        New-Item -ItemType Directory -Force -Path $auditRoot | Out-Null
        $steps += Invoke-Captured `
            -Name "code_quality_audit" `
            -Command "powershell" `
            -Arguments @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $audit, "-Target", $targetRoot, "-OutputRoot", $auditRoot, "-ProjectKey", $ProjectKey) `
            -WorkingDirectory $targetRoot `
            -StdoutPath (Join-Path $runDir "code-quality-audit.out.txt") `
            -StderrPath (Join-Path $runDir "code-quality-audit.err.txt")
    } else {
        $warnings += "code-quality-audit not found; set CODE_QUALITY_AUDIT_SCRIPT or install/provide an equivalent CLI."
    }
}

if (-not $SkipOCR) {
    $ocr = Resolve-ToolFromCheck -ToolCheck $toolCheck -Name "open-code-review"
    if ($ocr) {
        $ocrArgs = @("review", "--audience", "agent")
        if ($Background) {
            $ocrArgs += @("--background", $Background)
        }
        if ($Commit) {
            $ocrArgs += @("--commit", $Commit)
        } elseif ($From -and $To) {
            $ocrArgs += @("--from", $From, "--to", $To)
        }
        $steps += Invoke-Captured `
            -Name "open_code_review" `
            -Command $ocr `
            -Arguments $ocrArgs `
            -WorkingDirectory $targetRoot `
            -StdoutPath (Join-Path $runDir "open-code-review.txt") `
            -StderrPath (Join-Path $runDir "open-code-review.err.txt")
    } else {
        $warnings += "open-code-review not found; set OCR_BIN or install @alibaba-group/open-code-review."
    }
}

$summary = [ordered]@{
    target = $targetRoot
    output_root = $outputBase
    run_dir = $runDir
    timestamp = $timestamp
    project_key = $ProjectKey
    background = $Background
    refs = [ordered]@{
        from = $From
        to = $To
        commit = $Commit
    }
    tool_check = $toolCheckPath
    steps = $steps
    warnings = $warnings
    next_step = "Use software-design-review with this evidence package and references/report-schema.md to produce the final decision."
}

$summaryPath = Join-Path $runDir "evidence-summary.json"
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$nextStepPath = Join-Path $runDir "next-step.md"
@(
    '# Governance Evidence Package',
    '',
    "Run directory: $runDir",
    '',
    'Use $software-design-review to review this evidence package.',
    '',
    'Required high-signal files:',
    '',
    '- evidence-summary.json',
    '- collect-diff.json',
    '- analyze-imports.json',
    '- extension-cost.json',
    '- code-quality-audit/ when present',
    '- open-code-review.txt when present',
    '- codebase-memory-index.json when present'
) | Set-Content -LiteralPath $nextStepPath -Encoding UTF8

$auditFindingsPath = Join-Path $runDir "audit-findings.md"
@(
    '# Governance Audit Findings',
    '',
    'Decision: PENDING_SOFTWARE_DESIGN_REVIEW',
    '',
    'This file is created by run_governance_review.ps1 as a stable repair artifact.',
    'Use $software-design-review to fill or replace it from the evidence package.',
    '',
    '## High',
    '',
    '- Pending final review.',
    '',
    '## Medium',
    '',
    '- Pending final review.',
    '',
    '## Low',
    '',
    '- Pending final review.',
    '',
    '## Open Questions',
    '',
    '- Pending final review.'
) | Set-Content -LiteralPath $auditFindingsPath -Encoding UTF8

$repairBriefPath = Join-Path $runDir "repair-brief.md"
@(
    '# Repair Brief',
    '',
    'Status: PENDING_SOFTWARE_DESIGN_REVIEW',
    '',
    '## Repair Order',
    '',
    '1. Fix High findings first.',
    '2. Fix high-confidence Medium findings next.',
    '3. Leave Low findings unless they are adjacent to required edits.',
    '',
    '## Constraints',
    '',
    '- Preserve existing behavior.',
    '- Do not broaden public APIs unless required by the finding.',
    '- Keep fixes minimal and localized.',
    '- Add or update boundary, contract, or regression tests.',
    '- Rerun governance review after repair.',
    '',
    '## Findings To Fix',
    '',
    '- Pending final review.'
) | Set-Content -LiteralPath $repairBriefPath -Encoding UTF8

Write-Output $summaryPath
