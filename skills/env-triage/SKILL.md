---
name: env-triage
description: "Triage a hung, slow, or wedged build, test run, or process: is it my code, my toolchain, or my machine? Trigger on 'the build hangs', 'tests never finish', 'why is this so slow', a process sitting at zero CPU, or when a second theory about an environment problem has also failed. NOT for Slurm jobs (stampede3-debug) or a reproducible code bug (bug-hunter)."
---

# Env Triage

Environment problems get misdiagnosed as code problems because the code is
what you were looking at when it hung. Each wrong theory costs a full build
or test cycle to disprove. This checklist exists to short-circuit that: the
cheap, decisive checks come first, and it tells you when to stop theorizing
about code and look at the machine. It was written after a session lost
over an hour to a wedged OS daemon misdiagnosed twice as a code problem.

The ordering is the content. Work it in order.

## 1 — CPU time vs elapsed (check this first)

```bash
ps -o pid,stat,time,etime,comm -p <pid>
```

A process with ~zero CPU time against minutes of elapsed is **blocked, not
slow**. This one ratio separates the two most common lookalikes: a
throttled process (some CPU, growing slowly) from one stuck before
`main()` (0.00s CPU, minutes elapsed, e.g. a loader hang). If you skip
everything else, do this.

## 2 — Process state

Sleeping with 0.00s CPU means it never got going: suspect the loader, the
OS, or the launch wrapper, not your code. Running with sustained CPU means
it *is* computing; only now is theorizing about your algorithm warranted.

## 3 — Get a stack before theorizing

- macOS: `sample <pid>`. The stack names the cause outright: a dyld hang
  shows the image-load wait, a deadlocked lock shows the lock.
- Linux: `cat /proc/<pid>/stack`, `gdb -p <pid> -batch -ex bt`, or
  `py-spy dump --pid <pid>` for Python.

One stack trace replaces twenty minutes of hypothesis.

## 4 — Reproduce outside the toolchain

Run the failing thing directly: no cargo, no conda, no nice, no test
harness. If a freshly built binary hangs when invoked bare, the problem is
system-wide and you've proven it in seconds. If it only hangs inside the
wrapper, the wrapper is the suspect (output buffering, QoS demotion,
environment scrubbing).

## 5 — Check system health before blaming the build

- Core daemons: any spinning at high CPU, any recently watchdog-killed?
  On macOS a WindowServer watchdog kill wedges the session and every
  freshly built binary with it; check
  `log show --last 10m --predicate 'eventMessage CONTAINS "watchdog"'`.
- DNS resolving (`dig` or `host` something), network mounts alive.
- Disk space and memory pressure. A full disk hangs builds in ways that
  look like everything else.

## 6 — Know the platform's traps

The machine profile in the global config carries the known traps for the
box you're on; read it. The shape of what lives there:

- Apple Silicon: `nice` demotes work to background QoS and pins it to
  E-cores (~1% duty cycle on an otherwise idle machine). Cap parallelism
  (`CARGO_BUILD_JOBS`, `-j`) instead.
- `conda run` buffers subprocess output; long or parallel builds need
  `--no-capture-output` or they look hung while running fine.

## When two theories have failed

Each failed theory about an environment problem is evidence you're at the
wrong layer, not that the next code theory is slightly better. After two,
stop and go down a layer: code → toolchain (wrapper, build system) → OS
(loader, daemons, resources). Never make a third attempt on the same layer;
that's thrashing.

## Boundaries

- **Slurm jobs**: `stampede3-debug` owns "why is my job wedged" and knows
  the scheduler. This skill questions the machine under the job; reach for
  it when the cluster answers don't hold, or when *every* job and shell
  command misbehaves at once.
- **A bug you can reproduce**: `bug-hunter`. This skill is for when what
  changed is the environment, not the code.
