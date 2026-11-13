# CLAUDE.md

Guidance for Claude Code in this repository. Keep it short.

## What this is

A fork of `github.com/bogdanfinn/utls`, which is a fork of `refraction-networking/utls`, which
is a fork of Go's `crypto/tls`. It lets the caller decide every byte of the TLS ClientHello, so
a Go client can present a browser's TLS fingerprint. The module path is still
`github.com/bogdanfinn/utls` and must stay so. This repository is **public**.

**The ClientHello is byte-strict.** A change to how the hello is built, ordered, padded,
GREASEd or resumed changes the fingerprint of the application that pins this fork. It must be
proven by a capture, and it is released as a new tag that the application adopts deliberately.
Read `.claude/rules/clienthello.md` before you change a `.go` file.

## Ours and upstream's

- Almost everything here is upstream's. Keep it that way: do not reformat, rename or tidy
  inherited code, so that an upstream merge stays possible. Files named `u_*.go` are uTLS's
  additions to `crypto/tls`; the rest tracks the standard library.
- **Ours** is one commit by this organisation, in `handshake_client_tls13.go` and
  `u_handshake_client.go`: the TLS 1.3 transcript hashes the Certificate, CertificateRequest
  and CompressedCertificate messages as received instead of re-marshalled. Its message states
  it does not change the ClientHello.

## Where the releases are (checked 2026-11-12; check again before you rely on it)

- `master` is upstream's `v1.7.8-barnius` and nothing more.
- `v1.7.9-barnius`, the tag the application pins, is the tip of the branch
  `fix/cert-transcript-raw-bytes`, one commit ahead of `master`. **It was never merged:
  `master` does not contain the release.**
- Upstream has moved on to `v1.8.x-barnius` and has no `v1.7.9-barnius` of its own.

So: a tag cut from `master` today would silently lose the transcript fix. Check with
`git merge-base --is-ancestor v1.7.9-barnius master` (exit 1 means still not merged), and
follow the release list in `.claude/rules/git-and-prs.md`.

## How a release reaches the application

The application that uses this fork pins it at a release tag, in a `replace` line of its
`go.mod`.

A release here changes nothing there. Adoption is a pull request in that repository that
changes the version on that line; it counts as a change to request bytes and owes a live A/B
test. The organisation's `fhttp` fork imports this package too, so an exported name it uses
must keep compiling.

## Commands

```bash
go build ./...          # passes
go vet ./...            # passes
go test ./...           # passes; the root package takes about five seconds
go test -run TestUTLS . # the uTLS tests only

git config core.hooksPath .githooks     # once per clone: turn on the commit-msg hook
powershell -NoProfile -ExecutionPolicy Bypass -File .claude/hooks/test-hooks.ps1   # the hooks' own tests
```

Passing tests do not prove an unchanged fingerprint: the profiles the application uses are
built by the caller and are not in these tests. Never run a test with `-update` to make it
pass (`.claude/rules/recorded-handshakes.md`).

## How work lands

Branch from `master`, in a git worktree; pull request into `master`; merged on green checks.
No `beta` branch. Never push to `master`, never force-push, never move a tag. No commit or pull
request credits a coding agent. Every push, pull request, merge and tag needs the owner's yes
at the time.

## Rules by area (`.claude/rules/`)

| File | Covers | The rule in one line |
|---|---|---|
| `git-and-prs.md` | every session | Pull request into `master`; how upstream is merged; the release list. |
| `choosing-a-solution.md` | every session | Pick the best solution; in a fork that is usually the smallest diff. |
| `clienthello.md` | every `.go` file, `go.mod` | A fingerprint change is proven by a capture, one per pull request and per tag. |
| `recorded-handshakes.md` | `testdata/`, test files | A recording that stops matching is a finding; never `-update` to get green. |
