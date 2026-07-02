# extract.jq — input: slurped array of claude stream-json events (jq -s -f extract.jq).
# output: JSON array of activated skill ids (deduped). Empty array = no skill activated.
# Field confirmed by Spike-0: the Skill tool_use carries .input.skill; fallbacks
# guard against future CLI shape changes.
[ .[]
  | select(.type == "assistant")
  | .message.content[]?
  | select(.type == "tool_use" and .name == "Skill")
  | (.input.skill // .input.command // .input.name // empty)
] | unique
