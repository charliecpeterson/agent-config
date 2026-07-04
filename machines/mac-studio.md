- Mac Studio, Apple M2 Ultra, 192 GB unified memory, macOS.
- Primary dev box: personal AI tooling, MCP servers, writing, image gen.
- Local models run MLX-accelerated; big unified memory suits large-model
  inference. No CUDA — ctranslate2/whisperx run CPU-only here, and CUDA
  training belongs on linux-4090 or the clusters.
- No scheduler. Scratch: `~/scratch`.
