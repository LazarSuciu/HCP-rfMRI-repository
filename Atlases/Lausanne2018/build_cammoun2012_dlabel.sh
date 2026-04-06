#!/bin/bash
# Build Cammoun2012 (Lausanne2008) .dlabel.nii atlases (scales 033, 060, 125, 250, 500)
# for HCP rsfMRI parcellation.
#
# Atlas: Cammoun et al. (2012) multiscale cortical parcellation, derived from cmp_nipype (https://github.com/LTS5/cmp_nipype/tree/master/cmtklib).
# Reference: Cammoun et al. (2012). Mapping the human connectome at multiple scales with
#   diffusion spectrum MRI. J. Neuroscience Methods 203(2):386-397.
#   doi:10.1016/j.jneumeth.2011.09.031
#
# Subcortex: 15 ROIs matching the structural connectomes from cmp_nipype:
#   Right: Thalamus-Proper, Caudate, Putamen, Pallidum, Accumbens-area, Hippocampus, Amygdala (nodes 1-7)
#   Left:  Thalamus-Proper, Caudate, Putamen, Pallidum, Accumbens-area, Hippocampus, Amygdala (nodes 8-14)
#   Brain-Stem (node 15)
# Source: /Atlases/Glasser/info/FreesurferSubcortex.nii — Conte69 modal-average subcortical segmentation extracted
#   from the Glasser MMP1.0 dlabel. Already in 2mm MNI152 (91x109x91).
#   Reference: Glasser et al. (2013) NeuroImage 80:105-124, fMRISurface pipeline, p.121.
#   The Conte69 modal-average contains 19 CIFTI structures; this script zeros out
#   Cerebellum (L/R) and Ventral Diencephalon (L/R) to retain only the 15 matching ROIs.
#
# Cortex: pre-built fsLR 32k GIFTI .label.gii files from netneurotools fetch_cammoun2012('fslr32k').
#   These were originally generated from FreeSurfer .gcs probabilistic atlas files (from cmp_nipype)
#   applied to the fsaverage surface, then resampled to fsLR 32k with ADAP_BARY_AREA resampling.
#   See: github.com/netneurolab/netneurotools/blob/main/resources/generate_atl-cammoun2012_surface.py
#   Files are downloaded automatically on first run and cached in ~/nnt-data/atl-cammoun2012/.
#
# Scale region counts (cortical + 15 subcortical):
#   scale033: 83 total (68 cortical + 15 subcortical)
#   scale060: 129 total
#   scale125: 234 total
#   scale250: 463 total
#   scale500: 1015 total (1000 cortical + 15 subcortical)
#
# The .dlabel.nii is built using wb_command -cifti-create-dense-from-template, matching
# the brainordinate space of 91282_Greyordinates.dscalar.nii (HCP 2mm MNI152 standard).
# This is the same method used to build the Schaefer+Tian atlases in this repository, .dscalar.nii is available under /Atlases/Schaefer/info.
#
# Requirements:
#   - Connectome Workbench (WB_COMMAND below)
#   - Python with netneurotools, nibabel, numpy (PYTHON below)
#   - 91282_Greyordinates.dscalar.nii (GREYORD below) — ships with this repository
#   - FreesurferSubcortex.nii (GLASSER_SUBCORTEX below) — ships with this repository

set -euo pipefail

########## Configure paths ##########

WB_COMMAND="${WB_COMMAND:-/home/lazar-suciu/workbench-linux64-v2.1.0/workbench/bin_linux64/wb_command}"
PYTHON="${PYTHON:-/home/lazar-suciu/miniconda3/envs/mind_msn_headmotion/bin/python}"

# HCP 91282 greyordinates template — defines the CIFTI brainordinate space (2mm MNI152, 91x109x91)
# Glasser et al. (2013) NeuroImage doi:10.1016/j.neuroimage.2013.04.127
GREYORD="${GREYORD:-$(dirname "$0")/../Schaefer/info/91282_Greyordinates.dscalar.nii}"

# Conte69 modal-average subcortical segmentation, already in 2mm MNI152 (91x109x91).
# Extracted from the Glasser MMP1.0 dlabel with:
#   wb_command -cifti-separate <glasser.dlabel.nii> COLUMN -volume-all FreesurferSubcortex.nii
# Contains 19 CIFTI structures (labels 361-379). Cerebellum (361, 371) and Ventral
# Diencephalon (370, 379) are zeroed out in Step 1 to retain only the 15 ROIs matching
# the cmp_nipype structural connectomes.
GLASSER_SUBCORTEX="${GLASSER_SUBCORTEX:-$(dirname "$0")/../Glasser/info/FreesurferSubcortex.nii}"

# Output directory
OUTDIR="${OUTDIR:-$(dirname "$0")}"

########## Check dependencies ##########

if [ ! -f "$WB_COMMAND" ]; then
    echo "ERROR: wb_command not found at $WB_COMMAND"; exit 1
fi
if [ ! -f "$GREYORD" ]; then
    echo "ERROR: 91282_Greyordinates.dscalar.nii not found at $GREYORD"; exit 1
fi
if [ ! -f "$GLASSER_SUBCORTEX" ]; then
    echo "ERROR: FreesurferSubcortex.nii not found at $GLASSER_SUBCORTEX"; exit 1
fi

TMPDIR_WORK="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_WORK"' EXIT

echo "=== Cammoun2012 (Lausanne2008) .dlabel.nii builder ==="
echo "Output:   $OUTDIR"
echo "Temp:     $TMPDIR_WORK"
echo "Template: $GREYORD"
echo

########## Step 1: Build MNI152 subcortex label volume (2mm, 91x109x91) ##########
#
# Source: FreesurferSubcortex.nii — the Conte69 modal-average subcortical segmentation
# used internally by wb_command to assign CIFTI structure membership. It is already in
# 2mm MNI152 space (91x109x91), the exact space required by -cifti-create-dense-from-template.
# Reference: Glasser et al. (2013) NeuroImage 80:105-124, fMRISurface pipeline section (p.121):
#   "modal-average subcortical parcellation of these structures across the Conte69 atlas
#    subjects in 2 mm MNI space"
#
# The file contains 19 CIFTI subcortical structures (labels 361-379):
#   361 CEREBELLUM_LEFT        (excluded — not in cmp_nipype structural connectomes)
#   362 THALAMUS_LEFT
#   363 CAUDATE_LEFT
#   364 PUTAMEN_LEFT
#   365 PALLIDUM_LEFT
#   366 BRAIN_STEM
#   367 HIPPOCAMPUS_LEFT
#   368 AMYGDALA_LEFT
#   369 ACCUMBENS_LEFT
#   370 DIENCEPHALON_VENTRAL_LEFT  (excluded — not in cmp_nipype structural connectomes)
#   371 CEREBELLUM_RIGHT       (excluded)
#   372 THALAMUS_RIGHT
#   373 CAUDATE_RIGHT
#   374 PUTAMEN_RIGHT
#   375 PALLIDUM_RIGHT
#   376 HIPPOCAMPUS_RIGHT
#   377 AMYGDALA_RIGHT
#   378 ACCUMBENS_RIGHT
#   379 DIENCEPHALON_VENTRAL_RIGHT (excluded)
#
# Labels 361, 370, 371, 379 are zeroed out. The remaining 15 are remapped to 1-15
# matching the node order verified from an example subject (100206) scale33 GraphML structural connectome (also verifiable from LUT in nipype cmtk).

echo "--- Step 1: Building subcortex label volume ---"

SUBCORTEX_LABELED="$OUTDIR/cammoun2012_subcortex_mni2mm_labeled.nii.gz"
SUBCORTEX_LABELS="$OUTDIR/cammoun2012_subcortex_label_annotation.txt"

if [ ! -f "$SUBCORTEX_LABELED" ]; then
    echo "  Remapping FreesurferSubcortex.nii (Conte69 modal-average) to 15-label volume..."
    SUBCORTEX_INT="$TMPDIR_WORK/cammoun2012_subcortex_relabeled.nii.gz"

    $PYTHON - "$GLASSER_SUBCORTEX" "$SUBCORTEX_INT" <<'PYEOF'
import sys
import nibabel as nib
import numpy as np

in_path, out_path = sys.argv[1], sys.argv[2]

img  = nib.load(in_path)
data = img.get_fdata().astype(int)

# Conte69 FreesurferSubcortex label IDs -> output labels 1-15
# Node order matches subject 100206 scale33 GraphML (cmp_nipype structural connectome).
# Labels 361 (CEREBELLUM_LEFT), 371 (CEREBELLUM_RIGHT), 370 (DIENCEPHALON_VENTRAL_LEFT),
# and 379 (DIENCEPHALON_VENTRAL_RIGHT) are not present in the cmp_nipype connectomes
# and are excluded (mapped to 0 / unlabeled).
label_map = {
    372: 1,  # THALAMUS_RIGHT       -> Right-Thalamus-Proper
    373: 2,  # CAUDATE_RIGHT        -> Right-Caudate
    374: 3,  # PUTAMEN_RIGHT        -> Right-Putamen
    375: 4,  # PALLIDUM_RIGHT       -> Right-Pallidum
    378: 5,  # ACCUMBENS_RIGHT      -> Right-Accumbens-area
    376: 6,  # HIPPOCAMPUS_RIGHT    -> Right-Hippocampus
    377: 7,  # AMYGDALA_RIGHT       -> Right-Amygdala
    362: 8,  # THALAMUS_LEFT        -> Left-Thalamus-Proper
    363: 9,  # CAUDATE_LEFT         -> Left-Caudate
    364: 10, # PUTAMEN_LEFT         -> Left-Putamen
    365: 11, # PALLIDUM_LEFT        -> Left-Pallidum
    369: 12, # ACCUMBENS_LEFT       -> Left-Accumbens-area
    367: 13, # HIPPOCAMPUS_LEFT     -> Left-Hippocampus
    368: 14, # AMYGDALA_LEFT        -> Left-Amygdala
    366: 15, # BRAIN_STEM           -> Brain-Stem
}

out = np.zeros_like(data, dtype=np.int16)
for src, dst in label_map.items():
    out[data == src] = dst

nib.save(nib.Nifti1Image(out, img.affine), out_path)
print(f"Labels present: {np.unique(out[out > 0])}")
PYEOF

    # Import integer label volume as wb_command label volume.
    # Label annotation file maps integer values to region names and colours.
    # Names match CIFTI structure identifiers used by -cifti-create-dense-from-template.
    cat > "$SUBCORTEX_LABELS" <<'EOF'
Right-Thalamus-Proper
1 255 0 0 255
Right-Caudate
2 255 128 0 255
Right-Putamen
3 255 255 0 255
Right-Pallidum
4 0 200 0 255
Right-Accumbens-area
5 0 255 255 255
Right-Hippocampus
6 0 128 255 255
Right-Amygdala
7 0 0 255 255
Left-Thalamus-Proper
8 128 0 0 255
Left-Caudate
9 128 64 0 255
Left-Putamen
10 128 128 0 255
Left-Pallidum
11 0 100 0 255
Left-Accumbens-area
12 0 128 128 255
Left-Hippocampus
13 0 64 128 255
Left-Amygdala
14 0 0 128 255
Brain-Stem
15 128 128 128 255
EOF

    "$WB_COMMAND" -volume-label-import \
        "$SUBCORTEX_INT" \
        "$SUBCORTEX_LABELS" \
        "$SUBCORTEX_LABELED"

    echo "  Subcortex label volume saved: $SUBCORTEX_LABELED"
else
    echo "  Subcortex label volume already exists, skipping."
fi
echo

########## Step 2: Fetch Cammoun2012 fsLR 32k cortical label files via netneurotools ##########
#
# netneurotools ships pre-built fsLR 32k GIFTI .label.gii files for all 5 Cammoun2012 scales.
# Files are downloaded from OSF on first call and cached in ~/nnt-data/atl-cammoun2012/fslr32k/.
#
# How these files were originally produced (see generate_atl-cammoun2012_surface.py):
#   1. GCS probabilistic atlas files (from cmp_nipype/cmtklib/data/colortable_and_gcs/my_atlas_gcs/)
#      were applied to the fsaverage surface using FreeSurfer mris_ca_label, producing
#      deterministic .annot files in fsaverage space for each scale and hemisphere.
#      Scale 500 required three separate GCS files (P1-16, P17-28, P29-36) that were
#      merged into a single .annot per hemisphere.
#   2. Labels were reordered to match the expected connectome node ordering from the
#      Cammoun2012 info CSV (netneurotools/netneurotools/datasets/data/atl-cammoun2012_info.csv).
#   3. Each fsaverage .annot was converted to GIFTI format (.label.gii) with mris_convert,
#      then resampled from fsaverage 164k to fsLR 32k using:
#        wb_command -label-resample ... ADAP_BARY_AREA -area-metrics ...
#      using HCP standard_mesh_atlases resample_fsaverage sphere and area metric files.

echo "--- Step 2: Fetching Cammoun2012 fsLR 32k label files via netneurotools ---"
echo "    (RH keys will be offset by max(LH keys) to avoid CIFTI label table conflicts)"

PATHS_FILE="$TMPDIR_WORK/cammoun2012_fslr32k_paths.txt"

$PYTHON - "$PATHS_FILE" "$TMPDIR_WORK" <<'PYEOF'
# -cifti-create-dense-from-template merges label tables from ALL inputs
# (cortex LH label.gii, cortex RH label.gii, and the subcortex volume) into a
# single global CIFTI label table.  All keys and all label names must be unique
# across the combined table.  Two problems arise with raw netneurotools files:
#
#   1. KEY CONFLICT with subcortex: the subcortex volume uses keys 1-15 for the
#      15 subcortical ROIs; both LH and RH label.gii files also start keys at 1.
#   2. SAME-NAME MERGE (LH vs RH): both hemispheres share label names (e.g. key 1
#      = 'lateralorbitofrontal' in both).  wb_command tries to merge same-named
#      labels into a single CIFTI key, collapsing bilateral parcels — wrong, and
#      can create secondary key conflicts that abort the build.
#
# Fix:
#   - Append '_lh'/'_rh' suffixes to all non-zero label names → prevents merging.
#   - Offset LH cortex keys by SUBCORTEX_MAX_KEY (15) → clears subcortex range.
#   - Offset RH cortex keys by SUBCORTEX_MAX_KEY + max(LH keys) → clears both.
# Result: subcortex keys 1-15, LH cortex keys 16-(15+N_lh), RH keys above that.
import sys, os
import numpy as np
import nibabel as nib
from netneurotools import datasets

paths_file, tmpdir = sys.argv[1], sys.argv[2]
d = datasets.fetch_cammoun2012('fslr32k')

SUBCORTEX_MAX_KEY = 15  # subcortex volume occupies keys 1-15

with open(paths_file, 'w') as f:
    for scale in sorted(d.keys()):
        lh_orig, rh_orig = d[scale]

        lh_gii = nib.load(lh_orig)
        rh_gii = nib.load(rh_orig)

        # Add hemisphere suffix to prevent wb_command same-name merging
        for lb in lh_gii.labeltable.labels:
            if lb.key != 0 and lb.label:
                lb.label = lb.label + '_lh'
        for lb in rh_gii.labeltable.labels:
            if lb.key != 0 and lb.label:
                lb.label = lb.label + '_rh'

        # Offset LH keys above subcortex range (1-15)
        for lb in lh_gii.labeltable.labels:
            if lb.key != 0:
                lb.key += SUBCORTEX_MAX_KEY
        lh_data = lh_gii.darrays[0].data.copy().astype(np.int32)
        lh_data[lh_data != 0] += SUBCORTEX_MAX_KEY
        lh_gii.darrays[0].data = lh_data

        # Offset RH keys above LH range
        lh_max = max(lb.key for lb in lh_gii.labeltable.labels if lb.key != 0)
        for lb in rh_gii.labeltable.labels:
            if lb.key != 0:
                lb.key += lh_max
        rh_data = rh_gii.darrays[0].data.copy().astype(np.int32)
        rh_data[rh_data != 0] += lh_max
        rh_gii.darrays[0].data = rh_data

        lh_out = os.path.join(tmpdir, f'lh.cammoun2012.{scale}.label.gii')
        rh_out = os.path.join(tmpdir, f'rh.cammoun2012.{scale}.label.gii')
        nib.save(lh_gii, lh_out)
        nib.save(rh_gii, rh_out)

        rh_max = max(lb.key for lb in rh_gii.labeltable.labels if lb.key != 0)
        f.write(f'{scale} {lh_out} {rh_out}\n')
        print(f'  {scale}: subcortex 1-{SUBCORTEX_MAX_KEY}, LH {SUBCORTEX_MAX_KEY+1}-{lh_max}, RH {lh_max+1}-{rh_max}')
PYEOF

echo

########## Step 3: Combine cortex + subcortex -> .dlabel.nii ##########
#
# Uses -cifti-create-dense-from-template, matching the brainordinate space of the
# 91282_Greyordinates template. This is the same approach used to build the
# Schaefer+Tian atlases in this repository (verified from their file provenance metadata).
# The -volume-all flag assigns subcortical voxels from the label volume; CIFTI structure
# membership (THALAMUS_LEFT etc.) is determined by the template's structure definitions.

echo "--- Step 3: Building .dlabel.nii files ---"

for SCALE in 033 060 125 250 500; do
    LH=$(awk "/^scale${SCALE} /{print \$2}" "$PATHS_FILE")
    RH=$(awk "/^scale${SCALE} /{print \$3}" "$PATHS_FILE")

    if [ -z "$LH" ] || [ -z "$RH" ]; then
        echo "  ERROR: could not find paths for scale${SCALE} in $PATHS_FILE"; exit 1
    fi

    OUT_DLABEL="$OUTDIR/cammoun2012_scale${SCALE}.dlabel.nii"
    echo "  Building $OUT_DLABEL ..."

    "$WB_COMMAND" -cifti-create-dense-from-template \
        "$GREYORD" \
        "$OUT_DLABEL" \
        -label CORTEX_LEFT  "$LH" \
        -label CORTEX_RIGHT "$RH" \
        -volume-all "$SUBCORTEX_LABELED"

    echo "    Saved: $OUT_DLABEL"
done

echo
echo "=== Done ==="
echo "Output files:"
ls -lh "$OUTDIR"/cammoun2012_scale*.dlabel.nii 2>/dev/null
