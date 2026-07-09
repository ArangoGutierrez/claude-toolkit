---
name: eureka
disable-model-invocation: true
description: Capture technical breakthroughs as structured documents. Triggered by "breakthrough", "key insight", "document discovery", or /eureka
user-invocable: true
tools:
  - Read
  - Write
  - Edit
---

# Eureka — Breakthrough Capture

Capture technical breakthroughs worth remembering across projects.

## Bar
"Would this surprise a senior engineer?" Routine solutions are not breakthroughs.

## Process

1. **Prompt for details:**
   - Problem: What were you trying to solve?
   - Insight: What was the non-obvious realization?
   - Implementation: How did you apply it?
   - Impact: What changed (quantify if possible)?

2. **Write structured document** to `docs/breakthroughs/YYYY-MM-DD-<slug>.md`:

   ```markdown
   # [Title]

   **Date:** YYYY-MM-DD
   **Tags:** [go, k8s, gpu, performance, ...]
   **Project:** [name or "cross-project"]

   ## Problem
   ## Insight
   ## Implementation
   ## Impact
   ```

   (Interim location until cross-IDE memory architecture ships)

3. **Optional:** If insight implies a new convention, propose update to relevant `rules/` file.

## Gotchas
- Don't capture routine debugging — that's /reflection
- The insight section must be specific enough to be actionable
- Don't capture well-documented knowledge
