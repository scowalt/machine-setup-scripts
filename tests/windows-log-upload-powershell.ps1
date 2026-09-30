# Offline only: extract logging functions, use temporary homes, and replace HTTP
# with an in-memory handler. Never source win.ps1 or contact the real collector.
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'win.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'win.ps1 does not parse' }
foreach ($node in $ast.EndBlock.Statements) {
    if ($node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        ($node.Name -match 'SetupLog' -or $node.Name -in @('Upload-Log', 'Initialize-WindowsEnvironment'))) {
        . ([scriptblock]::Create($node.Extent.Text))
    }
}
Add-Type -AssemblyName System.Net.Http
$compilerOptions = @{}
if ($PSVersionTable.PSVersion.Major -le 5) { $compilerOptions.ReferencedAssemblies = @('System.Net.Http', 'System') }
Add-Type @compilerOptions -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
public class SetupUploadFixtureHandler : HttpMessageHandler {
    public static Queue<int> Results = new Queue<int>();
    public static int Calls;
    public static string Uri, Method, Field, FileName;
    public static byte[] Bytes;
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
        Calls++;
        Uri = request.RequestUri.ToString();
        Method = request.Method.Method;
        foreach (var part in (MultipartFormDataContent)request.Content) {
            Field = part.Headers.ContentDisposition.Name.Trim('"');
            FileName = part.Headers.ContentDisposition.FileName.Trim('"');
            Bytes = part.ReadAsByteArrayAsync().GetAwaiter().GetResult();
        }
        int result = Results.Count > 0 ? Results.Dequeue() : 200;
        if (result == -1) throw new HttpRequestException("DO-NOT-PRINT-SECRET network failure");
        if (result == -2) throw new TaskCanceledException("DO-NOT-PRINT-SECRET timeout");
        if (result == -3) throw new HttpRequestException("DO-NOT-PRINT-SECRET TLS", new System.Security.Authentication.AuthenticationException());
        if (result == -4) {
            token.WaitHandle.WaitOne();
            token.ThrowIfCancellationRequested();
        }
        return Task.FromResult(new HttpResponseMessage((HttpStatusCode)result) {
            Content = new StringContent("DO-NOT-PRINT-SECRET response body")
        });
    }
}
'@
$script:Messages = [Collections.Generic.List[string]]::new()
$script:Sleeps = [Collections.Generic.List[int]]::new()
function Write-Debug($message) { $script:Messages.Add([string]$message) }
function Write-Warning($message) { $script:Messages.Add([string]$message) }
function Start-Sleep { param([int]$Seconds) $script:Sleeps.Add($Seconds) }
function New-SetupLogHttpClient { [Net.Http.HttpClient]::new([SetupUploadFixtureHandler]::new()) }
# Regression guard: this mock deliberately has the Windows PowerShell 5.1
# parameter set, which has no -Form. Any old call fails before reaching HTTP.
function Invoke-RestMethod {
    [CmdletBinding()]
    param($Uri, $Method, $Body, $ContentType, $TimeoutSec)
    throw 'Unexpected legacy transport call'
}
function Invoke-WindowsSetupTasks { throw 'UNIQUE-SETUP-FAILURE-7491' }
function Assert-Log($Condition, [string]$Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}
$root = Join-Path ([IO.Path]::GetTempPath()) ('windows-upload-contract-' + [guid]::NewGuid())
$originalProfile = $env:USERPROFILE
$originalComputer = $env:COMPUTERNAME
$env:USERPROFILE = Join-Path $root 'home'
$env:COMPUTERNAME = 'offline-fixture'
New-Item -ItemType Directory -Path $env:USERPROFILE -Force | Out-Null
try {
    $caught = $null
    try { Initialize-WindowsEnvironment } catch { $caught = $_ }
    Assert-Log ($caught.Exception.Message -eq 'UNIQUE-SETUP-FAILURE-7491') 'Original setup exception must survive finalization'
    Assert-Log ([SetupUploadFixtureHandler]::Calls -eq 1) 'Log must upload even with PowerShell 5.1-style web cmdlets'
    $uploadedText = [IO.File]::ReadAllText($script:SetupLogFile)
    Assert-Log ($uploadedText.Contains('UNIQUE-SETUP-FAILURE-7491')) 'Uploaded transcript must contain the setup failure'
    Assert-Log ([Convert]::ToBase64String([SetupUploadFixtureHandler]::Bytes) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes($script:SetupLogFile))) 'Upload must preserve transcript encoding and bytes'
    Assert-Log (-not $script:SetupTranscriptStarted) 'Transcript must be closed before uploading'
    Assert-Log ([SetupUploadFixtureHandler]::Field -eq 'file') 'Collector multipart field must remain file'
    Assert-Log ([SetupUploadFixtureHandler]::Method -eq 'POST') 'Collector method must remain POST'
    Assert-Log ([SetupUploadFixtureHandler]::Uri -eq 'https://logs.scowalt.com/upload?hostname=offline-fixture') 'Collector destination must remain unchanged'
    Write-Output 'PASS: Windows logging lifecycle and legacy compatibility'

    function New-FixtureLog {
        $path = Join-Path (Get-SetupLogDirectory) ("2026-09-12-120000-" + [guid]::NewGuid().ToString('N') + '.log')
        # Include UTF-16, non-ASCII, CRLF, and a NUL to catch text re-encoding.
        [IO.File]::WriteAllBytes($path, [Text.Encoding]::Unicode.GetPreamble() + [Text.Encoding]::Unicode.GetBytes("log: $([char]0x2713)`r`n`0"))
        return $path
    }
    function Reset-Transport([int[]]$Results = @(200)) {
        [SetupUploadFixtureHandler]::Calls = 0
        [SetupUploadFixtureHandler]::Results.Clear()
        foreach ($result in $Results) { [SetupUploadFixtureHandler]::Results.Enqueue($result) }
        $script:Messages.Clear()
        $script:Sleeps.Clear()
    }
    function Get-FixtureState([string]$Path) { Get-Content -LiteralPath "$Path.upload.json" -Raw | ConvertFrom-Json }
    function Set-FixturePending([string]$Path) {
        $state = @{ schema = 1; state = 'pending'; hostname = 'original-host' }
        [IO.File]::WriteAllText("$Path.upload.json", ($state | ConvertTo-Json))
    }
    function Assert-NoSecrets {
        $diagnostics = $script:Messages -join "`n"
        foreach ($path in [IO.Directory]::EnumerateFiles((Get-SetupLogDirectory), '*.upload.json')) {
            $diagnostics += [IO.File]::ReadAllText($path)
        }
        Assert-Log (-not $diagnostics.Contains('DO-NOT-PRINT-SECRET')) 'Upload diagnostics must not disclose raw response/exception content'
    }

    foreach ($failure in @(408, 429, 500, 503, -1, -2)) {
        Reset-Transport @($failure, 200)
        $path = New-FixtureLog
        Upload-Log -LogPath $path
        Assert-Log ([SetupUploadFixtureHandler]::Calls -eq 2) "Transient failure $failure must retry once then succeed"
        Assert-Log ((Get-FixtureState $path).state -eq 'uploaded') 'Successful retry must clear pending state'
        Assert-Log ($script:Sleeps.Count -eq 1 -and $script:Sleeps[0] -eq 2) 'First retry must use a short delay'
        Assert-Log ([Convert]::ToBase64String([SetupUploadFixtureHandler]::Bytes) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes($path))) 'Multipart must preserve all file bytes'
        Assert-Log ([SetupUploadFixtureHandler]::FileName -eq [IO.Path]::GetFileName($path)) 'Multipart filename must be the local log basename'
        Assert-NoSecrets
    }
    foreach ($failure in @(301, 400, 401, 403, 413, -3)) {
        Reset-Transport @($failure, 200)
        $path = New-FixtureLog
        Upload-Log -LogPath $path
        Assert-Log ([SetupUploadFixtureHandler]::Calls -eq 1) "Permanent failure $failure must not loop"
        Assert-Log ($script:Sleeps.Count -eq 0) 'Permanent failures must not sleep'
        $state = Get-FixtureState $path
        Assert-Log ($state.state -eq 'pending') 'Failed log must remain recoverable'
        $expected = if ($failure -eq -3) { 'tls-validation' } else { "http-$failure" }
        Assert-Log ($state.reason -eq $expected -and $state.attempts -eq 1) 'Persistent diagnostics must contain a safe failure category and count'
        Assert-NoSecrets
        # Clear pending state through a successful upload so other scenarios are isolated.
        Reset-Transport
        Upload-Log -LogPath $path -Recovery
    }
    Reset-Transport @(503, 503, 503, 200)
    $path = New-FixtureLog
    Upload-Log -LogPath $path
    Assert-Log ([SetupUploadFixtureHandler]::Calls -eq 3) 'Retries must stop after three attempts'
    Assert-Log (($script:Sleeps -join ',') -eq '2,4') 'Backoff must remain bounded'
    Assert-Log ((Get-FixtureState $path).reason -eq 'http-503') 'Exhaustion must persist the final status'
    Reset-Transport
    Upload-Log -LogPath $path -Recovery

    Reset-Transport @(-4)
    $path = New-FixtureLog
    $timer = [Diagnostics.Stopwatch]::StartNew()
    Upload-Log -LogPath $path -MaxDurationSeconds 2
    Assert-Log ([SetupUploadFixtureHandler]::Calls -eq 1 -and $timer.Elapsed.TotalSeconds -lt 5) 'HTTP cancellation must honor the remaining time budget'
    Assert-Log ((Get-FixtureState $path).reason -eq 'timeout') 'Cancellation must persist a timeout category'
    Reset-Transport
    Upload-Log -LogPath $path -Recovery
    Write-Output 'PASS: Multipart bytes, safe diagnostics, retry policy, and real HTTP cancellation'

    # Only marked logs are retried, at most three in one recovery pass. A
    # successful record is not re-uploaded and original host attribution stays.
    $unmarked = New-FixtureLog
    $pending = @(1..4 | ForEach-Object { $file = New-FixtureLog; Set-FixturePending $file; $file })
    Reset-Transport
    Invoke-PendingSetupLogUploads
    Assert-Log ([SetupUploadFixtureHandler]::Calls -eq 3) 'Recovery must process at most three pending logs'
    Assert-Log ([SetupUploadFixtureHandler]::Uri -like '*hostname=original-host') 'Recovery must retain the original hostname'
    Assert-Log (-not [IO.File]::Exists("$unmarked.upload.json")) 'Unmarked historical logs must stay untouched'
    Reset-Transport
    Invoke-PendingSetupLogUploads
    Assert-Log ([SetupUploadFixtureHandler]::Calls -eq 1) 'Next recovery pass must handle the remaining log only'
    Reset-Transport
    Invoke-PendingSetupLogUploads
    Assert-Log ([SetupUploadFixtureHandler]::Calls -eq 0) 'Uploaded logs must not be sent again'
    foreach ($file in $pending) { Assert-Log ([IO.File]::Exists($file)) 'Recovery must not delete source logs' }

    # A new setup run must replay a pending closed log even if setup then fails.
    $path = New-FixtureLog
    Set-FixturePending $path
    Reset-Transport
    $caught = $null
    try { Initialize-WindowsEnvironment } catch { $caught = $_ }
    Assert-Log ($caught.Exception.Message -eq 'UNIQUE-SETUP-FAILURE-7491') 'Recovery must preserve later setup exceptions'
    Assert-Log ([SetupUploadFixtureHandler]::Calls -eq 2) 'Next setup run must upload the pending log and its own transcript'
    Assert-Log ((Get-FixtureState $path).state -eq 'uploaded') 'Next-run recovery must remove pending state'
    Write-Output 'PASS: Bounded pending-log recovery on later setup runs'

    foreach ($invalidState in @('', '{invalid-private-state', ('x' * 4097),
        '{"schema":true,"state":"pending","hostname":"fixture"}',
        '{"schema":1,"state":"pending","hostname":"fixture","unrelated":"preserve"}',
        '{"schema":1,"state":"pending","hostname":"../other-host"}')) {
        $path = New-FixtureLog
        [IO.File]::WriteAllText("$path.upload.json", $invalidState)
        Reset-Transport
        Upload-Log -LogPath $path
        Invoke-PendingSetupLogUploads
        Assert-Log ([SetupUploadFixtureHandler]::Calls -eq 0) 'Malformed or unrecognized state must prevent uploads'
        Assert-Log ([IO.File]::ReadAllText("$path.upload.json") -ceq $invalidState) 'Invalid metadata must remain unchanged'
    }
    Reset-Transport
    Upload-Log -LogPath $unmarked -Recovery
    Assert-Log ([SetupUploadFixtureHandler]::Calls -eq 0 -and -not [IO.File]::Exists("$unmarked.upload.json")) 'Recovery must not create state for an unmarked log'

    $path = New-FixtureLog
    Set-FixturePending $path
    $lease = [IO.File]::Open("$path.upload.json", 'Open', 'ReadWrite', 'None')
    try {
        Reset-Transport
        Upload-Log -LogPath $path -Recovery
        Invoke-PendingSetupLogUploads
        Assert-Log ([SetupUploadFixtureHandler]::Calls -eq 0) 'An existing upload lease must prevent concurrent requests'
    } finally { $lease.Dispose() }
    Reset-Transport
    Upload-Log -LogPath $path -Recovery

    $path = New-FixtureLog
    $writer = [IO.File]::Open($path, 'Open', 'ReadWrite', 'None')
    try {
        Reset-Transport
        Upload-Log -LogPath $path
        Assert-Log ([SetupUploadFixtureHandler]::Calls -eq 0) 'A file open for writing must not reach HTTP'
        Assert-Log ((Get-FixtureState $path).reason -eq 'local-file-or-client-error') 'File locks must produce a non-retrying local error'
    } finally { $writer.Dispose() }
    Reset-Transport
    Upload-Log -LogPath $path -Recovery

    # Symlink tests use only temporary paths; no real account directories.
    $target = Join-Path $root 'unrelated-private-file'
    [IO.File]::WriteAllText($target, 'unrelated sentinel')
    $linkSupported = $true
    $probe = Join-Path $root 'link-probe'
    try { New-Item -ItemType SymbolicLink -Path $probe -Target $target -ErrorAction Stop | Out-Null }
    catch { $linkSupported = $false; Write-Output 'SKIP: Symlinks require Windows Developer Mode or appropriate permission' }
    if ($linkSupported) {
        Remove-Item -LiteralPath $probe -Force
        foreach ($linkedPart in @('log', 'state', 'directory', 'home')) {
            $path = New-FixtureLog
            Set-FixturePending $path
            $link = switch ($linkedPart) {
                'log' { $path }
                'state' { "$path.upload.json" }
                'directory' { Get-SetupLogDirectory }
                'home' { $env:USERPROFILE }
            }
            $backup = "$link.fixture-backup"
            Move-Item -LiteralPath $link -Destination $backup
            $destination = if ($linkedPart -in @('home', 'directory')) { $backup } else { $target }
            try {
                New-Item -ItemType SymbolicLink -Path $link -Target $destination | Out-Null
                Reset-Transport
                Upload-Log -LogPath $path -Recovery
                Invoke-PendingSetupLogUploads
                Assert-Log ([SetupUploadFixtureHandler]::Calls -eq 0) "Linked $linkedPart must not upload"
                Assert-Log ([IO.File]::ReadAllText($target) -eq 'unrelated sentinel') 'Linked targets must remain unchanged'
            } finally {
                Remove-Item -LiteralPath $link -Force
                Move-Item -LiteralPath $backup -Destination $link
            }
            Reset-Transport
            Upload-Log -LogPath $path -Recovery
        }
    }
    Write-Output 'PASS: Unmarked, malformed, locked, and linked files remain protected'

    # All network failures must leave the original setup error authoritative.
    Reset-Transport @(503, 503, 503)
    $caught = $null
    try { Initialize-WindowsEnvironment } catch { $caught = $_ }
    Assert-Log ($caught.Exception.Message -eq 'UNIQUE-SETUP-FAILURE-7491') 'Collector outage must not replace setup exception'
    Assert-Log ((Get-FixtureState $script:SetupLogFile).state -eq 'pending') 'Failed-run upload must stay pending'
    Reset-Transport
    Invoke-PendingSetupLogUploads
    function Invoke-WindowsSetupTasks { Write-Host 'Successful fixture setup' }
    Reset-Transport @(403)
    Initialize-WindowsEnvironment
    Assert-Log ((Get-FixtureState $script:SetupLogFile).reason -eq 'http-403') 'Upload failure must not turn successful setup into failure'
    Reset-Transport
    Invoke-PendingSetupLogUploads

    # Closing failure must skip upload, not mark an active log for recovery.
    function Invoke-WindowsSetupTasks { throw 'UNIQUE-SETUP-FAILURE-7491' }
    function Stop-Transcript { [CmdletBinding()] param() throw 'DO-NOT-PRINT-SECRET close failure' }
    Reset-Transport
    try { Initialize-WindowsEnvironment } catch { $caught = $_ }
    Assert-Log ($caught.Exception.Message -eq 'UNIQUE-SETUP-FAILURE-7491') 'Transcript close failure must preserve setup exception'
    Assert-Log ([SetupUploadFixtureHandler]::Calls -eq 0) 'Failed transcript closure must skip upload'
    Assert-Log (-not [IO.File]::Exists("$script:SetupLogFile.upload.json")) 'Active transcript must not become a recovery candidate'
    Remove-Item Function:Stop-Transcript
    Stop-Transcript | Out-Null
    $script:SetupTranscriptStarted = $false
    Assert-NoSecrets

    # Start-Transcript can create a partial file before failing. It must never
    # be labeled closed or queued, nor may setup tasks run without logging.
    function Start-Transcript {
        [CmdletBinding()]
        param($Path, [switch]$NoClobber)
        [IO.File]::WriteAllText($Path, 'partial transcript')
        throw 'UNIQUE-TRANSCRIPT-START-FAILURE'
    }
    Reset-Transport
    try { Initialize-WindowsEnvironment } catch { $caught = $_ }
    Assert-Log ($caught.Exception.Message -eq 'UNIQUE-TRANSCRIPT-START-FAILURE') 'Transcript startup failure must stay authoritative'
    Assert-Log ([SetupUploadFixtureHandler]::Calls -eq 0) 'Partial startup transcript must not upload'
    Assert-Log (-not [IO.File]::Exists("$script:SetupLogFile.upload.json")) 'Partial startup transcript must not become pending'
    Remove-Item Function:Start-Transcript

    function Complete-SetupLog { throw 'UNIQUE-FINALIZATION-FAILURE' }
    Reset-Transport
    try { Initialize-WindowsEnvironment } catch { $caught = $_ }
    Assert-Log ($caught.Exception.Message -eq 'UNIQUE-SETUP-FAILURE-7491') 'Unexpected finalization exception must not mask setup error'
    Stop-Transcript | Out-Null
    $script:SetupTranscriptStarted = $false
    Write-Output 'PASS: Setup results survive collector, transcript, and finalization failures'
}
finally {
    if ($script:SetupTranscriptStarted) { Stop-Transcript -ErrorAction SilentlyContinue | Out-Null }
    $env:USERPROFILE = $originalProfile
    $env:COMPUTERNAME = $originalComputer
    Remove-Item -LiteralPath $root -Recurse -Force
}
