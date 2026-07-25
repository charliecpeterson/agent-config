- MacBook Air (Mac16,13), Apple M4, 10 CPU cores (4 performance, 6
  efficiency), 32 GB unified memory, macOS.
- Portable development machine: fine for editing, small builds, light local
  testing, and travel work.
- Modest thermal headroom compared with mac-studio. Route large builds,
  model work, sustained parallel tests, and CUDA workloads to mac-studio,
  linux-4090, or the clusters.
- No scheduler. Scratch: `~/scratch`.
- Apple Silicon QoS caveats apply here too: avoid `nice` for builds; cap
  parallelism instead when the machine needs to stay responsive.
