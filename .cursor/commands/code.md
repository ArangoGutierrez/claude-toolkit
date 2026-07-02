# Code
(no args)→next[TODO]|`#{N}`→specific task

## Flow
1.Read AGENTS.md→find[TODO]
2.Display:Task#{N}+desc+files,update[TODO]→[WIP]
3.Impl:ONLY this task,minimal changes
4.Verify:✓compile|✓task-accept|✓no-unrelated
5.Commit:`git add {f} && git commit -s -S -m "{type}({scope}): {desc}\n\nRefs: #{issue}\nTask: {N}/{total}"`
6.Update AGENTS.md:[WIP]→[DONE]+hash
7.Report:commit,files,progress,next

## Blocked
Update:[BLOCKED:{reason}]

## Reflect
Single-concern?|Minimal?|Compiles?|Tests?

## Troubleshoot
|Issue|Fix|
|no-AGENTS.md|run `/issue #{n}` or `/task {desc}` first|
|no-TODO|check [BLOCKED] tasks|unblock or run `/test`/`/self-review`|
|dep-missing|work on prerequisite task first|
|commit-fail|GPG: `git config --global user.signingkey {KEY}`|hook: fix lint|conflict: `git pull --rebase`|
|build-fail|check imports/interfaces|revert if needed|

## Rules
1task=1commit|atomic|update AGENTS.md|refs issue
