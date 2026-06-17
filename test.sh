#!/usr/bin/env bash
# Run the agent-config test suite (stdlib unittest — no third-party deps) plus a
# bash syntax check on install.sh.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

bash -n install.sh && echo "install.sh: syntax OK"

py="python3"
for c in python3.14 python3.13 python3.12 python3.11; do
  command -v "$c" >/dev/null 2>&1 && { py="$c"; break; }
done
exec "$py" -m unittest discover -s tests -p 'test_*.py' -v
