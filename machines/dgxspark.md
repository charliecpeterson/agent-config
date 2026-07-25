- NVIDIA DGX Spark (`spark-b56c`), NVIDIA GB10, ARM aarch64, 20 CPU cores
  (10 Cortex-X925 and 10 Cortex-A725), about 128 GB unified memory
  (121 GiB visible to Linux).
- Local Grace Blackwell development box: useful for GB10/CUDA testing,
  local inference experiments, and ARM Linux compatibility checks.
- ARM architecture matters. Prefer linux-4090 or the clusters for x86_64
  CUDA workflows, binary-only scientific packages, and container images that
  assume an x86_64 NVIDIA stack.
- No scheduler; it's a personal machine. Scratch: `~/scratch`.
