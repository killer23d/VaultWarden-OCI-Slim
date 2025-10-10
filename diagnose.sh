#!/usr/bin/env bash
# diagnose.sh -- Phase 2 (thresholds via config, docker via dashboard-metrics)
# See Phase 1 diagnose.sh; this version ensures all comparisons use config values

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/common.sh" || { echo "ERROR: lib/common.sh required" >&2; exit 1; }
source "$SCRIPT_DIR/lib/logger.sh" || true

[[ -f "$SCRIPT_DIR/config/performance-targets.conf" ]] && source "$SCRIPT_DIR/config/performance-targets.conf"
CPU_CRITICAL_THRESHOLD=${CPU_CRITICAL_THRESHOLD:-90}
MEMORY_CRITICAL_THRESHOLD=${MEMORY_CRITICAL_THRESHOLD:-85}
LOAD_CRITICAL_THRESHOLD=${LOAD_CRITICAL_THRESHOLD:-1.5}
SQLITE_SIZE_CRITICAL_MB=${SQLITE_SIZE_CRITICAL_MB:-500}
SQLITE_WAL_CRITICAL_MB=${SQLITE_WAL_CRITICAL_MB:-50}
SQLITE_FRAGMENTATION_CRITICAL=${SQLITE_FRAGMENTATION_CRITICAL:-1.5}

loaded=()
if source "$SCRIPT_DIR/lib/perf-collector.sh"; then perf_collector_init; loaded+=("perf-collector"); fi
if source "$SCRIPT_DIR/lib/dashboard-sqlite.sh"; then dashboard_sqlite_init; loaded+=("dashboard-sqlite"); fi
if source "$SCRIPT_DIR/lib/dashboard-metrics.sh"; then loaded+=("dashboard-metrics"); fi

echo -e "${BOLD}Diagnostics (Phase 2)${NC}"
if [[ " ${loaded[*]} " =~ " perf-collector " ]]; then
  sys=$(perf_collector_system_full)
  eval "$(echo "$sys" | grep -E '^(cpu_usage|mem_usage_pct|load_1m)=')"
  command -v bc >/dev/null 2>&1 || bc() { awk "BEGIN{print $*}"; }
  (( $(echo "$cpu_usage > $CPU_CRITICAL_THRESHOLD" | bc -l) )) && echo "CPU critical: $cpu_usage%"
  (( $(echo "$mem_usage_pct > $MEMORY_CRITICAL_THRESHOLD" | bc -l) )) && echo "Memory critical: $mem_usage_pct%"
  (( $(echo "$load_1m > $LOAD_CRITICAL_THRESHOLD" | bc -l) )) && echo "Load critical: $load_1m"
fi
if [[ " ${loaded[*]} " =~ " dashboard-sqlite " ]]; then
  m=$(dashboard_sqlite_get_detailed_metrics || echo "available=false")
  if [[ "$m" =~ available=true ]]; then
    eval "$(echo "$m" | grep -E '^(file_size_mb|wal_size_mb|fragmentation_ratio)=')"
    (( $(echo "$file_size_mb > $SQLITE_SIZE_CRITICAL_MB" | bc -l) )) && echo "SQLite size high: ${file_size_mb}MB"
    (( $(echo "$wal_size_mb > $SQLITE_WAL_CRITICAL_MB" | bc -l) )) && echo "WAL large: ${wal_size_mb}MB"
    (( $(echo "$fragmentation_ratio > $SQLITE_FRAGMENTATION_CRITICAL" | bc -l) )) && echo "Fragmented: ${fragmentation_ratio}"
  fi
fi
if [[ " ${loaded[*]} " =~ " dashboard-metrics " ]]; then
  c=$(dashboard_get_container_metrics)
  if [[ "$c" =~ docker_available=true ]]; then
    eval "$(echo "$c" | grep -E '^containers_(running|total)=')"
    echo "Containers running: ${containers_running}/${containers_total}"
  fi
fi
