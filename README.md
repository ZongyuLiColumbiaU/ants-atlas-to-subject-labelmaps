# ANTs Label Map Propagation (Population Template ↔ Subject Space)

This repo contains three Bash scripts for a practical ANTs workflow:

1) Build a population template from subject NIfTI images (and save per-subject transforms).
2) Bring an atlas label map (or any mask like a brain mask) into the population-template space (manual or semi-automatic).
3) Propagate the population-template-space label map back into each subject native space using inverse transforms (label-safe NN).

The scripts are designed for NIfTI (.nii / .nii.gz) datasets and ANTs-based registration.

---

## Requirements

- Linux shell (bash)
- ANTs installed and in PATH:
  - `antsRegistration`
  - `antsApplyTransforms`
  - Optional fallback: `WarpImageMultiTransform`
- ANTs Scripts directory containing `buildtemplateparallel.sh`

Quick check:
```bash
which antsApplyTransforms
which antsRegistration
ls /path/to/ANTs/Scripts/buildtemplateparallel.sh
