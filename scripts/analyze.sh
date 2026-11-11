#!/usr/bin/env bash
# ============================================================
#  analyze.sh  -  Analisis rapido del log de Snort (en la VM ids)
#  Uso:  sudo ./analyze.sh
# ============================================================
LOG="${1:-/var/log/snort/alert}"
[ -r "$LOG" ] || { echo "No puedo leer $LOG (¿corriste 'sudo snort-lab fast'?)"; exit 1; }

echo "=== Alertas por regla (SID + mensaje) ==="
grep -oE '\[1:[0-9]+:[0-9]+\] [^[]+' "$LOG" | sort | uniq -c | sort -nr

echo; echo "=== Top IPs de origen ==="
grep -oE '\{(TCP|UDP|ICMP)\} [0-9.]+' "$LOG" | awk '{print $2}' | sort | uniq -c | sort -nr | head

echo; echo "=== Puertos destino mas atacados ==="
grep -oE '-> [0-9.]+:[0-9]+' "$LOG" | cut -d: -f2 | sort | uniq -c | sort -nr | head

echo; echo "=== Total de alertas: $(wc -l < "$LOG") ==="
