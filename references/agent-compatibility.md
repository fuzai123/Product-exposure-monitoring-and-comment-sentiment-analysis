# Cross-agent installation and compatibility

This package follows the open Agent Skills layout: one directory containing `SKILL.md`, optional `scripts/`, `references/`, and `assets/`. Keep this directory intact when installing it.

## Simplest universal usage

Give the GitHub URL to an agent with terminal/file access and say:

```text
Install and use this Agent Skill: https://github.com/fuzai123/product-global-exposure-monitoring-comment-analysis. Monitor [product name] across the web, analyze comments, and update [tracker URL]. Ask me only for missing campaign details or login approval.
```

After installation, use this prompt:

```text
Use product-global-exposure-monitoring-comment-analysis. Monitor [product], including official and third-party content, update existing URLs in place, analyze new comments, and produce today's brief.
```

## Native Agent Skills clients

| Agent application | Market | Recommended location or command | Invocation |
|---|---|---|---|
| OpenAI Codex | International | `~/.codex/skills/product-global-exposure-monitoring-comment-analysis/` or shared `~/.agents/skills/product-global-exposure-monitoring-comment-analysis/` | `$product-global-exposure-monitoring-comment-analysis` or natural language |
| Anthropic Claude Code | International | `~/.claude/skills/product-global-exposure-monitoring-comment-analysis/` | `/product-global-exposure-monitoring-comment-analysis` or natural language |
| GitHub Copilot and VS Code Agent | International | `~/.agents/skills/product-global-exposure-monitoring-comment-analysis/` or `.github/skills/product-global-exposure-monitoring-comment-analysis/` | Natural language; Copilot loads matching skills |
| Google Gemini CLI | International | `gemini skills install https://github.com/fuzai123/product-global-exposure-monitoring-comment-analysis` | Natural language; inspect with `/skills list` |
| Cursor Agent | International | `.agents/skills/product-global-exposure-monitoring-comment-analysis/` or `.cursor/skills/product-global-exposure-monitoring-comment-analysis/` | `/product-global-exposure-monitoring-comment-analysis` or natural language |
| OpenCode | International | `~/.agents/skills/product-global-exposure-monitoring-comment-analysis/` | Natural language through the native skill tool |
| Kimi Code CLI | Chinese | `~/.agents/skills/product-global-exposure-monitoring-comment-analysis/` or `~/.kimi-code/skills/product-global-exposure-monitoring-comment-analysis/` | `/skill:product-global-exposure-monitoring-comment-analysis` or natural language |
| Qwen Code | Chinese | `~/.qwen/skills/product-global-exposure-monitoring-comment-analysis/` | `/product-global-exposure-monitoring-comment-analysis` or natural language |
| Tencent CodeBuddy Code | Chinese | `~/.codebuddy/skills/product-global-exposure-monitoring-comment-analysis/` | Natural language or slash menu |

The preferred shared install is:

```bash
git clone https://github.com/fuzai123/product-global-exposure-monitoring-comment-analysis "$HOME/.agents/skills/product-global-exposure-monitoring-comment-analysis"
```

Use a client-specific path from the table when the client does not scan `.agents/skills/`.

## Rule-file adapters

Windsurf Cascade, Cline, Roo Code, Trae, and similar agents may use Rules or `AGENTS.md` instead of native Agent Skills in some versions. Keep the skill directory anywhere inside the project, then add a short project rule:

```markdown
# Product exposure monitoring

When the user asks for product exposure monitoring or comment sentiment analysis, read and follow:
`path/to/product-global-exposure-monitoring-comment-analysis/SKILL.md`.
Load its referenced files only when needed and preserve its write/QA gates.
```

Typical rule locations include root `AGENTS.md`, `.clinerules/`, `.windsurf/rules/`, or the client's project Rules panel. Treat these as adapters: the core workflow remains in `SKILL.md`.

## Runtime capability differences

- Web access: prefer Agent Reach when installed; otherwise use the client's web search, browser, API, or MCP connectors.
- Feishu: use a structured connector when it supports range readback; otherwise use an authenticated interactive browser. Never claim a successful write without verification.
- Scheduling: use the client's native automation/scheduler. If absent, use cron, Windows Task Scheduler, or CI and keep the same state/QA contract.
- Scripts: use `scripts/delta_state.py` on Windows, macOS, and Linux. `scripts/delta_state.ps1` remains a Windows fallback.
- Permissions: expect the user to approve browser login, external writes, script execution, and destructive cleanup according to the host client's safety model.

## Official compatibility references

- Agent Skills open specification: https://agentskills.io/specification
- Claude Code Skills: https://code.claude.com/docs/en/skills
- GitHub Copilot Agent Skills: https://docs.github.com/en/copilot/how-tos/copilot-on-github/customize-copilot/customize-cloud-agent/add-skills
- Gemini CLI Agent Skills: https://geminicli.com/docs/cli/using-agent-skills/
- Cursor Agent Skills: https://cursor.com/changelog/2-4
- OpenCode Agent Skills: https://opencode.ai/docs/skills
- Kimi Code CLI Agent Skills: https://moonshotai.github.io/kimi-code/en/customization/skills
- Qwen Code Agent Skills: https://qwenlm.github.io/qwen-code-docs/en/users/features/skills/
- Tencent CodeBuddy Skills: https://staging-codebuddy.tencent.com/docs/cli/skills
