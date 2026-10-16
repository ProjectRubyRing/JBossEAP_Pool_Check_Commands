# =============================================================================
# jbpool.sh : JBoss EAP / WildFly datasource connection-pool inspector
#   Paste ALL of this text into the shell of the container
#   (ECS Exec / docker compose exec). A snapshot runs right after the paste.
#   After that you can type:
#     jbpool                  snapshot (detailed report, once)
#     jbpool watch 10         trend every 10 sec (Ctrl+C to stop)
#     jbpool csv 10 360 > /tmp/pool.csv   CSV for Excel
#     jbpool threads          stack traces of threads waiting for a connection
#     jbpool enable-stats     turn statistics on (runtime only)
#     jbpool help
#   Read-only, except enable-stats / disable-stats.
#   Optional env: JBOSS_HOME MGMT_HOST MGMT_PORT CONTROLLER CLI_USER CLI_PASS
#                 JBP_LABEL JBP_WARN JBP_CSV JBP_JAVA_OPTS JBP_MIN_FREE_MB JBP_FORCE
#                 TZ (e.g. TZ=JST-9)
#   ASCII only / no TAB / no history-expansion chars: safe to paste.
#   Long paste may be cut in some terminals: then paste PART 1, 2, 3 one by one.
# =============================================================================
# ---------------------------------------------------------------- PART 1/3 : functions
case $- in *H*) set +H ;; esac

jbp_help() {
  cat <<'JBP_HELP'
jbpool - JBoss EAP / WildFly datasource connection-pool inspector
  jbpool                    snapshot : detailed report (once)
  jbpool watch [sec] [n]    trend    : every sec (default 10), n times (0 = until Ctrl+C)
  jbpool csv   [sec] [n]    CSV      : same as watch, CSV lines for Excel
  jbpool threads            stack traces of threads queued for a connection
  jbpool enable-stats       statistics-enabled=true on every pool (runtime only)
  jbpool disable-stats      statistics-enabled=false
  jbpool raw                raw CLI output (debug)
env  JBOSS_HOME   EAP install dir (auto: /opt/server /opt/eap /opt/jboss/wildfly ...)
     MGMT_PORT    management port (auto: 9990 + port-offset of the running server)
     MGMT_HOST    management address (auto: 127.0.0.1 or -bmanagement)
     CONTROLLER   full controller URL, e.g. remote+http://127.0.0.1:10090
     CLI_USER / CLI_PASS   management user (only if local silent auth fails)
     JBP_LABEL    name to show (auto: ECS container name or hostname)
     JBP_WARN     BUSY threshold in % of max-pool-size (default 80)
     JBP_CSV      file to append CSV rows to while "watch" runs
     TZ           display time zone, e.g. TZ=JST-9 (works without tzdata)
     JBP_MIN_FREE_MB  stop if container memory headroom is below this (default 200)
     JBP_FORCE=1      run even if headroom is low
JBP_HELP
}

jbp_setup() {
  JBP_CLI=""
  for JBP_d in "${JBOSS_HOME:-}" /opt/server /opt/eap /opt/jboss/wildfly /opt/wildfly \
               /opt/jboss-eap /opt/jboss-eap-8.1 /opt/jboss-eap-8.0 /opt/jboss-eap-7.4 /usr/share/wildfly; do
    if [ -n "$JBP_d" ] && [ -f "$JBP_d/bin/jboss-cli.sh" ]; then JBP_CLI="$JBP_d/bin/jboss-cli.sh"; break; fi
  done
  if [ -z "$JBP_CLI" ]; then
    JBP_CLI=$(find / -xdev -path '*/bin/jboss-cli.sh' 2>/dev/null | head -n 1)
  fi
  if [ -z "$JBP_CLI" ]; then
    echo "[jbpool] jboss-cli.sh not found. set JBOSS_HOME=/path/to/eap and retry." >&2
    return 1
  fi
  # --- find the running standalone server and its management port / address
  JBP_NPROC=0; JBP_PID=""; JBP_off=""; JBP_mp=""; JBP_mh=""
  for JBP_p in /proc/[0-9]*; do
    [ -r "$JBP_p/cmdline" ] || continue
    JBP_c=$(tr '\000' ' ' < "$JBP_p/cmdline" 2>/dev/null)
    case "$JBP_c" in *org.jboss.as.standalone*) ;; *) continue ;; esac
    JBP_NPROC=$((JBP_NPROC + 1))
    [ -n "$JBP_PID" ] && continue
    JBP_PID=${JBP_p#/proc/}
    JBP_off=$(printf '%s\n' "$JBP_c" | sed -n 's/.*-Djboss\.socket\.binding\.port-offset=\([0-9][0-9]*\).*/\1/p')
    JBP_mp=$(printf '%s\n' "$JBP_c" | sed -n 's/.*-Djboss\.management\.http\.port=\([0-9][0-9]*\).*/\1/p')
    JBP_mh=$(printf '%s\n' "$JBP_c" | sed -n 's/.*-Djboss\.bind\.address\.management=\([^ ]*\).*/\1/p')
    [ -z "$JBP_mh" ] && JBP_mh=$(printf '%s\n' "$JBP_c" | sed -n 's/.*-bmanagement[= ]\([^ ]*\).*/\1/p')
  done
  JBP_host=${MGMT_HOST:-$JBP_mh}
  case "$JBP_host" in ""|0.0.0.0|::|"[::]") JBP_host=127.0.0.1 ;; esac
  JBP_port=${MGMT_PORT:-$(( ${JBP_mp:-9990} + ${JBP_off:-0} ))}
  JBP_CTRL=${CONTROLLER:-remote+http://$JBP_host:$JBP_port}
  # --- helpers: timeout command, temp dir, label
  JBP_TO=""
  command -v timeout >/dev/null 2>&1 && JBP_TO="timeout ${JBP_CLI_TIMEOUT:-90}"
  JBP_TMP=""
  for JBP_d in "${TMPDIR:-}" /tmp /dev/shm /var/tmp "${JBP_CLI%/bin/jboss-cli.sh}/standalone/tmp" "${HOME:-}"; do
    if [ -n "$JBP_d" ] && [ -d "$JBP_d" ] && [ -w "$JBP_d" ]; then JBP_TMP=$JBP_d; break; fi
  done
  if [ -z "$JBP_TMP" ]; then echo "[jbpool] no writable temp directory" >&2; return 1; fi
  JBP_F="$JBP_TMP/jbpool.$$.cli"; JBP_E="$JBP_TMP/jbpool.$$.err"
  JBP_HOSTN=$(hostname 2>/dev/null || cat /proc/sys/kernel/hostname 2>/dev/null)
  JBP_LBL=${JBP_LABEL:-}; JBP_TASK=""
  if [ -n "${ECS_CONTAINER_METADATA_URI_V4:-}" ]; then
    JBP_j=$( { curl -s -m 2 "$ECS_CONTAINER_METADATA_URI_V4" || wget -q -T 2 -O - "$ECS_CONTAINER_METADATA_URI_V4"; } 2>/dev/null )
    [ -z "$JBP_LBL" ] && JBP_LBL=$(printf '%s' "$JBP_j" | sed -n 's|.*"com\.amazonaws\.ecs\.container-name":"\([^"]*\)".*|\1|p')
    JBP_TASK=$(printf '%s' "$JBP_j" | sed -n 's|.*"com\.amazonaws\.ecs\.task-arn":"[^"]*/\([^"/]*\)".*|\1|p')
  fi
  [ -z "$JBP_LBL" ] && JBP_LBL=$JBP_HOSTN
  # --- memory headroom: the CLI JVM needs about 120-150 MB (measured RSS ~119 MB)
  JBP_MEM=""; JBP_lim=""; JBP_cur=""
  if [ -r /sys/fs/cgroup/memory.max ]; then
    JBP_lim=$(cat /sys/fs/cgroup/memory.max 2>/dev/null); JBP_cur=$(cat /sys/fs/cgroup/memory.current 2>/dev/null)
  elif [ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    JBP_lim=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null); JBP_cur=$(cat /sys/fs/cgroup/memory/memory.usage_in_bytes 2>/dev/null)
  fi
  case "$JBP_lim" in ""|*[a-z]*) JBP_lim="" ;; esac
  case "$JBP_cur" in ""|*[a-z]*) JBP_cur="" ;; esac
  if [ -n "$JBP_lim" ] && [ -n "$JBP_cur" ] && [ "$JBP_lim" -lt 1000000000000 ]; then
    JBP_free=$(( (JBP_lim - JBP_cur) / 1048576 ))
    JBP_MEM="$(( JBP_cur / 1048576 ))MB used / $(( JBP_lim / 1048576 ))MB limit (headroom ${JBP_free}MB)"
    if [ "$JBP_free" -lt "${JBP_MIN_FREE_MB:-200}" ] && [ -z "${JBP_FORCE:-}" ]; then
      echo "[jbpool] STOP: container memory headroom is only ${JBP_free}MB; the CLI JVM needs ~150MB (OOM-kill risk)." >&2
      echo "         run anyway:  JBP_FORCE=1 jbpool ...   (or set JBP_MIN_FREE_MB)" >&2
      return 1
    fi
  fi
  return 0
}

# run jboss-cli with a small, isolated JVM (does not inherit the server heap / agents)
jbp_cli() {
  ( unset JAVA_TOOL_OPTIONS _JAVA_OPTIONS JDK_JAVA_OPTIONS
    JAVA_OPTS=${JBP_JAVA_OPTS:-"-Xms16m -Xmx128m -XX:+UseSerialGC -XX:TieredStopAtLevel=1"}
    export JAVA_OPTS
    if [ -n "${CLI_USER:-}" ]; then
      $JBP_TO sh "$JBP_CLI" --connect --controller="$JBP_CTRL" --timeout=15000 \
        --user="$CLI_USER" --password="${CLI_PASS:-}" --file="$1" </dev/null
    else
      $JBP_TO sh "$JBP_CLI" --connect --controller="$JBP_CTRL" --timeout=15000 --file="$1" </dev/null
    fi )
}

jbp_fail() {
  echo "[jbpool] jboss-cli failed (rc=$1)  controller=$JBP_CTRL" >&2
  [ -n "${2:-}" ] && printf '%s\n' "$2" | grep -v '^JBPMARK' | head -n 10 >&2
  head -n 15 "$JBP_E" >&2
  JBP_msg=$( { printf '%s\n' "${2:-}"; cat "$JBP_E"; } 2>/dev/null )
  if printf '%s\n' "$JBP_msg" | grep -qiE 'refused|not available|WFLYPRT0053|timed out|unreachable'; then
    echo "  hint: management port not reachable. front/back in ONE task share localhost," >&2
    echo "        so one of them usually has a port-offset:  MGMT_PORT=10090 jbpool" >&2
  fi
  if printf '%s\n' "$JBP_msg" | grep -qiE 'authenticat|unauthori|JBREM|ELY0'; then
    echo "  hint: local (silent) auth failed. run as root/server user, or CLI_USER=... CLI_PASS=... jbpool" >&2
  fi
  [ "$1" = 124 ] && echo "  hint: CLI timed out (server hung? long GC?). thread dump: jcmd <pid> Thread.print" >&2
  return 0
}

# datasource names -> JBP_NAMES ("data-source NAME" lines)
jbp_names() {
  printf '%s\n' 'echo JBPMARK N data-source' \
    '/subsystem=datasources:read-children-names(child-type=data-source)' \
    'echo JBPMARK N xa-data-source' \
    '/subsystem=datasources:read-children-names(child-type=xa-data-source)' > "$JBP_F"
  JBP_out=$(jbp_cli "$JBP_F" 2>"$JBP_E"); JBP_rc=$?
  if [ "$JBP_rc" -ne 0 ]; then jbp_fail "$JBP_rc" "$JBP_out"; return 1; fi
  JBP_NAMES=$(printf '%s\n' "$JBP_out" | awk '
    /^JBPMARK N / { t = $3; r = 0; next }
    t != "" && /"result"/ { r = 1 }
    r == 1 { s = $0; sub(/.*"result" =>/, "", s)
             while (match(s, /"[^"]*"/)) { print t, substr(s, RSTART + 1, RLENGTH - 2); s = substr(s, RSTART + RLENGTH) }
             if ($0 ~ /]/) r = 0 }')
  return 0
}

# one sample = one CLI run: root info, pool config, pool statistics, queued threads, io worker
jbp_mkfile() {
  {
    echo 'echo JBPMARK ROOT'
    echo ':read-resource(attributes-only=true,include-runtime=true)'
    for JBP_a in jndi-name enabled statistics-enabled min-pool-size initial-pool-size max-pool-size \
                 pool-prefill pool-use-strict-min pool-fair blocking-timeout-wait-millis idle-timeout-minutes \
                 allocation-retry allocation-retry-wait-millis flush-strategy background-validation \
                 background-validation-millis validate-on-match; do
      echo "echo JBPMARK A $JBP_a"
      for JBP_t in data-source xa-data-source; do
        printf 'try\n/subsystem=datasources/%s=*:read-attribute(name=%s,resolve-expressions=true)\ncatch\necho JBPMARK AERR\nend-try\n' "$JBP_t" "$JBP_a"
      done
    done
    echo 'echo JBPMARK STAT'
    for JBP_t in data-source xa-data-source; do
      printf 'try\n/subsystem=datasources/%s=*/statistics=pool:read-resource(include-runtime=true)\ncatch\necho JBPMARK SERR\nend-try\n' "$JBP_t"
    done
    printf '%s\n' "$JBP_NAMES" | while read -r JBP_t JBP_n; do
      [ -n "$JBP_n" ] || continue
      printf 'echo JBPMARK Q %s %s\ntry\n/subsystem=datasources/%s=%s:dump-queued-threads-in-pool\ncatch\necho JBPMARK QERR\nend-try\n' "$JBP_t" "$JBP_n" "$JBP_t" "$JBP_n"
    done
    printf 'echo JBPMARK WORKER\ntry\n/subsystem=io/worker=*:read-resource(include-runtime=true)\ncatch\necho JBPMARK WERR\nend-try\necho JBPMARK END\n'
  } > "$JBP_F"
}

jbp_loop() {
  JBP_i=0
  while :; do
    JBP_i=$((JBP_i + 1))
    if [ $((JBP_i % 30)) -eq 0 ]; then jbp_names >/dev/null 2>&1; fi
    jbp_mkfile
    echo "JBPMARK SAMPLE $JBP_i"
    jbp_cli "$JBP_F" 2>"$JBP_E"
    JBP_rc=$?
    echo "JBPMARK TIME $(date +%s)"
    echo "JBPMARK RC $JBP_rc"
    if [ "$JBP_rc" -ne 0 ]; then sed -n '1,12s/^/JBPMARK ERR /p' "$JBP_E"; fi
    echo "JBPMARK DONE"
    if [ "$JBP_CNT" -gt 0 ] && [ "$JBP_i" -ge "$JBP_CNT" ]; then break; fi
    sleep "$JBP_INT"
  done
  rm -f "$JBP_F" "$JBP_E"
}

jbp_threads() {
  printf '%s\n' "$JBP_NAMES" | while read -r JBP_t JBP_n; do
    [ -n "$JBP_n" ] || continue
    printf 'echo ===== %s %s : threads waiting for a connection =====\ntry\n/subsystem=datasources/%s=%s:dump-queued-threads-in-pool\ncatch\necho not-available\nend-try\n' "$JBP_t" "$JBP_n" "$JBP_t" "$JBP_n"
  done > "$JBP_F"
  jbp_cli "$JBP_F" 2>"$JBP_E" | awk '{ gsub(/\\n/, "\n"); gsub(/\\t/, "    "); print }'
  rm -f "$JBP_F" "$JBP_E"
}

jbp_stats() {
  printf '%s\n' "$JBP_NAMES" | while read -r JBP_t JBP_n; do
    [ -n "$JBP_n" ] || continue
    for JBP_s in pool jdbc; do
      printf 'echo %s %s statistics=%s statistics-enabled=%s\ntry\n/subsystem=datasources/%s=%s/statistics=%s:write-attribute(name=statistics-enabled,value=%s)\ncatch\necho failed\nend-try\n' \
        "$JBP_t" "$JBP_n" "$JBP_s" "$1" "$JBP_t" "$JBP_n" "$JBP_s" "$1"
    done
  done > "$JBP_F"
  jbp_cli "$JBP_F" 2>"$JBP_E" | grep -E 'statistics-enabled=|failed|outcome|process-state|failure-description'
  cat "$JBP_E" >&2
  rm -f "$JBP_F" "$JBP_E"
  echo "[jbpool] runtime switch: it is lost on reload/restart. permanent: data-source attribute" >&2
  echo "         statistics-enabled=true + reload, or start with -Dwildfly.datasources.statistics-enabled=true" >&2
  echo "         (only if the datasource uses that expression)." >&2
}

# ---------------------------------------------------------------- PART 2/3 : renderer (awk)
JBP_AWK='
BEGIN {
  s = substr(TZOFF, 1, 1); TZS = (substr(TZOFF, 2, 2) + 0) * 3600 + (substr(TZOFF, 4, 2) + 0) * 60
  if (s == "-") TZS = -TZS
  if (WARN == "") WARN = 80
  MAXQ = 4; nsamp = 0; start = ""
  LINE = "------------------------------------------------------------------------------------------"
}
function trim(x) { sub(/^[ \t\r]+/, "", x); sub(/[ \t\r,]+$/, "", x); return x }
function val(x,   y) {
  x = trim(x)
  if (x ~ /^expression "/) { y = x; if (sub(/^.*:/, "", y) == 0) return "?"; gsub(/[}"]/, "", y); return y }
  if (x ~ /^".*"$/) return substr(x, 2, length(x) - 2)
  if (x ~ /^-?[0-9]+L$/) sub(/L$/, "", x)
  return x
}
function nz(x, d) { return (x == "" || x == "undefined" || x == "?") ? d : x }
function dv(d, k, def) { return (conf[d, k] == "" || conf[d, k] == "undefined") ? def "*" : conf[d, k] }
function hms(t,   x) { x = (t + TZS) % 86400; if (x < 0) x += 86400; return sprintf("%02d:%02d:%02d", int(x / 3600), int((x % 3600) / 60), x % 60) }
function ymd(t,   z, era, doe, yoe, y, doy, mp, dd, mm) {
  z = int((t + TZS) / 86400) + 719468; era = int(z / 146097); doe = z - era * 146097
  yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
  y = yoe + era * 400; doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
  mp = int((5 * doy + 2) / 153); dd = doy - int((153 * mp + 2) / 5) + 1
  mm = (mp < 10) ? mp + 3 : mp - 9; if (mm <= 2) y++
  return sprintf("%04d-%02d-%02d", y, mm, dd)
}
function at(t) { return (ymd(t) == ymd(now)) ? hms(t) : ymd(t) " " hms(t) }
function dur(x) { x = int(x); if (x >= 3600) return sprintf("%dh%02dm", int(x / 3600), int((x % 3600) / 60)); if (x >= 60) return sprintf("%dm%02ds", int(x / 60), x % 60); return x "s" }
function ms(x) { x = nz(x, ""); return (x == "") ? "-" : x "ms" }
function sd(d, k, sign) { if (R[d, "has"] == 0) return "-"; if (R[d, k] < 0) return "rst"; return sign R[d, k] }

/^JBPMARK SAMPLE / {
  split("", conf); split("", st); split("", root); split("", seen); split("", dtype); split("", qn); split("", qok)
  split("", qname); split("", wk); split("", wseen); split("", errl)
  nerr = 0; rc = 0; sec = ""; curds = ""; curw = ""; cura = ""; qds = ""; samp = $3; next
}
/^JBPMARK TIME / { now = $3 + 0; next }
/^JBPMARK RC / { rc = $3 + 0; next }
/^JBPMARK ERR / { errl[++nerr] = substr($0, 13); next }
/^JBPMARK DONE/ { render(); next }
/^JBPMARK ROOT/ { sec = "R"; next }
/^JBPMARK A / { sec = "A"; cura = $3; curds = ""; next }
/^JBPMARK STAT/ { sec = "S"; curds = ""; next }
/^JBPMARK Q / { sec = "Q"; qds = $4; seen[qds] = 1; dtype[qds] = $3; qok[qds] = 1; qn[qds] = 0; next }
/^JBPMARK QERR/ { qok[qds] = 0; next }
/^JBPMARK WORKER/ { sec = "W"; curw = ""; next }
/^JBPMARK END/ { sec = ""; next }
/^JBPMARK / { next }
sec == "Q" {
  p = index($0, "Queued thread: ")
  if (p > 0) { t = substr($0, p + 15); sub(/[\\"].*$/, "", t); t = trim(t); qn[qds]++; qname[qds, qn[qds]] = t }
  next
}
/\("(xa-)?data-source" => "/ {
  if (match($0, /"(xa-)?data-source" => "[^"]*"/)) {
    t = substr($0, RSTART, RLENGTH); dt = (t ~ /^"xa-/) ? "xa-data-source" : "data-source"
    sub(/^[^>]*> "/, "", t); sub(/"$/, "", t); curds = t; seen[t] = 1; dtype[t] = dt
  }
  next
}
/\("worker" => "/ {
  if (match($0, /"worker" => "[^"]*"/)) { t = substr($0, RSTART, RLENGTH); sub(/^[^>]*> "/, "", t); sub(/"$/, "", t); curw = t; wseen[t] = 1 }
  next
}
/^[ \t]*"[A-Za-z][A-Za-z0-9._-]*" => / {
  k = $0; sub(/^[ \t]*"/, "", k); sub(/".*$/, "", k)
  v = $0; sub(/^[^>]*=> /, "", v); v = val(v)
  if (sec == "A") { if (k == "result" && curds != "" && v != "" && (v ~ /^[\[{]/) == 0) conf[curds, cura] = v }
  else if (sec == "S") { if (curds != "") st[curds, k] = v }
  else if (sec == "R") root[k] = v
  else if (sec == "W") { if (curw != "") wk[curw, k] = v }
  next
}

function calc(d,   mn, mx, bt, it, ar, arw, wl, son, act, use, idl, cr, de, to, wc, bf, q, j, k, n, ord, tj, tmin, tmax, unk, fl, ex, del, nd, parts, tx, st2) {
  mn = nz(conf[d, "min-pool-size"], 0) + 0;   mx = nz(conf[d, "max-pool-size"], 20) + 0
  bt = nz(conf[d, "blocking-timeout-wait-millis"], 30000) + 0;   it = nz(conf[d, "idle-timeout-minutes"], 30) + 0
  ar = nz(conf[d, "allocation-retry"], 0) + 0;   arw = nz(conf[d, "allocation-retry-wait-millis"], 0) + 0
  wl = bt * (ar + 1) + arw * ar
  R[d, "mn"] = mn; R[d, "mx"] = mx; R[d, "bt"] = bt; R[d, "it"] = it; R[d, "ar"] = ar; R[d, "arw"] = arw; R[d, "wl"] = wl
  son = st[d, "statistics-enabled"]; if (son == "") son = conf[d, "statistics-enabled"]; R[d, "son"] = son
  act = nz(st[d, "ActiveCount"], 0) + 0; use = nz(st[d, "InUseCount"], 0) + 0
  idl = nz(st[d, "IdleCount"], act - use) + 0; R[d, "neg"] = 0
  if (act < 0 || act < use) { R[d, "neg"] = 1; act = use + idl }
  R[d, "act"] = act; R[d, "use"] = use; R[d, "idl"] = idl; R[d, "avl"] = nz(st[d, "AvailableCount"], mx - use) + 0
  R[d, "pct"] = (mx > 0) ? int(use * 100 / mx) : 0
  cr = nz(st[d, "CreatedCount"], 0) + 0; de = nz(st[d, "DestroyedCount"], 0) + 0; to = nz(st[d, "TimedOut"], 0) + 0
  wc = nz(st[d, "WaitCount"], 0) + 0;    bf = nz(st[d, "BlockingFailureCount"], 0) + 0
  R[d, "cr"] = cr; R[d, "de"] = de; R[d, "to"] = to; R[d, "wc"] = wc; R[d, "bf"] = bf
  R[d, "mxu"] = nz(st[d, "MaxUsedCount"], 0) + 0; R[d, "mwc"] = nz(st[d, "MaxWaitCount"], 0) + 0
  if (d in pcr) {
    R[d, "has"] = 1; R[d, "dcr"] = cr - pcr[d]; R[d, "dde"] = de - pde[d]; R[d, "dto"] = to - pto[d]
    R[d, "dwc"] = wc - pwc[d]; R[d, "dbf"] = bf - pbf[d]; R[d, "pact"] = pact[d]
  } else R[d, "has"] = 0
  pcr[d] = cr; pde[d] = de; pto[d] = to; pwc[d] = wc; pbf[d] = bf; pact[d] = act
  # ---- queued threads: first-seen time + wait limit = latest time it is resolved
  q = (d in qok) ? ((qok[d] == 1) ? qn[d] + 0 : -1) : -1
  split("", qcur)
  for (j = 1; j <= qn[d]; j++) {
    k = d SUBSEP qname[d, j]; qcur[k] = 1
    if ((k in qfs) == 0 || now > qfs[k] + wl / 1000 + 5) qfs[k] = now
  }
  nd = 0; for (k in qfs) { split(k, parts, SUBSEP); if (parts[1] == d && (k in qcur) == 0) del[++nd] = k }
  for (j = 1; j <= nd; j++) delete qfs[del[j]]
  n = 0; for (k in qcur) { n++; ord[n] = k }
  for (j = 2; j <= n; j++) { k = ord[j]; tj = j - 1; while (tj > 0 && qfs[ord[tj]] > qfs[k]) { ord[tj + 1] = ord[tj]; tj-- }; ord[tj + 1] = k }
  tx = ""; R[d, "qby"] = 0
  for (j = 1; j <= n; j++) {
    split(ord[j], parts, SUBSEP)
    if (j <= MAXQ) tx = tx ((j > 1) ? ", " : "") parts[2] " (<=" hms(qfs[ord[j]] + wl / 1000) ")"
    if (qfs[ord[j]] + wl / 1000 > R[d, "qby"]) R[d, "qby"] = qfs[ord[j]] + wl / 1000
  }
  if (n > MAXQ) tx = tx ", ... +" (n - MAXQ) " more"
  R[d, "q"] = q; R[d, "qtxt"] = tx
  # ---- idle surplus: the pool re-uses the newest connection first (LIFO), so "level j"
  #      was last used when in-use >= j (lal) and returned before it was seen free (fre).
  #      TotalUsageTime grows on every return -> also catches returns between two samples.
  if ((d in t0) == 0) t0[d] = now
  tx = nz(st[d, "TotalUsageTime"], "")
  if (tx != "" && (d in ptu) && tx + 0 != ptu[d]) actt[d] = now
  if (tx != "") ptu[d] = tx + 0
  for (j = 1; j <= use; j++) { lal[d, j] = now; if ((d, j) in fre) delete fre[d, j] }
  for (j = use + 1; j <= act; j++) if (((d, j) in lal) && (((d, j) in fre) == 0)) fre[d, j] = now
  nd = 0; for (k in lal) { split(k, parts, SUBSEP); if (parts[1] == d && parts[2] + 0 > act) del[++nd] = k }
  for (j = 1; j <= nd; j++) { delete lal[del[j]]; if (del[j] in fre) delete fre[del[j]] }
  # min-pool-size is kept only with pool-prefill or pool-use-strict-min (otherwise idle-timeout can go to 0)
  R[d, "keepmin"] = (conf[d, "pool-prefill"] == "true" || conf[d, "pool-use-strict-min"] == "true") ? 1 : 0
  fl = (R[d, "keepmin"] == 1 && mn > use) ? mn : use; ex = act - fl; if (ex < 0) ex = 0
  R[d, "fl"] = fl; R[d, "ex"] = ex; R[d, "e1"] = ""; R[d, "e2"] = ""; R[d, "unk"] = 0
  if (ex > 0 && it > 0 && son == "true") {
    tmin = -1; tmax = t0[d]; unk = 0
    for (j = fl + 1; j <= act; j++) {
      if ((d, j) in lal) {
        if (tmin < 0 || lal[d, j] < tmin) tmin = lal[d, j]
        tj = ((d, j) in fre) ? fre[d, j] : now; if (tj > tmax) tmax = tj
      } else unk++
    }
    if ((d in actt) && actt[d] > tmax) tmax = actt[d]
    R[d, "e1"] = (tmin < 0) ? "" : tmin + it * 60; R[d, "e2"] = tmax + it * 60 + CHK; R[d, "unk"] = unk
  }
  # ---- status
  if (conf[d, "enabled"] == "false") st2 = "DISABLED"
  else if (son != "true") st2 = "STATS-OFF"
  else if (q > 0) st2 = "OVERFLOW"
  else if (mx > 0 && use >= mx) st2 = "FULL"
  else if (mx > 0 && use * 100 >= WARN * mx) st2 = "BUSY"
  else st2 = "OK"
  if (R[d, "has"] == 1 && R[d, "dbf"] > 0) st2 = st2 "+TMOUT"
  R[d, "status"] = st2
}

function render(   n, i, j, d, nm, minit, it) {
  nsamp++
  if (start == "") start = now
  n = 0; for (d in seen) { n++; nm[n] = d }
  for (i = 2; i <= n; i++) { d = nm[i]; j = i - 1; while (j > 0 && nm[j] > d) { nm[j + 1] = nm[j]; j-- }; nm[j + 1] = d }
  minit = 0
  for (i = 1; i <= n; i++) {
    d = nm[i]; it = nz(conf[d, "idle-timeout-minutes"], 30) + 0
    if (conf[d, "enabled"] != "false" && it > 0 && (minit == 0 || it < minit)) minit = it
  }
  # IdleRemover wakes every SCAN sec; one pool is checked at most once per minute -> worst gap CHK
  SCAN = minit * 30; CHK = (SCAN > 60) ? SCAN : SCAN * (int(60 / SCAN) + 1)
  for (i = 1; i <= n; i++) calc(nm[i])
  if (MODE == "csv") { if (rc != 0) perr(); for (i = 1; i <= n; i++) csvrow(nm[i], 1); fflush(); return }
  if (CSVF != "") for (i = 1; i <= n; i++) csvrow(nm[i], 0)
  if (MODE == "watch") pwatch(n, nm); else psnap(n, nm)
  fflush()
}

function perr(   i) {
  printf " ** jboss-cli rc=%d : management call failed (server restarting / port / auth ?)\n", rc
  for (i = 1; i <= nerr && i <= 8; i++) print "    " errl[i]
}

function csvrow(d, out,   line) {
  if (csvh == "") {
    csvh = "date,time,epoch,label,datasource,status,active,in_use,idle,max,available,created,destroyed,timed_out,wait_count,blocking_failures,queued,max_used,max_wait_count,max_wait_ms,avg_get_ms,max_get_ms,avg_usage_ms,idle_release_from,idle_release_by,queue_resolved_by"
    if (out) print csvh; else if (CSVHDR == "1") { print csvh >> CSVF; close(CSVF) }
  }
  line = ymd(now) "," hms(now) "," now "," LABEL "," d "," R[d, "status"] "," R[d, "act"] "," R[d, "use"] "," R[d, "idl"] "," R[d, "mx"] "," R[d, "avl"]
  line = line "," R[d, "cr"] "," R[d, "de"] "," R[d, "to"] "," R[d, "wc"] "," R[d, "bf"] "," ((R[d, "q"] < 0) ? "" : R[d, "q"]) "," R[d, "mxu"] "," R[d, "mwc"]
  line = line "," nz(st[d, "MaxWaitTime"], "") "," nz(st[d, "AverageGetTime"], "") "," nz(st[d, "MaxGetTime"], "") "," nz(st[d, "AverageUsageTime"], "")
  line = line "," ((R[d, "e1"] == "" || R[d, "unk"] > 0) ? "" : at(R[d, "e1"])) "," ((R[d, "e2"] == "") ? "" : at(R[d, "e2"])) "," ((R[d, "q"] > 0) ? at(R[d, "qby"]) : "")
  if (out) print line; else { print line >> CSVF; close(CSVF) }
}

function idleline(d, head) {
  if (R[d, "it"] == 0) { print head "idle-timeout-minutes=0 -> idle connections are never closed by timeout"; return }
  if (R[d, "ex"] == 0 || R[d, "e2"] == "") return
  if (R[d, "unk"] == R[d, "ex"])
    printf "%s%d idle conn above floor %d (%d->%d) -> closed by <= %s if not reused (idle %dm + check<=%s)\n", head, R[d, "ex"], R[d, "fl"], R[d, "act"], R[d, "fl"], at(R[d, "e2"]), R[d, "it"], dur(CHK)
  else if (R[d, "unk"] > 0)
    printf "%s%d idle conn above floor %d (%d->%d) -> some any time, all by <= %s (est.)\n", head, R[d, "ex"], R[d, "fl"], R[d, "act"], R[d, "fl"], at(R[d, "e2"])
  else
    printf "%s%d idle conn above floor %d (%d->%d) -> closing ~%s .. %s (est.)\n", head, R[d, "ex"], R[d, "fl"], R[d, "act"], R[d, "fl"], at(R[d, "e1"]), at(R[d, "e2"])
}

function psnap(n, nm,   i, d, w, a, na, x) {
  print "=========================================================================================="
  printf " JBoss connection pool snapshot : %s %s %s\n", ymd(now), hms(now), TZN
  printf " target    : %s   (host %s%s)\n", LABEL, HOSTN, ((TASK != "") ? ", task " TASK : "")
  printf " server    : %s %s  state=%s  controller=%s\n", nz(root["product-name"], "?"), nz(root["product-version"], ""), nz(root["server-state"], "?"), CTRL
  if (MEM != "") printf " memory    : %s\n", MEM
  if (rc != 0) perr()
  if (SCAN > 0) printf " idle check: IdleRemover wakes every %s (smallest idle-timeout %d min / 2), a pool is checked max once/min -> gap <= %s\n", dur(SCAN), SCAN / 30, dur(CHK)
  for (w in wseen) printf " io worker : %s  busy %s / max %s  queue %s\n", w, nz(wk[w, "busy-task-thread-count"], "?"), nz(wk[w, "max-pool-size"], nz(wk[w, "task-max-threads"], "?")), nz(wk[w, "queue-size"], "?")
  if (n == 0) print " (no datasource found)"
  for (i = 1; i <= n; i++) {
    d = nm[i]
    print LINE
    printf " [%s] %s  %s   STATUS: %s\n", d, dtype[d], nz(conf[d, "jndi-name"], "?"), R[d, "status"]
    printf "   config   : min %s / initial %s / max %s   prefill=%s strict-min=%s fair=%s\n", dv(d, "min-pool-size", 0), nz(conf[d, "initial-pool-size"], "-"), dv(d, "max-pool-size", 20), dv(d, "pool-prefill", "false"), dv(d, "pool-use-strict-min", "false"), dv(d, "pool-fair", "true")
    printf "              blocking-timeout %sms  idle-timeout %smin  allocation-retry %s x %sms\n", dv(d, "blocking-timeout-wait-millis", 30000), dv(d, "idle-timeout-minutes", 30), dv(d, "allocation-retry", 0), dv(d, "allocation-retry-wait-millis", 0)
    printf "              flush=%s  background-validation=%s (%sms)  validate-on-match=%s   (*=default)\n", dv(d, "flush-strategy", "FailingConnectionOnly"), dv(d, "background-validation", "false"), nz(conf[d, "background-validation-millis"], "-"), dv(d, "validate-on-match", "false")
    if (R[d, "status"] == "DISABLED") continue
    if (R[d, "son"] != "true") { print "   stats    : DISABLED -> counters are not collected.  enable with:  jbpool enable-stats"; continue }
    printf "   now      : in-use %d + idle %d = active %d / max %d   (use %d%%, free permits %d)\n", R[d, "use"], R[d, "idl"], R[d, "act"], R[d, "mx"], R[d, "pct"], R[d, "avl"]
    printf "   peak     : max-used %d   max-waiting %d   max-wait %s   max-get %s\n", R[d, "mxu"], R[d, "mwc"], ms(st[d, "MaxWaitTime"]), ms(st[d, "MaxGetTime"])
    printf "   total    : created %d  destroyed %d (idle-timeout %d, other %d)  waited %d  timeouts %d\n", R[d, "cr"], R[d, "de"], R[d, "to"], R[d, "de"] - R[d, "to"], R[d, "wc"], R[d, "bf"]
    printf "   timing   : avg-get %s   avg-create %s   avg-usage %s   max-usage %s\n", ms(st[d, "AverageGetTime"]), ms(st[d, "AverageCreationTime"]), ms(st[d, "AverageUsageTime"]), ms(st[d, "MaxUsageTime"])
    if (R[d, "q"] < 0) print "   queue    : (dump-queued-threads-in-pool not available)"
    else if (R[d, "q"] == 0) print "   queue    : 0 thread waiting for a connection"
    else {
      printf "   queue    : %d thread(s) WAITING for a connection (pool overflow)\n", R[d, "q"]
      printf "              %s\n", R[d, "qtxt"]
      printf "   forecast : waiting threads get a connection or fail with IJ000655 by <= %s (wait limit %s)\n", at(R[d, "qby"]), dur(R[d, "wl"] / 1000)
    }
    idleline(d, "   forecast : ")
    na = 0
    if (R[d, "son"] == "true" && R[d, "mx"] > 0 && R[d, "mxu"] >= R[d, "mx"]) a[++na] = "pool reached max-pool-size (MaxUsedCount=" R[d, "mxu"] "). guide: max-pool-size >= acceptable MaxUsedCount x 1.15, check slow SQL / leaks"
    if (R[d, "bf"] > 0) a[++na] = R[d, "bf"] " request(s) timed out waiting (look for IJ000453 / IJ000655 in the log)"
    if (R[d, "q"] > 0) a[++na] = "requests are queuing now -> jbpool threads  (shows which code is waiting)"
    x = nz(st[d, "MaxUsageTime"], 0) + 0
    if (x >= 60000) a[++na] = "a connection was held for " dur(x / 1000) " (MaxUsageTime) -> long transaction or connection leak ?"
    if (R[d, "neg"] == 1) a[++na] = "ActiveCount looked inconsistent (counter reset / flush); shown as in-use + idle"
    if (R[d, "mn"] > 0 && R[d, "keepmin"] == 0) a[++na] = "min-pool-size " R[d, "mn"] " is NOT kept after idle-timeout (pool-prefill / pool-use-strict-min are false)"
    for (x = 1; x <= na; x++) printf "   %s : %s\n", ((x == 1) ? "advice  " : "        "), a[x]
  }
  print "=========================================================================================="
}

function pwatch(n, nm,   i, d, ev) {
  printf "--- %s %s %s  #%d  %s  (%s %s, %s)  idle-check<=%s ---\n", ymd(now), hms(now), TZN, samp, LABEL, nz(root["product-name"], "?"), nz(root["product-version"], ""), nz(root["server-state"], "?"), ((SCAN > 0) ? dur(CHK) : "-")
  if (rc != 0) perr()
  if (n == 0) { print "  (no datasource)"; return }
  printf "%-20s %-14s %7s %5s %4s %4s %5s %5s %5s %5s %5s %5s %5s %7s\n", "DATASOURCE", "STATUS", "USE/MAX", "USE%", "ACT", "IDLE", "NEW", "DEL", "T/O", "WAIT", "TMOUT", "QUEUE", "MAXU", "AVGGET"
  for (i = 1; i <= n; i++) {
    d = nm[i]
    printf "%-20s %-14s %7s %4d%% %4d %4d %5s %5s %5s %5s %5s %5s %5d %7s\n", substr(d, 1, 20), R[d, "status"], R[d, "use"] "/" R[d, "mx"], R[d, "pct"], R[d, "act"], R[d, "idl"], sd(d, "dcr", "+"), sd(d, "dde", "-"), sd(d, "dto", "-"), sd(d, "dwc", "+"), sd(d, "dbf", "+"), ((R[d, "q"] < 0) ? "n/a" : R[d, "q"]), R[d, "mxu"], ms(st[d, "AverageGetTime"])
    if (R[d, "q"] > 0) printf "   queue  : %d waiting -> all resolved by <= %s : %s\n", R[d, "q"], at(R[d, "qby"]), R[d, "qtxt"]
    idleline(d, "   idle   : ")
    if (R[d, "has"] == 1) {
      ev = ""
      if (R[d, "dcr"] > 0) ev = ev " | pool grew " R[d, "pact"] "->" R[d, "act"] " (+" R[d, "dcr"] " created)"
      if (R[d, "dto"] > 0) ev = ev " | " R[d, "dto"] " closed by idle-timeout"
      if (R[d, "dde"] - R[d, "dto"] > 0) ev = ev " | " (R[d, "dde"] - R[d, "dto"]) " destroyed (validation/flush/error)"
      if (R[d, "dwc"] > 0) ev = ev " | " R[d, "dwc"] " request(s) had to wait"
      if (R[d, "dbf"] > 0) ev = ev " | " R[d, "dbf"] " TIMEOUT error(s) IJ000655"
      if (ev != "") print "   event " substr(ev, 2)
    }
  }
}
'

# ---------------------------------------------------------------- PART 3/3 : main + run
jbpool() {
  JBP_MODE=${1:-snapshot}
  case "$JBP_MODE" in help|-h|--help) jbp_help; return 0 ;; esac
  case "$JBP_MODE" in
    snapshot|snap|s) JBP_MODE=snapshot; JBP_INT=0; JBP_CNT=1 ;;
    watch|w)         JBP_MODE=watch; JBP_INT=${2:-10}; JBP_CNT=${3:-0} ;;
    csv)             JBP_INT=${2:-10}; JBP_CNT=${3:-0} ;;
    threads|t|enable-stats|disable-stats|raw) ;;
    *) echo "[jbpool] unknown mode: $JBP_MODE" >&2; jbp_help; return 1 ;;
  esac
  jbp_setup || return 1
  echo "[jbpool] target=$JBP_LBL  controller=$JBP_CTRL  cli=$JBP_CLI  server-pid=${JBP_PID:-?}" >&2
  if [ "$JBP_NPROC" -gt 1 ]; then
    echo "[jbpool] WARNING: $JBP_NPROC JBoss servers are visible (shared pid namespace?). check MGMT_PORT." >&2
  fi
  jbp_names || return 1
  [ -z "$JBP_NAMES" ] && echo "[jbpool] no datasource is defined in this server" >&2
  case "$JBP_MODE" in
    threads|t)     jbp_threads; return 0 ;;
    enable-stats)  jbp_stats true; return 0 ;;
    disable-stats) jbp_stats false; return 0 ;;
    raw)           jbp_mkfile; jbp_cli "$JBP_F"; rm -f "$JBP_F" "$JBP_E"; return 0 ;;
  esac
  JBP_hdr=0
  if [ -n "${JBP_CSV:-}" ] && [ ! -s "$JBP_CSV" ]; then JBP_hdr=1; fi
  jbp_loop | awk -v MODE="$JBP_MODE" -v TZOFF="$(date +%z 2>/dev/null)" -v TZN="$(date +%Z 2>/dev/null)" \
    -v WARN="${JBP_WARN:-80}" -v LABEL="$JBP_LBL" -v HOSTN="$JBP_HOSTN" -v TASK="$JBP_TASK" \
    -v CTRL="$JBP_CTRL" -v MEM="$JBP_MEM" -v CSVF="${JBP_CSV:-}" -v CSVHDR="$JBP_hdr" "$JBP_AWK"
}

if [ $# -eq 0 ]; then jbpool snapshot; else jbpool "$@"; fi
