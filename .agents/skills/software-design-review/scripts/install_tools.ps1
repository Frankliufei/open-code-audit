param(
    [string]$OcrPackage = "@alibaba-group/open-code-review",
    [string]$CodebaseMemoryPackage = "codebase-memory-mcp",
    [string]$PythonAuditToolsRoot = (Join-Path $env:LOCALAPPDATA "CodexTools\software-design-review-python-audit"),
    [switch]$SkipOcr,
    [switch]$SkipCodebaseMemory,
    [switch]$SkipPythonAuditTools
)

$ErrorActionPreference = "Stop"

function Assert-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name"
    }
}

function Invoke-WithoutProxy {
    param(
        [scriptblock]$Script
    )

    $proxyNames = @(
        "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "WS_PROXY", "WSS_PROXY",
        "http_proxy", "https_proxy", "all_proxy", "ws_proxy", "wss_proxy"
    )
    $oldValues = @{}

    foreach ($name in $proxyNames) {
        $oldValues[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
        Remove-Item "Env:$name" -ErrorAction SilentlyContinue
    }

    try {
        & $Script
    } finally {
        foreach ($name in $proxyNames) {
            if ($oldValues[$name]) {
                Set-Item "Env:$name" $oldValues[$name]
            }
        }
    }
}

Assert-Command "npm"

if (-not $SkipOcr) {
    Write-Output "Installing open-code-review package: $OcrPackage"
    npm install -g $OcrPackage
}

if (-not $SkipCodebaseMemory) {
    Write-Output "Installing codebase-memory package: $CodebaseMemoryPackage"
    npm install -g $CodebaseMemoryPackage
}

if (-not $SkipPythonAuditTools) {
    Assert-Command "python"
    $venvRoot = Join-Path $PythonAuditToolsRoot ".venv"
    $venvPython = Join-Path $venvRoot "Scripts\python.exe"

    if (-not (Test-Path -LiteralPath $venvPython)) {
        Write-Output "Creating Python audit tools venv: $venvRoot"
        New-Item -ItemType Directory -Force -Path $PythonAuditToolsRoot | Out-Null
        python -m venv $venvRoot
    }

    Write-Output "Installing Python audit tools into dedicated venv: ruff semgrep import-linter"
    Invoke-WithoutProxy {
        & $venvPython -m pip install --upgrade pip
        & $venvPython -m pip install PySocks ruff semgrep import-linter
    }
}

Write-Output "Tool installation commands finished. Run check_tools.ps1 to verify."
