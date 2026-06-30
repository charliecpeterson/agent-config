# doc lint — the always-on layer

The cheap, deterministic, no-LLM half of `doc-sync`. It catches the
highest-frequency doc drift on every commit, for free:

1. **Link/path integrity** — dead local links and missing referenced files,
   via [`lychee`](https://github.com/lycheeverse/lychee) (offline by default;
   `DOCS_LINT_WEB=1` also checks URLs).
2. **Denylist** — tokens that must never reappear in the docs once removed from
   the code (old env vars, deleted crates, dead filenames), from a `.docs-lint`
   file at the repo root.

The LLM `doc-sync` audit is the periodic, semantic counterpart — run it before
a release or after a big change. This layer is what keeps the docs from
re-drifting between those runs.

## Install into a repo

```bash
cp check-docs.sh   <repo>/scripts/check-docs.sh   && chmod +x <repo>/scripts/check-docs.sh
cp docs-lint.yml   <repo>/.github/workflows/docs-lint.yml
cp docs-lint.example <repo>/.docs-lint            # then edit: seed your denylist
```

Run it locally any time: `bash scripts/check-docs.sh`. Optional pre-commit hook:

```bash
echo 'bash scripts/check-docs.sh' >> <repo>/.git/hooks/pre-commit
chmod +x <repo>/.git/hooks/pre-commit
```

## Maintaining the denylist

When you delete a thing — an env var, a crate, a script, a doc path — add its
name to `.docs-lint`. That single line means a stale doc naming it again fails
CI instead of rotting unnoticed. This is the durable record of "things that no
longer exist," and it's what makes the cheap check keep paying off.
