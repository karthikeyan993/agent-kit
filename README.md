# agent-kit

One command sets up a developer's Mac or a GCP Linux VM with our agent tooling:

- **herdr**: terminal multiplexer for coding agents
- **pi**: coding agent, plus our team skills/extensions as pi packages
- **node, gh, ripgrep, fd, jq**: what pi and the skills need

All tool versions are pinned in [mise.toml](mise.toml). Team pi packages are listed in [pi-packages.txt](pi-packages.txt). pi defaults to our GitHub Copilot subscription, using `gpt-6-luna` with `xhigh` thinking ([pi-settings.json](pi-settings.json)).

## New developer (macOS)

```bash
git clone https://github.com/YOUR_ORG/agent-kit.git ~/agent-kit
```

```bash
~/agent-kit/bootstrap.sh
```

On a brand-new Mac, the first `git` command asks to install the Xcode Command Line Tools. Accept it, then re-run the clone. If GitHub isn't logged in yet, the bootstrap opens `gh auth login` in your browser. It needs this to fetch our private skill repos.

Then open a new terminal and sign in to GitHub Copilot. You do this once per machine:

1. Run `pi` and type `/login`.
2. Pick **GitHub Copilot**.
3. Leave the Enterprise domain blank, unless we're on `*.ghe.com`.
4. Enter the device code at github.com/login/device.

pi uses its own Copilot sign-in, so `gh auth login` alone isn't enough. Start a workspace with `herdr`.

`bootstrap.sh` does the following:

- Installs [mise](https://mise.jdx.dev) if needed.
- Links `mise.toml` into `~/.config/mise/conf.d/` so the tools work in every directory, then installs them.
- Logs in to GitHub if needed, then runs `gh auth setup-git`.
- Merges `pi-settings.json` into `~/.pi/agent/settings.json`. Keys a developer has already set win.
- Runs `pi install` for each package in `pi-packages.txt`.
- Installs herdr's pi integration.

You can re-run it safely. A fresh install takes a few minutes; a re-run takes about a second.

## Updating

- **Everyone:** `git -C ~/agent-kit pull && ~/agent-kit/bootstrap.sh`
- **Tool bump:** change the version in `mise.toml` and open a PR. Keep one herdr version on every machine, because the client and server must be protocol-compatible.
- **New or changed skills:** merge to the skills repo, tag it, then bump the `@tag` in `pi-packages.txt`.

Don't use `herdr update` or `pi update self` on these machines, because mise manages those binaries.

## Testing changes

```bash
scripts/test-sandbox.sh
```

This runs the bootstrap twice in a throwaway `HOME` with a bare `PATH`, so your real setup is untouched. It then checks:

- Every tool resolves from the sandbox.
- The team pi settings landed.
- The second run duplicated nothing.
- pi loads skills from every package. It prints their names.
- pi starts on the team default model.
- herdr's pi integration is installed.

Run it before every PR. `KEEP=1` keeps the sandbox for inspection.

## Remote devbox (GCP)

Agents, pi, and the skills run on the VM. Your Mac only needs the herdr client.

1. Create a Linux VM (Debian/Ubuntu, x86_64 or Arm) and make plain `ssh` reach it under one name, because herdr uses the system `ssh`.
   - **VM with an external IP:**
     ```bash
     gcloud compute config-ssh
     ```
     This writes `Host <vm>.<zone>.<project>` entries to `~/.ssh/config`.
   - **IAP only:** add a host entry by hand:
     ```
     Host devbox
       HostName <vm-name>
       ProxyCommand gcloud compute start-iap-tunnel %h 22 --listen-on-stdin --zone=<zone> --project=<project>
     ```
2. SSH in, run the clone and bootstrap commands from "New developer", then do the Copilot `/login`. Device-code login works over SSH. Credentials stay on the VM.
3. On your Mac:
   ```bash
   herdr machine add devbox --label "GCP devbox"
   ```
   ```bash
   herdr --remote devbox
   ```
4. From a phone: SSH to the VM and run `herdr` there.

The VM still has the herdr binary, because the same binary runs the server. If herdr can't find one, `herdr machine add` offers to install it into `~/.local/bin`. The bootstrap installs the pinned version instead, so client and server match.

## Why mise (not Nix, not only APM)

- Everything we need is a first-class mise tool. herdr is in the mise registry, and pi ships GitHub release binaries. One file covers macOS and Linux, with no root and no `/nix` store.
- pi packages already do what we needed from APM: `pi install git:...@tag` pins and installs skills, extensions, and prompts.
- Nix gives stronger reproducibility, but pi installs packages with npm at runtime anyway, so that purity ends at the agent. Consider Nix later for building identical devbox images.
