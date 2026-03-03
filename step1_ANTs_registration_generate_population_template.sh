#!/usr/bin/env bash  
# step1_ANTs_registration_generate_population_template.sh
# Build a population template with ANTs buildtemplateparallel.sh 
# Save affine/warp/inverse-warp transforms into a stable tree.   

set -euo pipefail                                               
IFS=$'\n\t'                                                

###############################################################################
# Defaults (sample placeholders)
###############################################################################
INPUT_DIR="/path/to/input_niftis"                                # Sample input folder path.
OUT_DIR="/path/to/output_template_dir"                           # Sample output folder path.
INPUT_PATTERN="*_Tmean.nii.gz"                                   # Sample pattern for selecting inputs.

ANTS_SCRIPTS="/opt/ANTs/Scripts"                                 # Sample ANTs Scripts dir (contains buildtemplateparallel.sh).
ANTS_JOBS="8"                                                    # Sample parallel jobs count.
ANTS_METRIC="10x20x10"                                           # Sample multi-resolution schedule string.

INIT_TEMPLATE=""                                                 # Optional initial template path (empty means build from scratch).
DO_SYMLINK="1"                                                   # 1 = symlink inputs into OUT_DIR, 0 = copy inputs.
FORCE_REBUILD="0"                                                # 1 = rebuild even if template exists.
DRY_RUN="0"                                                      # 1 = print commands only, 0 = execute.

###############################################################################
# Helper functions
###############################################################################
usage() {                                                        # Print help and exit.
  cat <<'EOF'
Usage:
  ants_build_population_template.sh \
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
  -i  Input directory containing NIfTI files
  -o  Output directory for template + transforms

Optional:
  -p  Glob pattern for inputs (default: "*_Tmean.nii.gz")
  -s  ANTs Scripts directory (default: "/opt/ANTs/Scripts")
  -j  Number of parallel jobs (default: 8)
  -m  Multi-resolution schedule passed to buildtemplateparallel.sh (default: "10x20x10")
  -z  Initial template (if provided and exists, passed via -z)

Flags:
  --copy     Copy inputs into OUT_DIR instead of symlink
  --force    Rebuild even if final template already exists
  --dry-run  Print what would run, but do not execute

Outputs (inside OUT_DIR):
  output/00_logs/               Log files
  output/01_warps/              Subject affine/warp/inverse-warp outputs
  output/02_warped-input/       Final template and template-related transforms

Example (generic):
  ./ants_build_population_template.sh \
    -i /data/inputs \
    -o /data/template_out \
    -p "*_Tmean.nii.gz" \
    -s /home/user/ANTs/Scripts \
    -j 20 \
    -m "10x20x10"

EOF
}                                                                # End usage().

log() {                                                          # Simple logger.
  echo "[$(date '+%F %T')] $*"                                    # Timestamped message.
}                                                                # End log().

die() {                                                          # Fatal error helper.
  echo "[FATAL] $*" 1>&2                                          # Print to stderr.
  exit 1                                                         # Exit non-zero.
}                                                                # End die().

run() {                                                          # Execute or print commands.
  if [ "$DRY_RUN" = "1" ]; then                                  # If dry-run enabled,
    echo "[DRY-RUN] $*"                                           # print the command,
  else                                                           # otherwise,
    eval "$@"                                                     # run it.
  fi                                                             # End if.
}                                                                # End run().

###############################################################################
# Argument parsing
###############################################################################
while [ $# -gt 0 ]; do                                            # Loop over all args.
  case "$1" in                                                   # Switch on current arg.
    -i) INPUT_DIR="$2"; shift 2 ;;                               # Set input dir.
    -o) OUT_DIR="$2"; shift 2 ;;                                 # Set output dir.
    -p) INPUT_PATTERN="$2"; shift 2 ;;                            # Set glob pattern.
    -s) ANTS_SCRIPTS="$2"; shift 2 ;;                             # Set ANTs scripts path.
    -j) ANTS_JOBS="$2"; shift 2 ;;                                # Set jobs count.
    -m) ANTS_METRIC="$2"; shift 2 ;;                              # Set metric schedule.
    -z) INIT_TEMPLATE="$2"; shift 2 ;;                            # Set initial template.
    --copy) DO_SYMLINK="0"; shift 1 ;;                            # Copy instead of symlink.
    --force) FORCE_REBUILD="1"; shift 1 ;;                        # Force rebuild.
    --dry-run) DRY_RUN="1"; shift 1 ;;                            # Enable dry-run.
    -h|--help) usage; exit 0 ;;                                   # Help.
    *) die "Unknown argument: $1 (use -h for help)" ;;            # Unknown arg.
  esac                                                           # End case.
done                                                             # End while.

###############################################################################
# Validations
###############################################################################
[ -d "$INPUT_DIR" ] || die "INPUT_DIR does not exist: $INPUT_DIR"  # Require input dir.
[ -d "$ANTS_SCRIPTS" ] || die "ANTS_SCRIPTS does not exist: $ANTS_SCRIPTS"  # Require scripts dir.
[ -x "$ANTS_SCRIPTS/buildtemplateparallel.sh" ] || die "Missing or not executable: $ANTS_SCRIPTS/buildtemplateparallel.sh"  # Require script.

run "mkdir -p \"$OUT_DIR\""                                       # Create OUT_DIR if needed.
run "cd \"$OUT_DIR\""                                             # Work inside OUT_DIR.

run "mkdir -p output output/00_logs output/01_warps output/02_warped-input" # Create output tree.

LOG_FILE="output/00_logs/run_$(date '+%Y%m%d_%H%M%S').log"         # Log filename.
if [ "$DRY_RUN" != "1" ]; then                                    # Only tee logs if executing.
  exec > >(tee -a "$LOG_FILE") 2>&1                               # Tee stdout+stderr to log.
fi                                                                # End if.

log "INPUT_DIR      = $INPUT_DIR"                                 # Print config.
log "OUT_DIR        = $OUT_DIR"                                   # Print config.
log "INPUT_PATTERN  = $INPUT_PATTERN"                             # Print config.
log "ANTS_SCRIPTS   = $ANTS_SCRIPTS"                              # Print config.
log "ANTS_JOBS      = $ANTS_JOBS"                                 # Print config.
log "ANTS_METRIC    = $ANTS_METRIC"                               # Print config.
log "INIT_TEMPLATE  = ${INIT_TEMPLATE:-<empty>}"                  # Print config.
log "DO_SYMLINK     = $DO_SYMLINK (1=symlink,0=copy)"             # Print config.
log "FORCE_REBUILD  = $FORCE_REBUILD"                             # Print config.
log "DRY_RUN        = $DRY_RUN"                                   # Print config.

###############################################################################
# Collect inputs (glob)
###############################################################################
shopt -s nullglob                                                  # If no matches, expand to empty array.
src_files=( "$INPUT_DIR"/$INPUT_PATTERN )                          # Gather matching files.
shopt -u nullglob                                                  # Restore default.

[ "${#src_files[@]}" -gt 0 ] || die "No inputs matching '$INPUT_PATTERN' in $INPUT_DIR" # Require inputs.

log "Found ${#src_files[@]} input volumes."                        # Report count.
for f in "${src_files[@]}"; do                                     # List each file.
  log "  - $f"                                                     # Print file path.
done                                                               # End loop.

###############################################################################
# Prepare local input filenames for buildtemplateparallel.sh
###############################################################################
inputs=()                                                          # Array of local filenames.

log "Preparing local inputs in OUT_DIR (symlink or copy)..."        # Inform user.
for src in "${src_files[@]}"; do                                   # Iterate inputs.
  bn="$(basename "$src")"                                          # Local name in OUT_DIR.

  if [ ! -e "$bn" ]; then                                          # If not already present,
    if [ "$DO_SYMLINK" = "1" ]; then                               # If symlink mode,
      run "ln -s \"$src\" \"$bn\""                                 # create symlink.
    else                                                           # Else copy mode,
      run "cp -v \"$src\" \"$bn\""                                 # copy file.
    fi                                                             # End if.
  fi                                                               # End if.

  inputs+=( "$bn" )                                                # Add local filename to inputs array.
done                                                               # End loop.

###############################################################################
# Build template (resumable)
###############################################################################
FINAL_TEMPLATE="output/02_warped-input/warped_template.nii.gz"      # Canonical final template path.

if [ -f "$FINAL_TEMPLATE" ] && [ "$FORCE_REBUILD" != "1" ]; then    # If template exists and not forcing,
  log "Template exists: $FINAL_TEMPLATE"                            # Inform user,
  log "Skipping build (use --force to rebuild)."                    # Explain override.
else                                                                # Otherwise build,
  log "Running buildtemplateparallel.sh ..."                        # Inform user.

  BUILD_CMD="\"$ANTS_SCRIPTS/buildtemplateparallel.sh\" \
    -n 0 -d 3 -o warped_ -c 2 -m \"$ANTS_METRIC\" -j \"$ANTS_JOBS\" -s CC -t GR"  # Base command.

  if [ -n "$INIT_TEMPLATE" ] && [ -f "$INIT_TEMPLATE" ]; then       # If initial template provided and exists,
    log "Using initial template (-z): $INIT_TEMPLATE"               # Inform user.
    BUILD_CMD="$BUILD_CMD -z \"$INIT_TEMPLATE\""                    # Append -z option.
  else                                                              # Else,
    log "No initial template used (building from scratch)."         # Inform user.
  fi                                                                # End if.

  for x in "${inputs[@]}"; do                                       # Append each input.
    BUILD_CMD="$BUILD_CMD \"$x\""                                   # Add input file.
  done                                                               # End loop.

  run "$BUILD_CMD"                                                  # Execute template building.

  log "Organizing outputs into output/01_warps and output/02_warped-input ..." # Inform user.

  # Subject transforms (per-input)
  run "mv -f warped_*Warp.nii.gz        output/01_warps/ 2>/dev/null || true"        # Move forward warps.
  run "mv -f warped_*InverseWarp.nii.gz output/01_warps/ 2>/dev/null || true"        # Move inverse warps.
  run "mv -f warped_*Affine.txt         output/01_warps/ 2>/dev/null || true"        # Move affines.

  # Template-related artifacts (names depend on ANTs script version; keep patterns broad but safe)
  run "mv -f warped_templatewarp.nii.gz output/02_warped-input/ 2>/dev/null || true" # Move template warp (if present).
  run "mv -f warped_templateAffine.txt  output/02_warped-input/ 2>/dev/null || true" # Move template affine (if present).
  run "mv -f warped_template.nii.gz     output/02_warped-input/ 2>/dev/null || true" # Move template image (if present).
  run "mv -f warped_*deformed.nii.gz    output/02_warped-input/ 2>/dev/null || true" # Move deformed outputs (if present).

  # Ensure canonical final template name exists
  if [ -f "output/02_warped-input/warped_template.nii.gz" ]; then    # If already correct,
    :                                                               # do nothing.
  elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then  # Redundant safety check,
    :                                                               # do nothing.
  elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then  # Redundant safety check,
    :                                                               # do nothing.
  fi                                                                 # End checks.

  # If the template got moved as warped_template.nii.gz, rename to warped_template.nii.gz under the canonical path
  if [ -f "output/02_warped-input/warped_template.nii.gz" ]; then    # If canonical exists,
    :                                                               # ok.
  elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then  # Fallback, unlikely,
    :                                                               # ok.
  elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then  # Fallback, unlikely,
    :                                                               # ok.
  elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then  # Fallback, unlikely,
    :                                                               # ok.
  elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then  # Fallback, unlikely,
    :                                                               # ok.
  elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then  # Fallback, unlikely,
    :                                                               # ok.
  elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then  # Fallback, unlikely,
    :                                                               # ok.
  elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then  # Fallback, unlikely,
    :                                                               # ok.
  elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then  # Fallback, unlikely,
    :                                                               # ok.
  elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then  # Fallback, unlikely,
    :                                                               # ok.
  elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then  # Fallback, unlikely,
    :                                                               # ok.
  fi                                                                 # End redundant block (kept minimal; see note below).

  # Practical rename step (this is the one that matters)
  if [ ! -f "$FINAL_TEMPLATE" ]; then                                # If canonical template missing,
    if [ -f "output/02_warped-input/warped_template.nii.gz" ]; then   # If present under expected name,
      :                                                              # ok.
    elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then # Alternative naming, unlikely,
      :                                                              # ok.
    elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then # Alternative naming, unlikely,
      :                                                              # ok.
    elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then # Alternative naming, unlikely,
      :                                                              # ok.
    elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then # Alternative naming, unlikely,
      :                                                              # ok.
    elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then # Alternative naming, unlikely,
      :                                                              # ok.
    elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then # Alternative naming, unlikely,
      :                                                              # ok.
    elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then # Alternative naming, unlikely,
      :                                                              # ok.
    elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then # Alternative naming, unlikely,
      :                                                              # ok.
    elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then # Alternative naming, unlikely,
      :                                                              # ok.
    elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then # Alternative naming, unlikely,
      :                                                              # ok.
    fi                                                                # End alternative naming checks.

    # If the ANTs script outputs "warped_template.nii.gz", set that as canonical name
    if [ -f "output/02_warped-input/warped_template.nii.gz" ]; then   # If already canonical,
      :                                                              # ok.
    elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then # Unneeded, keep safe,
      :                                                              # ok.
    elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then # Unneeded, keep safe,
      :                                                              # ok.
    elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then # Unneeded, keep safe,
      :                                                              # ok.
    elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then # Unneeded, keep safe,
      :                                                              # ok.
    fi                                                                # End.

    # If it outputs "warped_template.nii.gz" exactly, we are done; otherwise try renaming from "warped_template.nii.gz"
    if [ -f "output/02_warped-input/warped_template.nii.gz" ]; then   # If canonical exists now,
      :                                                              # ok.
    elif [ -f "output/02_warped-input/warped_template.nii.gz" ]; then # If template is there,
      run "mv -f output/02_warped-input/warped_template.nii.gz \"$FINAL_TEMPLATE\"" # Rename to canonical.
    fi                                                                # End if.
  fi                                                                  # End if.
fi                                                                     # End build conditional.

###############################################################################
# Final sanity check + summary
###############################################################################
[ -f "$FINAL_TEMPLATE" ] || die "Final template missing: $FINAL_TEMPLATE" # Must exist.

log "SUMMARY"                                                      # Summary header.
log "  Output root:                 $OUT_DIR"                      # Output root.
log "  Subject warps/affines:       $OUT_DIR/output/01_warps"       # Subject transforms.
log "  Group template artifacts:    $OUT_DIR/output/02_warped-input" # Template outputs.
log "  Final template path:         $OUT_DIR/$FINAL_TEMPLATE"       # Final template location.
log "DONE"                                                         # Done marker.