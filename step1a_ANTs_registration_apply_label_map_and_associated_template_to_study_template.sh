#!/usr/bin/env bash
# step1a_ANTs_registration_apply_label_map_and_associated_template_to_study_template_v2.sh
#
# Register an atlas template (moving) to a population template (fixed),
# then apply the SAME transforms to the atlas label map(s) so they land in
# population-template space.
#
# Outputs (inside OUT_DIR):
#   output/00_logs/          Logs
#   output/01_transforms/    Atlas-to-population transforms (affine + warp + inversewarp)
#   output/02_warped/        Warped atlas template and warped label map(s) in population space
#
# Notes:
# - Use NearestNeighbor interpolation for labels.
# - Use Linear interpolation for intensity images (templates).
# - The produced transforms can be reused to warp any other atlas-space image into population space.

set -euo pipefail
IFS=$'\n\t'

###############################################################################
# Defaults (sample placeholders)
###############################################################################
FIXED_POP_TEMPLATE="/path/to/population_template_out/output/02_warped-input/warped_template.nii.gz"
MOVING_ATLAS_TEMPLATE="/path/to/atlas_space/atlas_template.nii.gz"
ATLAS_LABEL_NONLR="/path/to/atlas_space/atlas_labels.nii.gz"
ATLAS_LABEL_LR=""

OUT_DIR="/path/to/atlas_to_population_registration_out"

THREADS="8"
FORCE="0"
DRY_RUN="0"
SKIP_REG="0"

###############################################################################
# Helpers
###############################################################################
usage() {
  cat <<'EOF'
Usage:
  step1a_ANTs_registration_apply_label_map_and_associated_template_to_study_template_v2.sh \
    -f FIXED_POP_TEMPLATE \
    -m MOVING_ATLAS_TEMPLATE \
    -a ATLAS_LABEL_NONLR \
    [-b ATLAS_LABEL_LR] \
    -o OUT_DIR \
    [--threads N] \
    [--skip-reg] \
    [--force] \
    [--dry-run]

Required:
  -f  Fixed population template image:
        <POP_TEMPLATE_OUT_DIR>/output/02_warped-input/warped_template.nii.gz
  -m  Moving atlas template intensity image (same space as the labels)
  -a  Moving atlas label map (same space as the atlas template)
  -o  Output directory

Optional:
  -b  Moving LR-separated atlas label map
  --threads N  Number of threads (default: 8)
  --skip-reg   Skip registration step, only apply transforms if they exist
  --force      Rerun registration and overwrite outputs
  --dry-run    Print commands without executing

Outputs:
  OUT_DIR/output/01_transforms/atlas2pop_0GenericAffine.mat
  OUT_DIR/output/01_transforms/atlas2pop_1Warp.nii.gz
  OUT_DIR/output/01_transforms/atlas2pop_1InverseWarp.nii.gz
  OUT_DIR/output/02_warped/atlas_template_in_population_space.nii.gz
  OUT_DIR/output/02_warped/atlas_labels_in_population_space.nii.gz
  OUT_DIR/output/02_warped/atlas_labels_LR_in_population_space.nii.gz (if -b provided)

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

check_file() { [ -f "$1" ] || die "File not found: $1"; }
check_cmd() { command -v "$1" >/dev/null 2>&1 || die "Command not found in PATH: $1"; }

###############################################################################
# Args
###############################################################################
while [ $# -gt 0 ]; do
  case "$1" in
    -f) FIXED_POP_TEMPLATE="$2"; shift 2 ;;
    -m) MOVING_ATLAS_TEMPLATE="$2"; shift 2 ;;
    -a) ATLAS_LABEL_NONLR="$2"; shift 2 ;;
    -b) ATLAS_LABEL_LR="$2"; shift 2 ;;
    -o) OUT_DIR="$2"; shift 2 ;;
    --threads) THREADS="$2"; shift 2 ;;
    --skip-reg) SKIP_REG="1"; shift 1 ;;
    --force) FORCE="1"; shift 1 ;;
    --dry-run) DRY_RUN="1"; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1 (use -h/--help)" ;;
  esac
done

###############################################################################
# Validations
###############################################################################
check_cmd antsRegistration
check_cmd antsApplyTransforms

check_file "$FIXED_POP_TEMPLATE"
check_file "$MOVING_ATLAS_TEMPLATE"
check_file "$ATLAS_LABEL_NONLR"
if [ -n "$ATLAS_LABEL_LR" ]; then check_file "$ATLAS_LABEL_LR"; fi

run "mkdir -p \"$OUT_DIR/output/00_logs\" \"$OUT_DIR/output/01_transforms\" \"$OUT_DIR/output/02_warped\""

LOG_FILE="$OUT_DIR/output/00_logs/run_$(date '+%Y%m%d_%H%M%S').log"
if [ "$DRY_RUN" != "1" ]; then
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS="$THREADS"

log "FIXED_POP_TEMPLATE     = $FIXED_POP_TEMPLATE"
log "MOVING_ATLAS_TEMPLATE  = $MOVING_ATLAS_TEMPLATE"
log "ATLAS_LABEL_NONLR      = $ATLAS_LABEL_NONLR"
log "ATLAS_LABEL_LR         = ${ATLAS_LABEL_LR:-<none>}"
log "OUT_DIR                = $OUT_DIR"
log "THREADS                = $THREADS"
log "SKIP_REG               = $SKIP_REG"
log "FORCE                  = $FORCE"
log "DRY_RUN                = $DRY_RUN"
echo

###############################################################################
# Output naming
###############################################################################
XFM_PREFIX="$OUT_DIR/output/01_transforms/atlas2pop_"
AFFINE="${XFM_PREFIX}0GenericAffine.mat"
WARP="${XFM_PREFIX}1Warp.nii.gz"
INVWARP="${XFM_PREFIX}1InverseWarp.nii.gz"

OUT_WARPED_ATLAS="$OUT_DIR/output/02_warped/atlas_template_in_population_space.nii.gz"
OUT_LABEL_NONLR="$OUT_DIR/output/02_warped/atlas_labels_in_population_space.nii.gz"
OUT_LABEL_LR="$OUT_DIR/output/02_warped/atlas_labels_LR_in_population_space.nii.gz"

###############################################################################
# Registration: atlas template -> population template
###############################################################################
if [ "$SKIP_REG" = "1" ]; then
  log "Skipping registration (--skip-reg). Expecting transforms at:"
  log "  $AFFINE"
  log "  $WARP"
else
  if [ -f "$AFFINE" ] && [ -f "$WARP" ] && [ "$FORCE" != "1" ]; then
    log "Transforms already exist. Skipping registration (use --force to rerun)."
  else
    log "Running antsRegistration (Rigid + Affine + SyN): atlas -> population template."

    run "antsRegistration -d 3 \
      -o [\"$XFM_PREFIX\"] \
      -r [\"$FIXED_POP_TEMPLATE\",\"$MOVING_ATLAS_TEMPLATE\",1] \
      -m CC[\"$FIXED_POP_TEMPLATE\",\"$MOVING_ATLAS_TEMPLATE\",1,4] \
      -t Rigid[0.1] \
      -c [1000x500x250x0,1e-6,10] \
      -s 4x2x1x0vox \
      -f 8x4x2x1 \
      -m CC[\"$FIXED_POP_TEMPLATE\",\"$MOVING_ATLAS_TEMPLATE\",1,4] \
      -t Affine[0.1] \
      -c [1000x500x250x0,1e-6,10] \
      -s 4x2x1x0vox \
      -f 8x4x2x1 \
      -m CC[\"$FIXED_POP_TEMPLATE\",\"$MOVING_ATLAS_TEMPLATE\",1,4] \
      -t SyN[0.1,3,0] \
      -c [200x100x50x20,1e-6,10] \
      -s 3x2x1x0vox \
      -f 4x3x2x1 \
      -u 1 -z 1"
  fi
fi

# Sanity check transforms exist before warping
[ -f "$AFFINE" ] || die "Missing affine: $AFFINE"
[ -f "$WARP" ] || die "Missing warp:   $WARP"

###############################################################################
# Warp atlas template (intensity) and labels (NN) into population space
###############################################################################
# Transform order for moving->fixed:
#   -t WARP -t AFFINE
# (ANTs applies transforms in the correct internal order for this convention.)
if [ ! -f "$OUT_WARPED_ATLAS" ] || [ "$FORCE" = "1" ]; then
  log "Warping atlas template -> population space (Linear): $OUT_WARPED_ATLAS"
  run "antsApplyTransforms -d 3 \
    -i \"$MOVING_ATLAS_TEMPLATE\" \
    -r \"$FIXED_POP_TEMPLATE\" \
    -o \"$OUT_WARPED_ATLAS\" \
    -n Linear \
    -t \"$WARP\" \
    -t \"$AFFINE\""
else
  log "Atlas template output exists, skipping: $OUT_WARPED_ATLAS"
fi

if [ ! -f "$OUT_LABEL_NONLR" ] || [ "$FORCE" = "1" ]; then
  log "Warping non-LR labels -> population space (NearestNeighbor): $OUT_LABEL_NONLR"
  run "antsApplyTransforms -d 3 \
    -i \"$ATLAS_LABEL_NONLR\" \
    -r \"$FIXED_POP_TEMPLATE\" \
    -o \"$OUT_LABEL_NONLR\" \
    -n NearestNeighbor \
    -t \"$WARP\" \
    -t \"$AFFINE\""
else
  log "Non-LR label output exists, skipping: $OUT_LABEL_NONLR"
fi

if [ -n "$ATLAS_LABEL_LR" ]; then
  if [ ! -f "$OUT_LABEL_LR" ] || [ "$FORCE" = "1" ]; then
    log "Warping LR labels -> population space (NearestNeighbor): $OUT_LABEL_LR"
    run "antsApplyTransforms -d 3 \
      -i \"$ATLAS_LABEL_LR\" \
      -r \"$FIXED_POP_TEMPLATE\" \
      -o \"$OUT_LABEL_LR\" \
      -n NearestNeighbor \
      -t \"$WARP\" \
      -t \"$AFFINE\""
  else
    log "LR label output exists, skipping: $OUT_LABEL_LR"
  fi
else
  log "No LR label map provided (-b not set)."
fi

echo
log "SUMMARY"
log "  Transforms:"
log "    Affine  = $AFFINE"
log "    Warp    = $WARP"
log "    InvWarp = $INVWARP"
log "  Warped atlas template:"
log "    $OUT_WARPED_ATLAS"
log "  Warped label maps:"
log "    Non-LR  = $OUT_LABEL_NONLR"
if [ -n "$ATLAS_LABEL_LR" ]; then log "    LR      = $OUT_LABEL_LR"; fi
log "DONE"
