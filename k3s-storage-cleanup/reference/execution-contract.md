# Execution contract

The contract for any **automated** implementation of this skill — the planned
PowerShell tool, or a future port in another language. The Bash steps in
`SKILL.md` are the manual path and must satisfy the same rules by hand.

**Status: contract only.** No tool is implemented yet. Do not schedule an
automated reclaim until every clause below is covered by a passing test.

## 1. Modes

| Mode | Invocation | Mutates? | Use |
| :-- | :-- | :-- | :-- |
| **Audit** (default) | `Invoke-K3sStorageCleanup` | no | Always the first run; produces the candidate report |
| **Apply** | `-Apply` | yes | Only after a human has read the audit output |
| **WhatIf** | `-WhatIf` | no | Functional dry run; identical code path with mutations suppressed |

Rules:

- Omitting both `-Apply` and `-WhatIf` **is** audit. Silence must never mean
  mutate.
- `-WhatIf` must be a real switch on the cmdlet (`SupportsShouldProcess`), not a
  log-only flag, and it must still execute every eligibility check so the report
  matches what Apply would do.
- `-Confirm:$false` does not imply `-Apply`; it only suppresses the prompt.
- Apply without a preceding audit artifact (same `runId` lineage) is a
  precondition failure.

## 2. Parameters

Implementation-neutral names; PowerShell conventions shown.

| Parameter | Type | Default | Meaning |
| :-- | :-- | :-- | :-- |
| `-Apply` | switch | off | Execute deletions |
| `-Node` | string[] | all inventory nodes | Restrict scope |
| `-Kind` | enum[] | `Image,Orphan,Journal,DockerCache` | What may be reclaimed; `Volume` is never a default |
| `-OrphanMinAgeHours` | int | 24 | Eligibility floor for orphan age |
| `-RollbackRevisions` | int | 1 | Prior ReplicaSet revisions whose images are protected |
| `-Registry` | string | `192.168.0.236:5000` | Recovery-proof target |
| `-VolumeAllowlist` | string | none | Path to an explicit disposable-volume list |
| `-TimeoutPerObject` | timespan | 2 min | Bounded wait per deletion |
| `-TimeoutPerPhase` | timespan | 15 min | Bounded wait per phase |
| `-ReportPath` | string | `./reports` | JSON + CSV destination |

Scope comes from `WindowsLab/homelab-nodes.json`. A node not in the inventory is
an error, not a skip. Expected node count is read from the inventory, never
hardcoded.

## 3. Locking

One lock per node, shared with the DaemonSet:

```
/run/lock/k3s-disk-cleanup.lock
```

- The tool takes it with `flock -n` semantics for the whole run (host-side) and
  holds it across all node operations.
- `monitoring/node-disk-cleanup` takes the same lock before its pass and exits
  0 when it cannot.
- Lock contention exits **4** and mutates nothing. It is not retried
  automatically within the same invocation.

## 4. Candidate records

Every object considered — deleted, retained, or protected — produces one record.
Uniform shape so the report can be diffed and audited:

```json
{
  "schema": "k3s-storage-cleanup/candidate/v1",
  "runId": "20261018T221500Z-7f3a",
  "node": "kubernetes1",
  "kind": "image",
  "id": "sha256:3bbc6cc5...",
  "reference": "192.168.0.236:5000/ai-language-learning:latest",
  "sizeBytes": 83399828,
  "evidence": {
    "referencedByContainer": false,
    "referencedByTemplate": true,
    "templateSources": ["deploy/ai-language-learning/ai-lang-backend"],
    "registryRecoverable": true,
    "requiredPlatform": "linux/amd64"
  },
  "verdict": "protected",
  "reason": "named in a live Deployment template (replicas=1)",
  "checkedAt": "2026-10-18T22:15:03Z"
}
```

Verdicts: `eligible`, `protected`, `retained` (eligible but skipped — give the
reason, e.g. `revalidated: appeared in a container since audit`).

Kind-specific evidence is required:

| Kind | Evidence that must be present |
| :-- | :-- |
| `image` | container refs, template refs, registry recoverability + resolved digest, platform |
| `orphan` | type, `dataCleanable`, `error`, age, (node, disk, directory) tuple, matched references, volume robustness on that node |
| `docker-cache` | Docker's own reported bytes before/after |
| `docker-image` | container refs, registry digest, recoverability |
| `volume` | allowlist entry id + approver; absent either → not a candidate |

## 5. Pre-deletion revalidation

Immediately before each deletion, re-read the live state and re-run the
eligibility predicate for that object only. A candidate whose predicate no
longer holds is recorded as `retained` and skipped — never "deleted anyway".

This closes the audit→apply race: the audit may be minutes or hours old.

## 6. Bounded waits and stop-on-regression

- Every deletion uses `--wait` with `-TimeoutPerObject`; every phase is capped
  by `-TimeoutPerPhase`.
- Timeout means **uncertain**, not success: mark the record `retained` with
  `reason: "timeout"`, stop that phase, continue to the health check.
- Checked exit codes for every external command. A non-zero from `kubectl` or
  `crictl` is a phase failure, not a log line.
- **Stop on regression.** After each phase, probe: node readiness, pod phase
  counts, `state`/`robustness` of every volume touched or on a touched node,
  etcd member health. Any change from the preflight snapshot aborts the
  remaining phases and exits **3**.
- No unbounded retry loops. Retries are bounded and only for transient
  transport errors, never for a timed-out deletion.

## 7. Reports

Two files per run, same `runId`:

- `<runId>.json` — `{schema, runId, mode, startedAt, finishedAt, exitCode,
  inventory: {expectedNodes, seenNodes}, phases: [...], candidates: [...]}`
- `<runId>.csv` — stable header:
  `runId,mode,node,kind,id,reference,sizeBytes,verdict,reason,checkedAt`

Rules:

- Every candidate appears exactly once, including `protected` ones.
- Numbers carry units in the column name (`sizeBytes`, `usedMiB`), never bare.
- Preflight and postflight measurements are included so the arithmetic is
  checkable from the artifact alone.
- No credentials, tokens, kubeconfig contents, or sudo material.

## 8. Tests (Pester)

Each clause above needs a test. Minimum set:

1. Audit is the default; with no switches, zero mutating calls occur.
2. `-WhatIf` performs zero mutations **and** emits the same candidate set as
   `-Apply` on the same fixture.
3. Lock contention exits 4 and mutates nothing.
4. A scaled-to-zero Deployment's image is `protected`.
5. A previous ReplicaSet revision's image is `protected` within
   `-RollbackRevisions`, `eligible` beyond it.
6. An image whose registry content is incomplete is `protected` (fail closed).
7. Each orphan condition independently vetoes eligibility (7 table-driven
   cases).
8. Orphan reference matching uses the (node, disk, directory) tuple: the same
   directory name on a different node does **not** count as a reference.
9. No Docker volume is ever a candidate without an allowlist entry; a missing
   allowlist file aborts.
10. Exit-code mapping 0/2/3/4 is asserted per scenario.
11. Report schema validates; CSV header is stable; output contains no
    secret-shaped strings.
12. Inventory mismatch (node missing, extra node) aborts before any phase.
13. A deletion that never completes hits `-TimeoutPerObject`, is recorded
    `retained/timeout`, and does not hang.
14. A simulated volume-robustness change mid-run exits 3 and stops the
    remaining phases.

## 9. Scheduling

Only after 1–14 pass:

- Run audit on a schedule; run Apply on approval, or gate Apply behind a
  separate manual trigger.
- Keep the DaemonSet's emergency path for the day nothing runs — it prevents
  eviction, and it is not a substitute for this contract.
