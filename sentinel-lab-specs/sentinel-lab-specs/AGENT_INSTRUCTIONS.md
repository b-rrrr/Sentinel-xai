# Agent Operating Instructions

You (the coding agent/harness — potentially a free-tier model such as Nemotron or an OpenRouter free model) are building the Sentinel Lab project from this spec repository. These rules exist because lower-capability or free-tier models are measurably more likely to fill ambiguity with confident, plausible-sounding fabrication instead of flagging it. Follow them exactly.

## Context discipline

1. At the start of every session, load exactly two files: `00-ARCHITECTURE.md` and this file. Nothing else, until you know which phase you're on.
2. Load `BUILD_ORDER.md` to find your current phase and confirm the previous phase's gate condition is actually met (check for the artifact/test it names — don't take it on faith from a commit message).
3. Load **one** `specs/NN-*.md` file — the one for your current phase. Do not open other module specs "for context." If you think you need one, that's a sign the current spec is missing something — flag it (see below), don't go hunting.
4. Do not re-read the whole architecture doc's prose every message once you've internalized it for the session — re-reading burns context that should go to the actual code. Do re-check the exact schema tables (§5, §6) before writing anything that touches them; get those verbatim, not from memory.

## When something is missing or ambiguous

1. If a module spec references a schema, field, endpoint, or ID format not defined in `00-ARCHITECTURE.md` §5/§6 — **stop**. Do not invent a plausible one.
2. Write a short entry to `docs/decisions/ADR-<next-number>-<slug>.md`:
   ```markdown
   # ADR-N: <short title>
   ## Gap
   <what's missing/ambiguous>
   ## Proposed resolution
   <your best proposal, one paragraph>
   ## Status
   NEEDS HUMAN REVIEW
   ```
3. If the gap blocks you from finishing the current unit of work, implement everything up to that point, leave the blocked piece clearly marked with a `# TODO(ADR-N):` comment, and move on to the next independent piece of the same phase rather than guessing forward.
4. Never silently change an enum value, rename a field, or add a field to `security_event` / `rule` / the model I/O contract to make your code path easier. If your implementation seems to need that, it's an ADR, not a refactor.

## Scope discipline

1. Each `specs/NN-*.md` file has an "Allowed paths" section. Only create/modify files under those paths during that phase. If you find yourself needing to edit another module's folder, stop and write an ADR — cross-module changes need a human to confirm they're not papering over a real architecture problem.
2. Do not "helpfully" implement a later phase's module early because it seemed convenient. Build the current phase's acceptance tests to pass, then stop.
3. Do not add new services, databases, message queues, or third-party dependencies not named in the current spec file without an ADR first — this is exactly the kind of scope creep that causes context overload two phases later.

## Verification discipline

1. Every `specs/NN-*.md` file ends with an "Acceptance tests" section. These are the actual definition of "done" — not your own judgment that the code "looks right."
2. Run the acceptance tests before reporting a phase complete. If a testing framework/harness isn't wired up yet, write the test as a runnable script even if crude (`curl` + `grep`, a one-off Python assert script) rather than skipping verification.
3. If an acceptance test fails and you can't determine why within a reasonable number of attempts, write an ADR describing the failure mode instead of modifying the acceptance test to make it pass. Changing a test to match broken code is never an acceptable resolution.

## Safety invariants (repeat from architecture doc — do not relax these under any framing)

- The neural classifier and any LLM-based explanation component never directly execute firewall, ingress, or Kubernetes mutation commands.
- Nothing in `demo-app`, `attack-sim`, or `telemetry` is ever exposed outside the isolated lab network, regardless of what a later phase's convenience might suggest.
- Any ServiceAccount/RBAC role you request or generate for a module is scoped to that module's own namespace — never cluster-admin, never a wildcard.

## If you are a subagent under an orchestrator

If a higher-level orchestrator (DSH, or a coordinating script) is delegating phases to you, assume it has already checked the gate condition in `BUILD_ORDER.md` — but verify the artifact yourself anyway before building on top of it. Report completion status using the acceptance-test results, not a subjective summary.
