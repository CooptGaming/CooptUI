# CoopUI — Model Selection Guide

Which Claude model to use for each type of task during the CoopUI refactor. The goal is to get the best results while keeping usage efficient.

---

## Quick Reference

| Task Type | Recommended Model | Why |
|-----------|------------------|-----|
| **Architecture decisions** | Opus | Needs deep reasoning about tradeoffs, system design |
| **Code review / audit** | Opus | Pattern recognition across large files, subtle bugs |
| **Writing new README / docs** | Opus or Sonnet | Opus for high-stakes user-facing docs; Sonnet for internal |
| **Find/replace rebranding** | Sonnet | Mechanical; clear instructions, low ambiguity |
| **Rewriting file headers** | Sonnet | Template-following, repetitive across files |
| **Lua code optimization** | Opus | Performance tuning requires understanding MQ2 + Lua nuance |
| **Simple bug fixes** | Sonnet | Straightforward, well-scoped changes |
| **Writing new Lua modules** | Opus | Architecture + correctness matter; needs full context |
| **INI/config file edits** | Sonnet | Mechanical, low risk |
| **PowerShell script fixes** | Sonnet | Small scope, clear requirements |
| **Generating test checklists** | Sonnet | Structured output, doesn't need deep reasoning |
| **Answering "how does X work"** | Opus | Requires tracing through multi-file codebase |
| **Planning next phase** | Opus | Strategic thinking, prioritization |

---

## Decision Framework

### Use Opus When:

- **Multiple files interact** — The task requires understanding how 3+ files relate to each other (e.g., how `init.lua` → `context.lua` → `views/*.lua` pass state)
- **Architecture decisions** — You're deciding *what* to build, not just *how* to write it (e.g., Option A vs B for the CoopUI loader shell)
- **Subtle correctness matters** — MQ2/Lua edge cases like the 200-upvalue limit, TLO query timing, zone transition safety
- **Large code review** — Reviewing `init.lua` (5000+ lines) for optimization opportunities, dead code, or structural issues
- **User-facing writing** — README, DEPLOY.md, or anything players/testers will read — tone and clarity matter
- **Debugging weird behavior** — When something works sometimes but not others, or the fix isn't obvious
- **Tradeoff analysis** — Performance vs. readability, backward compatibility vs. clean design

### Use Sonnet When:

- **Clear, mechanical tasks** — Find/replace across files, adding headers, renaming variables
- **Well-defined scope** — "Add CoopUI branding to the header of these 6 files"
- **Template-following** — Generating file headers, config entries, or structured output to a spec you've already defined
- **Internal dev docs** — Phase summaries, implementation notes, changelogs
- **Small edits** — Fixing a typo, adjusting a threshold, adding a nil check
- **Repetitive transforms** — Applying the same pattern across multiple similar files
- **Quick questions** — "What's the MQ2 command for X?" or "What does this Lua pattern do?"

### Use Haiku When:

- **Trivial lookups** — "What line is `VERSION` on in init.lua?"
- **Simple formatting** — Reformatting a table, fixing markdown
- **Yes/no questions** — "Does this file contain CoopUI?"
- **Not currently available on claude.ai** — but good to know for API usage

---

## Phase-by-Phase Recommendations

### Phase 1: Rebranding

| Task | Model | Notes |
|------|-------|-------|
| Write new README.md | **Opus** | User-facing, sets the tone for the whole project |
| Rewrite RELEASE_AND_DEPLOYMENT.md sections | **Sonnet** | Mostly find/replace with some reframing |
| Rewrite GITHUB_HTTPS_SETUP.md | **Sonnet** | Straightforward substitutions |
| Update .cursor/agents/*.md | **Sonnet** | Clear scope, known replacements |
| Update internal dev docs (lua/itemui/docs/) | **Sonnet** | Path replacement, minor reframing |
| Fix phase7_check.ps1 paths | **Sonnet** | Mechanical |
| Add CoopUI headers to Lua files | **Sonnet** | Template-following |
| Version bump | **Sonnet** | One-line change |
| Final verification (grep audit) | **Sonnet** | Run commands, check output |

### Phase 2: Code Optimization

| Task | Model | Notes |
|------|-------|-------|
| Review init.lua architecture | **Opus** | 5000+ lines, complex dependency graph |
| Identify performance bottlenecks | **Opus** | Needs MQ2/Lua domain knowledge |
| Plan the init.lua split | **Opus** | Architecture decision with tradeoffs |
| Extract individual modules | **Opus first, then Sonnet** | Opus for the first extraction (set the pattern), Sonnet for subsequent ones following the same pattern |
| Optimize buildItemFromMQ | **Opus** | ~50 TLO calls, need to reason about which are necessary per view |
| Add error handling / nil checks | **Sonnet** | Mechanical once pattern is established |
| Remove dead code | **Sonnet** | Clear targets from audit |
| Consolidate cache mechanisms | **Opus** | Design decision (perfCache vs core/cache.lua) |

### Phase 3: Architectural Cohesion

| Task | Model | Notes |
|------|-------|-------|
| Design unified API patterns | **Opus** | System design |
| Option A vs B decision (CoopUI loader) | **Opus** | Architecture tradeoff analysis |
| Create shared utility libraries | **Opus for design, Sonnet for implementation** | |
| Standardize code structure | **Sonnet** | Apply established patterns across files |
| Integration testing planning | **Sonnet** | Checklist generation |

### Phase 4: Documentation & Launch

| Task | Model | Notes |
|------|-------|-------|
| Write installation guide | **Opus** | User-facing, needs to be clear and complete |
| Write developer documentation | **Opus** | Needs deep codebase understanding |
| Configuration documentation | **Sonnet** | Structured, can reference existing config.lua |
| Release notes / changelog | **Sonnet** | Summarization of known changes |
| Troubleshooting guide | **Opus** | Needs to anticipate user issues |

---

## Cost-Saving Tips

1. **Start sessions with Opus for planning**, then switch to Sonnet for execution. Opus sets the strategy, Sonnet follows it.

2. **Batch mechanical work for Sonnet.** Instead of asking Opus to "rebrand these 5 files," give Sonnet a clear spec (from this audit doc) and let it execute.

3. **Use Opus for the first instance of a pattern**, then Sonnet for repetition. Example: have Opus extract the first view module from init.lua, then use Sonnet to extract the remaining ones following the same approach.

4. **Don't use Opus for verification.** Running grep commands, checking file contents, and confirming changes are Sonnet-tier tasks.

5. **When in doubt, start with Sonnet.** If it struggles or produces something that doesn't feel right, escalate to Opus. You'll know within the first response whether the task needs more horsepower.

---

## Current Session Context

You're currently using **Opus** — which is the right choice for:
- This initial planning and audit phase
- The README rewrite (user-facing, tone-setting)
- Architecture review and Phase 2 planning

After we finish the README and audit, the bulk of Phase 1 execution (find/replace in docs, adding headers, path fixes) can shift to **Sonnet** to conserve usage.
