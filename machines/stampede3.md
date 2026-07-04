- Stampede3 at TACC, allocated via NSF ACCESS. Shared HPC cluster.
- Slurm scheduler; MPI launches use `ibrun`, never mpirun. The
  `stampede3-submit` and `stampede3-debug` skills carry the queue tables
  and cluster-specific failure modes — use them.
- Big files and job output go to `$SCRATCH` (purged, but large), not
  `$HOME` (small quota). Login nodes are for editing and submission only;
  no heavy compute there.
- The right target for multi-node MPI, large CPU jobs, and cluster-scale
  GPU work (H100/PVC partitions).
