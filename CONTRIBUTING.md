# Contributing to claude-toolkit

Thank you for your interest in contributing! This library aims to be a community resource for research-backed AI prompt engineering.

## How to Contribute

### Reporting Issues

- Use GitHub Issues for bug reports or feature requests
- Include the prompt file name and a clear description
- For prompt improvements, cite research if available

### Submitting Changes

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feat/your-feature`
3. **Make your changes**
4. **Test your prompts** with Claude/Cursor to verify they work
5. **Submit a Pull Request**

### Contribution Guidelines

#### Adding New Prompts

New prompts should follow the existing structure:

```markdown
# PROMPT NAME

## ROLE
**Title** — Domain Expertise

### Responsibilities:
- Specific action 1
- Specific action 2

### Boundaries:
- Evidence-based findings only
- Scope limitations

## GOAL
One-line description of what this prompt achieves

## TRIGGER
How users invoke this prompt

## EXEC
Step-by-step execution instructions

## OUTPUT
Expected output format/template

## CONSTRAINTS
List of rules and limitations

## Self-Check
Verification checklist before finalizing
```

#### Modifying Existing Prompts

When modifying prompts:

1. **Cite research** - Link to papers/findings that support your change
2. **Preserve patterns** - Don't remove working patterns without justification
3. **Update the PR description** - Document what changed and why
4. **Test the change** - Verify the prompt still works as expected

#### Research-Backed Improvements

We prioritize changes backed by research. When proposing improvements:

| Element | Required |
|---------|----------|
| Research citation | Paper name, year, or URL |
| Claimed improvement | What metric improves (accuracy, token efficiency, etc.) |
| Before/after example | Optional but helpful |

### Code Style

- **Markdown**: Use consistent headers, tables, code blocks
- **Prompts**: Follow the Role → Goal → Exec → Output → Constraints structure
- **Documentation**: Keep it concise; prefer tables over prose

### Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```text
feat(prompts): add new code-review prompt
fix(audit-go): correct security scope reference
docs: update getting-started guide
refactor(task-prompt): simplify iteration budget section
```

### Pull Request Process

1. Ensure your PR description explains **what** and **why**
2. Link to any related issues
3. Wait for review - maintainers will provide feedback
4. Address review comments
5. Once approved, a maintainer will merge

## Development Setup

1. Clone the repository:

   ```bash
   git clone https://github.com/ArangoGutierrez/claude-toolkit.git
   cd claude-toolkit
   ```

2. Set up your environment (optional):

   ```bash
   export PROMPTS_LIB="$(pwd)"
   ```

3. Deploy Cursor config:

   ```bash
   ./scripts/deploy.sh
   ```

   This syncs `.cursor/` (including rules, agents, and commands) to `~/.cursor/`.

## Questions?

Open a GitHub Issue or Discussion for questions about contributing.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
