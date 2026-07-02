# Git-Polish
Rewrite local→atomic signed commits

## Setup
`GIT_EDITOR="true" && git config gpg.format ssh && git config user.signingkey ~/.ssh/id_ed25519.pub && git config commit.gpgsign true`

## Flow
1.`git log --oneline -n 10`→ask commits back→`git reset --soft [TARGET]`
2.`git status`→group:chore(cfg)|refactor(rename)|feat/fix(logic by domain)
3.Verify each:ONLY stated type?|cross-cut?|compiles?|msg accurate?→✓valid/✗split/?review
4.`git commit -S -s -m "type(scope): desc"`(-S:sign,-s:DCO,-m:inline)
5.`git log --show-signature -n [COUNT]`→✓signed|✓compiles|✓conventional
