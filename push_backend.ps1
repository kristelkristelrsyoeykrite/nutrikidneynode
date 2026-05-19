param(
    [string]$CommitMessage = "Update NutriKidney Node backend",
    [string]$RemoteUrl = "https://github.com/kristelkristelrsyoeykrite/nutrikidneynode.git"
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

$repoPath = $PSScriptRoot
Set-Location -LiteralPath $repoPath

Write-Step "Checking repository"
if (-not (Test-Path -LiteralPath ".git")) {
    throw "This script must be run from the nutrikidneynode git repository."
}

$origin = git remote get-url origin 2>$null
if (-not $origin) {
    git remote add origin $RemoteUrl
} elseif ($origin -ne $RemoteUrl) {
    git remote set-url origin $RemoteUrl
}

Write-Step "Checking ignored secret files"
$blockedTrackedFiles = @(
    ".env",
    "firebase/serviceAccountKey.json"
)

$trackedFiles = git ls-files
foreach ($file in $blockedTrackedFiles) {
    if ($trackedFiles -contains $file) {
        throw "Refusing to push because '$file' is tracked. Remove it from git first."
    }
}

Write-Step "Running Node syntax checks"
$changedJsFiles = git status --short |
    ForEach-Object { $_.Substring(3).Trim() } |
    Where-Object { $_ -like "*.js" -and (Test-Path -LiteralPath $_) }

foreach ($file in $changedJsFiles) {
    node --check $file
}

Write-Step "Staging changes"
git add -A

$pendingChanges = git status --porcelain
if ($pendingChanges) {
    Write-Step "Committing changes"
    git commit -m $CommitMessage
} else {
    Write-Host "No changes to commit."
}

$branch = git branch --show-current
if (-not $branch) {
    $branch = "main"
}

Write-Step "Pushing to GitHub"
git push origin $branch

Write-Host ""
Write-Host "Done. Pushed '$branch' to $RemoteUrl" -ForegroundColor Green
