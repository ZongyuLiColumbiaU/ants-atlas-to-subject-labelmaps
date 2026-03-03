#!/usr/bin/env bash
# step1_ANTs_registration_generate_population_template_v2.sh
#
# Build a population template with ANTs buildtemplateparallel.sh and organize outputs
# into a stable directory tree:
#   <OUT_DIR>/output/00_logs/
#   <OUT_DIR>/output/01_warps/
#   <OUT_DIR>/output/02_warped-input/
#
# Key outputs:
#   - output/02_warped-input/warped_template.nii.gz
#   - output/01_warps/warped_<SUBJECT_BASENAME>{Affine.txt,Warp.nii.gz,InverseWarp.nii.gz}
#
# Notes:
# - Resumable by default: if the final template already exists, the build is skipped unless --force.
# - Inputs are symlinked into OUT_DIR by default (fast, avoids duplication). Use --copy to copy instead.

set -euo pipefail
IFS=$'\n\t'

###############################################################################
# Defaults (sample placeholders)
###############################################################################
INPUT_DIR="/path/to/input_niftis"
OUT_DIR="/path/to/output_template_dir"
INPUT_PATTERN="*_Tmean.nii.gz"

ANTS_SCRIPTS="/opt/ANTs/Scripts"
ANTS_JOBS="8"
ANTS_METRIC="10x20x10"
INIT_TEMPLATE=""

DO_SYMLINK="1"      # 1 = symlink inputs into OUT_DIR; 0 = copy inputs
FORCE_REBUILD="0"   # 1 = rebuild even if final template exists
DRY_RUN="0"         # 1 = print commands only

###############################################################################
# Helpers
###############################################################################
usage() {
  cat <<'EOF'
Usage:
  step1_ANTs_registration_generate_population_template_v2.sh \
    -i INPUT_DIR \
    -o OUT_DIR \
    [-p INPUT_PATTERN] \
    [-s ANTS_SCRIPTS] \
    [-j ANTS_JOBS] \
    [-m ANTS_METRIC] \
    [-z INIT_TEMPLATE] \
    [--copy] \
    [--force] \
    [--dry-run]

Required:
  -i  Input directory containing subject NIfTI images
  -o  Output directory for population template + transforms

Optional:
  -p  Glob pattern for inputs (default: "*_Tmean.nii.gz")
  -s  ANTs Scripts directory (default: "/opt/ANTs/Scripts")
  -j  Parallel jobs passed to buildtemplateparallel.sh (default: 8)
  -m  Multi-resolution schedule string (default: "10x20x10")
  -z  Initial template (optional). If provided and exists, passed via -z.

Flags:
  --copy     Copy inputs into OUT_DIR instead of symlinking
  --force    Rebuild even if output/02_warped-input/warped_template.nii.gz exists
  --dry-run  Print commands without executing

Outputs (inside OUT_DIR):
  output/00_logs/          log files
  output/01_warps/         per-subject transforms (Affine/Warp/InverseWarp)
  output/02_warped-input/  population template and template-related artifacts

EOF
}

log() { echo "[$(date '+%F %T')] $*"; }

die() { echo "[FATAL] $*" 1>&2; exit 1; }

run() {
  if [ "$DRY_RUN" = "1" ]; then
    echo "[DRY-RUN] $*"
  else
    eval "$@"
  fi
}

###############################################################################
# Args
###############################################################################
while [ $# -gt 0 ]; do
  case "$1" in
    -i) INPUT_DIR="$2"; shift 2 ;;
    -o) OUT_DIR="$2"; shift 2 ;;
    -p) INPUT_PATTERN="$2"; shift 2 ;;
    -s) ANTS_SCRIPTS="$2"; shift 2 ;;
    -j) ANTS_JOBS="$2"; shift 2 ;;
    -m) ANTS_METRIC="$2"; shift 2 ;;
    -z) INIT_TEMPLATE="$2"; shift 2 ;;
    --copy) DO_SYMLINK="0"; shift 1 ;;
    --force) FORCE_REBUILD="1"; shift 1 ;;
    --dry-run) DRY_RUN="1"; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1 (use -h/--help)" ;;
  esac
done

###############################################################################
# Validations
###############################################################################
[ -d "$INPUT_DIR" ] || die "INPUT_DIR does not exist: $INPUT_DIR"
[ -d "$ANTS_SCRIPTS" ] || die "ANTS_SCRIPTS does not exist: $ANTS_SCRIPTS"
[ -x "$ANTS_SCRIPTS/buildtemplateparallel.sh" ] || die "Missing or not executable: $ANTS_SCRIPTS/buildtemplateparallel.sh"

run "mkdir -p \"$OUT_DIR\""
run "cd \"$OUT_DIR\""

run "mkdir -p output output/00_logs output/01_warps output/02_warped-input"

LOG_FILE="output/00_logs/run_$(date '+%Y%m%d_%H%M%S').log"
if [ "$DRY_RUN" != "1" ]; then
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

log "INPUT_DIR      = $INPUT_DIR"
log "OUT_DIR        = $OUT_DIR"
log "INPUT_PATTERN  = $INPUT_PATTERN"
log "ANTS_SCRIPTS   = $ANTS_SCRIPTS"
log "ANTS_JOBS      = $ANTS_JOBS"
log "ANTS_METRIC    = $ANTS_METRIC"
log "INIT_TEMPLATE  = ${INIT_TEMPLATE:-<empty>}"
log "DO_SYMLINK     = $DO_SYMLINK (1=symlink,0=copy)"
log "FORCE_REBUILD  = $FORCE_REBUILD"
log "DRY_RUN        = $DRY_RUN"

###############################################################################
# Collect inputs
###############################################################################
shopt -s nullglob
src_files=( "$INPUT_DIR"/$INPUT_PATTERN )
shopt -u nullglob

[ "${#src_files[@]}" -gt 0 ] || die "No inputs matching '$INPUT_PATTERN' in $INPUT_DIR"

log "Found ${#src_files[@]} input volumes."
for f in "${src_files[@]}"; do
  log "  - $f"
done

###############################################################################
# Prepare local inputs for buildtemplateparallel.sh
###############################################################################
inputs=()

log "Preparing local inputs in OUT_DIR (symlink or copy)..."
for src in "${src_files[@]}"; do
  bn="$(basename "$src")"

  if [ ! -e "$bn" ]; then
    if [ "$DO_SYMLINK" = "1" ]; then
      run "ln -s \"$src\" \"$bn\""
    else
      run "cp -v \"$src\" \"$bn\""
    fi
  fi

  inputs+=( "$bn" )
done

###############################################################################
# Build template (resumable)
###############################################################################
FINAL_TEMPLATE="output/02_warped-input/warped_template.nii.gz"

if [ -f "$FINAL_TEMPLATE" ] && [ "$FORCE_REBUILD" != "1" ]; then
  log "Template exists: $FINAL_TEMPLATE"
  log "Skipping build (use --force to rebuild)."
else
  log "Running buildtemplateparallel.sh ..."

  BUILD_CMD="\"$ANTS_SCRIPTS/buildtemplateparallel.sh\" \
    -n 0 -d 3 -o warped_ -c 2 -m \"$ANTS_METRIC\" -j \"$ANTS_JOBS\" -s CC -t GR"

  if [ -n "$INIT_TEMPLATE" ] && [ -f "$INIT_TEMPLATE" ]; then
    log "Using initial template (-z): $INIT_TEMPLATE"
    BUILD_CMD="$BUILD_CMD -z \"$INIT_TEMPLATE\""
  else
    log "No initial template used (building from scratch)."
  fi

  for x in "${inputs[@]}"; do
    BUILD_CMD="$BUILD_CMD \"$x\""
  done

  run "$BUILD_CMD"

  log "Organizing outputs into output/01_warps and output/02_warped-input ..."

  # Per-subject transforms
  run "mv -f warped_*Warp.nii.gz        output/01_warps/ 2>/dev/null || true"
  run "mv -f warped_*InverseWarp.nii.gz output/01_warps/ 2>/dev/null || true"
  run "mv -f warped_*Affine.txt         output/01_warps/ 2>/dev/null || true"

  # Template-related artifacts (names vary slightly across ANTs versions)
  run "mv -f warped_template.nii.gz          output/02_warped-input/ 2>/dev/null || true"
  run "mv -f warped_template0.nii.gz         output/02_warped-input/ 2>/dev/null || true"
  run "mv -f warped_template1.nii.gz         output/02_warped-input/ 2>/dev/null || true"
  run "mv -f warped_templatewarp.nii.gz      output/02_warped-input/ 2>/dev/null || true"
  run "mv -f warped_templateAffine.txt       output/02_warped-input/ 2>/dev/null || true"
  run "mv -f warped_*deformed.nii.gz         output/02_warped-input/ 2>/dev/null || true"

  # Canonicalize template filename to output/02_warped-input/warped_template.nii.gz
  if [ ! -f "$FINAL_TEMPLATE" ]; then
    # Priority list of possible template outputs
    candidates=(
      "output/02_warped-input/warped_template.nii.gz"
      "output/02_warped-input/warped_template0.nii.gz"
      "output/02_warped-input/warped_template1.nii.gz"
      "warped_template.nii.gz"
      "warped_template0.nii.gz"
      "warped_template1.nii.gz"
    )

    found=""
    for c in "${candidates[@]}"; do
      if [ -f "$c" ]; then
        found="$c"
        break
      fi
    done

    # As a last resort, pick the first match of warped_template*.nii.gz in output/02_warped-input
    if [ -z "$found" ]; then
      shopt -s nullglob
      any=( output/02_warped-input/warped_template*.nii.gz )
      shopt -u nullglob
      if [ "${#any[@]}" -gt 0 ]; then
        found="${any[0]}"
      fi
    fi

    [ -n "$found" ] || die "Could not locate a template output (expected something like warped_template*.nii.gz)."

    # Ensure it lives in output/02_warped-input and has the canonical name
    if [[ "$found" != output/02_warped-input/* ]]; then
      run "mv -f \"$found\" output/02_warped-input/"
      found="output/02_warped-input/$(basename "$found")"
    fi

    if [ "$found" != "$FINAL_TEMPLATE" ]; then
      run "mv -f \"$found\" \"$FINAL_TEMPLATE\""
    fi
  fi
fi

###############################################################################
# Final sanity check + summary
###############################################################################
[ -f "$FINAL_TEMPLATE" ] || die "Final template missing: $FINAL_TEMPLATE"

log "SUMMARY"
log "  Output root:              $OUT_DIR"
log "  Subject transforms:       $OUT_DIR/output/01_warps"
log "  Population template dir:  $OUT_DIR/output/02_warped-input"
log "  Final template:           $OUT_DIR/$FINAL_TEMPLATE"
log "DONE"
