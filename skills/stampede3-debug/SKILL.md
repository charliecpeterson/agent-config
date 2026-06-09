---
name: stampede3-debug
description: "Diagnose a failed, stuck, slow, or pending Slurm job on Stampede3 (TACC). Use when the user reports a JobID that crashed, exited early, ran out of memory/time, \"is stuck in queue\", produced unexpected output, or was killed. Walks through sacct, output logs, partition state, and Stampede3-specific failure modes (ibrun misuse, scratch purge, AVX mismatch, SPR HBM OOM). To write a new job script, use stampede3-submit."
---

# stampede3-debug — diagnose Stampede3 Slurm jobs

## Triage workflow

Ask for one of: a **JobID**, a **stderr/stdout file**, or the **submitted script + symptom**. Then run a fixed sequence:

### 1. Pending? Find out why.
```bash
squeue -j <jobid> -o "%i %P %T %r %S %L"
```
`%r` (Reason) is the answer. Common values:
- `Priority` / `Resources` — normal, just waiting. Estimated start: `--start` flag.
- `QOSMaxJobsPerUserLimit` — too many of your jobs queued; check `qlimits`.
- `AssocGrpCPUMinutesLimit` — allocation is out of SUs. Confirm with `/usr/local/etc/taccinfo`.
- `PartitionNodeLimit` — you asked for more nodes than the queue allows (see the queue table in the `stampede3-submit` skill).
- `ReqNodeNotAvail` — usually a maintenance reservation; check `sinfo -R` and the TACC user news.
- `Dependency` — waiting on another job (`scontrol show job <id>` to see which).

### 2. Completed/failed? Pull sacct.
```bash
sacct -j <jobid> --format=JobID,JobName,State,ExitCode,Elapsed,Timelimit,MaxRSS,ReqMem,NodeList,Partition,Start,End
```
Decode `State` + `ExitCode`:
- `COMPLETED` with `0:0` — clean exit.
- `TIMEOUT` — hit `-t` wall. Resubmit with longer time or checkpoint.
- `OUT_OF_MEMORY` / OOM in dmesg — see §4.
- `CANCELLED by <uid>` — user or admin scancel.
- `NODE_FAIL` — hardware. Resubmit; report to TACC if repeated on same node.
- `FAILED 1:0` — program returned non-zero. Read stderr.
- `FAILED 0:9` / `0:15` — killed by SIGKILL/SIGTERM (usually OOM or wall).
- `FAILED 0:53` — often segfault from MPI launch issues.

### 3. Read the logs (in order).
```bash
ls -la slurm-<jobid>*.out
tail -100 slurm-<jobid>.out
```
Grep for these red flags:
- `slurmstepd: error: Exceeded job memory limit` → OOM.
- `srun: error` or `MPI_ABORT` → MPI launch / rank failure.
- `Illegal instruction` → AVX-512 binary running on wrong arch (e.g., SPR build on SKX).
- `Disk quota exceeded` → `$HOME` or `$WORK` is full. Check `/usr/local/etc/tacc_quota`.
- `No such file or directory` referencing `$SCRATCH/...` → purged. Files older than 10-day atime are removed.
- `command not found: ibrun` → submitted from a context without TACC modules; add `module reset` to script.
- `Lmod has detected the following error` → module conflict; rebuild env with `module reset && module load <fresh>`.

### 4. Confirm OOM specifically.
```bash
sacct -j <jobid> --format=JobID,MaxRSS,MaxVMSize,ReqMem,NodeList
```
- `MaxRSS` near node RAM (SKX 192 GB, ICX 256 GB, SPR 128 GB HBM, NVDIMM 4 TB, GPU nodes 1 TB) means OOM.
- **SPR trap**: only 128 GB HBM/node. Codes that fit on SKX/ICX may OOM on SPR. Either fewer ranks per node, or move to `icx`/`nvdimm`.

### 5. Wall time / efficiency.
```bash
sacct -j <jobid> --format=JobID,Elapsed,Timelimit,CPUTime,TotalCPU
seff <jobid>     # if available
```
- `Elapsed` ≈ `Timelimit` and state `TIMEOUT` → underestimated wall. Bump `-t` next run.
- `CPUTime`/`TotalCPU` ≪ `Elapsed × ncpus` → poor parallel scaling or wrong launcher (using `mpirun` instead of `ibrun`, or no MPI at all). Re-check the script.

### 6. Node-specific failure?
```bash
sacct -j <jobid> --format=JobID,NodeList,State
sinfo -n <node> -o "%n %T %E"
```
If the same node ID shows up across multiple failed jobs, mention it to the user and suggest a ticket to TACC.

## Stampede3-specific gotchas (check these first)

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| MPI ranks not laid out across nodes | Used `mpirun`/`srun` instead of `ibrun` | Replace with `ibrun` |
| `Illegal instruction` | Binary built with `-xSAPPHIRERAPIDS` running on SKX/ICX | Rebuild with `-axCORE-AVX512,ICELAKE-SERVER,SAPPHIRERAPIDS` or match build host to run queue |
| Job script errors `command not found` for things in your `.bashrc` | Slurm strips most environment; `--export=...` interferes | Put `module load` lines in the script, drop `--export` |
| Files vanished between jobs on `$SCRATCH` | 10-day atime purge | Move long-lived data to `$WORK` |
| Disk-full on `$HOME` mid-run | Logs/checkpoints to `$HOME` (15 GB cap) | Redirect output to `$SCRATCH` |
| H100 job sees 0 GPUs | `module load cuda` missing or container started before module | Add `module load cuda` to script |
| PVC job: SYCL device not found | Missing `module load oneapi` | Load oneapi (and verify with `sycl-ls`) |
| `MaxRSS` looks low but job was killed | Check per-node memory, not total — `MaxRSS` is per-step, not summed | Re-check with `--units=G` and consider rank-per-node math |

## Reporting back to the user

Give a structured diagnosis:
1. **What happened** (one sentence, e.g., "Job 1234567 hit the 4-hour wall after 3h59m on `spr`.")
2. **Evidence** (the specific `sacct` field or log line you keyed off)
3. **Fix** (concrete change: bump `-t`, switch partition, rebuild binary, etc.)
4. **Next step** (offer to draft a corrected script via `stampede3-submit`, or to dig deeper into a specific node/log)

Keep it tight. Don't dump the full sacct table unless asked — quote the field that mattered.

## When the user is fishing ("my job is slow")

Without a JobID, ask for one. With one, look at:
- `seff <jobid>` for CPU efficiency
- `sacct ... CPUTime,TotalCPU,Elapsed` ratio
- `MaxRSS` vs requested resources (over-asked = wasted SU; near-limit = OOM risk)
- `ibrun` vs other launcher in the script
- Build flags vs run partition (AVX mismatch)
- I/O target — heavy I/O on `$HOME`/`$WORK` is slow; should be `$SCRATCH`

Then suggest one targeted experiment, not a laundry list.
