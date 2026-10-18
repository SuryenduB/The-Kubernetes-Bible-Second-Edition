# Measurement discipline

Read this before writing any reclaim report. Every arithmetic error in the
2026-10-18 report came from one of the four traps below, not from the cleanup.

## 1. One unit per claim, stated

| Source | Native unit | Convert by |
| :-- | :-- | :-- |
| `df -m`, `du -sm` | MiB | — |
| `df -P -k`, `du -sk` | KiB | ÷ 1024 → MiB |
| `df -h` | human, **rounded per node** | do not use for arithmetic |
| Docker (`docker system df`, prune output) | decimal **GB/MB** | 1 GB = 1000 MB |
| containerd manifest sizes | bytes | ÷ 1024² → MiB |

1 MiB = 1 048 576 B. 1 GiB = 1024 MiB. Docker's GB is 10⁹ B, so
**6.575 GB = 6.13 GiB** — a 7% difference that is enough to make two correct
figures look contradictory.

Label every number `MiB`, `GiB`, or `GB (decimal)`. "725 GB" for a figure that
is really 725 GiB understates it by 7% and is the single most common way a
reclaim report loses credibility.

## 2. Never sum `df -h`

GNU `df -h` rounds **each node up** to the next integer. On 10 nodes that adds
up to several GiB of phantom space: a real 982.0 GiB total displayed as 988.

Sum the precise column (`df -m` or `df -k ÷ 1024`), and if you quote display
values, say "as displayed, per node" and never total them.

## 3. Only the filesystem delta is additive

| Figure | Additive? | Why |
| :-- | :-- | :-- |
| Σ(`df` used before − after) | **yes** | partitions are disjoint |
| containerd store reduction | no | it *is* part of the `df` delta |
| `/var/lib/longhorn` reduction | no | same |
| Docker store reduction | no | same |
| journal reduction | no | same |
| Docker's own prune report | no | overlaps `du` of `/var/lib/docker` |

Present the directory-level numbers **beside** the headline, labelled
"corroborating, not additive". Adding them produces a total larger than the
disk, which is how the earlier draft ended up with 589.7 "GB" of images on a
node that had 320 GiB used.

## 4. Comparisons need one method and one moment

Three things quietly change the answer:

- **Method** — `df -m` vs `df -P -k` agree; `df -h` does not. Pick one and use
  it for both ends.
- **Moment** — containerd's GC reclaims *after* `crictl rmi` returns. A `du`
  taken seconds later understates the prune. Wait, then re-measure (**settle**).
- **Window** — a `df` delta spanning a Docker prune *and* a journal vacuum
  attributes both to Docker. Measure the directory you claim to have changed.

If two snapshots disagree, both can be correct. State both, name the cause, and
report the settled pair as the headline.

## Reconciliation pattern

When a figure is challenged, do not recompute it silently. Publish:

| # | Claimed | Resolved | Cause |
| :-- | :-- | :-- | :-- |
| 1 | 988 GiB before | 982.0 GiB | summed rounded `df -h` values |
| 2 | 589.7 GB containerd | 575.8 GiB (589 586 MiB) | MiB total carrying a GB label |

Rules for this table:

- Keep the originally recorded value visible; explain it, do not overwrite it.
- Name the cause in one phrase (`unit mislabel`, `display rounding`,
  `different snapshot`, `overlapping windows`).
- Where a number genuinely cannot be recovered, write "approximate" and say
  which input is missing. Never fill the gap with a plausible estimate.

## Report checklist

- [ ] Headline is the filesystem delta, in MiB **and** GiB **and** decimal GB.
- [ ] Every table's rows sum to its stated total (check with `awk`, not mentally).
- [ ] Directory-level figures are in a separate section marked non-additive.
- [ ] Before/after name the command and the timestamp.
- [ ] Retained items and pre-existing exceptions are listed.
- [ ] Conclusion is scoped: what was verified, when, and what remains broken.
