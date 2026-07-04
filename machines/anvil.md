- Anvil at Purdue RCAC, allocated via NSF ACCESS. Shared HPC cluster.
- Slurm scheduler. No dedicated skills for it yet (the Stampede3 pair is
  the pattern; an Anvil pair is planned) — ground queue/partition answers
  in live `sinfo`/`man sbatch` output, not memory.
- Big files go to `$SCRATCH`, not `$HOME`. Login nodes are for editing
  and submission only.
- Overflow capacity when Stampede3 queues are long, and the alternate GPU
  allocation.
