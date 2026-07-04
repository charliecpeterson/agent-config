- Not one of my main machines — a borrowed, temporary, or new box whose
  hostname isn't in the fleet map yet.
- Assume modest resources; ask before starting anything heavy (big
  builds, model downloads, long jobs). The fleet below is available
  remotely for work that doesn't fit here.
- If this machine turns out to be permanent: add a `machines/<name>.md`
  profile and a `[machine.<name>]` hosts entry to `manifest.toml`, or
  write `~/.agent-config/machine.local.md` for a machine-local profile
  that never syncs.
