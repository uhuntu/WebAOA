# MyApp

This project was generated with [Angular CLI](https://github.com/angular/angular-cli) version 17.3.2.

## Build and test

```bash
npm start      # ng serve -> http://localhost:4200/
npm run build  # ng build
npm test       # ng test (Karma)
```

## USB permissions (Linux)

Chrome needs permission to open the phone, otherwise connecting fails with
`USBDevice.open(): Access denied`. Install the udev rule once:

```bash
./udev/install.sh
```

Edit `udev/52-webaoa.rules` to add your phone's vendor ID (`lsusd`) if it isn't MediaTek (0e8d).

## Branches

`webaao/` is an upstream snapshot, not our own codebase. History forks in two lines off `499148b` ("webaao", the 2024-02 upstream snapshot, common ancestor):

```
 ├─ master                        <- force-moved here 2026-10-08 from the explore line
 │   └─ sync-webaoa-from-google3  <- old master: your hand-adapted src/ + internal-copy sync
 └─ explore-pristine-baseline     <- 2026-02 upstream snapshot + CLI adaptation (this experiment)
```

| Branch | What it is |
| --- | --- |
| `master` | **was** `explore-pristine-baseline` (force-moved 2026-10-08). Current upstream snapshot adapted for the standalone CLI build. No `src/`, no `yarn.lock`. |
| `explore-pristine-baseline` | The experiment that produced it. Same lineage. Kept by request. |
| `master-backup-20261008` + tag `backup/master-20261010` | The **old master tip** (`2785d13`, 2024-04-06), before the force move. |
| `sync-webaoa-from-google3` | The old master line: your hand-adapted `src/` Angular CLI skeleton, plus the 2026-08-05 sync from the internal `multitest_transport` copy. |

**Where your own work lives:** only on the old line (`master-backup-20261008`,
`sync-webaoa-from-google3`). That means `src/`,
`angular.enable-strict-mode-prompt: false`, the `box-shadow` / `display: flex`
style fixes, `yarn.lock` and the `matListItemMeta` commit `ee34200`. If you go
looking for any of it, it is on those refs, not on `master`.

`origin/master` is the default branch, so do not force-push again unless you
mean it: no other clone can fast-forward past it.

## The `matListItemMeta` trap (history got this backwards)

`ee34200` (2024-04-06, yours) **added** `matListItemMeta` to two mat-list
templates -- upstream 2024-02 did not position meta content on its own. It is
tempting to read `90f6892`'s "today's markup no longer needs the matListItemMeta
fix" as upstream solving the problem upstream-side. It didn't.

What actually happened: when `explore-pristine-baseline` pulled the 2026-02
snapshot in `44f9b9e`, upstream **removed all of it again** and went back to
plain `class` / `aria-label` markup. Nothing replaced the fix, upstream or
otherwise.

So on `master` / `explore-pristine-baseline` there is **no meta fix at all**.
If mat-list items ever render misaligned there, that is upstream's current
state -- not a regression you introduced, and not something any local patch is
fixing. It is a known gap, not a bug to chase.

## `webaoa/` is a vendored upstream snapshot

The two-commit refresh procedure:

```bash
git -C ~/multitest_transport pull                      # your upstream checkout
UP=~/multitest_transport/multitest_transport/tools/webaao
git rm -rq --ignore-unmatch webaao && cp -r "$UP" webaao
git commit -am "webaoa: refresh from multitest_transport (raw, unmodified snapshot)"
./scripts/reapply-adaptation.sh                       # the de-google3 layer
npm run build && npm test
git commit -am "Re-adapt refreshed webaoa/ for standalone Angular CLI build"
```

`44f9b9e` is the raw-snapshot commit and `90f6892` the adaptation commit;
keeping them separate is what makes the diff against upstream reviewable.

**`scripts/reapply-adaptation.sh` replays one known vintage only** -- the
2026-02-17 snapshot. On a changed upstream it fails *silently*: sed rules that
stop matching are skipped without a word, and only a missing expected file
exits non-zero. Always follow it with `diff -rq "$UP" webaao/`, and expect to
adapt new upstream changes by hand. The judgement calls -- what to keep, what
to drop -- are recorded in `90f6892`'s commit message. That is the authority,
not the script.
