# TypeScript tool project

For UIs, editor extensions, and node-based tooling.

## Init

```bash
npm init -y
npm install --save-dev typescript @types/node vitest
npx tsc --init --strict --module nodenext --target es2022 --outDir dist
```

## Layout

```
<name>/
├── package.json        scripts: build (tsc), test (vitest), start
├── tsconfig.json       strict; nodenext modules
├── README.md
├── CLAUDE.md
├── src/
│   └── index.ts
└── tests/
```

## Conventions

- Strict TypeScript, no `any` escapes without a comment saying why.
- Plain `tsc` for building; reach for a bundler only when a deployment
  target demands one (browser extension, single-file distribution).
- `vitest` for tests.
- Few dependencies, checked before adding: prefer node built-ins
  (`node:fs`, `node:path`, fetch) over micro-packages.
- For an editor extension or UI, start from the host's official scaffold
  (e.g. `yo code` for VS Code) instead of this layout — keep these
  conventions, take their structure.
