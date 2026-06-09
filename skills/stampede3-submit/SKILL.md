---
name: stampede3-submit
description: "Build a Slurm sbatch script for Stampede3 (TACC). Use when the user on Stampede3 asks to \"run X on the cluster\", \"submit a job\", \"make a batch script\", or \"request N nodes/GPUs\". Covers serial, MPI, OpenMP, hybrid, and GPU (H100/PVC) workloads with the correct partition, ibrun launch, and module setup. For diagnosing a job that already failed, use stampede3-debug."
---

# stampede3-submit — Stampede3 sbatch script builder

## Queue reference

| Queue | Node | Cores/node | RAM/node | Max nodes/job | Max wall | Max jobs/user | SU/node-hr |
|-------|------|-----------|----------|---------------|----------|---------------|------------|
| `skx` | Skylake | 48 | 192 GB | 256 | 48 h | 40 | 1 |
| `skx-dev` | Skylake | 48 | 192 GB | 16 | 2 h | 2 | 1 |
| `icx` | Ice Lake | 80 | 256 GB | 32 | 48 h | 12 | 1.5 |
| `spr` | Sapphire Rapids | 112 | 128 GB HBM2e | 32 | 48 h | 24 | 2 |
| `nvdimm` | Ice Lake large-mem | 80 | 4 TB | 1 | 48 h | 2 | 4 |
| `h100` | 4× H100 SXM5 (96 GB/GPU) | 96 | 1 TB | 4 | 48 h | 2 | 4 |
| `pvc` | 4× Max 1550 (124 GB/GPU) | 96 | 1 TB | 4 | 48 h | 2 | 3 |

## Workflow

1. **Gather requirements** before writing anything. If the user hasn't said, ask (one short batch of questions):
   - What's the workload? (which executable, MPI? OpenMP? GPU? serial?)
   - How many nodes / ranks / threads / GPUs?
   - Estimated wall time?
   - Which allocation/project? (only if user has multiple — check `/usr/local/etc/taccinfo`)
   - Inputs/outputs path — should I `cd $SCRATCH/<jobdir>` first?

2. **Pick the partition** with this decision flow, using the queue table above for cores/RAM/limits.

   **Step 2a — is this a test or a production run?**
   - Test / debugging / first time running the script → `skx-dev` (2 h max, 16 nodes max). Always start here. Faster queue, same SKX hardware.

   **Step 2b — GPU or CPU?**
   - NVIDIA CUDA / PyTorch / TensorFlow / JAX → `h100` (4× H100 SXM5, 96 GB/GPU, NDR IB).
   - Intel oneAPI / SYCL / DPC++ → `pvc` (4× Max 1550, 124 GB/GPU).
   - No GPU → continue to 2c.

   **Step 2c — does one rank need > 256 GB RAM?**
   - Yes → `nvdimm` (single node, 4 TB, 80 cores). Note: only 3 nodes total in this queue and only 1 per job — be sure you actually need it.
   - No → continue to 2d.

   **Step 2d — pick the CPU queue by workload character:**
   | Workload | Recommended | Reason |
   |----------|-------------|--------|
   | Memory-bandwidth bound (sparse linalg, stencil, FFT, CFD) | `spr` | HBM2e gives 3.5× per-core bandwidth vs SKX |
   | Memory-capacity bound (RAM/core matters more than BW) | `icx` | 256 GB / 80 cores = 3.2 GB/core (vs SPR's ~1.1) |
   | Compute-bound, moderate memory, large job (>32 nodes) | `skx` | Only queue that scales past 32 nodes (up to 256) |
   | Legacy / well-validated SKX binary | `skx` | No re-build risk, 1 SU/node-hr (cheapest) |

   **Tie-break rules:**
   - Need > 32 nodes? `skx` is your only option for CPU.
   - SU budget tight? Cheaper-first: `skx` (1) < `icx` (1.5) < `spr` (2) < `pvc` (3) < `h100` = `nvdimm` (4).
   - Don't pick a queue just because it's "the newest" — match it to the workload's bottleneck.

   **SPR memory trap:** SPR's 128 GB HBM2e is *per node*, not per core. With 112 cores, that's ~1.1 GB/core. A code that runs fine on SKX (4 GB/core) or ICX (3.2 GB/core) may OOM on SPR. Either reduce ranks/node or pick `icx`.

3. **Compute `-N`/`-n`/threads** before writing:
   - Pure MPI: `-n = N × cores_per_node` (SKX 48, ICX 80, SPR 112, H100/PVC 96).
   - Pure OpenMP: `-N 1 -n 1` and set `OMP_NUM_THREADS`.
   - Hybrid: `-n = N × ranks_per_node` and `OMP_NUM_THREADS = cores_per_node / ranks_per_node`. Document the math in a one-line comment.
   - GPU: `-n 1` per node is fine; one process per GPU is typical (so `-n 4` for 4 GPUs).

4. **Write the script** to a file the user names (default `job.slurm` in CWD). Always include:
   - `#!/bin/bash` shebang
   - `#SBATCH` block in the order: `-J -N -n [-ntasks-per-node] -t -p [-A] -o`
   - `module reset` then explicit `module load` lines — never rely on the user's `.bashrc`
   - `cd` to the run directory explicitly (don't rely on submit CWD if files live elsewhere)
   - `ibrun` for MPI; bare executable for serial/OpenMP; `./prog` with `CUDA_VISIBLE_DEVICES`/`ZE_AFFINITY_MASK` only if asked

5. **Write the script and hand it off.** Claude cannot submit jobs on Stampede3 from inside an idev session — `sbatch` is blocked from compute by Slurm policy, and `ssh login*` requires MFA. So the workflow is: write the file, tell the user where it is and what it'll cost, and stop.

   Hand-off message template:
   > Wrote `job.slurm`. Submit from a login-node terminal with `sbatch job.slurm`. Estimated cost: `N × T × rate` SUs.

6. After the user submits and reports back with a JobID, Claude can take over again from inside idev:
   - `squeue -j <jobid>` for queue state
   - `sacct -j <jobid> --format=...` for accounting
   - Reading `slurm-<jobid>.out` once the job runs
   - Hand off to the `stampede3-debug` skill if it failed

   These all work fine from compute — only `sbatch` is blocked.

## Hard "don't" list

- Don't emit `--mem` (unsupported on Stampede3).
- Don't emit `--export=...` (breaks env propagation).
- Don't use `mpirun`/`mpiexec`/`srun` to launch MPI — always `ibrun`.
- Don't use `lfs setstripe` on `$HOME` or `$SCRATCH` (VAST, not Lustre). `$WORK` is Lustre.
- Don't request more nodes than the queue allows (see the queue table).
- Don't pick max wall time "to be safe" — shorter jobs schedule faster and the 15-min minimum still applies.

## Templates

### Serial / single-threaded
```bash
#!/bin/bash
#SBATCH -J serial
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -t 02:00:00
#SBATCH -p skx
#SBATCH -o slurm-%j.out

module reset
module load intel/24.0

cd $SCRATCH/myrun
./myprogram input.txt
```

### Pure MPI (SPR example: 4 nodes × 112 ranks = 448)
```bash
#!/bin/bash
#SBATCH -J mpi-spr
#SBATCH -N 4
#SBATCH -n 448
#SBATCH -t 04:00:00
#SBATCH -p spr
#SBATCH -o slurm-%j.out

module reset
module load intel/24.0 impi/21.11

cd $SCRATCH/myrun
ibrun ./mpi_program
```

### Pure OpenMP (single SKX node, 48 threads)
```bash
#!/bin/bash
#SBATCH -J omp
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -t 02:00:00
#SBATCH -p skx
#SBATCH -o slurm-%j.out

module reset
module load intel/24.0

export OMP_NUM_THREADS=48
export OMP_PLACES=cores
export OMP_PROC_BIND=close

cd $SCRATCH/myrun
./omp_program
```

### Hybrid MPI + OpenMP (2 ICX nodes, 4 ranks/node × 20 threads = 80 cores/node)
```bash
#!/bin/bash
#SBATCH -J hybrid
#SBATCH -N 2
#SBATCH -n 8
#SBATCH --ntasks-per-node=4
#SBATCH -t 03:00:00
#SBATCH -p icx
#SBATCH -o slurm-%j.out

module reset
module load intel/24.0 impi/21.11

# 4 ranks × 20 threads = 80 cores per ICX node
export OMP_NUM_THREADS=20
export OMP_PLACES=cores
export OMP_PROC_BIND=close

cd $SCRATCH/myrun
ibrun ./hybrid_program
```

### H100 GPU (1 node, 4 H100s, one process per GPU)
```bash
#!/bin/bash
#SBATCH -J h100
#SBATCH -N 1
#SBATCH -n 4
#SBATCH -t 02:00:00
#SBATCH -p h100
#SBATCH -o slurm-%j.out

module reset
module load cuda

cd $SCRATCH/myrun
ibrun ./gpu_program     # or: python train.py for single-process multi-GPU
```

### Single-process multi-GPU (PyTorch / TF on one H100 node)
```bash
#!/bin/bash
#SBATCH -J torch
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -t 04:00:00
#SBATCH -p h100
#SBATCH -o slurm-%j.out

module reset
module load cuda python3

source $WORK/venvs/torch/bin/activate
cd $SCRATCH/myrun
python train.py        # framework sees all 4 GPUs via CUDA_VISIBLE_DEVICES
```

### PVC GPU (Intel Max 1550, SYCL)
```bash
#!/bin/bash
#SBATCH -J pvc
#SBATCH -N 1
#SBATCH -n 4
#SBATCH -t 02:00:00
#SBATCH -p pvc
#SBATCH -o slurm-%j.out

module reset
module load intel oneapi

cd $SCRATCH/myrun
ibrun ./sycl_program
```

### Large memory (NVDIMM, 4 TB single node)
```bash
#!/bin/bash
#SBATCH -J bigmem
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -t 12:00:00
#SBATCH -p nvdimm
#SBATCH -o slurm-%j.out

module reset
module load intel/24.0

cd $SCRATCH/myrun
./memory_hog        # can use up to ~4 TB
```

### Job array (parameter sweep, throttled to 20 concurrent)
```bash
#!/bin/bash
#SBATCH -J sweep
#SBATCH -N 1
#SBATCH -n 1
#SBATCH -t 01:00:00
#SBATCH -p skx
#SBATCH -a 1-100%20
#SBATCH -o slurm-%A_%a.out

module reset
module load intel/24.0

cd $SCRATCH/sweep
./run.sh input_${SLURM_ARRAY_TASK_ID}.dat
```

### Job dependency (B starts after A succeeds)
```bash
JID_A=$(sbatch --parsable a.slurm)
sbatch --dependency=afterok:$JID_A b.slurm
```

## After submitting

Report back to the user:
- The JobID
- `squeue -j <id>` snapshot (state, reason, ETA if running)
- Where stdout/stderr will land
- The estimated SU cost: `nodes × max_wall_hours × rate` (note: actual bill is by elapsed seconds, 15-min minimum)

## When the user wants interactive instead

If they're iterating fast, suggest `idev` instead of repeated `sbatch`:
```bash
idev -p skx-dev -N 1 -n 48 -t 01:00:00
# drops you onto a compute node; run ibrun / programs as usual; `exit` to release
```
