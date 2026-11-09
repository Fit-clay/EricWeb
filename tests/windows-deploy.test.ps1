# Runs offline on Windows PowerShell 5.1 and PowerShell 7; never connects to a server.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.IO.Compression.FileSystem
$root = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('pixiu-windows-test-' + [Guid]::NewGuid().ToString('N'))
$utf8 = New-Object Text.UTF8Encoding($false)
$originalPath = $env:Path
function Assert-True($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Write-Fixture([string]$Name, [string]$Value) {
    $file = Join-Path $fixture $Name
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($file))
    [IO.File]::WriteAllText($file, $Value, $utf8)
}
try {
    Write-Fixture 'scripts\placeholder' ''
    Copy-Item -LiteralPath (Join-Path $root 'scripts\deploy-vps.ps1') -Destination (Join-Path $fixture 'scripts')
    Write-Fixture 'package.json' '{}'
    Write-Fixture 'package-lock.json' '{}'
    Write-Fixture 'scripts\deploy-vps-remote.sh' "#!/bin/bash`r`necho ok`r`n"
    Write-Fixture 'scripts\publish-html-remote.py' '# fixture'
    Write-Fixture 'html-pages\example.html' '<title>Fixture</title>'
    Write-Fixture 'html-pages\nested\style.css' 'body {}'
    Write-Fixture 'html-pages\.env' 'DO NOT UPLOAD'
    Write-Fixture 'html-pages\helper.sh' "#!/bin/bash`r`necho ok`r`n"
    Write-Fixture '.env.example' 'EXAMPLE=yes'
    Write-Fixture '.deploy.env.example' 'VPS_HOST=example.com'
    Write-Fixture '.deploy.env' "VPS_HOST=example.com`nVPS_SSH_USER=root`n"
    foreach ($name in @('node_modules\secret.txt', '.git\config', '.next\cache',
        '.env', '.env.local', '.deploy.env.backup', 'data\pixiu.sqlite', 'data\pixiu.sqlite-wal',
        'private.pem', 'id_ed25519', '.npm-cache\cache', 'outputs\old.zip', 'custom-config.txt',
        'identity-without-extension', '.agents\private.txt')) { Write-Fixture $name 'DO NOT UPLOAD' }
    Write-Fixture 'custom-config.txt' "export VPS_HOST='example.com' # comment`nVPS_SSH_USER=`"root`"`n"
    $script = Join-Path $fixture 'scripts\deploy-vps.ps1'
    $config = Join-Path $fixture 'custom-config.txt'
    $identity = Join-Path $fixture 'identity-without-extension'
    & $script -ConfigFile $config -IdentityFile $identity -Mode Html -PackageOnly
    $archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $fixture 'outputs\html-pages.zip'))
    try {
        $names = @($archive.Entries | ForEach-Object { $_.FullName })
        foreach ($expected in @('example.html', 'nested/style.css', 'helper.sh')) {
            Assert-True ($names -contains $expected) "Missing or invalid archive path: $expected"
        }
        Assert-True (-not ($names -contains 'package.json')) 'HTML package contains application source.'
        Assert-True (-not ($names -contains '.deploy.env')) 'Default deployment config was packaged.'
        foreach ($entry in $archive.Entries) {
            if ($entry.Name) {
                $reader = New-Object IO.StreamReader($entry.Open())
                try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
                Assert-True (-not $text.Contains('DO NOT UPLOAD')) "Secret or generated file packaged: $($entry.FullName)"
                Assert-True ($entry.FullName -ne 'custom-config.txt') 'Custom config was packaged.'
                if ($entry.FullName.EndsWith('.sh')) {
                    Assert-True (-not $text.Contains("`r")) 'CRLF not normalized.'
                    $stream = $entry.Open()
                    try { Assert-True ($stream.ReadByte() -eq 35) 'Shell script has an unexpected BOM.' }
                    finally { $stream.Dispose() }
                }
            }
        }
    } finally { $archive.Dispose() }

    # Exercise the actual documented -File entry point, not only in-process invocation.
    $powershellExecutable = (Get-Process -Id $PID).Path
    & $powershellExecutable -NoProfile -ExecutionPolicy Bypass -File $script -Mode Html -PackageOnly
    Assert-True ($LASTEXITCODE -eq 0) 'Standalone CLI invocation failed.'

    # A fake local Docker executable validates orchestration without a Docker daemon or SSH.
    # This is not a substitute for the real Linux build and memory-limited smoke test.
    $mockBin = Join-Path $fixture 'outputs\mock-bin'
    [void][IO.Directory]::CreateDirectory($mockBin)
    $env:PIXIU_DOCKER_TEST_LOG = Join-Path $fixture 'outputs\docker-test.log'
    $env:PIXIU_DOCKER_TEST_FAIL = ''
    $mockSource = @'
using System;
using System.IO;
public class DockerMock {
    public static int Main(string[] args) {
        File.AppendAllText(Environment.GetEnvironmentVariable("PIXIU_DOCKER_TEST_LOG"), String.Join(" ", args) + "\n");
        if (Array.IndexOf(args, "scripts/build-release-local.sh") >= 0) {
            if (Environment.GetEnvironmentVariable("PIXIU_DOCKER_TEST_FAIL") == "1") return 42;
            foreach (string arg in args) {
                if (!arg.StartsWith("type=bind,source=")) continue;
                string path = arg.Substring(17);
                path = path.Substring(0, path.Length - ",target=/workspace".Length);
                string release = Path.Combine(path, ".release");
                Directory.CreateDirectory(release);
                File.WriteAllText(Path.Combine(release, "release.tar.gz"), "fixture-artifact");
            }
        }
        return 0;
    }
}
'@
    Add-Type -TypeDefinition $mockSource -OutputAssembly (Join-Path $mockBin 'docker.exe') -OutputType ConsoleApplication
    $env:Path = $mockBin + ';' + $env:Path
    Write-Fixture 'deploy\Dockerfile.builder' 'FROM fixture'
    & $script -ConfigFile $config -Mode Full -PackageOnly
    $calls = [IO.File]::ReadAllText($env:PIXIU_DOCKER_TEST_LOG)
    Assert-True ($calls.Contains('--platform linux/amd64') -and $calls.Contains('--memory=512m') -and
        $calls.Contains('--memory-swap=512m') -and $calls.Contains('STANDALONE_NODE=/workspace/.release/payload/runtime/node')) 'Full update omitted Linux or final-artifact 512MB checks.'
    Assert-True ((Test-Path -LiteralPath (Join-Path $fixture 'outputs\release.tar.gz'))) 'Local artifact not exported.'
    $env:PIXIU_DOCKER_TEST_FAIL = '1'
    $buildRejected = $false
    try { & $script -ConfigFile $config -Mode Full -PackageOnly } catch { $buildRejected = $_.Exception.Message.Contains('Local compilation and production tests failed (42)') }
    Assert-True $buildRejected 'Local build failure did not stop the update.'
    $env:Path = $originalPath

    $tokens = $null
    $parseErrors = $null
    $syntax = [Management.Automation.Language.Parser]::ParseFile($script, [ref]$tokens, [ref]$parseErrors)
    $nativeFunction = $syntax.Find({ param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-Native'
    }, $true)
    Set-Item Function:Invoke-Native -Value ($nativeFunction.Body.GetScriptBlock())
    $failureMessage = ''
    try { Invoke-Native $env:ComSpec @('/d', '/c', 'exit 137') 'Remote build fixture' }
    catch { $failureMessage = $_.Exception.Message }
    Assert-True ($failureMessage.Contains('Remote build fixture failed (137)') -and
        $failureMessage.Contains('-DiagnoseOnly')) 'Exit 137 lost its stage or diagnostic guidance.'
    $rejected = $false
    try { & $script -ConfigFile $config -Mode Html -PackageOnly -DiagnoseOnly } catch { $rejected = $true }
    Assert-True $rejected 'Conflicting offline and diagnostic switches were accepted.'

    foreach ($invalid in @(
        "VPS_BASE_DIR=/var`n", "VPS_DATA_DIR=/var/lib/../`n", "VPS_SSH_PORT=70000`n",
        "VPS_HOST=host;echo-injected`n", "VPS_HEALTHCHECK_URL=http://127.0.0.1:0/`n",
        "VPS_ENV_FILE=/etc/../tmp/settings`n", "VPS_APP_USER=-root`n"
    )) {
        Write-Fixture 'custom-config.txt' ("VPS_HOST=example.com`nVPS_SSH_USER=root`n" + $invalid)
        $rejected = $false
        try { & $script -ConfigFile $config -Mode Html -PackageOnly } catch { $rejected = $true }
        Assert-True $rejected 'Unsafe deployment configuration was accepted.'
    }
    Write-Host 'PASS: archive, paths, CRLF, exclusions, config rejection, and exit-137 diagnostics.'
} finally {
    $env:Path = $originalPath
    Remove-Item Env:PIXIU_DOCKER_TEST_LOG, Env:PIXIU_DOCKER_TEST_FAIL -ErrorAction SilentlyContinue
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
    if ([IO.Path]::GetDirectoryName($resolvedFixture).TrimEnd('\', '/') -eq $tempRoot -and
        [IO.Path]::GetFileName($resolvedFixture) -match '^pixiu-windows-test-[a-f0-9]{32}$' -and
        (Test-Path -LiteralPath $resolvedFixture)) {
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
}
