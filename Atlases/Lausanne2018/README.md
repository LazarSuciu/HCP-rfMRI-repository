### Cammoun2012 (Lausanne2008) atlas .dlabel construction for fMRI parcellation

The goal is to produce `.dlabel.nii` atlas files (HCP CIFTI format, fsLR 32k surface + volumetric subcortex) for all five Cammoun2012 scales, for use with `wb_command -cifti-parcellate` on rsfMRI data. The atlas must match the Cammoun2012 parcellation used by cmp_nipype when generating the HCP structural connectomes, so that functional and structural connectivity ROIs are identical.

---

#### Background: Lausanne atlas versions

The Lausanne multiscale parcellation was introduced in Hagmann et al. (2008) and extended by Cammoun et al. (2012). Two distinct versions exist:

- **Cammoun2012 ("Lausanne2008")**: the original 5-scale cortical parcellation derived from `.gcs` probabilistic atlas files applied to each subject's FreeSurfer surface via `mris_ca_label`. Distributed in `cmp_nipype` (github.com/LTS5/cmp_nipype). Available pre-built in `netneurotools` as `fetch_cammoun2012()`. Hemispheres are parcellated independently (not mirrored). **This is the version used to generate the PIT Group HCP structural connectomes.**
- **Lausanne2018**: a revised version developed alongside connectomemapper3. Key differences: (1) hemispheric symmetry — right hemisphere labels are mirrored from the left; (2) `.annot` files distributed directly instead of requiring `.gcs` generation; (3) extended subcortical parcellation (thalamic nuclei, hippocampal subfields, brainstem sub-structures). **Not applicable here.**

References:
- Hagmann et al. (2008). *Mapping the Structural Core of Human Cerebral Cortex.* PLoS Biology. doi:10.1371/journal.pbio.0060159
- Cammoun et al. (2012). *Mapping the human connectome at multiple scales with diffusion spectrum MRI.* J. Neuroscience Methods 203(2):386–397. doi:10.1016/j.jneumeth.2011.09.031

---

#### Cortical parcellation files

The Cammoun2012 cortical atlas is distributed as FreeSurfer `.gcs` (Gaussian Classifier Surface) probabilistic atlas files in cmp_nipype:

```
https://github.com/LTS5/cmp_nipype/tree/master/cmtklib/data/colortable_and_gcs/my_atlas_gcs/
  myatlas_36_lh.gcs / myatlas_36_rh.gcs         (scale033)
  myatlas_60_lh.gcs / myatlas_60_rh.gcs         (scale060)
  myatlas_125_lh.gcs / myatlas_125_rh.gcs       (scale125)
  myatlas_250_lh.gcs / myatlas_250_rh.gcs       (scale250)
  myatlasP1_16_lh/rh.gcs                        (scale500, part 1 of 3)
  myatlasP17_28_lh/rh.gcs                       (scale500, part 2 of 3)
  myatlasP29_36_lh/rh.gcs                       (scale500, part 3 of 3)
```

Scale 500 is split into three GCS files per hemisphere for historical FreeSurfer reasons; they must be merged after application.

Scale region counts (cortical + 15 subcortical):
| Scale | Total ROIs |
|-------|-----------|
| scale033 | 83 (68 cortical + 15 subcortical) |
| scale060 | 129 |
| scale125 | 234 |
| scale250 | 463 |
| scale500 | 1015 (1000 cortical + 15 subcortical) |

**Pre-built fsLR 32k files**: `netneurotools` ships pre-built fsLR 32k GIFTI `.label.gii` files for all scales, downloadable via `fetch_cammoun2012('fslr32k')`. These are used directly in the build script — no GCS application or resampling required.

---

#### How netneurotools produced the fsLR 32k label files

The full generation pipeline is in `generate_atl-cammoun2012_surface.py` (github.com/netneurolab/netneurotools/blob/main/resources/generate_atl-cammoun2012_surface.py):

1. **GCS → fsaverage .annot**: The `.gcs` files from cmp_nipype were applied to the fsaverage surface using FreeSurfer `mris_ca_label` (`freesurfer.apply_prob_atlas()`), producing deterministic `.annot` files per hemisphere per scale in fsaverage space. Scale 500's three partial GCS files were combined into a single `.annot` per hemisphere.

2. **Label reordering**: Labels were reordered to match the expected connectome node ordering from the Cammoun2012 info CSV (node IDs match the structural connectome GraphML ordering).

3. **fsaverage .annot → GIFTI**: Each `.annot` was converted to GIFTI `.label.gii` format using FreeSurfer `mris_convert`.

4. **Resample to fsLR 32k**: Each `.label.gii` was resampled from fsaverage 164k to fsLR 32k using:
   ```bash
   wb_command -label-resample \
       <fsaverage.label.gii> \
       fsaverage_std_sphere.{L/R}.164k_fsavg_{L/R}.surf.gii \
       fs_LR-deformed_to-fsaverage.{L/R}.sphere.32k_fs_LR.surf.gii \
       ADAP_BARY_AREA \
       <output.32k_fs_LR.label.gii> \
       -area-metrics \
       fsaverage.{L/R}.midthickness_va_avg.164k_fsavg_{L/R}.shape.gii \
       fs_LR.{L/R}.midthickness_va_avg.32k_fs_LR.shape.gii
   ```
   `ADAP_BARY_AREA` (adaptive barycentric area-corrected) resampling is the recommended method for label files per HCP Pipelines documentation, minimising label boundary distortion during surface registration.

Files are hosted on OSF and cached locally in `~/nnt-data/atl-cammoun2012/fslr32k/` on first download.

---

#### How cmp_nipype builds the subcortex

cmp_nipype builds a subject-specific subcortical parcellation using each subject's FreeSurfer `aparc+aseg.mgz`. Seven bilateral structures are extracted by FreeSurfer aseg label ID:

| Structure | Left aseg ID | Right aseg ID |
|-----------|-------------|--------------|
| Thalamus-Proper | 10 | 49 |
| Caudate | 11 | 50 |
| Putamen | 12 | 51 |
| Pallidum | 13 | 52 |
| Accumbens-area | 26 | 58 |
| Hippocampus | 17 | 53 |
| Amygdala | 18 | 54 |

Plus Brain-Stem as a single whole-structure node. Total: 15 subcortical nodes.

---

#### Constructing the Cammoun2012 `.dlabel.nii` for rsfMRI parcellation

**Step 1: Subcortex label volume**

Source: `FreesurferSubcortex.nii` — the Conte69 modal-average subcortical segmentation, already in 2mm MNI152 (91×109×91). Present in this repository at `Atlases/Glasser/info/FreesurferSubcortex.nii`. Extracted from the Glasser MMP1.0 `.dlabel.nii` with:

```bash
wb_command -cifti-separate Q1-Q6_RelatedValidation210...dlabel.nii COLUMN \
    -volume-all FreesurferSubcortex.nii
```

This is the exact volume `wb_command -cifti-create-dense-from-template` uses internally to assign subcortical voxels to CIFTI structures, ensuring perfect voxel-level consistency with the template's structure masks.

Reference: Glasser et al. (2013) *NeuroImage* 80:105–124, fMRISurface pipeline (p.121): *"modal-average subcortical parcellation of these structures across the Conte69 atlas subjects in 2 mm MNI space"*. doi:10.1016/j.neuroimage.2013.04.127

The 2mm MNI152 space is enforced by the CIFTI template: `wb_command -cifti-create-dense-from-template` requires all input volumes to match the volumetric space of the `91282_Greyordinates.dscalar.nii` template exactly (Glasser et al. 2013).

**CIFTI subcortical structures and exclusions**

`FreesurferSubcortex.nii` contains 19 CIFTI structures (labels 361–379). Four are not present in the cmp_nipype connectomes and are zeroed out before building the `.dlabel.nii`:

| Label | Structure | Action |
|-------|-----------|--------|
| 361 | CEREBELLUM_LEFT | **Zero out** |
| 362 | THALAMUS_LEFT | Keep → node 8 |
| 363 | CAUDATE_LEFT | Keep → node 9 |
| 364 | PUTAMEN_LEFT | Keep → node 10 |
| 365 | PALLIDUM_LEFT | Keep → node 11 |
| 366 | BRAIN_STEM | Keep → node 15 |
| 367 | HIPPOCAMPUS_LEFT | Keep → node 13 |
| 368 | AMYGDALA_LEFT | Keep → node 14 |
| 369 | ACCUMBENS_LEFT | Keep → node 12 |
| 370 | DIENCEPHALON_VENTRAL_LEFT | **Zero out** |
| 371 | CEREBELLUM_RIGHT | **Zero out** |
| 372 | THALAMUS_RIGHT | Keep → node 1 |
| 373 | CAUDATE_RIGHT | Keep → node 2 |
| 374 | PUTAMEN_RIGHT | Keep → node 3 |
| 375 | PALLIDUM_RIGHT | Keep → node 4 |
| 376 | HIPPOCAMPUS_RIGHT | Keep → node 6 |
| 377 | AMYGDALA_RIGHT | Keep → node 7 |
| 378 | ACCUMBENS_RIGHT | Keep → node 5 |
| 379 | DIENCEPHALON_VENTRAL_RIGHT | **Zero out** |

Labels 361, 370, 371, 379 are set to 0 (unlabeled key). Key 0 is automatically excluded by `wb_command -cifti-parcellate`. The remaining 15 structures are remapped to **per-scale final key values** and imported with `wb_command -volume-label-import`. The subcortex volume is rebuilt separately for each scale so that keys slot directly into the correct position after that scale's cortical parcels.

**Step 2: Cortex — fetch pre-built fsLR 32k label files**

```python
from netneurotools import datasets
d = datasets.fetch_cammoun2012('fslr32k')
# d['scale033'] = (lh_path, rh_path), d['scale060'] = ..., etc.
```

Files are downloaded once and cached in `~/nnt-data/atl-cammoun2012/fslr32k/`.

For each scale the cortical GIFTI label files are remapped so that:
- `corpuscallosum` is excluded (set to key 0, the medial wall / unlabeled convention)
- RH parcel keys start at 1; LH parcel keys start at `N_rh + 8` (leaving room for the 7 RH subcortical keys)
- `_rh` / `_lh` suffixes are appended to all parcel names to keep keys unique across hemispheres in the shared CIFTI label table

**Step 3: Build `.dlabel.nii` (per scale)**

For each scale `Scripts/build_cammoun2012_dlabel.py` calls:

```bash
wb_command -cifti-create-dense-from-template \
    91282_Greyordinates.dscalar.nii \
    cammoun2012_scale<N>.dlabel.nii \
    -label CORTEX_LEFT  <lh.cammoun2012.scale<N>.label.gii> \
    -label CORTEX_RIGHT <rh.cammoun2012.scale<N>.label.gii> \
    -volume-all subcortex_scale<N>.nii.gz
```

The per-scale subcortex volume (`subcortex_scale<N>.nii.gz`) is written to a temp directory and deleted after the dlabel is assembled.

**Cons:** group-average MNI subcortex, as opposed to subject-specific subcortex in cmtk pipeline. (Same trade-off as all other atlases in this pipeline).

---

## Hardware requirements for producing per-subject functional connectomes (single subject, all Lausanne2008 atlases, rsfMRI pipeline script for HCP-YA in /Scripts)

Measured for one HCP-YA subject with all 5 Lausanne2018 atlas scales.
Per-subject pipeline: download 4 dtseries.nii files from S3 → demean/variance-normalize
→ concatenate → parcellate with each atlas → correlate → convert to .txt. Downloaded dtseries.nii are deleted at pipeline end. Summary of requirements available in monitor_20260406_182144_summary.txt
at repo root, detailed timeseries in monitor_20260406_182144.tsv.