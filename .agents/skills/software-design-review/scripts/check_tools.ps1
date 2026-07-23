param(
    [string]$Target = ".",
    [switch]$AsJson
)

$ErrorActionPreference = "Stop"

function Resolve-FromNodeModules {
    param(
        [string]$TargetRoot,
        [string[]]$Names
    )

    $binRoot = Join-Path (Resolve-Path -LiteralPath $TargetRoot).Path "node_modules\.bin"
    foreach ($name in $Names) {
        foreach ($suffix in @("", ".cmd", ".ps1", ".exe")) {
            $candidate = Join-Path $binRoot ($name + $suffix)
            if (Test-Path -LiteralPath $candidate) {
                return (Resolve-Path -LiteralPath $candidate).Path
            }
        }
    }
    return $null
}

function Resolve-Tool {
    param(
        [string]$Name,
        [string]$EnvVar,
        [string[]]$Commands,
        [string[]]$FallbackPaths,
        [string]$TargetRoot
    )

    $envValue = [Environment]::GetEnvironmentVariable($EnvVar)
    if ($envValue -and (Test-Path -LiteralPath $envValue)) {
        return [ordered]@{
            name = $Name
            found = $true
            path = (Resolve-Path -LiteralPath $envValue).Path
            source = "env:$EnvVar"
        }
    }

    $nodePath = Resolve-FromNodeModules -TargetRoot $TargetRoot -Names $Commands
    if ($nodePath) {
        return [ordered]@{
            name = $Name
            found = $true
            path = $nodePath
            source = "node_modules"
        }
    }

    foreach ($command in $Commands) {
        $resolved = Get-Command $command -ErrorAction SilentlyContinue
        if ($resolved) {
            return [ordered]@{
                name = $Name
                found = $true
                path = $resolved.Source
                source = "PATH"
            }
        }
    }

    $auditToolsRoot = [Environment]::GetEnvironmentVariable("PYTHON_AUDIT_TOOLS_ROOT")
    if (-not $auditToolsRoot) {
        $auditToolsRoot = Join-Path $env:LOCALAPPDATA "CodexTools\software-design-review-python-audit"
    }
    $auditToolsScripts = Join-Path $auditToolsRoot ".venv\Scripts"
    if (Test-Path -LiteralPath $auditToolsScripts) {
        foreach ($command in $Commands) {
            foreach ($suffix in @("", ".exe", ".cmd", ".ps1")) {
                $candidate = Join-Path $auditToolsScripts ($command + $suffix)
                if (Test-Path -LiteralPath $candidate) {
                    return [ordered]@{
                        name = $Name
                        found = $true
                        path = (Resolve-Path -LiteralPath $candidate).Path
                        source = "python-audit-tools"
                    }
                }
            }
        }
    }

    $pythonScripts = & python -c "import sysconfig; print(sysconfig.get_path('scripts'))" 2>$null
    if ($pythonScripts) {
        foreach ($command in $Commands) {
            foreach ($suffix in @("", ".exe", ".cmd", ".ps1")) {
                $candidate = Join-Path $pythonScripts ($command + $suffix)
                if (Test-Path -LiteralPath $candidate) {
                    return [ordered]@{
                        name = $Name
                        found = $true
                        path = (Resolve-Path -LiteralPath $candidate).Path
                        source = "python-scripts"
                    }
                }
            }
        }
    }

    foreach ($fallback in $FallbackPaths) {
        if ($fallback -and (Test-Path -LiteralPath $fallback)) {
            return [ordered]@{
                name = $Name
                found = $true
                path = (Resolve-Path -LiteralPath $fallback).Path
                source = "fallback"
            }
        }
    }

    return [ordered]@{
        name = $Name
        found = $false
        path = $null
        source = $null
    }
}

$targetRoot = (Resolve-Path -LiteralPath $Target).Path
$tools = @(
    Resolve-Tool `
        -Name "open-code-review" `
        -EnvVar "OCR_BIN" `
        -Commands @("ocr", "ocr.exe") `
        -FallbackPaths @("D:\work\opensource\open-code-review\ocr.exe") `
        -TargetRoot $targetRoot
    Resolve-Tool `
        -Name "codebase-memory-mcp" `
        -EnvVar "CODEBASE_MEMORY_BIN" `
        -Commands @("codebase-memory-mcp", "codebase-memory-mcp.exe") `
        -FallbackPaths @("D:\work\opensource\codebase-memory-mcp-fei\build\c\codebase-memory-mcp.exe", "D:\work\opensource\codebase-memory-mcp-fei\build\codebase-memory-mcp.exe") `
        -TargetRoot $targetRoot
    Resolve-Tool `
        -Name "code-quality-audit" `
        -EnvVar "CODE_QUALITY_AUDIT_SCRIPT" `
        -Commands @("code-quality-audit", "run_audit") `
        -FallbackPaths @("D:\work\code-quanlity-analysis\tools\code-quality-audit\scripts\run_audit.ps1") `
        -TargetRoot $targetRoot
    Resolve-Tool `
        -Name "ruff" `
        -EnvVar "RUFF_BIN" `
        -Commands @("ruff", "ruff.exe") `
        -FallbackPaths @() `
        -TargetRoot $targetRoot
    Resolve-Tool `
        -Name "semgrep" `
        -EnvVar "SEMGREP_BIN" `
        -Commands @("semgrep", "semgrep.exe") `
        -FallbackPaths @() `
        -TargetRoot $targetRoot
    Resolve-Tool `
        -Name "import-linter" `
        -EnvVar "IMPORT_LINTER_BIN" `
        -Commands @("lint-imports", "lint-imports.exe") `
        -FallbackPaths @() `
        -TargetRoot $targetRoot
)

$result = [ordered]@{
    target = $targetRoot
    tools = $tools
    missing = @($tools | Where-Object { -not $_.found } | ForEach-Object { $_.name })
}

if ($AsJson) {
    $result | ConvertTo-Json -Depth 5
} else {
    foreach ($tool in $tools) {
        if ($tool.found) {
            Write-Output ("[OK] {0}: {1} ({2})" -f $tool.name, $tool.path, $tool.source)
        } else {
            Write-Output ("[MISSING] {0}" -f $tool.name)
        }
    }
}
