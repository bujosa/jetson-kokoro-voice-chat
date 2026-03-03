#!/bin/bash
# Check status of FRIDAY voice chat services
# Usage: ssh thor 'bash -s' < scripts/status.sh

echo "=== Services ==="
printf "%-15s %s\n" "FRIDAY:" "$(systemctl is-active friday 2>/dev/null || echo 'not installed')"
printf "%-15s %s\n" "Ollama:" "$(systemctl is-active ollama 2>/dev/null || echo 'not installed')"

echo ""
echo "=== Ports ==="
for port in 8000 11434; do
  if ss -tlnp 2>/dev/null | grep -q ":$port "; then
    echo "  :$port listening"
  else
    echo "  :$port not listening"
  fi
done

echo ""
echo "=== GPU Models ==="
ollama ps 2>/dev/null || echo "Ollama not running"

echo ""
echo "=== Memory ==="
free -h | head -2

echo ""
echo "=== FRIDAY Logs (last 10 lines) ==="
journalctl -u friday --no-pager -n 10 2>/dev/null || echo "No logs"
