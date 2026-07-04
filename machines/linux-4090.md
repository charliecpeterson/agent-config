- Linux desktop, NVIDIA RTX 4090 (24 GB VRAM), 64 GB system RAM.
- The CUDA box: fine-tuning, training runs, and GPU inference that needs
  CUDA rather than MLX. Anything over 24 GB VRAM or multi-GPU goes to the
  clusters instead.
- No scheduler; it's a personal machine. Scratch: `~/scratch`.
