# Git, pull requests and releases

Loaded in every session.

## The rules

- **Branch from `master`, open the pull request into `master`.** There is no `beta` branch. A
  pull request merges when its checks are green; nobody has to approve it.
- **Ask before anything that leaves this machine**: a push, a pull request, a merge, a tag
  push, a repository setting. Every one needs the owner's yes at the time. The command guard
  stops and asks. The repository is public: what is pushed is published.
- **No commit and no pull request credits a coding agent.** No `Co-Authored-By:` naming Claude,
  Codex, Copilot or any other agent; no "Generated with" line. A human co-author is fine.
- **Never skip a hook** (`--no-verify`, `git commit -n`), **never force-push**, **never push to
  `master`**, never delete a remote branch or tag.
- **One fingerprint change per commit and per pull request** (`clienthello.md`).
- **Work in a git worktree**, not in the main checkout; do not touch a branch you did not
  create.

## Merging upstream

Upstream is `github.com/bogdanfinn/utls` (itself a fork of `refraction-networking/utls`). No
remote for it is configured in a fresh clone:
`git remote add upstream https://github.com/bogdanfinn/utls.git`.

- Upstream comes in by a pull request that **merges** an upstream tag into a branch of ours.
  Never rebase our commits onto upstream and never fast-forward `master` by a push.
- An upstream merge is a fingerprint change, usually several at once. List every change it
  brings to the items in `clienthello.md`, and prove the result with captures.
- No upstream merge has been made in this organisation yet; there is no worked example.

## Cutting a release

A release is a version tag. The application pins the tag in its `go.mod`, and the Go module
proxy and every `go.sum` keep a tag's content for good.

- [ ] The commit is on `master`, reached by a merged pull request.
- [ ] It contains the previous release:
      `git merge-base --is-ancestor <previous tag> <commit>` exits 0. A tag cut from a commit
      that lacks the previous release silently drops that release's fix.
- [ ] The name is the next free version **here and upstream**, in upstream's form
      `vX.Y.Z-barnius`: check `git ls-remote --tags https://github.com/bogdanfinn/utls`.
      Never reuse a version upstream has used, and never move or delete a pushed tag.
- [ ] The change it carries has its capture proof (`clienthello.md`), and the tag carries
      exactly one fingerprint change since the previous tag.
- [ ] The owner pushes the tag, or says yes to the push at the time.
- [ ] Adoption is a separate pull request in the application's repository, which changes the
      version on the `replace` line of its `go.mod`. There it counts as a change to request bytes and owes a live A/B test
      before that repository's release. Nothing is adopted automatically.

## What enforces this today

- GitHub ruleset `trunk` on `master` (read on 2026-11-12): a pull request is required, force
  pushes and deletion are blocked. It requires **no status check**, and **nothing protects
  tags**: a tag can be pushed from any commit, moved or deleted by anyone with write access.
- `.github/workflows/go.yml` came with upstream; no run of it was listed for this repository
  when this was written (`recorded-handshakes.md`).
- `.claude/hooks/guard-command.ps1` (agents only): refuses agent attribution, `--no-verify`, a
  force push, a deleting push, a push to `master` and `git tag -f`; asks the person before any
  other push, a tag push, a tag deletion and a `gh` command that writes.
- `.githooks/commit-msg` refuses agent attribution, **only in a clone where
  `git config core.hooksPath .githooks` was run**.
- `.claude/settings.json` sets `attribution` to empty, so Claude Code adds no trailer.
- **The release list is not checked by anything.** The one release of ours that exists was
  cut outside it (see "Where the releases are" in `CLAUDE.md`).
