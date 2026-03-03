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

## Workflow overview (recommended)

1. **Build the population template and subject transforms**
   - Run `step1_ANTs_registration_generate_population_template.sh` to construct the population (study) template from subject images.
   - This step also saves the per-subject transforms produced by ANTs (Affine, Warp, and InverseWarp) into a consistent output tree (for example under `output/01_warps/`).

2. **Obtain a label map (or mask) in population-template space**
   - Create or edit your label map directly in the population-template space, for example by manually aligning an atlas label map to the population template or drawing a brain mask on the population template using tools like ITK-SNAP or 3D Slicer.
   - **Optional (semi-automatic path):** If you already have an atlas template that is well-aligned with your label map, you can register that atlas template to the population template and warp the associated label map into population-template space using:
     - `step1a_ANTs_registration_apply_label_map_and_associated_template_to_study_template.sh`

3. **Propagate the population-template label map back to subject native space**
   - Run `step2_ANTs_registration_apply_affine_inversewarp_to_template_space_label_map.sh` to generate one subject-level label map per subject.
   - This step applies the subject-specific **InverseWarp** and the **inverse of the Affine transform** to map the population-template-space label map back onto each subject’s native reference grid (nearest-neighbor interpolation is used to preserve discrete labels).
