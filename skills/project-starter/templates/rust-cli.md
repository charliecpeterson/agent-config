# Rust CLI project

For command-line tools and small services meant to be boring to maintain.

## Init

```bash
cargo new <name>
cargo add clap --features derive
cargo add anyhow
```

## Layout

```
<name>/
├── Cargo.toml
├── README.md
├── CLAUDE.md
└── src/
    └── main.rs         everything starts here; split only at real seams
```

## Conventions

- Single `main.rs` until it genuinely outgrows it (~700 lines or a second
  clear responsibility) — then split into modules, not a workspace.
- `clap` derive for args, `anyhow` for error plumbing in the binary. Add
  `thiserror` only if/when a library crate splits out.
- `cargo fmt` and `cargo clippy -- -D warnings` clean before any commit.
- Async (`tokio`) only when something actually blocks on I/O concurrency;
  most CLIs don't need it.
- Tests: unit tests in-module (`#[cfg(test)]`), integration tests in
  `tests/` once there's a stable surface to test.
