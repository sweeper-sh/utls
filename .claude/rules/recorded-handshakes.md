---
paths:
  - "testdata/**"
  - "**/*_test.go"
---
# Tests and the recorded handshakes

`testdata/` holds 181 recorded TLS connections (`Client-*`, `Server-*`, `ClientHello-*`). They
came from `crypto/tls`: each is a real exchange with a reference implementation (OpenSSL),
recorded once. A test replays its side with fixed randomness and checks that it produces the
same bytes, with no network (`handshake_test.go` explains the scheme at its top).

So **a recording that stops matching means the bytes this code sends have changed.** That is
the finding, not an obstacle.

## What runs today (measured on `master`, Go 1.26.1, Windows, 2026-11-12)

- `go build ./...`, `go vet ./...` and `go test ./...` pass; the root package's tests take
  about five seconds. Every other package has no tests.
- The race detector was not run. Linux and macOS were not measured.
- On a Windows checkout that turns files into CRLF, `gofmt -l .` lists every file; that is
  the checkout, not the code.

## The rules

1. **Never run a test with `-update` to make it pass.** `-update` rewrites the recordings of
   the failing tests. If a test fails after your change, find out which bytes changed and
   why (`clienthello.md`).
2. **Rewriting a recording is its own commit, with the owner's yes.** It needs OpenSSL 1.1.1
   built from source (`checkOpenSSLVersion` in `handshake_test.go` says how), and because the
   reference side draws fresh random numbers, most of the file changes each time. The commit
   message says which behaviour changed and that the change was intended.
3. **Do not edit a file in `testdata/` by hand.**
4. **A test you add runs offline and is deterministic**: no outside host, no clock, no real
   randomness. For a ClientHello, build the hello and compare bytes or parsed fields, as
   `u_fingerprinter_test.go` and `u_grease_sigalg_test.go` do.
5. **Do not delete, skip or loosen a test to get green.** If a test is wrong, fix the test as
   its own change and say why it was wrong.
6. **Passing tests do not prove an unchanged fingerprint.** The profiles the application uses
   are not in these tests. Say "the tests pass" and, separately, what you did to check the
   hello.

## What enforces this today

- `.claude/hooks/guard-command.ps1` (agents only) asks the person before `go test ... -update`.
- `.claude/hooks/verify-before-stop.ps1` (agents only) runs build, vet and the root package's
  tests when a Go file changed.
- `.github/workflows/go.yml` came with upstream: gofmt, vet, `go mod tidy`, build and test on
  Linux, Windows and macOS, and a race run, on pushes and pull requests to `master`. **No run
  of it was listed for this repository when this was written (2026-11-12), and the `master`
  ruleset requires no status check**, so today nothing stops a pull request with failing
  tests from merging. Whether the workflow runs as written here was not verified.
- Nothing checks rules 2, 3 and 6.
