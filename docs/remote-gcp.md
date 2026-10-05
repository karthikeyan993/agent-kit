# Remote agents on a GCP VM

On a VM, agents keep running after you disconnect. You can attach to them from your Mac, from another SSH session, or from a phone.

```
Your Mac (herdr client) ──SSH──▶ GCP VM (herdr server, pi, team skills) ──▶ GitHub Copilot
```

## 1. Create the VM

- **Image:** Debian or Ubuntu, on x86_64 or Arm.
- **Size:** the agents themselves are light, since the model runs at GitHub. Size the VM for the builds and tests your agents will run.
- **Access:** you log in as your own user, not root.

## 2. Make plain `ssh` reach it

herdr uses the system `ssh`, so the VM needs a name in `~/.ssh/config`.

**VM with an external IP:** run this, which writes `Host <vm>.<zone>.<project>` entries:

```bash
gcloud compute config-ssh
```

**IAP only (no external IP):** add an entry by hand:

```
Host devbox
  HostName <vm-name>
  ProxyCommand gcloud compute start-iap-tunnel %h 22 --listen-on-stdin --zone=<zone> --project=<project>
```

Check it works:

```bash
ssh devbox true
```

## 3. Set up the VM

SSH in, then run the normal quick start from the [README](../README.md): clone, run `./bootstrap.sh`, then do the Copilot `/login` in `pi`. The device-code login works over SSH. Your Copilot login stays on the VM.

## 4. Use it

**From your Mac, with your local herdr window** (run once):

```bash
herdr machine add devbox --label "GCP devbox"
```

Then, any time:

```bash
herdr --remote devbox
```

**On its own:** SSH in and run `herdr`, start agents, and detach. They keep running; reattach later from your Mac or from a phone.

## Things to know

- **Same herdr version on both ends.** Both machines run the same bootstrap, so they match. After a herdr upgrade, update both.
- **Reboots end running agents.** herdr survives you disconnecting, not a VM restart. Keeping it running across reboots would need a system service, which isn't part of this kit.
- **The VM needs the herdr binary,** because the same binary runs the server. If `herdr machine add` can't find it on the VM, it offers to install a copy into `~/.local/bin`. Decline, check that `./bootstrap.sh` ran on the VM, and see [troubleshooting](troubleshooting.md).
