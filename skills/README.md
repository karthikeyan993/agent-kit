# Skills written in this repo

For skills that don't live anywhere else. Each skill is a folder with a `SKILL.md`:

```
skills/code-review/SKILL.md
```

```markdown
---
name: code-review
description: Review a diff against our team checklist. Use when asked to review code or a PR.
---

Steps the agent should follow…
```

The `description` says what the skill does and when to use it. The agent decides whether to load a skill from that line alone.

To ship it, add `- ./skills/code-review` to [apm.yml](../apm.yml) and run `./setup.sh`.
