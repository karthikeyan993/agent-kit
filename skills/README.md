# Skills written in this repo

Every folder here that contains a `SKILL.md` is a skill everyone gets.

- **Add:** create the folder.
- **Remove:** delete the folder.

Nothing else needs changing. Each developer gets the change on their next `./setup.sh`.

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

For skills that live in other repos, use the `packages` list in [pi-settings.json](../pi-settings.json) instead.
