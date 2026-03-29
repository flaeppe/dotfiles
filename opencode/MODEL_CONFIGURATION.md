# OpenCode Model Configuration - Performance Optimized

## Configuration Strategy: Best-in-Class Multi-Model

This configuration uses the absolute best model for each specific task type, prioritizing **performance over cost**.

## Model Assignments

### Default Models

| Setting | Model | Purpose |
|---------|-------|---------|
| **Primary Model** | `anthropic/claude-opus-4-5` | Fallback for general tasks |
| **Small Model** | `anthropic/claude-haiku-4-5` | Lightweight tasks (titles, summaries) |

### Agent-Specific Models

#### 1. Build Agent
- **Model**: `github-copilot/gpt-5.1-codex-max`
- **Temperature**: `0.2`
- **Purpose**: Primary coding agent for daily development work
- **Why This Model**:
  - ✅ Specifically optimized for code generation
  - ✅ "Codex Max" variant = highest quality code output
  - ✅ Excellent for TypeScript, Python, and Go
  - ✅ Best-in-class for production code generation
  - ✅ Leverages your GitHub Copilot subscription

**Use Cases**:
- Writing new features
- Implementing functions
- Refactoring code
- Bug fixes
- Code generation tasks

#### 2. Plan Agent
- **Model**: `anthropic/claude-opus-4-5`
- **Temperature**: `0.05`
- **Purpose**: Strategic planning and task breakdown
- **Why This Model**:
  - ✅ Superior reasoning capabilities
  - ✅ Excellent at breaking down complex tasks
  - ✅ Best for strategic thinking
  - ✅ Most powerful Claude model
  - ✅ Read-only mode (no file edits), so can use most powerful model

**Use Cases**:
- Planning feature implementations
- Breaking down complex tasks
- Architectural decisions
- Strategy discussions
- High-level design

#### 3. Code Reviewer Agent
- **Model**: `anthropic/claude-opus-4-5`
- **Temperature**: `0.05`
- **Purpose**: Security, performance, and maintainability reviews
- **Why This Model**:
  - ✅ Exceptional at finding security vulnerabilities
  - ✅ Deep code analysis capabilities
  - ✅ Thorough and consistent reviews
  - ✅ Best for critical review tasks
  - ✅ Read-only mode, so can use most powerful model

**Use Cases**:
- Code reviews
- Security audits
- Performance analysis
- Best practice verification
- Pre-commit reviews

## Temperature Settings Explained

### Temperature: 0.2 (Build Agent)
- **Low-medium creativity**
- **Rationale**: Code generation needs some creativity for elegant solutions, but must remain deterministic and reliable
- **Effect**: Produces high-quality, consistent code with occasional creative approaches

### Temperature: 0.05 (Plan & Code Review Agents)
- **Very low creativity**
- **Rationale**: Planning and reviewing require focused, deterministic, and consistent output
- **Effect**: Highly consistent, thorough, and reliable analysis with minimal randomness

## Performance Benefits

### 1. Specialized Models for Specialized Tasks
- Each agent uses the model that's best at its specific task
- No compromise on quality for any operation

### 2. Maximum Code Quality
- GPT-5.1 Codex Max is specifically trained for code generation
- Produces production-ready code optimally

### 3. Superior Analysis
- Claude Opus 4.5 provides the deepest analysis for planning and reviews
- Catches more issues and provides better insights

### 4. Provider Diversification
- Not dependent on a single provider
- Can leverage strengths of both Anthropic and GitHub Copilot
- Redundancy if one provider has issues

## Cost Considerations

**Note**: This configuration prioritizes **performance over cost**.

- **Build Agent**: Uses GitHub Copilot (included in your subscription)
- **Plan Agent**: Uses Claude Opus 4.5 (most expensive, but used less frequently)
- **Code Review**: Uses Claude Opus 4.5 (most expensive, but used less frequently)
- **Small Tasks**: Uses Claude Haiku 4.5 (cost-effective)

**Estimated Usage Pattern**:
- 70% Build Agent (GitHub Copilot) - Daily coding
- 15% Plan Agent (Claude Opus) - Occasional planning
- 10% Code Review (Claude Opus) - Periodic reviews
- 5% Small tasks (Claude Haiku) - Titles, summaries

## Switching Models

You can switch models at any time:

### In OpenCode Session
```
/model anthropic/claude-opus-4-5
/model github-copilot/gpt-5.1-codex-max
```

### For Specific Agents
```
/agent plan
/agent build
/agent code-reviewer
```

### Via Command Line
```bash
opencode --model anthropic/claude-opus-4-5
opencode --model github-copilot/gpt-5.1-codex-max
```

## Available Models

### From Anthropic (Direct)
- `anthropic/claude-opus-4-5` - Most powerful
- `anthropic/claude-sonnet-4-5` - Excellent balance
- `anthropic/claude-haiku-4-5` - Fast, lightweight

### From GitHub Copilot
- `github-copilot/gpt-5.2` - Latest OpenAI
- `github-copilot/gpt-5.1-codex-max` - **Currently used for build**
- `github-copilot/gpt-5.1-codex` - Code-optimized
- `github-copilot/claude-opus-4.5` - Claude via Copilot
- `github-copilot/gemini-3-pro-preview` - Google's latest

## Testing Your Configuration

### Test Build Agent (GPT-5.1 Codex Max)
```bash
opencode run "Create a TypeScript function that validates email addresses with proper error handling"
```

### Test Plan Agent (Claude Opus 4.5)
```bash
# Switch to plan mode with Tab key, then:
opencode
# Ask: "Plan how to implement user authentication with JWT tokens"
```

### Test Code Review Agent (Claude Opus 4.5)
```bash
opencode run "/review"
# Or: "Review the current changes for security issues"
```

## Troubleshooting

### Build Agent Not Working
If GPT-5.1 Codex Max isn't available:
1. Check GitHub Copilot subscription status
2. Verify model is enabled in GitHub settings: https://github.com/settings/copilot
3. Fallback: Change build agent to `anthropic/claude-opus-4-5`

### Plan/Review Agent Not Working
If Claude Opus 4.5 isn't available:
1. Check Anthropic authentication: `opencode auth list`
2. Re-authenticate: `opencode auth login anthropic`
3. Fallback: Change to `anthropic/claude-sonnet-4-5`

## Alternative Configurations

### If You Want to Use Only Claude
```json
{
  "agent": {
    "build": {
      "model": "anthropic/claude-opus-4-5"
    },
    "plan": {
      "model": "anthropic/claude-opus-4-5"
    },
    "code-reviewer": {
      "model": "anthropic/claude-opus-4-5"
    }
  }
}
```

### If You Want to Use Only GitHub Copilot
```json
{
  "agent": {
    "build": {
      "model": "github-copilot/gpt-5.1-codex-max"
    },
    "plan": {
      "model": "github-copilot/gpt-5.2"
    },
    "code-reviewer": {
      "model": "github-copilot/claude-opus-4.5"
    }
  }
}
```

## Performance Monitoring

Track which models work best for your workflow:
- Note response quality for different tasks
- Compare code quality from different models
- Adjust temperature settings if needed
- Switch models based on task complexity

## Summary

Your configuration is optimized for **maximum performance**:

✅ **Best code generation**: GPT-5.1 Codex Max (specialized for code)
✅ **Best planning**: Claude Opus 4.5 (superior reasoning)
✅ **Best reviews**: Claude Opus 4.5 (deep analysis)
✅ **Cost-effective small tasks**: Claude Haiku 4.5
✅ **Diversified providers**: Anthropic + GitHub Copilot

This setup gives you the absolute best performance for daily senior software engineering work with TypeScript, Python, and Go.

---

**Last Updated**: January 10, 2026
**Configuration File**: `~/.config/opencode/opencode.json`
**OpenCode Version**: 1.1.11
