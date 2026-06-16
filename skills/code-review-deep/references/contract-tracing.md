# Contract & Data-Flow Tracing

The bugs a line-by-line read never finds don't live on a line — they live in
the *seam between two files*. A field is set in a panel but never copied in the
sync function. A cache key hashes nine of eleven fields, so toggling the other
two returns stale data. The GUI exports a preset the CLI silently ignores. A
default is declared in one place and overridden in another. Each site reads
perfectly on its own; the bug is the *gap between* them.

A reviewer reading top to bottom can't catch these, because nothing on any
single line is wrong. And you can't catch them by "being careful" either — you'd
need foresight about which field is supposed to flow where. This pass replaces
foresight with **exhaustive enumeration**: list every member at every site and
let the asymmetry be the finding. It's mostly mechanical (grep / AST), so it
costs almost nothing and doesn't depend on what the model happens to notice.

Run this pass whenever the change (or the codebase) has *state that crosses a
boundary*: UI state synced to a render/model layer, config consumed by more than
one reader, a producer on one side of a serialization boundary and a consumer on
the other, a cache key derived from a subset of some struct, or any "default"
that could be set in two places.

## Step 1 — Find the hubs

A **hub** is a set of named members (struct fields, config keys, enum variants,
flags) that must stay in lockstep across multiple sites. Find them by their
shape, not by reading every file:

- **State struct + a manual sync/copy function.** The classic. A `*UiState` /
  `*Options` / `*Settings` struct whose fields are hand-copied into another
  struct elsewhere. The copy function is where fields silently fall off.
  *(Orbitron I6: cartoon checkboxes written to panel state, never copied in
  `sync.rs`.)*
- **A cache key derived from a subset of fields.** Any `*CacheKey`, `Hash` impl,
  memoization key, or `deps`-style array. If it lists fields by hand, it will
  miss one. *(Orbitron I9: `RenderCacheKey` omitted two fields → toggling them
  hit a stale cache.)*
- **Two schemas for "the same" data.** Two serializers, two DTOs, two file
  formats, two `from_json`/`to_json` pairs that claim to represent one thing.
  *(Orbitron I8: `ThemePresetFileData` vs `AppearanceBundle`, both `.json`,
  asymmetric coverage — which export button you used changed what survived.)*
- **A producer/consumer pair across a boundary.** Code that writes a format and
  separate code that reads it: GUI export → CLI import, server serialize →
  client deserialize, writer → migration → reader. *(Orbitron I7: GUI wrote a
  full preset; the CLI render path read only color + radius + one flag.)*
- **A default declared in more than one place.** A `Default` impl *and* a
  bootstrap/init that hardcodes the same fields. One silently wins.
  *(Orbitron I4: `ViewUiState::default()` set `show_atom_labels: false` but
  `bootstrap.rs` hardcoded `true` — the default never took effect.)*

Grep for the smells: `fn sync`, `CacheKey`, `Default for`, `to_json`/`from_json`,
`serde`, `impl Hash`, paired `export`/`import`, `bootstrap`/`init` next to a
struct that also has a `Default`.

## Step 2 — Enumerate members at each site

For each hub, list the members on every side. Pull field names straight from the
definition — don't transcribe by hand.

```bash
# Field names of a struct (Rust example; adapt the brace-matching per language).
# Gives you the canonical member list to check every other site against.
awk '/struct ViewUiState/{f=1} f&&/^}/{f=0} f' src/.../view_state.rs \
  | grep -oE '^\s+[a-z_][a-z0-9_]*:' | tr -d ' :'
```

The output of this step is, per hub, a column of member names — the checklist
the other sites must satisfy.

## Step 3 — Diff the sets; the asymmetry is the finding

For each member, confirm it appears at every site it must. The cheap version is
one grep per member against the downstream file:

```bash
# For each field of the source struct, does the sync/cache/consumer mention it?
# Zero hits downstream = set-but-never-propagated (the inert-control bug).
for field in $(cat /tmp/fields.txt); do
  n=$(grep -c "\b$field\b" src/.../sync.rs)
  [ "$n" -eq 0 ] && echo "NOT SYNCED: $field"
done
```

Classify each asymmetry:

- **Set but never propagated** — present in the source struct, absent in the sync
  function. The control does nothing. *(I6.)*
- **Read but not in the key** — the rendered/derived output depends on a field
  the cache key doesn't hash. Stale results on change. Compare the fields the
  *output* reads against the fields the *key* includes. *(I9.)*
- **Present in A, dropped by B** — field exists in the producer's schema, ignored
  by the consumer. The feature looks wired but doesn't survive the boundary.
  *(I7, I8.)*
- **Defaulted twice** — same field assigned in `Default` and in init/bootstrap.
  Determine which actually runs; the other is dead and misleading. *(I4.)*

A nonzero grep count isn't a clear — confirm the field is actually *used*, not
just named in a comment or a log line. But a *zero* count is a high-confidence
hit: a field that exists upstream and is never mentioned downstream is almost
always a real gap. That asymmetry is the whole point of the pass — it needs no
judgment about intent.

## Step 4 — The fix is structural, not per-instance

When you find one of these, the instance is the symptom. The disease is that the
two sites are wired *by hand*, so every future field has to be threaded into both
or it silently dies the same way. Orbitron's own diagnosis, after the cache-key
bug: "the manual field-by-field `sync.rs` + cache-key is a standing trap — any
new view field added to a panel has to be wired into both or it silently dies."

So the finding isn't just "wire up these two fields." It's "this hub regenerates
this bug class; make the asymmetry impossible." Options, cheapest first:

- **An invariant test** that reflects over the source struct and asserts every
  field appears in the sync function / cache key / consumer schema. Fails the
  build the next time someone adds a field and forgets. This is usually the
  smallest durable fix and worth more than catching the instance.
- **Derive instead of hand-list** — derive the cache key / hash / serialization
  from the whole struct (`#[derive(Hash)]`, `#[derive(Serialize)]`) so a new
  field is included automatically, rather than enumerating fields by hand.
- **Single source of truth** — collapse two defaults or two schemas into one.
  *(I4: delete the bootstrap hardcode, let `Default` own it. I8: one preset
  format, not two.)*

Recommend the structural fix in the report, not just the line fix. A review that
patches I6 and leaves the manual-sync trap in place will be writing the same
finding again in three months.

## What this pass does not catch — run the code

Two of Orbitron's bugs (the bootstrap override and the cache key) read as
*correct* even under an adversarial static trace — the cache key looked right
until the toggle visibly did nothing on screen. Tracing narrows where to look;
it does not replace execution. After this pass, for any stateful or UI change,
run the thing and watch the behavior change (see the run-it-and-watch step in
`SKILL.md`). The tracer and the run step are complementary: the tracer finds the
gap you can prove from the source; running finds the gap that only exists at
runtime.
