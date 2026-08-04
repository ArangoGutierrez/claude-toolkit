# Report Style — ASD-STE100 Simplified Technical English

Write every report in ASD-STE100 Simplified Technical English (STE). STE is the
aerospace controlled-language standard. Its aim is one meaning per word and one
idea per sentence.

## Where this applies

**Apply STE to:** chat messages to the user; specs, plans, task briefs, code
reviews, handoffs, and progress ledgers; subagent report files.

**Do not apply STE to:** code, code comments, and commit messages, which keep
their own conventions; and outward-facing human writing — blog posts, emails,
Slack messages, and PR descriptions — which keep a relaxed, natural tone.

Quoted material stays verbatim: command output, file paths, identifiers, flags,
API names, and error strings. Never "simplify" an identifier.

## Writing rules

- Use the active voice. Write "the hook blocks the write", not "the write is
  blocked".
- Use the simple present tense. Use the simple past only for a past event.
- Give one idea or one instruction per sentence.
- Keep an instruction to 20 words. Keep a descriptive sentence to 25 words.
- Keep a paragraph to 6 sentences.
- Start an instruction with its verb. Write "Run the eval", not "You should run
  the eval".
- Keep the articles. Do not delete words to make a sentence short.
- Use a maximum of 3 nouns in a row. Break a longer cluster with a preposition.
  Write "the drift check for the deploy overlay", not "the deploy overlay drift
  check".
- Do not use an -ing form as a noun or as a main verb. Write "the deploy fails",
  not "deploying fails".
- Put complex data in a list or a table. Do not put it in one long sentence.
- Use the same word for the same thing every time. Do not change the word for
  variety.
- Write a warning before the step that it applies to.

## Preferred words

| Use | Do not use |
|---|---|
| use | utilize, leverage |
| start | commence, initiate |
| stop | terminate, cease |
| do, run | perform, execute (except "execute a binary") |
| to | in order to, so as to |
| before | prior to |
| after | subsequent to |
| about | approximately, regarding |
| because | due to the fact that |
| but | however, nevertheless |
| get | obtain, acquire |
| show | demonstrate, illustrate |
| help | facilitate, assist |
| enough | sufficient |
| change | modify, alter |
| let | enable (except "enable a flag") |

The full ASD-STE100 dictionary is copyright ASD. This file carries the writing
rules and a short word table only.

## Check before you send

Find the longest sentence in the report. If it has more than 25 words, split it.
