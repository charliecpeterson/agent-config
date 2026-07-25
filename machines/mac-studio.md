- Mac Studio, Apple M2 Ultra, 192 GB unified memory, macOS.
- Primary dev box: personal AI tooling, MCP servers, writing, image gen.
- Local models run MLX-accelerated; big unified memory suits large-model
  inference. No CUDA — ctranslate2/whisperx run CPU-only here, and CUDA
  training belongs on linux-4090 or the clusters.
- No scheduler. Scratch: `~/scratch`.
- Never `nice` a build: Apple Silicon demotes niced work to background QoS
  and pins it to E-cores (~1% duty cycle even on an idle machine). Cap
  `CARGO_BUILD_JOBS` instead.
- `conda run` buffers subprocess output; long or parallel builds need
  `--no-capture-output` or they look hung.
- A full-workspace Rust build pinning all 24 cores once ran long enough for
  macOS to watchdog-kill WindowServer, restarting the GUI session and taking
  every terminal with it. Leave headroom on big builds.
