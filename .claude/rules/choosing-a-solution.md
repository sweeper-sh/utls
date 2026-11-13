# Choosing a solution

Loaded in every session.

An agent's sense of how long work takes comes from how long it takes people. That estimate is
wrong for an agent by one or two orders of magnitude: what reads as weeks of engineering is
hours of your work. Left uncorrected, it makes you pick the smaller, weaker design to "save
time" that was never going to be spent.

## The rules

1. **Choose the best solution: the most correct, the most robust, the one that will still be
   right in a year.** Do not rank an option lower because it needs more code, more tests, more
   files or a larger refactor. Implementation effort is not a cost here.
2. **Do the whole job.** Do not ship a partial version, a stub, a special case or a workaround
   because the full version is big. If the right fix is to restructure, restructure.
3. **Do not defer because of size.** "Later", "a follow-up" and "backlog" are for work that is
   blocked on something real, and you name what: the owner's decision, a capture you do not
   have, a live test in the application, a tag only the owner pushes.
4. **Do not estimate in human time.** No "this would take a week". If you mention effort at
   all, name what actually costs:
   - the owner's attention: questions asked, things to review, decisions pushed back to them;
   - risk to the wire: a changed byte is a changed fingerprint in everything that pins this;
   - anything irreversible or outside this machine;
   - CI minutes, and many agents run in parallel.
5. **Quality is the bar for every part**, tests included: a test that would catch the bug, an
   error message that says what to do, names that are true. Not the minimum that passes.
6. **When you do recommend the smaller option, give the real reason.** "It is simpler and just
   as correct" is a reason. "It is quicker to build" is not.

## What this does not change

- Scope the owner has set stays set. This is a fork kept close to upstream: "do not clean up
  the inherited code" is a decision, not a shortcut for you to undo. The best solution to a
  wire bug is usually the smallest diff that fixes it, because every other changed line is a
  line to prove and a conflict with the next upstream merge.
- Simple is still better than clever when both are equally correct. This rule is against
  choosing *worse*, not against choosing *less*.
- You still ask before a push, a merge, a tag or a setting change.

## What enforces this today

Nothing. It is a rule of judgement; the owner sees it in what you propose.
