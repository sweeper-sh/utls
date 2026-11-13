# verify-before-stop.ps1 - a Claude Code Stop hook.
#
# When the agent is about to finish and a Go file, go.mod or go.sum changed, it runs
#   go build ./...
#   go vet ./...
#   go test .        (the root package: the handshake recordings and the uTLS tests)
# and keeps the agent working if one fails.
# It is built not to nag:
#   - it never blocks twice in a row (stop_hook_active);
#   - it does nothing when no Go file changed, or outside a git repository;
#   - it remembers the tree it last passed on and stays quiet until the tree changes;
#   - it does not run gofmt: on Windows gofmt -l reports CRLF working files;
#   - a command that takes longer than two minutes is let through with a note;
#   - when go is not on PATH the checks are skipped with a note.
# It is a convenience, not a gate, and a pass is not proof of an unchanged ClientHello: the
# tests replay recorded handshakes of old browser versions, not the profiles in use today.
#
# Works under Windows PowerShell 5.1 and pwsh 7. Keep this file ASCII.
# Tests: powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/test-hooks.ps1

$ErrorActionPreference = 'Stop'
$timeoutMs = 120000

function Invoke-Git([string]$dir, [string[]]$gitArgs) {
    # git's stderr must not become a terminating error (Windows PowerShell 5.1 makes it one).
    $ErrorActionPreference = 'Continue'
    $out = & git -C $dir @gitArgs 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    if ($null -eq $out) { return '' }
    return ($out -join "`n")
}

# Runs a command in $dir and returns @{ Code; Output; TimedOut; Missing }.
function Invoke-Checked([string]$dir, [string]$exe, [string[]]$cmdArgs) {
    $found = Get-Command -Name $exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $found) { return @{ Code = 0; Output = ''; TimedOut = $false; Missing = $true } }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $found.Source
    $psi.Arguments = (($cmdArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }) -join ' ')
    $psi.WorkingDirectory = $dir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi
    $null = $p.Start()
    # Read both streams while the process runs, or a full pipe would stall it.
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($timeoutMs)) {
        try { $p.Kill() } catch { }
        return @{ Code = 0; Output = ''; TimedOut = $true; Missing = $false }
    }
    $p.WaitForExit()
    return @{ Code = $p.ExitCode; Output = ($outTask.Result + "`n" + $errTask.Result); TimedOut = $false; Missing = $false }
}

function Write-Block([string]$reason) {
    [Console]::Out.WriteLine(([ordered]@{ decision = 'block'; reason = $reason } | ConvertTo-Json -Compress))
    exit 0
}

try {
    try { [Console]::InputEncoding = [Text.Encoding]::UTF8 } catch { }
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $call = $raw | ConvertFrom-Json
    if ($call.stop_hook_active) { exit 0 }
    $dir = [string]$call.cwd
    if ([string]::IsNullOrWhiteSpace($dir) -or -not (Test-Path -LiteralPath $dir)) { $dir = (Get-Location).Path }

    $root = Invoke-Git $dir @('rev-parse', '--show-toplevel')
    if ([string]::IsNullOrWhiteSpace($root)) { exit 0 }
    $root = $root.Trim()
    $status = Invoke-Git $root @('status', '--porcelain', '--untracked-files=all')
    if ($null -eq $status) { exit 0 }

    # Every changed path (a rename's new name), and the ones this hook acts on.
    $changed = @()
    foreach ($line in ($status -split "`n")) {
        if ($line.Length -lt 4) { continue }
        $path = $line.Substring(3)
        $arrow = $path.LastIndexOf(' -> ')
        if ($arrow -ge 0) { $path = $path.Substring($arrow + 4) }
        $changed += $path.Trim('"')
    }
    $watched = @($changed | Where-Object { $_ -match '\.go$' -or $_ -eq 'go.mod' -or $_ -eq 'go.sum' } | Sort-Object -Unique)
    if ($watched.Count -eq 0) { exit 0 }

    # The tree's identity: the commit, what git says changed, and each watched file's size
    # and time (an untracked file's content is not in any git output).
    $head = Invoke-Git $root @('rev-parse', 'HEAD')
    $parts = @([string]$head, $status)
    foreach ($f in $watched) {
        $full = Join-Path $root $f
        if (Test-Path -LiteralPath $full) {
            $item = Get-Item -LiteralPath $full
            $parts += ('{0}|{1}|{2}' -f $f, $item.Length, $item.LastWriteTimeUtc.Ticks)
        }
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    $key = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($parts -join "`n")))) -replace '-', ''
    $gitDir = (Invoke-Git $root @('rev-parse', '--absolute-git-dir')).Trim()
    $keyFile = Join-Path $gitDir 'agent-verify.key'
    if ((Test-Path -LiteralPath $keyFile) -and ((Get-Content -Raw -LiteralPath $keyFile).Trim() -eq $key)) { exit 0 }

    $checks = @()
    $checks += , @{ Dir = $root; Exe = 'go'; Args = @('build', './...'); Name = 'go build ./...' }
    $checks += , @{ Dir = $root; Exe = 'go'; Args = @('vet', './...'); Name = 'go vet ./...' }
    $checks += , @{ Dir = $root; Exe = 'go'; Args = @('test', '-count=1', '.'); Name = 'go test .' }

    foreach ($c in $checks) {
        $r = Invoke-Checked $c.Dir $c.Exe $c.Args
        if ($r.Missing) {
            [Console]::Error.WriteLine("verify-before-stop: $($c.Exe) is not on PATH; $($c.Name) was not run")
            continue
        }
        if ($r.TimedOut) {
            [Console]::Error.WriteLine("verify-before-stop: $($c.Name) took over two minutes and was let through")
            continue
        }
        if ($r.Code -ne 0) {
            $tail = (($r.Output -split "`r?`n") | Where-Object { $_ -ne '' } | Select-Object -Last 30) -join "`n"
            Write-Block ("$($c.Name) failed. Fix it before finishing; if the failure was there before your change, say so plainly and finish.`n`n$tail")
        }
    }

    Set-Content -LiteralPath $keyFile -Value $key -Encoding ASCII
    exit 0
} catch {
    # A broken hook must not trap the agent.
    [Console]::Error.WriteLine("verify-before-stop: $($_.Exception.Message)")
    exit 0
}
