# Python science / ML project

For computational chemistry, data analysis, and ML work. uv-managed, src
layout, pytest, ruff.

## Init

```bash
uv init --name <name> --package    # creates pyproject.toml + src/<pkg>/
uv add --dev pytest ruff
```

## Layout

```
<name>/
├── pyproject.toml      project metadata, deps, ruff + pytest config
├── README.md
├── CLAUDE.md
├── src/<pkg>/          the package (underscored name)
│   └── __init__.py
├── tests/
├── scripts/            one-off run/analysis entry points (only when needed)
└── data/               gitignored; document provenance in README instead
```

## Conventions

- `uv run pytest` and `uvx ruff check` must pass from a fresh clone.
- Pin nothing by hand; `uv.lock` is the lockfile and is committed.
- Numerical deps (numpy, scipy, pandas, ase, rdkit…) added when first used,
  not preemptively.
- `data/` and anything large stays out of git. Note where data comes from
  and how to regenerate it in the README.
- Notebooks (if any) live in `notebooks/`, are exploratory only, and never
  become load-bearing — promote real logic into `src/`.

## pyproject extras

```toml
[tool.ruff]
line-length = 100

[tool.pytest.ini_options]
testpaths = ["tests"]
```
