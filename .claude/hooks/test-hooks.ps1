# test-hooks.ps1 - runs the two hook scripts beside it against sample tool calls and says
# which answers were wrong. Exits 1 when any was.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/test-hooks.ps1
#
# The stop-hook cases build a throwaway git repository in the temp folder; the ones that
# run go are skipped when go is not on PATH. Keep this file ASCII.

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$guard = Join-Path $here 'guard-command.ps1'
$stop = Join-Path $here 'verify-before-stop.ps1'
$shell = (Get-Process -Id $PID).Path
$script:failed = 0
$script:ran = 0

function Invoke-Hook([string]$script, [string]$stdin) {
    $ErrorActionPreference = 'Continue'
    $out = $stdin | & $shell -NoProfile -ExecutionPolicy Bypass -File $script 2>$null
    if ($null -eq $out) { return '' }
    return (($out | ForEach-Object { [string]$_ }) -join "`n")
}

function Test-Guard([string]$want, [string]$tool, [string]$command) {
    $script:ran++
    $json = @{ tool_name = $tool; tool_input = @{ command = $command } } | ConvertTo-Json -Compress
    $out = Invoke-Hook $guard $json
    $got = 'pass'
    if ($out -ne '') { $got = [string]($out | ConvertFrom-Json).hookSpecificOutput.permissionDecision }
    if ($got -ne $want) {
        $script:failed++
        Write-Output "FAIL guard: want $want, got $got : [$tool] $command"
    }
}

function Test-Stop([string]$name, [string]$stdin, [string]$wantPattern) {
    $script:ran++
    $out = Invoke-Hook $stop $stdin
    $ok = if ($wantPattern -eq '') { $out -eq '' } else { $out -match $wantPattern }
    if (-not $ok) {
        $script:failed++
        Write-Output "FAIL stop: $name : want /$wantPattern/, got: $out"
    }
}

# --- guard-command.ps1 ----------------------------------------------------------------------

$b = 'Bash'
Test-Guard 'pass' $b 'git status'
Test-Guard 'pass' $b 'git commit -m "http2: keep the settings order"'
Test-Guard 'pass' $b 'go build ./...'
Test-Guard 'pass' $b 'go test -run TestHeaderOrder ./http2/'
Test-Guard 'pass' $b 'git log --oneline master..HEAD'
Test-Guard 'pass' $b 'git tag --sort=-creatordate'
Test-Guard 'pass' $b 'git tag -l "v0.6.*"'
Test-Guard 'pass' $b 'git tag v9.9.9'
Test-Guard 'pass' $b 'git merge-base --is-ancestor v0.6.10 HEAD'
Test-Guard 'pass' $b 'git ls-remote --tags origin'
Test-Guard 'pass' $b 'gh pr view 3 --json state'
Test-Guard 'pass' 'PowerShell' 'git commit -m "x`n`nCo-Authored-By: Ada <ada@example.org>"'

Test-Guard 'deny' $b "git commit -m `"x`n`nCo-Authored-By: Claude <noreply@anthropic.com>`""
Test-Guard 'deny' $b 'gh pr create --title x --body "Generated with Claude Code"'
Test-Guard 'deny' $b 'git commit --no-verify -m "x"'
Test-Guard 'deny' $b 'git commit -n -m "x"'
Test-Guard 'deny' $b 'git push --force origin fix/x'
Test-Guard 'deny' $b 'git push -f origin fix/x'
Test-Guard 'deny' $b 'git push origin +fix/x'
Test-Guard 'deny' $b 'git push origin master'
Test-Guard 'deny' $b 'git push origin HEAD:master'
Test-Guard 'deny' $b 'git -C ../x push origin fix/x:refs/heads/master'
Test-Guard 'deny' $b 'git push origin --delete v9.9.9'
Test-Guard 'deny' $b 'git push origin :refs/tags/v9.9.9'
Test-Guard 'deny' $b 'git tag -f v9.9.9'
Test-Guard 'deny' $b 'git tag --force v9.9.9 HEAD'

Test-Guard 'ask' $b 'git push -u origin docs/agent-rules'
Test-Guard 'ask' $b 'git push'
Test-Guard 'ask' $b 'git push origin v9.9.9'
Test-Guard 'ask' $b 'git push origin refs/tags/v9.9.9-x'
Test-Guard 'ask' $b 'git push --tags'
Test-Guard 'ask' $b 'git push --follow-tags origin fix/x'
Test-Guard 'ask' $b 'git tag -d v9.9.9'
Test-Guard 'ask' $b 'gh pr create --title "http2: x" --body "y"'
Test-Guard 'ask' $b 'gh pr merge 3 --merge'
Test-Guard 'ask' $b 'gh release create v9.9.9'
Test-Guard 'ask' $b 'gh api -X DELETE repos/o/r/git/refs/tags/v9.9.9'
Test-Guard 'ask' $b 'go test -run TestHandshake . -update'

$script:ran++
$readOut = Invoke-Hook $guard (@{ tool_name = 'Read'; tool_input = @{ } } | ConvertTo-Json -Compress)
if ($readOut -ne '' -or (Invoke-Hook $guard '') -ne '' -or (Invoke-Hook $guard 'not json') -ne '') {
    $script:failed++; Write-Output 'FAIL guard: another tool, empty input or bad input must pass silently'
}

# --- verify-before-stop.ps1 -----------------------------------------------------------------

function New-StopInput([string]$cwd, [bool]$active) {
    return (@{ cwd = $cwd; stop_hook_active = $active } | ConvertTo-Json -Compress)
}

Test-Stop 'empty input' '' ''
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('hooktest-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $tmp
try {
    Test-Stop 'not a repository' (New-StopInput $tmp $false) ''

    Set-Content -LiteralPath (Join-Path $tmp 'go.mod') -Value "module hooktest`n`ngo 1.22" -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $tmp 'a.go') -Value "package hooktest`n`nfunc A() int { return 1 }" -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $tmp 'README.md') -Value 'x' -Encoding ASCII
    $ErrorActionPreference = 'Continue'
    & git -C $tmp init -q 2>$null
    & git -C $tmp add -A 2>$null
    & git -C $tmp -c user.name=t -c user.email=t@example.org -c core.hooksPath= commit -q -m init 2>$null
    $ErrorActionPreference = 'Stop'

    Test-Stop 'clean tree' (New-StopInput $tmp $false) ''
    Set-Content -LiteralPath (Join-Path $tmp 'README.md') -Value 'y' -Encoding ASCII
    Test-Stop 'only an unwatched file changed' (New-StopInput $tmp $false) ''

    if (Get-Command -Name go -CommandType Application -ErrorAction SilentlyContinue) {
        Set-Content -LiteralPath (Join-Path $tmp 'a.go') -Value "package hooktest`n`nfunc A() int { return 2 }" -Encoding ASCII
        Test-Stop 'a Go file changed and builds' (New-StopInput $tmp $false) ''
        Set-Content -LiteralPath (Join-Path $tmp 'a.go') -Value "package hooktest`n`nfunc A() int { return }" -Encoding ASCII
        Test-Stop 'stop_hook_active' (New-StopInput $tmp $true) ''
        Test-Stop 'the build fails' (New-StopInput $tmp $false) '"decision":"block".*go build'
    } else {
        Write-Output 'skipped: the stop-hook cases that run go (go is not on PATH)'
    }
} finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "$($script:ran) cases, $($script:failed) failed"
if ($script:failed -gt 0) { exit 1 }
exit 0
