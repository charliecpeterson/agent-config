# Bug scan: uncovered lenses, 2026-07-24

Five parallel, read-only static scans over ground not covered by the earlier
same-day A-E parser/concurrency/panic sweep. Workers covered cross-module
contracts, CLI and Python bindings, test assertion quality, units/numerics,
and the WASM viewer. The conductor re-read every finding below; no build or
runtime test ran in this pass.

Already-covered findings in `scan-findings-2026-07-24.md` and the capacity
subsystem in `optimization-review-2026-07-24.md` were explicitly excluded.
The uncommitted memory-footprint worktree was read as-is, not modified.

## Tier 1: silently wrong output

### 1. Invalid `--pbc` values silently change the periodicity model

`automation/cli/src/handlers/util.rs:460-465` treats `--pbc` as an arbitrary
string and checks only whether it contains `a`, `b`, and `c`:

```rust
let s = pbc.unwrap_or("abc").to_ascii_lowercase();
let has = |ch: char| s.contains(ch);
[has('a'), has('b'), has('c')]
```

`orbitron --cell-cubic 10 --pbc abz info structure.xyz --json` silently uses
`[true, true, false]`; `--pbc nope` silently uses no periodicity. This affects
every command that accepts `--cell-cubic`, including selections, measurements,
exports, and JSON summaries. Reject anything except a non-repeating subset of
`abc`.

Confidence: verified static.

### 2. Valid VASP negative scale factors are interpreted correctly only by POSCAR

`io/pipelines/src/formats/vasp/poscar.rs:91-109` correctly recognizes a
negative scale as a target cell volume and derives a positive cubic scale.
The sibling CHGCAR, XDATCAR, and volumetric paths instead multiply lattice
vectors by the negative literal:

```rust
// chgcar.rs:61-63
let a = scale_vec3(a, scale);

// xdatcar.rs:66-68
let a = scale_v(a, scale);

// volumetric.rs:127-129
*component *= scale;
```

For a legal `-V` scale line, CHGCAR geometry/density, XDATCAR frames, and VASP
volumetric grids are mirrored and scaled by `V`, rather than by
`(|V| / |det(lattice)|)^(1/3)`. Surfaces can then be registered against the
wrong geometry. Extract the POSCAR normalization into a shared VASP header
helper and use it in all four parsers.

Confidence: verified static.

### 3. Native and WASM CUBE parsers accept non-finite physical values

The native CUBE parser uses raw float parsing for origin, voxel vectors, atom
coordinates, and grid values:

```rust
// io/pipelines/src/formats/cube/parser/grid.rs:18-24
let value: f32 = token.parse().map_err(|_| {
    IoPipelineError::parse(path, format!("Invalid grid value '{}'", token))
})?;
flat_values.push(value);
```

`f32`/`f64` parsing accepts `NaN` and infinity. The WASM CUBE parser repeats
the same grid-value behavior at
`viewer/wasm/src/wasm/volumetric/parse.rs:114-122`. Comparisons used for ranges
and marching cubes treat `NaN` as neither less nor greater, so corrupted or
diverged CUBE files can load successfully with malformed coordinates or
holey/incorrect isosurfaces. The automatic VASP volumetric companion parser
also uses raw float parsing at `io/pipelines/src/formats/vasp/volumetric.rs:111-114`

Use the existing finite-value policy at every physical-value boundary before
narrowing to `f32`.

Confidence: verified static.

### 4. `info --json` silently omits program-task summaries for remote and stdin QC inputs

`handle_info` correctly loads the scene through configured services, which
materialize stdin and use the configured data source:

```rust
// automation/cli/src/handlers/commands/info.rs:26-34
let graph = load_scene_with_cell_options(services, source, ...)?;
let summary = build_info_summary(source, &graph)?;
```

`build_info_summary` then performs a second, direct canonical load from the
original path and discards any error:

```rust
// automation/cli/src/handlers/reports.rs:155-169
match load_canonical_document_with_options(source, ...) {
    Ok(doc) => { ... }
    Err(_) => (None, Vec::new()),
}
```

For `source == "-"`, the first load uses the temp file created by
`resolve_source_path` (`handlers/util.rs:28-45`), but the second load receives
the literal `-`. For `--remote`, the first load uses the SFTP data source while
plausible JSON with empty `program_tasks` and `molpro` fields.

Derive task summaries from the already-loaded result, or surface the secondary
load failure rather than returning an empty summary.

Confidence: verified static.

### 5. WASM scene attributes are last-completion-wins, not last-request-wins

Changing `<orbitron-viewer scene>` starts an asynchronous load with no epoch,

```ts
// viewer/wasm/ts/src/orbitron-viewer.ts:553-576
const load = isInlineJson(value)
  ? loadSceneFromJSON(value)
  : loadSceneFromUrl(value);
load.then(() => this.dispatchEvent(new CustomEvent("scene-loaded", ...)));
```

`loadSceneFromUrl` installs the fetched payload immediately at
`viewer/wasm/ts/src/scene-loader.ts:11-30`. Set `scene=A`, then `scene=B`;
when B finishes first and A finishes later, A overwrites the canvas. The user
sees the wrong molecule and receives a successful `scene-loaded` event for A.

Stamp each request with an incrementing generation and discard stale
completions (or abort the preceding fetch).

Confidence: verified static.

## Tier 2: wrong but visible, or visible data loss

### 6. Cartoon cache keys omit manual and representation-group color overrides

`CartoonSettings.color_overrides` has `#[serde(skip)]` at
`viewer/core/src/ribbon/settings.rs:105-113`. The cache key serializes the
settings directly:

```rust
// ui/shell/src/viewer_loop/runtime/redraw/scene/cartoon.rs:12-29
if let Ok(bytes) = bincode::serialize(settings) {
    hasher.update(&bytes);
}
```

The same redraw path inserts effective group colors into that skipped map at
`:61` and `:182-255`; the ribbon sweep reads it when assigning colors. Apply a
manual residue color, import colors, or change a colored representation group:
at `:72-77`. The cartoon keeps its previous colors until an unrelated cache-key
input changes.

Hash the effective override map separately, in a deterministic order.

Confidence: verified static.

### 7. Session restore drops view settings and can retain the prior session's values

Session save persists only `cartoon_color_mode` and `ring_mode` from the
cartoon/nucleic settings (`ui/shell/src/session/save.rs:94-112`).
`SessionState` has no snapshot fields for full `CartoonSettings`,
`NucleicSettings`, diagram state, biological-assembly controls, or manual
per-residue colors (`session/types.rs:45-125`). This conflicts with the
`color_overrides` comment, which says UI-side persistence is the caller's
responsibility.

Restore mutates selected fields but never resets the omitted ones
(`session/restore.rs:45-74`). Save a session with a changed cartoon geometry,
open it after another session used those controls: it either resets to defaults
or inherits the prior in-process values.

Make session view state an explicit, complete snapshot, or reset every omitted
view field before applying saved state.

Confidence: verified static.

### 8. `info --json` accepts and ignores Molpro selectors

The JSON path serializes `InfoSummary` before `--molpro-task` or
`--molpro-kind` are parsed or applied:

```rust
// automation/cli/src/handlers/commands/info.rs:36-47
if json {
    let payload = serde_json::to_string_pretty(&summary)?;
    println!("{payload}");
} else {
    let ... = parse_cli_task_kind(label)?;
    print_human_summary(&summary, molpro_task, kind_filter, kind_label)?;
}
```

`orbitron info molpro.out --json --molpro-task 999` returns all tasks;
`--molpro-kind typo` also succeeds instead of rejecting the invalid selector.
Automation gets a valid but wrong scope.

Validate selectors before branching on output format and define/apply their JSON
semantics, or reject them for JSON explicitly.

Confidence: verified static.

### 9. Forced canonical import/export destroys the old destination before a replacement exists

`canonical export --force` removes the old bundle before creating/writing the
new manifest (`automation/cli/src/handlers/commands/canonical.rs:39-90`).
`canonical import --force` likewise removes the output before `fs::copy`
(`:351-370`). A full disk, permission error, interrupted copy, attachment-copy
failure, or cache-hydration failure leaves a partial bundle or no destination.

Write to a sibling temporary file/directory, validate it, then atomically rename
over the old destination.

Confidence: verified static.

### 10. WASM attachment fetch failure is swallowed after its delta operation is removed

`viewer/wasm/app.js:1986-2015` removes `attachment.put_url` operations before
fetching their payloads. The surrounding catch intentionally ignores all
errors as potential non-JSON payloads:

```js
} catch (err) {
  // Ignore JSON parsing errors for non-JSON payloads.
}
```

If the attachment URL fails, the attachment operation stays removed and the
remaining delta applies without a warning or delta failure. This silently loses
the attachment.

Only suppress JSON parsing failure; report attachment-fetch errors and preserve
or fail the corresponding operation.

Confidence: verified static.

### 11. Reconnecting an existing WASM custom element leaves its render loop stopped

`disconnectedCallback` stops the loop, but `connectedCallback` permanently
returns after the first initialization:

```ts
// viewer/wasm/ts/src/orbitron-viewer.ts:154-178
connectedCallback(): void {
  if (this.initialized) return;
  this.initialized = true;
  this.initialize().catch(...);
}
disconnectedCallback(): void {
  this.stopLoop();
  ...
}
```

Moving an existing `<orbitron-viewer>` node in a framework, or removing and
reattaching it, retains the scene but never restarts rendering. Either reset
initialization state and reconstruct resources, or keep resources and restart
the loop/input/resize handling on reconnection.

Confidence: verified static.

### 12. Renderer failures do not reach the documented component event channel

`viewer/wasm/src/wasm/render/renderer_ops.rs:82-93` says a `scene-error` event
fires when renderer initialization fails, but it only logs to the console and
sets `data-render-error`. `lifecycle/lifecycle_tick.rs:57-59` also consumes
render errors by setting that attribute. The TypeScript component emits
`render-error` only when `getWasm().tick()` throws
(`ts/src/orbitron-viewer.ts:512-523`), which these handled failures do not do.

An embedded host can retain a blank canvas after device loss or unavailable GPU
without receiving the documented event. Bridge render status to the component's
public event API, or correct the API documentation.

Confidence: verified static.

## Test safety-net gaps

These do not prove present runtime behavior is wrong. They prove regressions in
scientific output can return without a test failure.

### 13. FCHK Mulliken-charge test permits materially wrong atom charges

`io/pipelines/tests/gaussian_fchk.rs:41-62` asserts only that each net charge
is within five electrons of zero:

```rust
assert!(net.abs() < 5.0, ...);
```

Reversed sign, atom-order shift, or bad atomic-number conversion can pass while
coloring atoms with wrong charges. For
`gaussian/cubes/water_orbitals.fchk`, the fixture pins the three charges at
`-0.289140816, 0.144570408, 0.144570408`
(`tests/fixtures/gaussian/cubes/water_orbitals.fchk:525-526`). Assert those in
atom order with a tolerance appropriate for the parser.

Confidence: verified.

### 14. QE SCF-energy test permits a missing or wrong converged energy

`io/pipelines/tests/qe/scf.rs:39-48` makes the energy optional and checks only
that a present value is finite. The benzene fixture contains the exact converged
line `! total energy = 14.55169097 Ry` at
`tests/corpus/qe/benzene/scf.out:348`. Require
`scf_total_energy_ry` and pin that value. The current test accepts a missing
field, an SCF-iteration value, or the wrong numeric token.

Confidence: verified.

### 15. The volumetric indexing contract is internally inconsistent

`VolumetricData::get` and its slice test use x-fastest storage:

```rust
// io/pipelines/src/formats/cube/data_structures.rs:63-66
let idx = ix + nx * (iy + ny * iz);
```

But the CUBE marching-cubes reader documents and uses x-outermost storage
(`cube/marching_cubes/voxel.rs:21-29`), and the orbital-grid generator emits
that same `ix * ny * nz + iy * nz + iz` layout
(`core/services/src/analysis/orbitals/eval/grid.rs:30-46`). The current
`volume_slice_trilinear_recovers_grid_values` test constructs an x-fastest
synthetic grid, so it confirms the conflicting helper instead of the producer
contract.

Use one layout everywhere. Add a non-cubic `[2, 3, 4]` regression built in
producer order and assert coordinate-specific samples. Static analysis verifies
tab normally evaluates basis functions directly.

Confidence: verified internal contract; end-user reachability unverified.

## Verified negative results

- The assigned WASM `RENDER_STATE` concern is **confirmed safe**. The
  `delta_ops.rs:57-61` mutable borrow passes `&mut WasmRenderState` into
  `refresh_scene_with_selection`; its full body
  (`render/render_state.rs:5-76`) contains no `RENDER_STATE.with`, JS callback,
  or async suspension. No re-entrant borrow path was found.
- Temp-to-canonical UI synchronization does copy cartoon/nucleic settings,
  representation groups, and diagram state. The cartoon finding is a cache-key
  defect after that sync, not a dropped sync field.
- The Python bridge's checked conversion paths, returned Python-owned buffers,
  and GIL release around long operations were inspected without a confirmed
  defect.
- Main QE input coordinate tests pin Bohr, explicit-cell, and fractional
  behavior exactly. Shared Bohr/angstrom and Hartree/eV constants are also
  correctly defined and tested.

## Bottom line

The new findings are localized rather than architectural: reject malformed PBC
flags, share VASP scale normalization, reject non-finite volumetric values, and
stop `info --json` from manufacturing incomplete summaries. Those four fixes
address the highest-risk silent-science paths. The scan also validated that
the most suspicious WASM `RefCell` path is safe, so it did not merely pad the
report with guesses.
