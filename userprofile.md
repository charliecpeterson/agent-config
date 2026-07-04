# User profile

Stable information about who I am and how I work. Loaded on every
session via `CLAUDE.md`. Update when something genuinely changes:
role, institution, a new domain of deep expertise, a major shift in
working pattern. For per-project state, the project's own files
(`PROJECT_PLAN.md`, README, code) are the source of truth. For
conversational facts and corrections, the auto-memory system handles
it. This file is the load-bearing personal context everything else
sits on top of.

## Role

Senior HPC system administrator at UCLA. PhD computational chemist.
Research focus at the intersection of high-performance computing,
artificial intelligence / machine learning, and computational
chemistry — currently aimed at nuclear forensics and separation
chemistry. Also builds personal AI tooling: MCP servers, chat UIs,
terminal assistants, editor extensions.

Multi-role in practice: chemist + data scientist + HPC sysadmin +
tool builder, often inside the same conversation.

## Defer to me when

Domains where I have deep expertise. Defer to my judgment on the
science and methodology. Still push back on engineering, UX, and
code-quality choices — just not on the domain content.

- Computational chemistry: electronic structure, SCF, orbital
  methods, DFT-adjacent workflows.
- Nuclear forensics and separation chemistry.
- Metal complex chemistry: stability constants, ligand design,
  speciation.
- HPC system administration: SLURM and other schedulers, scientific
  Python deployment on shared clusters, containerization
  (Singularity / Apptainer, Docker), GPU and accelerator stacks.
- Running scientific workloads on HPC: queue strategy, MPI / hybrid
  parallelism, module systems, environment management on clusters.

## Treat as joint when

Areas I work in regularly but am not the world expert in. Propose
ideas, but don't assume I have the definitive answer. Cross-check
against current sources when stakes are high (model choice, library
selection, architectural decisions).

- General machine learning engineering. I use it; I'm not a
  specialist in ML methodology. Surface current best practice with
  citations.
- Chemistry-aware ML (graph nets, equivariant networks, message
  passing, descriptors for molecules and complexes). The
  intersection moves fast; check current literature.
- MCP server design and AI tool integration patterns. I build a
  lot of these, but the conventions are still evolving.
- Personal tooling in Rust, Go, and TypeScript (CLIs, chat UIs,
  editor extensions). Working knowledge; not language-specialist
  level.
- Academic paper writing: structure, venues, reviewer expectations.

## Push back when

Outside my expertise. Don't assume my framing is right. Surface
alternatives and tradeoffs explicitly. Reach for live sources
(`WebSearch` / `WebFetch`) before recommending. Explain more, not
less.

- UI / UX design: visual design, interaction design, accessibility,
  design systems.
- Web frontend ecosystem: bundlers, CSS frameworks, SSR strategies,
  browser quirks. I touch this for personal tools but I am not
  current.
- Biology and biochemistry. Adjacent to chemistry; distinct
  expertise.
- Business and product strategy, marketing, pricing.
- Production SaaS / cloud-native DevOps outside the HPC context:
  Kubernetes orchestration at scale, service meshes, multi-region
  cloud architecture.
- Mobile development (iOS, Android).
- Embedded systems and firmware.

If a conversation drifts into these areas, slow down, name the
shift, and treat my suggestions as starting points rather than
constraints.

## Compute & access

- The machine fleet — which box this session is on (specs, role,
  scheduler) and what else is available — is in the **Machines**
  section of this config, rendered per machine from the repo's
  `machines/` profiles. Read it rather than asking, and suggest a
  better-suited machine when a task clearly fits one.
- Compute is rarely the bottleneck. Data coverage, label quality,
  and method validity are the more common limits.

## How I work

- **Solo across most personal repos.** Operational surface area
  matters: a tool only I maintain has to be boring to keep alive.
- **Polyglot at the tooling layer.** Python for science and ML.
  Rust and Go for CLI tools and small services. TypeScript for
  UIs and editor extensions. Pick the boring choice within each
  language.
- **Integration shape: MCP servers.** Recent work leans heavily on
  MCP as the connective tissue between AI assistants and external
  systems (chemistry tools, EDA workflows, Office apps, image gen,
  documentation, more).
- **Builds AI tooling alongside science.** Chat UIs, terminal
  assistants, JupyterLab extensions, editor integrations. The line
  between "research tool" and "personal infrastructure" is thin.
- **Prefers durable tooling for things meant to last.** Willing to
  experiment for one-offs; conservative for anything I'll still be
  maintaining in two years.
- **Multi-role conversations.** A single question may need a
  chemist answer *and* a sysadmin answer *and* a code-quality
  answer. Don't assume one frame.

## References

- Profile: <https://charlespeterson.dev/>
- Code: <https://github.com/charliecpeterson>
