---
name: secondary-ai-delegation
description: >-
  Standard operating procedure for decomposing large architectural overhauls into atomic,
  token-bounded prompts for secondary code-generation AIs (e.g. Claude Opus or Claude Sonnet).
  Use whenever delegating code changes across multiple files or complex multi-phase refactors.
---

# Secondary AI Delegation & Prompting Workflow

## 1. Principles of Token-Bounded Delegation
1. **Single Responsibility:** Each prompt must modify at most 1–3 closely coupled files.
2. **Strict Context Isolation:** Supply only the relevant context, preventing context window exhaustion and hallucination.
3. **Interactive Macro-Area Checkpoint:** Group tasks by Macro Area and present one Macro Area at a time, requiring explicit user review before advancing.

## 2. Mandatory Prompt Template
Every atomic delegation task must strictly follow this structure:

> **[Copy to Claude] Prompt [MacroArea.SubArea.TaskNumber]:**
> **Context:** [Why this change is needed and what prior state exists]
> **Target Files:**
> - [Exact file path 1]
> - [Exact file path 2]
> **Action Required:**
> 1. [Specific, imperative instruction 1]
> 2. [Specific, imperative instruction 2]
> **Acceptance Criteria:**
> - [Objective, testable condition 1]
> - [Objective, testable condition 2]

## 3. Post-Execution Verification Loop
After the secondary AI completes a batch of prompts:
1. Run `flutter analyze` to verify zero new compilation errors or lints.
2. Run `flutter test` across all unit, widget, and integration suites.
3. Validate that edge cases (e.g., date formats, concurrency locks, nullability) are specifically tested.
