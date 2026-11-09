<#
.SYNOPSIS
Package and deploy Pixiu Library from Windows PowerShell 5.1 or PowerShell 7.
.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\scripts\deploy-vps.ps1
.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\scripts\deploy-vps.ps1 -PackageOnly
.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\scripts\deploy-vps.ps1 -DiagnoseOnly
#>
[CmdletBinding()]
param(
    [ValidateSet('Full', 'Html')][string]$Mode = 'Full',
    [ValidateSet('amd64', 'arm64')][string]$Architecture = 'amd64',
    [string]$ConfigFile,
    [string]$IdentityFile,
    [switch]$PackageOnly,
    [switch]$DiagnoseOnly,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$projectRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$Mode = if ($Mode -ieq 'Full') { 'Full' } else { 'Html' }
$archiveName = if ($Mode -eq 'Full') { 'release.tar.gz' } else { 'html-pages.zip' }
if (-not $ConfigFile) { $ConfigFile = Join-Path $projectRoot '.deploy.env' }
if (-not $OutputPath) { $OutputPath = Join-Path $projectRoot ('outputs\' + $archiveName) }
$utf8 = New-Object Text.UTF8Encoding($false)
if ($PackageOnly -and $DiagnoseOnly) { throw 'PackageOnly and DiagnoseOnly cannot be combined.' }

function Invoke-Native {
    param([string]$Executable, [string[]]$Arguments, [string]$Stage = 'External command')
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        $exitCode = $LASTEXITCODE
        $hint = ''
        if ($exitCode -eq 137) {
            if ($Stage -like 'Local*') {
                $hint = ' The local container was killed. Check Docker Desktop memory and local resource limits; no server build was attempted.'
            } else {
                $hint = ' Exit 137 commonly means SIGKILL. Check remote memory, swap and OOM logs with -DiagnoseOnly; this code alone does not prove an out-of-memory event.'
            }
        } elseif ($exitCode -eq 255) {
            $hint = ' Check the SSH authentication, network connection and server availability.'
        }
        throw "$Stage failed ($exitCode): $([IO.Path]::GetFileName($Executable)).$hint"
    }
}

function Assert-Pattern {
    param([string]$Name, [string]$Value, [string]$Pattern)
    if ($Value -cnotmatch $Pattern) { throw "Invalid deployment setting: $Name" }
}

function Assert-Directory {
    param([string]$Name, [string]$Value)
    Assert-Pattern $Name $Value '^/[A-Za-z0-9._/-]+$'
    if ($Value.EndsWith('/') -or $Value.Contains('//') -or
        $Value -match '(^|/)\.{1,2}(/|$)' -or
        $Value -in @('/bin', '/boot', '/dev', '/etc', '/home', '/lib', '/lib64', '/opt',
            '/proc', '/root', '/run', '/sbin', '/srv', '/sys', '/tmp', '/usr', '/var')) {
        throw "Deployment directory is too broad or contains unsafe segments: $Name"
    }
}

if (-not (Test-Path -LiteralPath $ConfigFile -PathType Leaf)) {
    throw 'Deployment config not found. Copy .deploy.env.example to .deploy.env and edit it first.'
}
$configPath = (Resolve-Path -LiteralPath $ConfigFile).Path
$settings = @{
    VPS_SSH_PORT = '22'; VPS_BASE_DIR = '/opt/pixiu-library'; VPS_APP_USER = 'pixiu'
    VPS_APP_GROUP = 'pixiu'; VPS_SERVICE_NAME = 'pixiu-library'
    VPS_DATA_DIR = '/var/lib/pixiu-library'; VPS_ENV_FILE = '/etc/pixiu-library.env'
    VPS_HEALTHCHECK_URL = 'http://127.0.0.1:3000/'
}
$lineNumber = 0
foreach ($line in [IO.File]::ReadAllLines($configPath, [Text.Encoding]::UTF8)) {
    $lineNumber++
    if ($line -match '^\s*(#.*)?$') { continue }
    if ($line -notmatch '^\s*(?:export\s+)?([A-Z][A-Z0-9_]*)\s*=\s*(.*?)\s*$') {
        throw "Invalid config assignment at line $lineNumber. Use KEY=value, without shell commands."
    }
    $key = $Matches[1]
    $value = $Matches[2]
    # Parse values as data. Never execute or expand a shell expression from this file.
    if ($value -match '^"([^"\r\n]*)"\s*(?:#.*)?$' -or
        $value -match "^'([^'\r\n]*)'\s*(?:#.*)?$") {
        $value = $Matches[1]
    } else {
        $value = ($value -replace '\s+#.*$', '').Trim()
    }
    $settings[$key] = $value
}
foreach ($required in @('VPS_HOST', 'VPS_SSH_USER')) {
    if (-not $settings.ContainsKey($required) -or -not $settings[$required]) {
        throw "Missing deployment setting: $required"
    }
}
Assert-Pattern 'VPS_HOST' $settings.VPS_HOST '^[A-Za-z0-9][A-Za-z0-9._-]*$'
foreach ($key in @('VPS_SSH_USER', 'VPS_APP_USER', 'VPS_APP_GROUP')) {
    Assert-Pattern $key $settings[$key] '^[A-Za-z_][A-Za-z0-9_-]*$'
}
Assert-Pattern 'VPS_SSH_PORT' $settings.VPS_SSH_PORT '^[0-9]{1,5}$'
if ([int]$settings.VPS_SSH_PORT -lt 1 -or [int]$settings.VPS_SSH_PORT -gt 65535) {
    throw 'VPS_SSH_PORT must be between 1 and 65535.'
}
foreach ($key in @('VPS_BASE_DIR', 'VPS_DATA_DIR')) { Assert-Directory $key $settings[$key] }
Assert-Pattern 'VPS_SERVICE_NAME' $settings.VPS_SERVICE_NAME '^[A-Za-z0-9_][A-Za-z0-9_.@-]*$'
Assert-Pattern 'VPS_ENV_FILE' $settings.VPS_ENV_FILE '^/[A-Za-z0-9._/-]+$'
if ($settings.VPS_ENV_FILE -match '(^|/)\.{1,2}(/|$)' -or $settings.VPS_ENV_FILE.EndsWith('/')) {
    throw 'Invalid deployment setting: VPS_ENV_FILE'
}
Assert-Pattern 'VPS_HEALTHCHECK_URL' $settings.VPS_HEALTHCHECK_URL '^http://127\.0\.0\.1:([0-9]{1,5})/[A-Za-z0-9_./?=&%-]*$'
$healthPort = [int]([regex]::Match($settings.VPS_HEALTHCHECK_URL, ':([0-9]+)/').Groups[1].Value)
if ($healthPort -lt 1 -or $healthPort -gt 65535) { throw 'Invalid health-check port.' }

$identityPath = ''
if ($IdentityFile) {
    if (-not (Test-Path -LiteralPath $IdentityFile -PathType Leaf)) { throw 'SSH identity file not found.' }
    $identityPath = (Resolve-Path -LiteralPath $IdentityFile).Path
}
$outputFullPath = [IO.Path]::GetFullPath($OutputPath)
if ($PackageOnly -and (-not $outputFullPath.EndsWith($(if ($Mode -eq 'Full') { '.tar.gz' } else { '.zip' }), [StringComparison]::OrdinalIgnoreCase) -or
    $outputFullPath -eq $configPath -or $outputFullPath -eq $identityPath)) {
    throw 'OutputPath must have the correct archive extension and differ from the config and SSH identity.'
}
foreach ($requiredFile in @('package.json', 'package-lock.json', 'scripts\deploy-vps-remote.sh',
    'scripts\publish-html-remote.py')) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $requiredFile) -PathType Leaf)) {
        throw "Required project file not found: $requiredFile"
    }
}

$sshOptions = @('-p', $settings.VPS_SSH_PORT, '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=4')
$scpOptions = @('-P', $settings.VPS_SSH_PORT, '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=4')
if ($identityPath) {
    $sshOptions += @('-i', $identityPath)
    $scpOptions += @('-i', $identityPath)
}
if (-not $PackageOnly) {
    $ssh = (Get-Command ssh.exe -ErrorAction Stop).Source
    if (-not $DiagnoseOnly) { $scp = (Get-Command scp.exe -ErrorAction Stop).Source }
}
if ($DiagnoseOnly) {
    $sshTarget = $settings.VPS_SSH_USER + '@' + $settings.VPS_HOST
    # Read-only checks; keep SSH interactive so the existing password/sudo flow still works.
    $diagnostics = "printf '\nMemory:\n'; free -h; printf '\nSwap:\n'; swapon --show; printf '\nDisk:\n'; df -h /; printf '\nRecent kernel OOM records (last hour):\n'; journalctl -k -b --since=-1h --no-pager -n 500 | grep -Ei 'out of memory|oom-kill|killed process' || true"
    Write-Host 'Checking remote resources only. No upload or deployment will be performed.'
    Write-Host 'An empty OOM result does not rule out a kill by a host/container limit; journal access may require root.'
    Invoke-Native $ssh ($sshOptions + @('-tt', $sshTarget, $diagnostics)) 'Remote diagnostics'
    return
}

function Copy-ReleaseDirectory {
    param([string]$Source, [string]$Destination)
    [void][IO.Directory]::CreateDirectory($Destination)
    foreach ($item in Get-ChildItem -LiteralPath $Source -Force) {
        if ($item.Name -in @('.git', '.agents', '.codex', '.aws', '.ssh', 'node_modules', '.next',
            'dist', 'out', '.vinext', '.wrangler', '.vercel', '.npm-cache', '.pnp', '.yarn',
            'coverage', 'outputs', 'work', '.release', '__pycache__', '.DS_Store', 'next-env.d.ts', 'yes', 'yes.pub') -or
            ($item.Name -like '.env*' -and $item.Name -ne '.env.example') -or
            ($item.Name -like '.deploy.env*' -and $item.Name -ne '.deploy.env.example') -or
            $item.Name -like 'id_*' -or $item.Name -match '\.(key|pem|log|tsbuildinfo)$' -or
            $item.Name -match '\.(sqlite|sqlite3|db)(-wal|-shm|-journal)?$' -or
            $item.FullName -eq $configPath -or $item.FullName -eq $identityPath -or
            $item.FullName -eq $outputFullPath) { continue }
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Linked files or directories cannot be packaged: $($item.Name)"
        }
        $targetPath = Join-Path $Destination $item.Name
        if ($item.PSIsContainer) {
            Copy-ReleaseDirectory $item.FullName $targetPath
        } elseif ($item.Extension -eq '.sh') {
            $content = [IO.File]::ReadAllText($item.FullName, [Text.Encoding]::UTF8)
            [IO.File]::WriteAllText($targetPath, ($content -replace "`r`n?", "`n"), $utf8)
        } else {
            [IO.File]::Copy($item.FullName, $targetPath)
        }
    }
}

$temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$temporaryDirectory = Join-Path $temporaryRoot ('pixiu-deploy-' + [Guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporaryDirectory)
try {
    Write-Host "[1/4] Preparing $Mode update locally..."
    $sourceDirectory = Join-Path $temporaryDirectory 'source'
    $archive = Join-Path $temporaryDirectory $archiveName
    if ($Mode -eq 'Full') {
        $dockerCommand = Get-Command docker.exe -ErrorAction SilentlyContinue
        if (-not $dockerCommand) { throw 'Full updates require Docker Desktop with Linux containers on THIS computer. The server never builds. HTML-only updates do not require Docker.' }
        $docker = $dockerCommand.Source
        Invoke-Native $docker @('info', '--format', '{{.OSType}}') 'Local Docker readiness'
        Copy-ReleaseDirectory $projectRoot $sourceDirectory
        $builderDirectory = Join-Path $temporaryDirectory 'builder'
        [void][IO.Directory]::CreateDirectory($builderDirectory)
        [IO.File]::Copy((Join-Path $sourceDirectory 'deploy\Dockerfile.builder'), (Join-Path $builderDirectory 'Dockerfile'))
        $image = 'pixiu-local-builder:node24-' + $Architecture
        Invoke-Native $docker @('build', '--platform', "linux/$Architecture", '-t', $image, $builderDirectory) 'Local Linux build image'
        Invoke-Native $docker @('run', '--rm', '--platform', "linux/$Architecture", '--mount',
            "type=bind,source=$sourceDirectory,target=/workspace", $image, 'bash', 'scripts/build-release-local.sh', $Architecture) 'Local compilation and production tests'
        Invoke-Native $docker @('run', '--rm', '--platform', "linux/$Architecture", '--memory=512m', '--memory-swap=512m', '--cpus=1',
            '-e', 'NODE_OPTIONS=--max-old-space-size=192 --max-semi-space-size=4', '--mount',
            "type=bind,source=$sourceDirectory,target=/workspace", '-e', 'STANDALONE_ROOT=/workspace/.release/payload/.next/standalone',
            '-e', 'STANDALONE_NODE=/workspace/.release/payload/runtime/node', '-e', 'HTML_SOURCE_ROOT=/workspace/.release/payload/html-pages',
            $image, 'node', '--test', 'tests/vps-runtime.test.mjs') 'Local 512MB runtime smoke test'
        [IO.File]::Copy((Join-Path $sourceDirectory '.release\release.tar.gz'), $archive)
    } else {
        $htmlRoot = Join-Path $projectRoot 'html-pages'
        if (-not (Test-Path -LiteralPath $htmlRoot -PathType Container)) { throw 'html-pages directory not found.' }
        Copy-ReleaseDirectory $htmlRoot $sourceDirectory
        if (@(Get-ChildItem -LiteralPath $sourceDirectory -Recurse -File).Count -eq 0) { throw 'No HTML files or assets to upload.' }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        Add-Type -AssemblyName System.IO.Compression
        $zip = [IO.Compression.ZipFile]::Open($archive, [IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($file in Get-ChildItem -LiteralPath $sourceDirectory -Recurse -File -Force) {
                $entryName = $file.FullName.Substring($sourceDirectory.Length + 1).Replace('\', '/')
                [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                    $zip, $file.FullName, $entryName, [IO.Compression.CompressionLevel]::Optimal)
            }
        } finally { $zip.Dispose() }
    }
    if ($PackageOnly) {
        if ($outputFullPath.StartsWith($temporaryDirectory + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) { throw 'OutputPath cannot be inside the temporary package directory.' }
        if ($outputFullPath.StartsWith($projectRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase) -and
            -not $outputFullPath.StartsWith((Join-Path $projectRoot 'outputs') + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase)) {
            throw 'For project-local archives, use the outputs directory to avoid overwriting source files.'
        }
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFullPath))
        [IO.File]::Copy($archive, $outputFullPath, $true)
        Write-Host "Package ready: $outputFullPath"
        return
    }

    $releaseId = [DateTime]::UtcNow.ToString('yyyyMMddHHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $remoteStage = '.pixiu-upload-' + $releaseId
    $sshTarget = $settings.VPS_SSH_USER + '@' + $settings.VPS_HOST
    $activationSource = [IO.File]::ReadAllText((Join-Path $projectRoot 'scripts\activate-upload-remote.sh'), [Text.Encoding]::UTF8)
    [IO.File]::WriteAllText((Join-Path $temporaryDirectory 'activate-upload-remote.sh'), ($activationSource -replace "`r`n?", "`n"), $utf8)
    [IO.File]::Copy((Join-Path $projectRoot 'scripts\publish-html-remote.py'), (Join-Path $temporaryDirectory 'publish-html-remote.py'))
    $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $temporaryDirectory 'checksum.sha256'), "$hash  $archiveName`n", $utf8)

    Write-Host '[2/4] Creating a remote staging directory...'
    Invoke-Native $ssh ($sshOptions + @($sshTarget, "test ! -e ~/$remoteStage && mkdir -p ~/$remoteStage")) 'Remote staging setup'
    Write-Host '[3/4] Uploading the completed update...'
    Push-Location $temporaryDirectory
    try {
        Invoke-Native $scp ($scpOptions + @($archiveName, 'checksum.sha256', 'publish-html-remote.py', 'activate-upload-remote.sh', "${sshTarget}:$remoteStage/")) 'Artifact upload'
    } finally { Pop-Location }
    Write-Host '[4/4] Activating the completed update (no remote compilation)...'
    Write-Host 'First deployment may ask for sudo and new administrator credentials.'
    $activateCommand = "bash ~/$remoteStage/activate-upload-remote.sh ~/$remoteStage '$Mode' '$($settings.VPS_BASE_DIR)' '$($settings.VPS_APP_USER)' '$($settings.VPS_APP_GROUP)' '$($settings.VPS_SERVICE_NAME)' '$($settings.VPS_HEALTHCHECK_URL)' '$($settings.VPS_DATA_DIR)' '$($settings.VPS_ENV_FILE)' '$releaseId'"
    Invoke-Native $ssh ($sshOptions + @('-tt', $sshTarget, $activateCommand)) 'Remote activation'
    Write-Host "Deployment completed: $($settings.VPS_HOST) (release $releaseId)"
} finally {
    # Delete only the uniquely named directory created by this invocation.
    $resolvedTemporary = [IO.Path]::GetFullPath($temporaryDirectory)
    if ([IO.Path]::GetDirectoryName($resolvedTemporary).TrimEnd('\', '/') -eq $temporaryRoot.TrimEnd('\', '/') -and
        [IO.Path]::GetFileName($resolvedTemporary) -match '^pixiu-deploy-[a-f0-9]{32}$' -and
        (Test-Path -LiteralPath $resolvedTemporary)) {
        Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force
    }
}
