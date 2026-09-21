#!/usr/bin/env bash
# =============================================================================
# benchmark.sh - Compara norm_scalar vs norm_vector para muchos valores de N
#                y genera CSV listos para graficar en Excel.
#
# Ubicacion: raiz del proyecto (la carpeta donde esta el Makefile).
#
# Uso:
#   chmod +x benchmark.sh
#   ./benchmark.sh                          # configuracion por defecto
#   ./benchmark.sh -t 15 -c 2               # 15 trials, fijado al nucleo 2
#   ./benchmark.sh -n "8 64 1000 100000"    # lista propia de N
#   ./benchmark.sh -h                       # ayuda
#
# Salidas (carpeta resultados/<fecha_hora>/):
#   resultados_raw.csv            una fila por (version, N, trial)
#   resumen.csv                   una fila por N (media, mediana, min, std, speedup)
#   resumen_excel_es.csv          igual, pero con ';' y coma decimal (Excel en espanol)
#   resultados_raw_excel_es.csv   idem para el raw
#   info_sistema.txt              CPU, caches, versiones (util para el informe)
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

# ------------------------- configuracion por defecto -------------------------
TRIALS=10                 # corridas independientes por (version, N)
TARGET_ELEMS=50000000     # trabajo total aprox. por corrida: reps = TARGET_ELEMS / N
MIN_REPS=5
MAX_REPS=200000
CPU=""                    # si se indica, fija el proceso a ese nucleo (taskset)
FORCE=0
# Mezcla: potencias de 2, N no multiplos de 8 (remanente) y potencias de 10.
NS="1 2 4 7 8 15 16 31 32 63 64 100 127 128 255 256 500 512 1000 1001 1024 \
2048 4096 8192 10000 16384 32768 65536 100000 131072 262144 524288 1000000 \
2097152 4194304 8388608 10000000"
STAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="resultados/$STAMP"

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  cat <<EOF
Opciones:
  -t TRIALS   corridas por (version, N)              [por defecto: $TRIALS]
  -e ELEMS    trabajo objetivo por corrida (reps=ELEMS/N) [por defecto: $TARGET_ELEMS]
  -n "LISTA"  lista de N separada por espacios
  -c CPU      fijar a un nucleo con taskset (ej. -c 2)
  -o DIR      carpeta de salida
  -f          continuar aunque falle la verificacion previa de correctitud
EOF
}

while getopts "t:e:n:c:o:fh" opt; do
  case $opt in
    t) TRIALS=$OPTARG ;;
    e) TARGET_ELEMS=$OPTARG ;;
    n) NS=$OPTARG ;;
    c) CPU=$OPTARG ;;
    o) OUTDIR=$OPTARG ;;
    f) FORCE=1 ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

# ------------------------- comprobaciones iniciales --------------------------
for cmd in python3 gcc nasm make; do
  command -v "$cmd" >/dev/null || { echo "Falta '$cmd'. Instalelo (sudo apt install nasm gcc make python3)."; exit 1; }
done
grep -q avx2 /proc/cpuinfo || echo "AVISO: esta CPU no reporta AVX2; norm_vector podria fallar."

PIN=()
if [[ -n "$CPU" ]]; then
  command -v taskset >/dev/null || { echo "taskset no disponible (paquete util-linux)."; exit 1; }
  PIN=(taskset -c "$CPU")
fi

echo ">> Compilando..."
make -s 2>&1 | grep -v -e 'GNU-stack' -e 'deprecated' || true
[[ -x bin/norm_scalar && -x bin/norm_vector ]] || { echo "No se generaron los binarios."; exit 1; }

# Directorio de trabajo en RAM (tmpfs) para que el I/O de disco no estorbe.
if [[ -d /dev/shm && -w /dev/shm ]]; then WORK=$(mktemp -d -p /dev/shm bench.XXXXXX)
else WORK=$(mktemp -d); fi
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUTDIR"

MAXN=0; for n in $NS; do (( n > MAXN )) && MAXN=$n; done
GENN=$(( MAXN > 100000 ? MAXN : 100000 ))   # el preflight usa hasta N=100000

# ------------------------- info del sistema ----------------------------------
{
  echo "fecha:      $(date)"
  echo "kernel:     $(uname -sr)"
  echo "gcc:        $(gcc --version | head -1)"
  echo "nasm:       $(nasm -v)"
  echo "trials:     $TRIALS   target_elems: $TARGET_ELEMS   cpu_pin: ${CPU:-ninguno}"
  echo "governor:   $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo n/d)"
  lscpu | grep -E 'Model name|^CPU\(s\)|MHz|L1d|L1i|L2|L3' || true
} > "$OUTDIR/info_sistema.txt"

# ------------------------- datos de entrada ----------------------------------
# Se genera UN archivo maestro de floats (semilla fija) y cada N usa sus primeros
# N valores, de modo que todos los tamanos comparten los mismos datos.
echo ">> Generando datos maestros ($GENN floats)..."
python3 - "$GENN" "$WORK/master.raw" <<'PY'
import sys, array, random
n, out = int(sys.argv[1]), sys.argv[2]
try:
    import numpy as np
    np.random.default_rng(42).uniform(-100, 100, n).astype('<f4').tofile(out)
except ImportError:
    random.seed(42)
    with open(out, 'wb') as f:
        array.array('f', (random.uniform(-100, 100) for _ in range(n))).tofile(f)
PY

make_input() {   # $1 = N, $2 = archivo destino  (formato: int32 N + N floats)
  python3 -c 'import sys,struct;sys.stdout.buffer.write(struct.pack("<i",int(sys.argv[1])))' "$1" > "$2"
  head -c $(( 4 * $1 )) "$WORK/master.raw" >> "$2"
}

run_once() {     # $1=version  $2=input  $3=reps  -> imprime kernel_ms
  local out="$WORK/out_$1.dat"
  "${PIN[@]+"${PIN[@]}"}" "./bin/norm_$1" "$2" "$out" "$3" >/dev/null
  sed -n 's/^kernel_ms=//p' "$out.stats.txt"
}

# ------------------------- verificacion previa de correctitud ----------------
# No tiene sentido medir tiempos de un kernel que calcula mal.
echo ">> Verificando correctitud de ambas versiones (estadisticos + arreglo normalizado)..."
FAILED=0
for n in 1 7 8 15 1001 100000; do
  make_input "$n" "$WORK/chk.dat"
  for v in scalar vector; do
    run_once "$v" "$WORK/chk.dat" 1 >/dev/null
    if ! python3 - "$WORK/chk.dat" "$WORK/out_$v.dat" "$WORK/out_$v.dat.stats.txt" <<'PY'
import sys, struct, math
inp, outp, statp = sys.argv[1:4]
def rd(p):
    d = open(p, 'rb').read(); n = struct.unpack('<i', d[:4])[0]
    return n, (list(struct.unpack(f'<{n}f', d[4:4+4*n])) if n > 0 else [])
n, x = rd(inp); _, o = rd(outp)
st = {k: float(v) for k, v in (l.strip().split('=', 1) for l in open(statp) if '=' in l)}
m = sum(x) / n; var = sum((v - m) ** 2 for v in x) / n; s = math.sqrt(var)
ref = {'sum': sum(x), 'mean': m, 'var': var, 'min': min(x), 'max': max(x)}
bad = [f"{k}: ref={r:.6g} obt={st[k]:.6g}" for k, r in ref.items()
       if abs(st[k] - r) / max(abs(r), 1.0) > 1e-3]
nref = [(v - m) / s if s > 1e-12 else v for v in x]
err = max((abs(a - b) for a, b in zip(o, nref)), default=0.0)
if err > 1e-3: bad.append(f"normalize_array: error abs. max = {err:.3g}")
if bad: print("   " + "; ".join(bad)); sys.exit(1)
PY
    then echo "   FALLA: version=$v N=$n"; FAILED=1; fi
  done
done
if (( FAILED )); then
  echo "!! La verificacion fallo (ver mensajes arriba)."
  if (( ! FORCE )); then echo "   Corrija el kernel o use -f para medir de todos modos."; exit 1; fi
  echo "   Continuando por -f: los tiempos NO son comparables hasta corregirlo."
else
  echo "   OK: ambas versiones producen resultados correctos."
fi

# ------------------------- mediciones ----------------------------------------
RAW="$OUTDIR/resultados_raw.csv"
echo "version,N,trial,reps,kernel_ms" > "$RAW"
total=$(wc -w <<< "$NS"); idx=0
echo ">> Midiendo: $total valores de N x 2 versiones x $TRIALS trials"
for n in $NS; do
  idx=$((idx + 1))
  reps=$(( TARGET_ELEMS / n ))
  if (( reps < MIN_REPS )); then reps=$MIN_REPS; fi
  if (( reps > MAX_REPS )); then reps=$MAX_REPS; fi
  make_input "$n" "$WORK/in.dat"
  printf "[%2d/%d] N=%-9d reps=%-7d " "$idx" "$total" "$n" "$reps"

  # calentamiento (descartado): estabiliza cache, frecuencia y paginas
  run_once scalar "$WORK/in.dat" "$reps" >/dev/null
  run_once vector "$WORK/in.dat" "$reps" >/dev/null

  for (( t = 1; t <= TRIALS; t++ )); do
    # se alterna el orden para que ninguna version quede siempre "primera"
    if (( t % 2 )); then order="scalar vector"; else order="vector scalar"; fi
    for v in $order; do
      ms=$(run_once "$v" "$WORK/in.dat" "$reps")
      echo "$v,$n,$t,$reps,$ms" >> "$RAW"
    done
    printf "."
  done
  echo " listo"
done

# ------------------------- resumen y CSV para Excel --------------------------
python3 - "$RAW" "$OUTDIR" <<'PY'
import csv, sys, statistics as S, os
raw, outdir = sys.argv[1], sys.argv[2]
data = {}
with open(raw) as f:
    for r in csv.DictReader(f):
        data.setdefault((int(r['N']), r['version']), []).append(float(r['kernel_ms']))
        data[(int(r['N']), 'reps')] = int(r['reps'])

def stats(xs):
    return (S.mean(xs), S.median(xs), min(xs), S.stdev(xs) if len(xs) > 1 else 0.0)

hdr = ['N', 'reps', 'working_set_KB',
       'scalar_mean_ms', 'scalar_median_ms', 'scalar_min_ms', 'scalar_std_ms',
       'vector_mean_ms', 'vector_median_ms', 'vector_min_ms', 'vector_std_ms',
       'speedup_median', 'speedup_min', 'scalar_ns_por_elem', 'vector_ns_por_elem']
rows = []
for n in sorted({k[0] for k in data}):
    sm, smed, smin, ssd = stats(data[(n, 'scalar')])
    vm, vmed, vmin, vsd = stats(data[(n, 'vector')])
    rows.append([n, data[(n, 'reps')], round(n * 4 * 2 / 1024, 3),   # arreglos in + out
                 sm, smed, smin, ssd, vm, vmed, vmin, vsd,
                 smed / vmed if vmed else float('nan'),
                 smin / vmin if vmin else float('nan'),
                 smed * 1e6 / n, vmed * 1e6 / n])

def fmt(x): return f"{x:.6f}" if isinstance(x, float) else str(x)
def write(path, table, header, es=False):
    with open(path, 'w', newline='', encoding='utf-8-sig' if es else 'utf-8') as f:
        w = csv.writer(f, delimiter=';' if es else ',')
        w.writerow(header)
        for r in table:
            cells = [fmt(c) for c in r]
            w.writerow([c.replace('.', ',') for c in cells] if es else cells)

write(os.path.join(outdir, 'resumen.csv'), rows, hdr)
write(os.path.join(outdir, 'resumen_excel_es.csv'), rows, hdr, es=True)

with open(raw) as f:
    rr = list(csv.reader(f))
write(os.path.join(outdir, 'resultados_raw_excel_es.csv'),
      [[c for c in r] for r in rr[1:]], rr[0], es=True)

print(f"\n{'N':>10} {'scalar[ms]':>12} {'vector[ms]':>12} {'speedup':>9}")
for r in rows:
    print(f"{r[0]:>10} {r[4]:>12.6f} {r[8]:>12.6f} {r[11]:>8.2f}x")
PY

echo
echo "Listo. Archivos en: $OUTDIR/"
ls -1 "$OUTDIR"
