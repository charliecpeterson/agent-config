- Linux desktop, Intel Core i7-12700K (12 cores, 20 threads), NVIDIA RTX
  4090 (24 GB VRAM), 64 GB system RAM.
- The CUDA box: fine-tuning, training runs, and GPU inference that needs
  CUDA rather than MLX. Anything over 24 GB VRAM or multi-GPU goes to the
  clusters instead.
- No scheduler; it's a personal machine. Scratch: `~/scratch`.
