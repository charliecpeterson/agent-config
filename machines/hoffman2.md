- UCLA OARC Hoffman2, the campus shared HPC cluster where Charlie is a
  sysadmin.
- Slurm scheduler. Ground partition, QOS, account, and module answers in live
  cluster state (`sinfo`, `sacct`, `scontrol`, `sacctmgr`, `module`, and local
  docs) rather than memory.
- Login nodes are for editing, submission, diagnostics, and sysadmin work only;
  run compute through Slurm.
- Home lives under `/u/home`; large files and job output belong under
  `/u/scratch`.
- When available on Hoffman2, prefer the local `h2mcp` server for cluster KB,
  queue, job, quota, module, and Hoffman2-specific Slurm tooling. Treat it as
  cluster-local infrastructure, not a portable MCP to install on every machine.
