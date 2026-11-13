# guard-command.ps1 - a Claude Code PreToolUse hook for the Bash and PowerShell tools.
#
# It reads the tool call from stdin and answers in one of three ways:
#   deny  a commit or pull request that credits a coding agent; a commit that skips the hooks;
#         a force push; a push that deletes a ref; a push straight to the trunk; moving a tag.
#   ask   (the person must say yes) anything that leaves this machine: any other push, a tag
#         push (a tag is a release), a gh command that writes; and deleting a local tag or
#         rewriting golden files.
#   pass  everything else, with no output.
#
# It must never stop ordinary work: on anything it does not understand (no input, bad JSON, a
# tool that is not a shell) it exits 0 and prints nothing. It is a convenience, not a gate: it
# only sees commands an agent runs through these tools.
#
# Works under Windows PowerShell 5.1 and pwsh 7. Keep this file ASCII.
# Tests: powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/test-hooks.ps1

$ErrorActionPreference = 'Stop'
$trunk = 'master'

function Write-Decision([string]$decision, [string]$reason) {
    $out = [ordered]@{
        hookSpecificOutput = [ordered]@{
            hookEventName            = 'PreToolUse'
            permissionDecision       = $decision
            permissionDecisionReason = $reason
        }
    }
    [Console]::Out.WriteLine(($out | ConvertTo-Json -Compress -Depth 5))
    exit 0
}

try {
    try { [Console]::InputEncoding = [Text.Encoding]::UTF8 } catch { }
    $raw = [Console]::In.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
    $call = $raw | ConvertFrom-Json
    if ($call.tool_name -ne 'Bash' -and $call.tool_name -ne 'PowerShell') { exit 0 }
    $cmd = [string]$call.tool_input.command
    if ([string]::IsNullOrWhiteSpace($cmd)) { exit 0 }
} catch {
    exit 0
}

# The command with its quoted strings and here-documents removed: a flag is a flag only
# outside a message. The attribution test below reads the whole text, messages included.
$bare = $cmd
$bare = [regex]::Replace($bare, "(?s)<<-?\s*['""]?(\w+)['""]?.*?\n\1\b", ' ')
$bare = [regex]::Replace($bare, '(?s)"(?:\\.|[^"\\])*"', ' "" ')
$bare = [regex]::Replace($bare, "(?s)'[^']*'", " '' ")

$sep = '[^|;&\r\n]*'

# 1. No commit and no pull request credits a coding agent.
if ($cmd -match '(?i)\b(git|gh)\b') {
    $agentTrailer = '(?im)co-authored-by:.*(\b(claude|codex|copilot|aider)\b|@anthropic\.com|@openai\.com|@cursor\.(com|sh)|\[bot\])'
    $generated = '(?im)generated with\b.*\b(claude|codex)\b'
    if ($cmd -match $agentTrailer -or $cmd -match $generated) {
        Write-Decision 'deny' 'No agent attribution: commits and pull requests here do not credit a coding agent. Remove the Co-Authored-By trailer or the "Generated with" line and run the command again. A human co-author is fine.'
    }
}

# 2. Hooks are not skipped.
$commit = [regex]::Match($bare, "(?i)\bgit\b$sep\bcommit\b($sep)")
if ($commit.Success) {
    $rest = $commit.Groups[1].Value
    if ($rest -match '(^|\s)--no-verify(\s|$)' -or $rest -cmatch '(^|\s)-[a-zA-Z]*n[a-zA-Z]*(\s|$)') {
        Write-Decision 'deny' 'Do not skip the commit hooks (--no-verify / -n). If a hook fails, fix what it reports.'
    }
}

# 3. A version tag is a release and never moves.
$tag = [regex]::Match($bare, "(?i)\bgit\b$sep\btag\b($sep)")
if ($tag.Success) {
    $rest = $tag.Groups[1].Value
    if ($rest -match '(^|\s)--force(\s|$)' -or $rest -cmatch '(^|\s)-[a-zA-Z]*f[a-zA-Z]*(\s|$)') {
        Write-Decision 'deny' 'A version tag never moves: the Go module proxy and every go.sum that names it hold the old content. Cut the next version instead.'
    }
    if ($rest -match '(^|\s)--delete(\s|$)' -or $rest -cmatch '(^|\s)-[a-zA-Z]*d[a-zA-Z]*(\s|$)') {
        Write-Decision 'ask' 'This deletes a tag. A tag that was ever pushed is a published release and must stay; only a local tag that never left this machine may go.'
    }
}

# 4. Pushing. Never a force push, a deleting push or a push to the trunk; every other push is
#    asked, and a tag push is asked as a release.
$push = [regex]::Match($bare, "(?i)\bgit\b$sep\bpush\b($sep)")
if ($push.Success) {
    $rest = $push.Groups[1].Value
    if ($rest -match '(^|\s)--force(-with-lease|-if-includes)?(=\S+)?(\s|$)' -or $rest -cmatch '(^|\s)-[a-zA-Z]*f[a-zA-Z]*(\s|$)') {
        Write-Decision 'deny' 'No force push: history on a shared branch is not rewritten and a pushed tag never moves. Add a new commit, or cut the next version.'
    }
    if ($rest -match '(^|\s)(--delete|--mirror|--prune)(\s|$)' -or $rest -cmatch '(^|\s)-[a-zA-Z]*d[a-zA-Z]*(\s|$)') {
        Write-Decision 'deny' 'An agent does not delete a branch or a tag on the remote. A pushed tag is a published release; ask the owner.'
    }
    $isTag = $rest -match '(^|\s)(--tags|--follow-tags)(\s|$)'
    foreach ($tok in ($rest -split '\s+')) {
        if ($tok -eq '' -or $tok.StartsWith('-')) { continue }
        if ($tok.StartsWith(':')) {
            Write-Decision 'deny' 'An agent does not delete a branch or a tag on the remote. A pushed tag is a published release; ask the owner.'
        }
        if ($tok.StartsWith('+')) {
            Write-Decision 'deny' 'No force push (a refspec that starts with +).'
        }
        if ($tok -match ('^([^:]*:)?(refs/heads/)?' + [regex]::Escape($trunk) + '$')) {
            Write-Decision 'deny' "Changes reach $trunk by pull request, never by a direct push. Push your own branch and open a pull request into $trunk."
        }
        if ($tok -match 'refs/tags/' -or $tok -match '^([^:]*:)?v\d+(\.\d+)*\S*$') { $isTag = $true }
    }
    if ($isTag) {
        Write-Decision 'ask' "This pushes a tag, and a tag here is a release: once pushed it is published for good. Before saying yes, check the release list in .claude/rules/git-and-prs.md: the tagged commit is on $trunk, it contains the previous release tag, the name is not one upstream has used, and the wire change it carries has its proof. This needs the owner's yes, given now."
    }
    Write-Decision 'ask' "A push leaves this machine, so it needs the owner's yes, given now. Check that the branch is yours and not $trunk."
}

# 5. gh commands that write: pull requests, releases, settings, workflow runs, API writes.
if ($bare -match "(?i)\bgh\b$sep\b(pr|issue|release|repo|workflow|run|secret|variable|ruleset|label|cache)\s+(create|merge|close|reopen|edit|comment|review|ready|delete|upload|rename|archive|unarchive|sync|run|set|enable|disable|rerun|cancel|update-branch|transfer|fork|lock|unlock|pin|unpin)\b") {
    Write-Decision 'ask' "This gh command changes something on GitHub, and this repository is public. An agent does that only with the owner's yes, given now."
}
if ($bare -match "(?i)\bgh\b$sep\bapi\b" -and ($bare -match '(?i)(^|\s)(-X|--method)[\s=]*(POST|PUT|PATCH|DELETE)\b' -or $bare -cmatch '(^|\s)(-f|-F|--field|--raw-field|--input)(\s|=|$)')) {
    Write-Decision 'ask' "This gh api call writes to GitHub. An agent does that only with the owner's yes, given now."
}

# 6. Rewriting golden files needs the person's yes.
if ($bare -match "(?i)\bgo\b$sep\btest\b$sep\s-{1,2}update\b") {
    Write-Decision 'ask' 'This rewrites recorded test data (-update). A changed recording is a changed wire behaviour: say what changed on the wire and why before the files are rewritten.'
}

exit 0
