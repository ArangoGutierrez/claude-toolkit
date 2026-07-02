# score.jq — args: --argjson pass <float> --argjson decoy <float>
# input: normalized results for one skill {skill, cases:[{id,expect,runs:[[skill...]|null]}]}
# output: scores object with per-case rate+verdict and a summary.
.skill as $skill
| {
    skill: $skill,
    pass_threshold: $pass,
    decoy_threshold: $decoy,
    cases: [
      .cases[]
      | ([ .runs[] | select(. != null) ]) as $valid
      | ($valid | length) as $n
      | ([ $valid[] | select(index($skill) != null) ] | length) as $fired
      | (if $n == 0 then null else ($fired / $n) end) as $rate
      | {
          id: .id, expect: .expect,
          attempts: (.runs | length), valid: $n, fired: $fired, rate: $rate,
          verdict: (
            if $n == 0 then "ERROR"
            elif .expect == "activate" then (if $rate >= $pass then "PASS" else "FAIL" end)
            elif .expect == "silent"   then (if $rate <= $decoy then "PASS" else "FAIL" end)
            else "ERROR" end )
        }
    ]
  }
| .summary = {
    total: (.cases | length),
    pass:  ([ .cases[] | select(.verdict=="PASS")  ] | length),
    fail:  ([ .cases[] | select(.verdict=="FAIL")  ] | length),
    error: ([ .cases[] | select(.verdict=="ERROR") ] | length)
  }
