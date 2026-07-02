# Testing Agent Model Configurations

This guide explains how to test and verify that Cursor agents are correctly configured with their model settings.

## Quick Test

Validate that deployed agents have correct frontmatter by inspecting them directly:

```bash
ls ~/.cursor/agents/*.md | head -5
head -10 ~/.cursor/agents/api-reviewer.md
```

This confirms:

- All agents have valid `model` fields
- Model values use correct format (`sonnet`, `opus`, `haiku`, `fast`, `inherit`, or full model IDs)
- Required frontmatter fields (`name`, `description`) are present

## Manual Testing in Cursor

### Method 1: Invoke an Agent Directly

1. **Deploy agents** (if not already deployed):

   ```bash
   ./scripts/deploy.sh
   ```

2. **Restart Cursor** to load the new configurations

3. **Test an agent**:
   - Open Cursor chat
   - Type: `/quality` (triggers multiple agents including `api-reviewer`, `auditor`, `perf-critic`, `verifier`)
   - Or mention directly: `@api-reviewer review this API endpoint`

4. **Verify model usage**:
   - Check response quality (Sonnet 4.5 should provide more detailed, nuanced responses than `fast`)
   - Look for model indicators in Cursor's UI (if available)
   - Compare responses between agents with different model settings

### Method 2: Compare Model Behavior

Create a simple test to compare agents:

1. **Use an agent with `model: sonnet`**:

   ```
   @api-reviewer review this endpoint: GET /users/{id}
   ```

2. **Note the response quality**:
   - Depth of analysis
   - Detail level
   - Reasoning quality

3. **Compare with `model: fast`** (if you temporarily change one):
   - `fast` should be quicker but less detailed
   - `sonnet` should be more thorough

## Automated Validation

### CI/CD Integration

The GitHub Actions workflow (`.github/workflows/validate-cursor.yml`) now validates:

- Agent frontmatter structure
- Model field format (if present)
- Required fields

Run locally:

```bash
# Simulate the CI validation
act -j validate-structure
```

Or push to trigger the workflow automatically.

### Validation

Inspect deployed agent frontmatter to confirm model fields are set correctly:

```bash
grep -r "^model:" ~/.cursor/agents/
```

Expected output shows each agent's model value (`sonnet`, `opus`, `haiku`, `fast`, `inherit`, or a full model ID).

## Valid Model Values

Cursor accepts these model values:

| Value | Description |
|-------|-------------|
| `claude-4-5-sonnet` | Claude Sonnet 4.5 (recommended format) |
| `claude-4-5-opus` | Claude Opus 4.5 |
| `sonnet` | Claude Sonnet (alias, may use latest) |
| `opus` | Claude Opus (alias, may use latest) |
| `haiku` | Claude Haiku (fastest, cost-effective) |
| `fast` | Fast model (optimized for speed) |
| `inherit` | Inherit model from parent conversation |
| `claude-sonnet-4-5-20250929` | Full model identifier with date |

## Troubleshooting

### Model Not Being Used

If an agent doesn't seem to be using the specified model:

1. **Check deployment**:

   ```bash
   ls -la ~/.cursor/agents/
   ```

2. **Verify frontmatter**:

   ```bash
   head -10 ~/.cursor/agents/api-reviewer.md
   ```

3. **Restart Cursor** completely

4. **Check Cursor logs** (if available) for model selection

### Invalid Model Format

If you see errors about invalid model values:

1. **Check the format**:
   - ✅ Correct: `model: claude-4-5-sonnet`
   - ✅ Correct: `model: sonnet` (alias)
   - ❌ Wrong: `model: Claude sonnet 4.5`
   - ❌ Wrong: `model: "sonnet"` (quotes not needed)

2. **Run validation**:

   ```bash
   grep -r "^model:" ~/.cursor/agents/
   ```

3. **Fix invalid values**:
   - Use aliases: `sonnet`, `opus`, `haiku`, `fast`, `inherit`
   - Or full IDs: `claude-sonnet-4-5-20250929`

## Testing Checklist

- [ ] Deploy agents: `./scripts/deploy.sh`
- [ ] Verify model fields: `grep -r "^model:" ~/.cursor/agents/`
- [ ] Restart Cursor
- [ ] Test `/quality` command
- [ ] Verify agent responses show expected quality
- [ ] Check CI validation passes (if applicable)

## Next Steps

- See [Cursor Configuration](cursor.md) for agent capabilities and how agents are invoked
