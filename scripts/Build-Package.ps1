[CmdletBinding()]
param(
    [string]$RepositoryRoot = '',
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [string]$NuGetPath = 'nuget.exe',
    [string]$MSBuildPath = 'msbuild.exe',
    [string]$CommitSha,
    [string]$Repository = 'OrcunUcuncu/kafe-232',
    [switch]$AllowDirtySourceForValidation
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent $PSScriptRoot
}

function Invoke-CheckedNative {
    param([string]$Executable, [string[]]$Arguments)
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $Executable"
    }
}

function Resolve-Executable {
    param([string]$Value)
    $command = Get-Command $Value -ErrorAction SilentlyContinue
    if ($null -eq $command) { throw "Required executable not found: $Value" }
    return $command.Source
}

$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path.TrimEnd('\', '/')
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\', '/')
if ($OutputDirectory.Equals($RepositoryRoot, [StringComparison]::OrdinalIgnoreCase) -or
    $OutputDirectory.StartsWith($RepositoryRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Publish outside the source checkout to avoid packaging build output as source.'
}
if (Test-Path -LiteralPath $OutputDirectory) {
    if (Get-ChildItem -LiteralPath $OutputDirectory -Force | Select-Object -First 1) {
        throw 'OutputDirectory must be empty. Use a new directory for each build.'
    }
} else {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}

$NuGetPath = Resolve-Executable $NuGetPath
$MSBuildPath = Resolve-Executable $MSBuildPath
$project = Join-Path $RepositoryRoot 'KafeYonetim\KafeYonetim.csproj'
$packagesConfig = Join-Path $RepositoryRoot 'KafeYonetim\packages.config'
if (!(Test-Path -LiteralPath $project) -or !(Test-Path -LiteralPath $packagesConfig)) {
    throw 'Expected the existing KafeYonetim .csproj and packages.config.'
}
$referenceAssembly = Join-Path ${env:ProgramFiles(x86)} 'Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8.1\mscorlib.dll'
if (!(Test-Path -LiteralPath $referenceAssembly)) { throw '.NET Framework 4.8.1 Targeting Pack is required.' }

$actualCommitSha = (& git -C $RepositoryRoot rev-parse HEAD | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot determine the source commit.' }
if ([string]::IsNullOrWhiteSpace($CommitSha)) { $CommitSha = $actualCommitSha }
if ($CommitSha -notmatch '^[a-fA-F0-9]{40}$') { throw 'CommitSha must be a complete 40-character Git commit SHA.' }
if ($CommitSha -ne $actualCommitSha) { throw 'CommitSha does not match the actual checked-out HEAD.' }
if ($Repository -ne 'OrcunUcuncu/kafe-232') { throw 'The package must belong to OrcunUcuncu/kafe-232.' }
$sourceChanges = @(& git -C $RepositoryRoot status --porcelain --untracked-files=normal)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the source worktree.' }
$sourceDirty = $sourceChanges.Count -gt 0
if ($sourceDirty -and !$AllowDirtySourceForValidation) {
    throw 'The source worktree is dirty. Commit the intended changes first. AllowDirtySourceForValidation creates a validation-only, non-deployable artifact.'
}

$testProjects = @(Get-ChildItem -LiteralPath $RepositoryRoot -Filter '*.csproj' -Recurse -File |
    Where-Object { $_.FullName -notmatch '[\\/](packages|bin|obj|\.git)[\\/]' } |
    Where-Object { $_.Name -match '(?i)test' -or (Select-String -LiteralPath $_.FullName -Pattern '<IsTestProject>\s*true\s*</IsTestProject>' -Quiet) })
if ($testProjects.Count -gt 0) {
    throw 'Test projects were added. Configure their real test execution in CI before packaging; this initial pipeline covers build and Razor validation only.'
}

Invoke-CheckedNative $NuGetPath @(
    'restore', $packagesConfig, '-PackagesDirectory', (Join-Path $RepositoryRoot 'packages'),
    '-NonInteractive', '-Verbosity', 'quiet'
)

Invoke-CheckedNative $MSBuildPath @(
    $project, '/nologo', '/m', '/verbosity:minimal', '/t:Rebuild',
    '/p:Configuration=Release', '/p:Platform=AnyCPU', '/p:MvcBuildViews=true',
    '/p:DeployOnBuild=true', '/p:DeployDefaultTarget=WebPublish', '/p:WebPublishMethod=FileSystem',
    ('/p:PublishUrl=' + $OutputDirectory), '/p:DeleteExistingFiles=false',
    '/p:ExcludeApp_Data=true'
)

foreach ($required in @('Web.config', 'Global.asax', 'bin\KafeYonetim.dll', 'Views\Home\Index.cshtml')) {
    if (!(Test-Path -LiteralPath (Join-Path $OutputDirectory $required) -PathType Leaf)) {
        throw "Publish output is incomplete: $required is missing."
    }
}
[xml]$webConfig = Get-Content -LiteralPath (Join-Path $OutputDirectory 'Web.config') -Raw
$compilation = $webConfig.SelectSingleNode('/configuration/system.web/compilation')
if ($null -eq $compilation -or $compilation.GetAttribute('debug') -eq 'true') {
    throw 'Published Web.config must disable debug compilation.'
}
$authentication = $webConfig.SelectSingleNode('/configuration/system.web/authentication')
if ($null -eq $authentication -or $authentication.GetAttribute('mode') -ne 'Windows') {
    throw 'Published application must retain Windows Authentication.'
}
if ($webConfig.SelectNodes('/configuration/system.web/authorization/deny[@users="?"]').Count -eq 0) {
    throw 'Published application must continue to deny anonymous users.'
}
if ($webConfig.SelectNodes('/configuration/connectionStrings/add').Count -gt 0) {
    throw 'Do not publish development connection strings. Define an environment configuration strategy before adding database connections.'
}
foreach ($setting in $webConfig.SelectNodes('/configuration/appSettings/add')) {
    if ($setting.GetAttribute('key') -match '(?i)(password|secret|token|privatekey|apikey|accesskey)' -and
        ![string]::IsNullOrWhiteSpace($setting.GetAttribute('value'))) {
        throw 'A secret-like application setting was found in the publish output. Use server-side environment configuration.'
    }
}

$files = @(Get-ChildItem -LiteralPath $OutputDirectory -File -Recurse -Force | Sort-Object FullName)
$inventory = @()
foreach ($file in $files) {
    $relative = $file.FullName.Substring($OutputDirectory.Length + 1).Replace('\', '/')
    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Reparse points are not allowed in the package.' }
    if ($relative -match '(?i)(^|/)(\.git|\.vs|\.env(?:\..*)?|app_data)(/|$)' -or
        $file.Extension -match '(?i)^\.(sql|mdf|ndf|ldf|bak|trn|pfx|p12|key|csproj|sln|slnx|cs|vb|user|pubxml)$') {
        throw "Unexpected source, database or credential file in package: $relative"
    }
    $inventory += [ordered]@{
        path = $relative
        sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        length = $file.Length
    }
}
$postBuildChanges = @(& git -C $RepositoryRoot status --porcelain --untracked-files=normal)
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect the source worktree after the build.' }
$sourceDirty = $sourceDirty -or ($postBuildChanges.Count -gt 0)
if ($sourceDirty -and !$AllowDirtySourceForValidation) { throw 'Build changed tracked or untracked source files; package rejected.' }
$manifest = [ordered]@{
    schemaVersion = 1
    repository = $Repository
    commitSha = $CommitSha.ToLowerInvariant()
    targetFramework = 'net481'
    sourceDirty = [bool]$sourceDirty
    validationOnly = [bool]$AllowDirtySourceForValidation
    builtAtUtc = [DateTime]::UtcNow.ToString('o')
    validation = [ordered]@{
        releaseBuild = $true
        razorViews = $true
        applicationTests = 'not-configured'
        databaseTests = 'not-run'
    }
    files = $inventory
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutputDirectory 'deployment-manifest.json') -Encoding utf8
Write-Host "Validated publish package: $OutputDirectory ($($files.Count) files)"
Write-Host 'Scope: Release build, Razor validation and package checks. No application, database or A01-A16 acceptance tests were executed.'
