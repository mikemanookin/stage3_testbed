# Stage — Spec Directory

This directory implements spec-driven development (SDD) for the Stage visual stimulus presenter. Stage is a MATLAB OpenGL-based display server that receives presentation commands from Symphony DAQ software over TCP/IP and renders visual stimuli on a dedicated monitor.

## Navigation

| File | Purpose |
|------|---------|
| [SPECS.md](SPECS.md) | Manifest of all normative specifications |
| [PLAN.md](PLAN.md) | Architecture direction + roadmap |
| [TASKS.md](TASKS.md) | Active work queue with acceptance criteria |
| [specs/](specs/) | Individual specification documents |
| [decisions/](decisions/) | Architecture Decision Records (ADRs) |

## Document Roles

| Document | Answers | Lifetime |
|----------|---------|----------|
| **Specs** | *What is true?* — wire protocol, player lifecycle, invariants | Long |
| **Plan** | *What's the strategy?* — roadmap, architecture choices | Medium |
| **Tasks** | *What's next?* — actionable items with acceptance criteria | Short |
| **ADRs** | *Why did we decide this?* — one decision per file | Permanent |

## Workflow

For any non-trivial change:

1. **Read** the relevant spec(s) in `specs/`.
2. If the change modifies a documented invariant, **update the spec first**.
3. If it's a new architectural direction, **propose an ADR** in `decisions/`.
4. **Add or update a task in `TASKS.md`** with explicit acceptance criteria.
5. **Implement** against the spec.
6. **If reality diverges, update the spec** before committing.

This layout mirrors the Symphony 3 SDD structure (see `C:\Users\dev\Documents\Symphony3\symphony3_testbed\spec\`) so contributors working across both projects see a consistent pattern.
