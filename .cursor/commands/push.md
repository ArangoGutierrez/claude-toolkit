# Push
→push+PR

## Pre-Check
✓all[DONE]in AGENTS.md|✓tests(/test)|✓review(/self-review)
Warn if unchecked

## Flow
1.`git status`+run tests
2.Read AGENTS.md→issue#,ctx
3.`git push -u origin HEAD`
4.`gh pr create --title "{type}({scope}): {title}" --body "Closes #{n}\n\n## Summary\n{ctx}\n\n## Changes\n{commits}\n\n## Checklist\n- [x] Tests\n- [x] Review\n- [x] Patterns\n\n## Testing\n{verify}"`
5.Report:PR#,branch,closes,link
6.Update AGENTS.md:Status:PR_OPEN,PR#{n},link

## Fail
List missing:[TODO]|tests|review→suggest steps
