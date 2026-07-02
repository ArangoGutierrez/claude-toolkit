# Self-Review
Review changes vs main

## Flow
1.`git log --oneline main..HEAD && git diff main..HEAD --stat && git diff main..HEAD`
2.Summary:commits,files,+/-
3.Each file:
  A.Correct:logic?edges?bugs?
  B.Style:patterns?naming?debug-code?
  C.Sec:secrets?input-val?err-safe?
  D.Tests:new-code-tested?meaningful?
4.Report:✅Good|⚠Consider(file:line+suggest)|❌Fix(file:line+req)
  Aspect:Correct|Style|Sec|Tests→✓/⚠/✗
  Verdict:Ready|Minor-fixes|Needs-work
5.Update AGENTS.md:Self-review→[DONE]

## Issues
List:file:line+issue+fix→/code→/self-review
