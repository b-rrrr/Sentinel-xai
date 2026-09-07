# Sentinel Lab — Specification Repository

This folder is the **specification**, not the project. It is designed to be handed to a coding agent/harness — including weaker or free-tier LLMs (Nemotron, OpenRouter free models, etc.) — one small file at a time.

## Why it's split up this way

A single giant spec document causes two failure modes in agent-driven builds:

1. **Context overload** — the agent has to hold irrelevant sections in its head while implementing one module, crowding out the details that actually matter for the task at hand.
2. **Hallucination** — when a spec is vague or the agent has forgotten an earlier-defined detail (a schema field, a naming convention), it invents a plausible-sounding replacement instead of asking. Weaker models do this more, not less.

The fix: **one immutable architecture document that defines every contract exactly once**, plus **one small, self-contained spec per module** that never redefines a contract — only references it.

## Files

| File | Purpose | When to open it |
|---|---|---|
| `00-ARCHITECTURE.md` | The single source of truth: invariants, data flow, every schema, the full module list, repo layout. | Once, at the start of every session, before anything else. Never edit without a human decision. |
| `AGENT_INSTRUCTIONS.md` | Operating rules for whichever agent/model is doing the work. | Once, at the start of every session, alongside the architecture doc. |
| `BUILD_ORDER.md` | The phase sequence and gate conditions. Tells you which spec file to open next. | Before starting each phase. |
| `specs/01`…`specs/11` | One self-contained module spec each. | Only the ONE file for the phase you are currently building. Do not open others. |
| `inventory/nodes.yaml` | Real hardware inventory — fill this in before Phase 0. | Once, before infrastructure work starts. |
| `docs/decisions/` | Architecture Decision Records — append-only log of any deviation from spec. | Whenever a spec is ambiguous or wrong and you had to make a call. |

## The one rule that matters most

> **If a spec file asks you to use a schema, ID, endpoint name, or field that isn't defined in `00-ARCHITECTURE.md`, stop. Do not invent one. Write an ADR in `docs/decisions/` describing the gap and proposing an answer, and flag it for human review before proceeding.**

This rule exists specifically because this project may be built with free/lower-capability models that are more likely to fill gaps with confident-sounding fabrications. A stop-and-flag is always cheaper than a hallucinated schema propagating through six modules.

## Per-session checklist for the agent

1. Open `00-ARCHITECTURE.md` and `AGENT_INSTRUCTIONS.md`.
2. Open `BUILD_ORDER.md`, find the current phase, confirm its gate condition from the previous phase is met.
3. Open **only** the one `specs/NN-*.md` file for the current phase.
4. Build. Touch only the file paths that spec's "Allowed paths" section names.
5. Run the acceptance tests listed in that spec file. Do not mark the phase done until they pass.
6. Log any deviation as an ADR. Do not silently redefine a contract.
