#!/usr/bin/env bash
# step2_ANTs_registration_apply_affine_inversewarp_to_template_space_label_map_v2.sh
#
# Propagate a population-template-space label map back to each subject native space using:
#   - subject-specific InverseWarp (template -> subject)
#   - inverse(subject-specific Affine) (template -> subject)
#
# The script scans the warp directory for:
#   warped_<SUBJECT_BASENAME>Affine.txt
# and expects:
#   warped_<SUBJECT_BASENAME>InverseWarp.nii.gz
# and a native-space reference image:
#   <REF_DIR>/<SUBJECT_BASENAME><REF_EXT>
#
# Interpolation:
#   - Labels: NearestNeighbor (label-safe)

set -euo pipefail
IFS=$'\n\t'

###############################################################################
# Defaults (sample placeholders)
###############################################################################
TEMPLATE_LABEL_NONLR="/path/to/population_template_space/labels_in_population_template_space.nii.gz"
TEMPLATE_LABEL_LR="/path/to/population_template_space/labels_in_population_template_space_LR_separated.nii.gz"

WARP_DIR="/path/to/population_template_out/output/01_warps"
REF_DIR="/path/to/subject_native_mean_images"

OUT_DIR_NONLR="/path/to/subject_level_labels/nonLR"
OUT_DIR_LR="/path/to/subject_level_labels/LR_separated"

REF_EXT=".nii.gz"          # Reference image extension (".nii.gz" or ".nii")
FORCE="0"
DRY_RUN="0"
SKIP_LR="0"

###############################################################################
# Helpers
###############################################################################
usage() {
  cat <<'EOF'
Usage:
  step2_ANTs_registration_apply_affine_inversewarp_to_template_space_label_map_v2.sh \
    -a TEMPLATE_LABEL_NONLR \
    [-b TEMPLATE_LABEL_LR] \
    -w WARP_DIR \
    -r REF_DIR \
    -o OUT_DIR_NONLR \
    [-l OUT_DIR_LR] \
    [--ref-ext EXT] \
    [--skip-lr] \
    [--force] \
    [--dry-run]

Required:
  -a  Template-space (population-space) non-LR label map (NIfTI)
  -w  Warp directory from Step 1:
        <POP_TEMPLATE_OUT_DIR>/output/01_warps
  -r  Subject native reference image directory
  -o  Output directory for non-LR subject-space labels

Optional:
  -b  Template-space LR-separated label map (NIfTI)
  -l  Output directory for LR-separated subject-space labels
  --ref-ext EXT  Reference extension (default: .nii.gz). Use ".nii" if needed.
  --skip-lr      Skip LR map processing (if you only have non-LR)
  --force        Overwrite outputs if they exist
  --dry-run      Print commands without executing

Expected files inside WARP_DIR:
  warped_<SUBJECT_BASENAME>Affine.txt
  warped_<SUBJECT_BASENAME>InverseWarp.nii.gz

Reference image expected at:
  REF_DIR/<SUBJECT_BASENAME><REF_EXT>

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
check_dir() { [ -d "$1" ] || die "Directory not found: $1"; }
has_cmd() { command -v "$1" >/dev/null 2>&1; }

###############################################################################
# Args
###############################################################################
while [ $# -gt 0 ]; do
  case "$1" in
    -a) TEMPLATE_LABEL_NONLR="$2"; shift 2 ;;
    -b) TEMPLATE_LABEL_LR="$2"; shift 2 ;;
    -w) WARP_DIR="$2"; shift 2 ;;
    -r) REF_DIR="$2"; shift 2 ;;
    -o) OUT_DIR_NONLR="$2"; shift 2 ;;
    -l) OUT_DIR_LR="$2"; shift 2 ;;
    --ref-ext) REF_EXT="$2"; shift 2 ;;
    --skip-lr) SKIP_LR="1"; shift 1 ;;
    --force) FORCE="1"; shift 1 ;;
    --dry-run) DRY_RUN="1"; shift 1 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1 (use -h/--help)" ;;
  esac
done

###############################################################################
# Validations
###############################################################################
check_file "$TEMPLATE_LABEL_NONLR"
check_dir "$WARP_DIR"
check_dir "$REF_DIR"

if [ "$SKIP_LR" != "1" ]; then
  check_file "$TEMPLATE_LABEL_LR"
  [ -n "$OUT_DIR_LR" ] || die "LR output dir (-l) is required unless --skip-lr is set."
fi

run "mkdir -p \"$OUT_DIR_NONLR\""
if [ "$SKIP_LR" != "1" ]; then
  run "mkdir -p \"$OUT_DIR_LR\""
fi

ENGINE=""
if has_cmd antsApplyTransforms; then
  ENGINE="antsApplyTransforms"
elif has_cmd WarpImageMultiTransform; then
  ENGINE="WarpImageMultiTransform"
else
  die "Neither antsApplyTransforms nor WarpImageMultiTransform found in PATH. Load ANTs or fix PATH."
fi

log "ENGINE              = $ENGINE"
log "TEMPLATE_LABEL_NONLR = $TEMPLATE_LABEL_NONLR"
if [ "$SKIP_LR" != "1" ]; then log "TEMPLATE_LABEL_LR    = $TEMPLATE_LABEL_LR"; fi
log "WARP_DIR             = $WARP_DIR"
log "REF_DIR              = $REF_DIR"
log "REF_EXT              = $REF_EXT"
log "OUT_DIR_NONLR        = $OUT_DIR_NONLR"
if [ "$SKIP_LR" != "1" ]; then log "OUT_DIR_LR           = $OUT_DIR_LR"; fi
log "FORCE                = $FORCE"
log "DRY_RUN              = $DRY_RUN"
log "SKIP_LR              = $SKIP_LR"
echo

###############################################################################
# Main loop over subjects
###############################################################################
shopt -s nullglob
AFF_FILES=( "$WARP_DIR"/warped_*Affine.txt )
shopt -u nullglob

[ "${#AFF_FILES[@]}" -gt 0 ] || die "No warped_*Affine.txt found in: $WARP_DIR"

for AFF in "${AFF_FILES[@]}"; do
  AFF_BASENAME="$(basename "$AFF")"                # warped_<SUBJECT_BASENAME>Affine.txt
  STEM="${AFF_BASENAME%Affine.txt}"                # warped_<SUBJECT_BASENAME>
  INVWARP="$WARP_DIR/${STEM}InverseWarp.nii.gz"    # warped_<SUBJECT_BASENAME>InverseWarp.nii.gz

  SUBJECT_BASENAME="${STEM#warped_}"               # <SUBJECT_BASENAME>
  REF_IMG="$REF_DIR/${SUBJECT_BASENAME}${REF_EXT}" # native-space reference image

  OUT_NONLR="$OUT_DIR_NONLR/${SUBJECT_BASENAME}_labels.nii.gz"
  OUT_LR="$OUT_DIR_LR/${SUBJECT_BASENAME}_labels_LR_separated.nii.gz"

  if [ ! -f "$INVWARP" ]; then
    log "[SKIP] Missing inverse warp: $INVWARP"
    continue
  fi
  if [ ! -f "$REF_IMG" ]; then
    log "[SKIP] Missing reference image: $REF_IMG"
    continue
  fi

  log "SUBJECT = $SUBJECT_BASENAME"
  log "  AFF   = $AFF"
  log "  INVW  = $INVWARP"
  log "  REF   = $REF_IMG"

  # Non-LR
  if [ -f "$OUT_NONLR" ] && [ "$FORCE" != "1" ]; then
    log "  [SKIP] Non-LR exists: $OUT_NONLR"
  else
    log "  Writing non-LR: $OUT_NONLR"
    if [ "$ENGINE" = "antsApplyTransforms" ]; then
      # Goal: template -> subject = InverseWarp then inverse(Affine).
      # In ANTs convention, list:
      #   -t [Affine,1] -t InverseWarp
      # so that InverseWarp is applied first, then inverse(Affine).
      run "antsApplyTransforms -d 3 \
        -i \"$TEMPLATE_LABEL_NONLR\" \
        -r \"$REF_IMG\" \
        -o \"$OUT_NONLR\" \
        -n NearestNeighbor \
        -t [\"$AFF\",1] \
        -t \"$INVWARP\""
    else
      run "WarpImageMultiTransform 3 \
        \"$TEMPLATE_LABEL_NONLR\" \
        \"$OUT_NONLR\" \
        -R \"$REF_IMG\" \
        -i \"$AFF\" \
        \"$INVWARP\" \
        --use-NN"
    fi
  fi

  # LR-separated
  if [ "$SKIP_LR" = "1" ]; then
    log "  [SKIP] LR disabled (--skip-lr)."
  else
    if [ -f "$OUT_LR" ] && [ "$FORCE" != "1" ]; then
      log "  [SKIP] LR exists: $OUT_LR"
    else
      log "  Writing LR: $OUT_LR"
      if [ "$ENGINE" = "antsApplyTransforms" ]; then
        run "antsApplyTransforms -d 3 \
          -i \"$TEMPLATE_LABEL_LR\" \
          -r \"$REF_IMG\" \
          -o \"$OUT_LR\" \
          -n NearestNeighbor \
          -t [\"$AFF\",1] \
          -t \"$INVWARP\""
      else
        run "WarpImageMultiTransform 3 \
          \"$TEMPLATE_LABEL_LR\" \
          \"$OUT_LR\" \
          -R \"$REF_IMG\" \
          -i \"$AFF\" \
          \"$INVWARP\" \
          --use-NN"
      fi
    fi
  fi

  echo
done

log "DONE"
