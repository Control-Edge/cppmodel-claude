#!/bin/bash
# Runs one CppModel simulation repeatedly with different inputs/parameters (a sweep), used by the
# cppmodel:parameter-sweep skill. Every API call goes through cppmodel-fetch.sh.
#
#   cppmodel-sweep.sh <plan.json> <out-dir> [--dry-run] [--timeout <seconds>] [--workspace <id>]
#
# Plan (JSON):
#   {
#     "simulation": "<name passed to CMODEL_SIMULATE>",
#     "binary": "<path to the built simulation, relative to the repo root>",
#     "base": "defaults" | "current" | { <full inputs document> },
#     "parameters": { "<name>": [v1, v2, ...] },         // grid: every combination of these ...
#     "inputs": { "<label>": { "<variant>": {"x": [...], "y": [...]} } },   // ... and these
#     "runs": [ { "name": "...", "parameters": {...}, "inputs": { "<label>": {"x","y"} } } ]
#   }
# Use either the grid keys (parameters/inputs) or "runs", not both. "base" is what each run starts
# from: "defaults" (the default) = nothing, so every name the run doesn't set uses the fallback in
# the code; "current" = the document pending now, or else the latest execution's recorded values.
#
# Posted inputs are consumed by the next execution, so each run posts its own document right before
# it starts. After every run the execution's recorded inputs/parameters are compared with what was
# posted, and the sweep stops if the simulation didn't actually use them (SDKs before 0.6.1
# consume posted documents without applying them).
#
# Output in <out-dir>: runs/NNN.json (posted body), runs/NNN.log (binary output), results/NNN.json
# (the execution from the API), summary.json. A document that was already pending before the
# sweep is saved to pending-before.json and re-posted at the end.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FETCH="$SCRIPT_DIR/cppmodel-fetch.sh"

PLAN="" OUT="" DRY_RUN=0 TIMEOUT="" WS_ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --workspace) WS_ARGS=(--workspace "$2"); shift 2 ;;
    *) if [ -z "$PLAN" ]; then PLAN="$1"; elif [ -z "$OUT" ]; then OUT="$1"; else echo "Unexpected argument: $1" >&2; exit 1; fi; shift ;;
    esac
done
[ -f "$PLAN" ] && [ -n "$OUT" ] || { echo "Usage: $0 <plan.json> <out-dir> [--dry-run] [--timeout <s>] [--workspace <id>]" >&2; exit 1; }

REPO_ROOT=$(git rev-parse --show-toplevel)
mkdir -p "$OUT/runs" "$OUT/results"
OUT="$(cd "$OUT" && pwd)"

fetch() { "$FETCH" "${WS_ARGS[@]+"${WS_ARGS[@]}"}" "$@"; }

plan_get() { python3 -c "import json,sys; v=json.load(open(sys.argv[1])).get(sys.argv[2], sys.argv[3]); print(v if isinstance(v, str) else 'inline')" "$PLAN" "$1" "${2:-}"; }
SIMULATION="$(plan_get simulation)"
BINARY="$(plan_get binary)"
BASE_KIND="$(plan_get base defaults)"
[ -n "$SIMULATION" ] || { echo "Plan has no \"simulation\"" >&2; exit 1; }
[[ "$BINARY" = /* ]] || BINARY="$REPO_ROOT/$BINARY"
if [ "$DRY_RUN" = 0 ] && [ ! -x "$BINARY" ]; then
    echo "Simulation binary not found or not executable: $BINARY (build it first)" >&2
    exit 1
fi
case "$BASE_KIND" in defaults|current|inline) ;; *) echo "Unknown base \"$BASE_KIND\" - use \"defaults\", \"current\", or an inline document." >&2; exit 1 ;; esac

rm -f "$OUT"/runs/* "$OUT"/results/* "$OUT/summary.json" "$OUT/pending-before.json" "$OUT/base.json" "$OUT/known-names.json"

# A document someone already posted for the next execution. GET returns 404 ("No input data
# found") when there is none, which is the normal case.
HAVE_PENDING=0
if [ "$DRY_RUN" = 0 ] || [ "$BASE_KIND" = current ]; then
    if fetch inputs "$SIMULATION" >"$OUT/pending-before.json" 2>/dev/null; then
        HAVE_PENDING=1
        echo "Note: '$SIMULATION' already had inputs pending; they'll be re-posted after the sweep."
    elif grep -q '"NOT_FOUND"' "$OUT/pending-before.json"; then
        rm -f "$OUT/pending-before.json"
    else
        cat "$OUT/pending-before.json" >&2
        echo "Could not read the pending inputs of '$SIMULATION'." >&2
        exit 1
    fi
fi
if [ "$BASE_KIND" = current ]; then
    if [ "$HAVE_PENDING" = 1 ]; then
        cp "$OUT/pending-before.json" "$OUT/base.json"
    elif fetch "$SIMULATION" >"$OUT/base.json" 2>/dev/null; then
        echo "Base: the latest execution's recorded inputs/parameters."
    else
        echo '{"inputs": [], "parameters": {}}' >"$OUT/base.json"
        echo "Base: defaults (no pending document and no previous execution)."
    fi
fi

# Names the simulation is known to use: the latest execution records every input/parameter it read.
KNOWN_NAMES="$OUT/known-names.json"
if fetch "$SIMULATION" 2>/dev/null | python3 -c "
import json, sys
d = json.load(sys.stdin)
json.dump({'inputs': [s['label'] for s in d.get('inputs', [])], 'parameters': list(d.get('parameters', {}))}, open(sys.argv[1], 'w'))
" "$KNOWN_NAMES" 2>/dev/null; then :; else rm -f "$KNOWN_NAMES"; fi

# Expand the plan into one full inputs document per run.
python3 - "$PLAN" "$OUT" <<'EOF'
import copy, datetime, itertools, json, sys
plan_path, out = sys.argv[1], sys.argv[2]
plan = json.load(open(plan_path))
base = plan.get("base", "defaults")
if base == "current":
    base = json.load(open(f"{out}/base.json"))
elif base == "defaults":
    base = {}
base = {"inputs": base.get("inputs", []), "parameters": base.get("parameters", {})}

grid_params = plan.get("parameters", {})
grid_inputs = plan.get("inputs", {})
if plan.get("runs") and (grid_params or grid_inputs):
    sys.exit('Plan uses both "runs" and grid keys ("parameters"/"inputs") - use one or the other.')

runs = []
if plan.get("runs"):
    for i, r in enumerate(plan["runs"], 1):
        runs.append({"name": r.get("name", f"run {i}"), "parameters": r.get("parameters", {}),
                     "inputs": r.get("inputs", {}), "variants": {}})
else:
    p_names, i_labels = list(grid_params), list(grid_inputs)
    axes = [grid_params[n] for n in p_names] + [list(grid_inputs[l].items()) for l in i_labels]
    for combo in itertools.product(*axes):
        params = dict(zip(p_names, combo[:len(p_names)]))
        chosen = dict(zip(i_labels, combo[len(p_names):]))
        name = ", ".join([f"{k}={v}" for k, v in params.items()] + [f"{l}={v[0]}" for l, v in chosen.items()])
        runs.append({"name": name or "base", "parameters": params,
                     "inputs": {l: v[1] for l, v in chosen.items()},
                     "variants": {l: v[0] for l, v in chosen.items()}})

# The server stores whatever it's given without validating it, so validate here.
def check_series(where, label, s):
    x, y = s.get("x"), s.get("y")
    if not isinstance(x, list) or not isinstance(y, list) or not x:
        sys.exit(f'{where}: input "{label}" needs non-empty "x" and "y" lists')
    if len(x) != len(y):
        sys.exit(f'{where}: input "{label}" has {len(x)} x values but {len(y)} y values')
    if any(b < a for a, b in zip(x, x[1:])):
        sys.exit(f'{where}: input "{label}" has x values out of order')

now = datetime.datetime.now().strftime("%d-%m-%Y %H:%M:%S")
for i, r in enumerate(runs, 1):
    body = copy.deepcopy(base)
    body["executionTime"] = now
    body["parameters"].update(r["parameters"])
    for label, series in r["inputs"].items():
        check_series(r["name"], label, series)
        body["inputs"] = [s for s in body["inputs"] if s["label"] != label]
        body["inputs"].append({"label": label, "x": series["x"], "y": series["y"]})
    json.dump(body, open(f"{out}/runs/{i:03d}.json", "w"), indent=2)
    meta = {"run": i, "name": r["name"], "parameters": r["parameters"],
            "inputs": r["variants"] or sorted(r["inputs"])}
    json.dump(meta, open(f"{out}/runs/{i:03d}.meta.json", "w"), indent=2)
print(f"{len(runs)} run(s) prepared in {out}/runs")

# A posted name the code never reads is accepted and even recorded, so a typo only shows up as the
# fallback being used. Warn about names the latest execution didn't read before anything is posted.
import os
known_path = f"{out}/known-names.json"
if os.path.exists(known_path):
    known = json.load(open(known_path))
    varied_p = sorted({k for r in runs for k in r["parameters"]} - set(known["parameters"]))
    varied_i = sorted({k for r in runs for k in r["inputs"]} - set(known["inputs"]))
    if varied_p or varied_i:
        print("WARNING: not read by the latest execution of this simulation - check for typos:"
              + "".join(f"\n  parameter \"{k}\"" for k in varied_p)
              + "".join(f"\n  input \"{k}\"" for k in varied_i), file=sys.stderr)
else:
    print("note: no previous execution to check names against - verify them against the source.", file=sys.stderr)
EOF

RUN_FILES=("$OUT"/runs/[0-9][0-9][0-9].json)
if [ "$DRY_RUN" = 1 ]; then
    for f in "${RUN_FILES[@]}"; do
        python3 -c "import json,sys; m=json.load(open(sys.argv[1])); print(f'{m[\"run\"]:03d}  {m[\"name\"]}')" "${f%.json}.meta.json"
    done
    echo "Dry run - nothing posted or executed."
    exit 0
fi

restore() {
    if [ "$HAVE_PENDING" = 1 ]; then
        echo "Re-posting the inputs that were pending before the sweep ..."
        fetch set-inputs "$SIMULATION" "$OUT/pending-before.json" || echo "WARNING: re-post failed - post $OUT/pending-before.json manually." >&2
    fi
}
trap restore EXIT
# Route Ctrl-C / kill through a normal exit so the EXIT trap always runs.
trap 'exit 130' INT TERM

top_execution_id() {
    fetch executions "$SIMULATION" 2>/dev/null | python3 -c "import json,sys; items=json.load(sys.stdin).get('items', []); print(items[0]['id'] if items else '')" || true
}
PREV_ID="$(top_execution_id)"

SUMMARY_LINES="$OUT/.summary.jsonl"
: >"$SUMMARY_LINES"
for f in "${RUN_FILES[@]}"; do
    n="$(basename "$f" .json)"
    echo "=== Run $n: $(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['name'])" "$OUT/runs/$n.meta.json")"
    fetch set-inputs "$SIMULATION" "$f"

    set +e
    (
        cd "$REPO_ROOT"
        set -a; source .env; set +a
        unset CPPMODEL_OFFLINE
        if [ -n "$TIMEOUT" ]; then exec timeout "$TIMEOUT" "$BINARY"; else exec "$BINARY"; fi
    ) </dev/null >"$OUT/runs/$n.log" 2>&1
    code=$?
    set -e

    # An offline run never read the posted inputs, so none of its numbers mean anything.
    if grep -q "Running offline" "$OUT/runs/$n.log"; then
        echo "Run $n ran OFFLINE (API unreachable) - posted inputs were not used. Aborting sweep." >&2
        exit 1
    fi

    exec_id="$(top_execution_id)"
    if [ -z "$exec_id" ] || [ "$exec_id" = "$PREV_ID" ]; then
        echo "Run $n produced no new execution on the server (see runs/$n.log). Aborting sweep." >&2
        exit 1
    fi
    PREV_ID="$exec_id"
    fetch execution "$SIMULATION" "$exec_id" >"$OUT/results/$n.json"

    # Did the simulation read what was posted? The execution records every input and parameter it
    # actually read - fallback values included - so compare those with the posted document.
    set +e
    python3 - "$f" "$OUT/results/$n.json" "$OUT/runs/$n.meta.json" "$code" "$exec_id" "$n" >>"$SUMMARY_LINES" <<'EOF'
import bisect, json, sys
posted_path, rec_path, meta_path, code, exec_id, n = sys.argv[1:]
posted, rec, meta = json.load(open(posted_path)), json.load(open(rec_path)), json.load(open(meta_path))

def same(a, b):
    return abs(float(a) - float(b)) <= 1e-6 * max(1.0, abs(float(a)))

def hold(series, t):
    i = bisect.bisect_right(series["x"], t) - 1
    return series["y"][i] if i >= 0 else None

mismatches = []
rec_params = rec.get("parameters", {})
for k, v in posted.get("parameters", {}).items():
    if k.startswith("CppModel."):
        continue
    if k not in rec_params:
        mismatches.append(f'parameter "{k}": posted {v}, missing from the execution record')
    elif not same(v, rec_params[k]):
        mismatches.append(f'parameter "{k}": posted {v}, simulation read {rec_params[k]}')
rec_inputs = {s["label"]: s for s in rec.get("inputs", [])}
for s in posted.get("inputs", []):
    r = rec_inputs.get(s["label"])
    if r is None:
        mismatches.append(f'input "{s["label"]}": posted, missing from the execution record')
        continue
    for t, got in zip(r["x"], r["y"]):
        want = hold(s, t)
        if want is not None and not same(want, got):
            mismatches.append(f'input "{s["label"]}" at {t} ms: posted {want}, simulation read {got}')
            break

meta.update(exitCode=int(code), passed=code == "0", executionId=exec_id, applied=not mismatches,
            results=f"results/{n}.json", log=f"runs/{n}.log")
print(json.dumps(meta))
if mismatches:
    print("Run " + n + ": the simulation did NOT use the posted values:\n  " + "\n  ".join(mismatches) +
          "\nIts results describe the default run, not this scenario (SDKs before 0.6.1 don't apply"
          " posted inputs - check dependencies/). Aborting sweep.", file=sys.stderr)
    sys.exit(2)
EOF
    check=$?
    set -e
    [ "$check" = 0 ] || exit 1
    echo "    exit $code, execution $exec_id"
done

python3 -c "
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
json.dump(rows, open(sys.argv[2], 'w'), indent=2)
print(f'{sum(r[\"passed\"] for r in rows)}/{len(rows)} runs passed. Summary: {sys.argv[2]}')" "$SUMMARY_LINES" "$OUT/summary.json"
rm -f "$SUMMARY_LINES"
