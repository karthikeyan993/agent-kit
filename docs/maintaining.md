# Maintaining agent-kit

## Every change follows the same loop

1. Edit a file in `config/`, or a step in `steps/`.
2. Run the checks locally:
   ```bash
   scripts/lint.sh
   ```
   ```bash
   scripts/test-sandbox.sh
   ```
3. Open a PR, and add a line under "Unreleased" in [CHANGELOG.md](../CHANGELOG.md). CI runs the same checks on macOS and Linux.
4. After the merge, ask the team to run:
   ```bash
   git -C ~/agent-kit pull && ~/agent-kit/bootstrap.sh
   ```

`scripts/test-sandbox.sh` never touches your real setup. It installs everything into a throwaway home directory, runs the bootstrap three times while changing config between runs, and checks the result. Add `KEEP=1` to inspect the sandbox afterwards.

## Upgrade a tool

See what's newer than the pinned versions. This works from any directory, because `config/mise.toml` is linked into mise's global config:

```bash
mise outdated --bump
```

Then change the version in `config/mise.toml` and follow the loop above. Plain `mise outdated` (without `--bump`) only reports "up to date", because our pins are exact. Bump `node` within LTS releases, not just to the newest version.

- **herdr:** a new version reaches each person's running herdr server only when it restarts, and restarting ends running agents. Tell people to restart when they're idle (`herdr server stop`, then `herdr`); `scripts/doctor.sh` warns until they do. Bump laptops and VMs together.
- **pi:** read its changelog for changes to settings or models, and check that the team default model still appears in `pi --list-models`.

## Add, update or remove a skill package

All three are edits to `config/pi-packages.txt`:

| To | Do this |
|---|---|
| Add | Add a line: `git:github.com/YOUR_ORG/REPO@v1.0.0` |
| Update | Tag a new release in the skills repo, then change the `@tag` |
| Remove | Delete the line. The next bootstrap removes the package from machines that got it from this kit. |

pi finds skills in a `skills/` directory, or wherever `package.json` points with `"pi": {"skills": ["./path"]}`. A skill is a folder containing `SKILL.md`. See pi's skills docs for the format.

**Private skill repos:**

- **Developers:** they need a GitHub login, which the bootstrap handles.
- **CI:** add a repository secret named `SKILLS_READ_TOKEN`. It should be a fine-grained token with read-only **Contents** access to the skill repos.

## Change a pi default

Edit `config/pi-settings.json`, for example `defaultModel`.

- **Who gets it:** a setting someone never changed follows the team file, so the new value reaches them on their next bootstrap. Someone who changed that setting themselves keeps their own value. `scripts/doctor.sh` shows them the difference.
- **Retiring a setting:** to remove it, delete it from the file. It's also removed from machines where nobody changed it.

The rules are in `lib/settings.jq`.

## Add a setup step

Add a file to `steps/`, numbered for where it should run (for example `65-something.sh`). Start it with `# shellcheck shell=bash` and a comment that says what it does and why. Keep it safe to re-run. Use `say`, `warn` and `die` from `lib/common.sh`. If it's worth checking later, add a check to `scripts/doctor.sh`.

## Releases

Developers track `main`. For traceability:

1. Move the "Unreleased" entries in `CHANGELOG.md` under a new version.
2. Tag it:
   ```bash
   git tag v0.2.0 && git push --tags
   ```

`scripts/doctor.sh` prints the kit version on every machine, which makes support easier.
