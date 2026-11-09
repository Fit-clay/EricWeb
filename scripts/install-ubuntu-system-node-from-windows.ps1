[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z_][A-Za-z0-9_-]*@[A-Za-z0-9._:-]+$')]
    [string]$Target,

    [ValidateRange(1, 65535)]
    [int]$Port = 22,

    [ValidateSet('22', '24')]
    [string]$NodeMajor = '24',

    [ValidatePattern('^[A-Za-z_][A-Za-z0-9_-]*$')]
    [string]$AppUser = 'pixiu',

    [string]$IdentityFile
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$sshCommand = Get-Command ssh -ErrorAction SilentlyContinue
$scpCommand = Get-Command scp -ErrorAction SilentlyContinue
if (-not $sshCommand -or -not $scpCommand) {
    throw 'OpenSSH client commands ssh and scp are required.'
}

$remoteScript = Join-Path $PSScriptRoot 'install-ubuntu-system-node-remote.sh'
if (-not (Test-Path -LiteralPath $remoteScript -PathType Leaf)) {
    throw "Missing remote installer: $remoteScript"
}

$sshArgs = @(
    '-tt',
    '-p', $Port.ToString(),
    '-o', 'ServerAliveInterval=15',
    '-o', 'ServerAliveCountMax=4'
)
$scpArgs = @(
    '-P', $Port.ToString(),
    '-o', 'ServerAliveInterval=15',
    '-o', 'ServerAliveCountMax=4'
)

if ($IdentityFile) {
    if (-not (Test-Path -LiteralPath $IdentityFile -PathType Leaf)) {
        throw "SSH identity file does not exist: $IdentityFile"
    }
    $resolvedIdentity = (Resolve-Path -LiteralPath $IdentityFile).Path
    $sshArgs += @('-i', $resolvedIdentity)
    $scpArgs += @('-i', $resolvedIdentity)
}

$remotePath = '/tmp/install-system-node-' + [Guid]::NewGuid().ToString('N') + '.sh'

Write-Host "Uploading the installer to $Target..."
& $scpCommand.Source @scpArgs $remoteScript "${Target}:$remotePath"
if ($LASTEXITCODE -ne 0) {
    throw "scp failed with exit code $LASTEXITCODE"
}

Write-Host "Installing system-wide Node.js $NodeMajor.x on $Target..."
$remoteCommand = "bash '$remotePath' '$NodeMajor' '$AppUser'; install_status=`$?; rm -f -- '$remotePath'; exit `$install_status"
& $sshCommand.Source @sshArgs $Target $remoteCommand
if ($LASTEXITCODE -ne 0) {
    throw "Remote installation failed with exit code $LASTEXITCODE"
}

Write-Host 'System-wide Node.js installation completed successfully.'
