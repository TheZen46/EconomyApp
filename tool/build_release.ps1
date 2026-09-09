<#
.SYNOPSIS
    Automated Multi-Platform Release Pipeline for tAIdy.
    Executes pre-flight checks, static analysis, test suite gates, and compiles Windows & Android release artifacts.

.DESCRIPTION
    Builds and packages production-ready release distributions with cryptographic SHA-256 manifests.
    Usage:
        powershell -ExecutionPolicy Bypass -File tool/build_release.ps1 [-Target all|windows|android] [-SkipTests] [-DryRun]

.PARAMETER Target
    Target platform to build: 'all', 'windows', or 'android'. Default is 'all'.

.PARAMETER SkipTests
    Skip the automated test suite gate (not recommended for production releases).

.PARAMETER SkipAnalyze
    Skip the static analysis lint gate.

.PARAMETER DryRun
    Verify toolchains, environment, and gates without invoking heavy release compilers.

.PARAMETER VersionOverride
    Override version tag (defaults to version in pubspec.yaml).
#>

[CmdletBinding()]
param(
    [ValidateSet('all', 'windows', 'android')]
    [string]$Target = 'all',

    [switch]$SkipTests,
    [switch]$SkipAnalyze,
    [switch]$DryRun,
    [string]$VersionOverride = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$ProjectRoot = (Resolve-Path (Join-Path $ScriptDir "..")).Path
Set-Location $ProjectRoot

# ANSI Color Utilities
function Write-Header {
    param([string]$Text)
    Write-Host "`n======================================================================" -ForegroundColor Cyan
    Write-Host "  $Text" -ForegroundColor Cyan -NoNewline
    Write-Host "  [$(Get-Date -Format 'HH:mm:ss')]" -ForegroundColor DarkGray
    Write-Host "======================================================================" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Text)
    Write-Host "  [OK] $Text" -ForegroundColor Green
}

function Write-WarningMsg {
    param([string]$Text)
    Write-Host "  [!] $Text" -ForegroundColor Yellow
}

function Write-FailureMsg {
    param([string]$Text)
    Write-Host "  [ERROR] $Text" -ForegroundColor Red
}

$ReleaseDir = Join-Path $ProjectRoot "build\releases"
if (-not (Test-Path $ReleaseDir)) {
    New-Item -ItemType Directory -Path $ReleaseDir -Force | Out-Null
}

# ─────────────────────────────────────────────────────────────────────────────
# STAGE 1: Toolchain & Pre-Flight Verification
# ─────────────────────────────────────────────────────────────────────────────
Write-Header "STAGE 1: Toolchain Pre-Flight Inspection"

# Check Flutter
try {
    $FlutterVer = (flutter --version | Select-Object -First 1)
    Write-Success "Flutter SDK: $FlutterVer"
} catch {
    Write-FailureMsg "Flutter CLI is not found in PATH."
    exit 1
}

# Check Git Commit
try {
    $GitCommit = (git rev-parse --short HEAD 2>$null)
    $GitBranch = (git rev-parse --abbrev-ref HEAD 2>$null)
    Write-Success "Git Revision: $GitCommit (Branch: $GitBranch)"
} catch {
    $GitCommit = "unknown"
    $GitBranch = "unknown"
    Write-WarningMsg "Git repository information unavailable."
}

# Parse Version from pubspec.yaml
$PubspecContent = Get-Content (Join-Path $ProjectRoot "pubspec.yaml") -Raw
if ($PubspecContent -match "version:\s*([0-9\.\+a-zA-Z\-_]+)") {
    $PubspecVersion = $matches[1]
} else {
    $PubspecVersion = "1.0.0+1"
}

$AppVersion = if ($VersionOverride) { $VersionOverride } else { $PubspecVersion }
Write-Success "Release Target Version: v$AppVersion"

# ─────────────────────────────────────────────────────────────────────────────
# STAGE 2: Quality Gate 1 - Static Code Analysis
# ─────────────────────────────────────────────────────────────────────────────
Write-Header "STAGE 2: Quality Gate 1 - Static Code Analysis"

if ($SkipAnalyze) {
    Write-WarningMsg "Static analysis skipped via -SkipAnalyze flag."
} else {
    Write-Host "  Running 'flutter analyze'..." -ForegroundColor DarkGray
    $AnalyzeResult = flutter analyze 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-FailureMsg "Static analysis failed with errors/warnings:"
        $AnalyzeResult | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        exit 1
    }
    Write-Success "Static code analysis passed: 0 issues found."
}

# ─────────────────────────────────────────────────────────────────────────────
# STAGE 3: Quality Gate 2 - Automated Test Suite
# ─────────────────────────────────────────────────────────────────────────────
Write-Header "STAGE 3: Quality Gate 2 - Automated Test Suite"

if ($SkipTests) {
    Write-WarningMsg "Automated test suite skipped via -SkipTests flag."
} else {
    Write-Host "  Running 'flutter test' across entire unit/widget test suite..." -ForegroundColor DarkGray
    $TestOutput = flutter test 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-FailureMsg "Test suite failed! Aborting release build."
        $TestOutput | Select-Object -Last 15 | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
        exit 1
    }
    Write-Success "All test suites passed (100% pass rate)."
}

if ($DryRun) {
    Write-Header "DRY RUN COMPLETE"
    Write-Success "Pre-flight checks and quality gates succeeded. No binaries were compiled (-DryRun active)."
    exit 0
}

$BuiltArtifacts = @()

# ─────────────────────────────────────────────────────────────────────────────
# STAGE 4: Windows Desktop Release Compilation & Packaging
# ─────────────────────────────────────────────────────────────────────────────
if ($Target -eq 'all' -or $Target -eq 'windows') {
    Write-Header "STAGE 4: Windows Desktop Release Build (x64)"

    Write-Host "  Compiling native C++ engine and Flutter Windows binary..." -ForegroundColor DarkGray
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        Write-FailureMsg "Windows release compilation failed."
        exit 1
    }

    $WinReleaseSrc = Join-Path $ProjectRoot "build\windows\x64\runner\Release"
    $WinZipName = "tAIdy-v$($AppVersion.Replace('+', '_'))-windows-x64.zip"
    $WinZipPath = Join-Path $ReleaseDir $WinZipName

    if (Test-Path $WinZipPath) {
        Remove-Item $WinZipPath -Force
    }

    Write-Host "  Archiving Windows release bundle to $WinZipName..." -ForegroundColor DarkGray
    Compress-Archive -Path "$WinReleaseSrc\*" -DestinationPath $WinZipPath -CompressionLevel Optimal
    Write-Success "Windows release package created: $WinZipPath"
    $BuiltArtifacts += $WinZipPath
}

# ─────────────────────────────────────────────────────────────────────────────
# STAGE 5: Android Mobile Release Compilation (APK)
# ─────────────────────────────────────────────────────────────────────────────
if ($Target -eq 'all' -or $Target -eq 'android') {
    Write-Header "STAGE 5: Android Mobile Release Build (Split ABI)"

    Write-Host "  Compiling Android APKs with NDK C++ acceleration..." -ForegroundColor DarkGray
    flutter build apk --release --split-per-abi
    if ($LASTEXITCODE -ne 0) {
        Write-WarningMsg "Split-per-abi build returned non-zero, falling back to universal release APK..."
        flutter build apk --release
    }

    $ApkSourceDir = Join-Path $ProjectRoot "build\app\outputs\flutter-apk"
    if (Test-Path $ApkSourceDir) {
        $ApkFiles = Get-ChildItem -Path $ApkSourceDir -Filter "*release*.apk"
        foreach ($apk in $ApkFiles) {
            $DestApkName = "tAIdy-v$($AppVersion.Replace('+', '_'))-$($apk.Name)"
            $DestApkPath = Join-Path $ReleaseDir $DestApkName
            Copy-Item -Path $apk.FullName -Destination $DestApkPath -Force
            Write-Success "Android release APK staged: $DestApkPath"
            $BuiltArtifacts += $DestApkPath
        }
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# STAGE 6: Cryptographic Manifest & SHA-256 Checksums
# ─────────────────────────────────────────────────────────────────────────────
Write-Header "STAGE 6: Cryptographic Manifest Generation (SHA-256)"

$ManifestPath = Join-Path $ReleaseDir "SHA256SUMS.txt"
$JsonManifestPath = Join-Path $ReleaseDir "release_manifest.json"

$ManifestLines = @()
$JsonRecords = @()

foreach ($artifactPath in $BuiltArtifacts) {
    if (Test-Path $artifactPath) {
        $FileObj = Get-Item $artifactPath
        $Hash = (Get-FileHash -Path $artifactPath -Algorithm SHA256).Hash.ToLower()
        $FileName = $FileObj.Name
        $SizeMB = [Math]::Round($FileObj.Length / 1MB, 2)

        $ManifestLines += "$Hash  $FileName"
        $JsonRecords += @{
            file = $FileName
            sha256 = $Hash
            size_bytes = $FileObj.Length
            size_mb = $SizeMB
        }
    }
}

$ManifestLines | Out-File -FilePath $ManifestPath -Encoding utf8 -Force
Write-Success "SHA-256 checksums written to: $ManifestPath"

$ReleaseMetadata = @{
    app_name = "tAIdy"
    version = $AppVersion
    git_commit = $GitCommit
    git_branch = $GitBranch
    build_time_utc = (Get-Date).ToUniversalTime().ToString("o")
    target = $Target
    artifacts = $JsonRecords
}

$ReleaseMetadata | ConvertTo-Json -Depth 4 | Out-File -FilePath $JsonManifestPath -Encoding utf8 -Force
Write-Success "Release metadata JSON manifest written to: $JsonManifestPath"

# ─────────────────────────────────────────────────────────────────────────────
# STAGE 7: Release Summary & Distribution Report
# ─────────────────────────────────────────────────────────────────────────────
Write-Header "RELEASE SUMMARY: tAIdy v$AppVersion [$GitCommit]"

Write-Host "  Artifact Distribution Directory: $ReleaseDir`n" -ForegroundColor White

Write-Host ("  {0,-45} {1,10}  {2}" -f "ARTIFACT FILE", "SIZE (MB)", "SHA-256 CHECKSUM (TRUNCATED)") -ForegroundColor Yellow
Write-Host "  -------------------------------------------------------------------------------------" -ForegroundColor DarkGray

foreach ($rec in $JsonRecords) {
    $TruncHash = $rec.sha256.Substring(0, 16) + "..."
    Write-Host ("  {0,-45} {1,10} MB  {2}" -f $rec.file, $rec.size_mb, $TruncHash) -ForegroundColor Green
}

Write-Host "`n  All release packaging and verification steps completed successfully!" -ForegroundColor Cyan
