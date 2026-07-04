# machines/

One profile per machine, rendered by the generator into every harness's
rules as a "Machines" section: the matched profile becomes "this
machine," the rest are listed as the available fleet.

- Files are **body-only** markdown (bullet lists); the renderer supplies
  the headings. Static facts only — specs, role, scheduler, scratch
  paths. Nothing that changes between installs (disk free, versions).
- Hostname-to-profile matching lives in `manifest.toml` under
  `[machine.<name>]` (`hosts` = glob patterns, first match wins).
- `other.md` is the fallback for unmatched hosts and is never listed as
  part of the fleet. A hand-written `~/.agent-config/machine.local.md`
  (never synced) takes precedence over it.
