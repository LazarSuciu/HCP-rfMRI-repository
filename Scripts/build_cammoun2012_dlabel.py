#!/usr/bin/env python3
"""
Build Cammoun2012 (Lausanne2008) .dlabel.nii atlases (scales 033, 060, 125, 250, 500)
for HCP rsfMRI parcellation.

Atlas: Cammoun et al. (2012) multiscale cortical parcellation, derived from cmp_nipype.
Reference: Cammoun et al. (2012). Mapping the human connectome at multiple scales with
  diffusion spectrum MRI. J. Neuroscience Methods 203(2):386-397.
  doi:10.1016/j.jneumeth.2011.09.031

Subcortex: 15 ROIs matching the structural connectomes from cmp_nipype (verified from
  subject 100206 scale33 GraphML).

Cortex: pre-built fsLR 32k GIFTI .label.gii files from netneurotools fetch_cammoun2012('fslr32k').
  The key ordering in these files already matches the GraphML node ordering for each scale
  (netneurotools reordered labels during generation to match the GraphML node orders).
  corpuscallosum is present in the label.gii files but is not a real parcel — it is
  excluded (zeroed out, key 0 = medial wall / unlabeled in CIFTI).

Output parcel key ordering (matches cmp_nipype GraphML node order exactly):
  keys 1..N_rh          — right cortical parcels (in GraphML/label.gii order)
  keys N_rh+1..N_rh+7   — right subcortical (Thalamus, Caudate, Putamen, Pallidum,
                           Accumbens, Hippocampus, Amygdala)
  keys N_rh+8..N_rh+7+N_lh — left cortical parcels
  keys N_rh+8+N_lh..N_rh+14+N_lh — left subcortical
  key  N_rh+15+N_lh     — Brain-Stem

  Example for scale033 (N_rh=34, N_lh=34):
    1-34: right cortical, 35-41: right subcortical,
    42-75: left cortical, 76-82: left subcortical, 83: Brain-Stem

Requirements:
  - Python with netneurotools, nibabel, numpy
  - Connectome Workbench (wb_command)
  - 91282_Greyordinates.dscalar.nii  (GREYORD, relative to this script)
  - FreesurferSubcortex.nii          (GLASSER_SUBCORTEX, relative to this script)
"""

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

import nibabel as nib
import numpy as np

# ---------------------------------------------------------------------------
# Paths (relative to this script's directory)
# ---------------------------------------------------------------------------

SCRIPT_DIR = Path(__file__).resolve().parent
GREYORD = SCRIPT_DIR / "../Schaefer/info/91282_Greyordinates.dscalar.nii"
GLASSER_SUBCORTEX = SCRIPT_DIR / "../Glasser/info/FreesurferSubcortex.nii"
WB_COMMAND = os.environ.get(
    "WB_COMMAND",
    "/home/lazar-suciu/workbench-linux64-v2.1.0/workbench/bin_linux64/wb_command",
)

SCALES = ["033", "060", "125", "250", "500"]

# Subcortex: Conte69 FreesurferSubcortex.nii label IDs -> sequential output keys.
# Right subcortical parcels come immediately after right cortical in GraphML order;
# left subcortical after left cortical; brainstem last.
# The offset into the sequential key space is computed at runtime from N_rh and N_lh.
SUBCORTEX_RIGHT = [
    (372, "Right-Thalamus-Proper",  (255,   0,   0, 255)),
    (373, "Right-Caudate",          (255, 128,   0, 255)),
    (374, "Right-Putamen",          (255, 255,   0, 255)),
    (375, "Right-Pallidum",         (  0, 200,   0, 255)),
    (378, "Right-Accumbens-area",   (  0, 255, 255, 255)),
    (376, "Right-Hippocampus",      (  0, 128, 255, 255)),
    (377, "Right-Amygdala",         (  0,   0, 255, 255)),
]
SUBCORTEX_LEFT = [
    (362, "Left-Thalamus-Proper",   (128,   0,   0, 255)),
    (363, "Left-Caudate",           (128,  64,   0, 255)),
    (364, "Left-Putamen",           (128, 128,   0, 255)),
    (365, "Left-Pallidum",          (  0, 100,   0, 255)),
    (369, "Left-Accumbens-area",    (  0, 128, 128, 255)),
    (367, "Left-Hippocampus",       (  0,  64, 128, 255)),
    (368, "Left-Amygdala",          (  0,   0, 128, 255)),
]
BRAIN_STEM = (366, "Brain-Stem", (128, 128, 128, 255))


# ---------------------------------------------------------------------------
# Step 1: Build subcortex label volume
# ---------------------------------------------------------------------------

# def build_subcortex_volume(outdir: Path, tmpdir: Path) -> Path:
#     """
#     Remap FreesurferSubcortex.nii (Conte69 modal-average, 19 structures, labels 361-379)
#     to a 15-label NIfTI matching the cmp_nipype GraphML subcortex node order.

#     The actual key values assigned here are placeholders (1-15); they are reassigned
#     per-scale in build_dlabel() to fit into the correct position after the cortical parcels.
#     This intermediate volume is passed to wb_command -volume-label-import which requires
#     fixed key values — the per-scale key remapping happens in the GIFTI label tables
#     for cortex and in the wb_command -volume-label-import call for subcortex.

#     Returns path to the labeled NIfTI usable by -cifti-create-dense-from-template.
#     """
#     out_path = outdir / "cammoun2012_subcortex_mni2mm_labeled.nii.gz"
#     if out_path.exists():
#         print("  Subcortex label volume already exists, skipping.")
#         return out_path

#     print("  Remapping FreesurferSubcortex.nii to 15-label volume...")

#     img = nib.load(GLASSER_SUBCORTEX)
#     data = img.get_fdata().astype(int)

#     # Build flat label_map: source label -> sequential key 1-15
#     # Order: right subcortex 1-7, left subcortex 8-14, brainstem 15
#     label_map = {}
#     for i, (src, _, _) in enumerate(SUBCORTEX_RIGHT, start=1):
#         label_map[src] = i
#     for i, (src, _, _) in enumerate(SUBCORTEX_LEFT, start=8):
#         label_map[src] = i
#     label_map[BRAIN_STEM[0]] = 15

#     out = np.zeros_like(data, dtype=np.int16)
#     for src, dst in label_map.items():
#         out[data == src] = dst

#     present = np.unique(out[out > 0])
#     print(f"    Labels present in subcortex volume: {present}")
#     assert len(present) == 15, f"Expected 15 labels, got {len(present)}"

#     int_path = tmpdir / "subcortex_relabeled_int.nii.gz"
#     nib.save(nib.Nifti1Image(out, img.affine), int_path)

#     # Label annotation file for wb_command -volume-label-import
#     # Format: name\nkey R G B A\n...
#     # Keys here are 1-15 (the intermediate numbering, not final per-scale keys).
#     # The per-scale key reassignment is handled in the CIFTI label table after
#     # -cifti-create-dense-from-template via a separate relabeling pass.
#     # NOTE: this volume is rebuilt per-scale in build_dlabel() with correct keys.
#     annotation_lines = []
#     for i, (_, name, (r, g, b, a)) in enumerate(SUBCORTEX_RIGHT, start=1):
#         annotation_lines += [name, f"{i} {r} {g} {b} {a}"]
#     for i, (_, name, (r, g, b, a)) in enumerate(SUBCORTEX_LEFT, start=8):
#         annotation_lines += [name, f"{i} {r} {g} {b} {a}"]
#     annotation_lines += [BRAIN_STEM[1], f"15 {BRAIN_STEM[2][0]} {BRAIN_STEM[2][1]} {BRAIN_STEM[2][2]} {BRAIN_STEM[2][3]}"]

#     annot_path = tmpdir / "subcortex_labels.txt"
#     annot_path.write_text("\n".join(annotation_lines) + "\n")

#     subprocess.run(
#         [WB_COMMAND, "-volume-label-import",
#          str(int_path), str(annot_path), str(out_path)],
#         check=True,
#     )
#     print(f"    Saved: {out_path}")
#     return out_path


# ---------------------------------------------------------------------------
# Step 2 + 3: Build per-scale dlabel
# ---------------------------------------------------------------------------

def build_dlabel(scale: str, subcortex_vol: Path, outdir: Path, tmpdir: Path) -> None:
    """
    Build cammoun2012_scale{scale}.dlabel.nii with parcel keys matching
    the cmp_nipype GraphML node order exactly.

    Key assignment:
      1 .. N_rh           right cortical (label.gii order, corpuscallosum excluded)
      N_rh+1 .. N_rh+7    right subcortical
      N_rh+8 .. N_rh+7+N_lh   left cortical
      N_rh+8+N_lh .. N_rh+14+N_lh  left subcortical
      N_rh+15+N_lh        Brain-Stem
    """
    from netneurotools import datasets

    out_dlabel = outdir / f"cammoun2012_scale{scale}.dlabel.nii"
    if out_dlabel.exists():
        print(f"  {out_dlabel.name} already exists, skipping.")
        return

    print(f"  Fetching label files for scale{scale}...")
    d = datasets.fetch_cammoun2012("fslr32k")
    lh_orig, rh_orig = d[f"scale{scale}"]

    lh_gii = nib.load(lh_orig)
    rh_gii = nib.load(rh_orig)

    def remap_cortex_gii(gii, hemi_suffix, key_offset):
        """
        Return (new_gii, n_parcels) where new_gii has:
          - corpuscallosum → key 0
          - remaining parcels renumbered key_offset+1, key_offset+2, ...
            in the original label.gii key order (which already matches GraphML)
          - label names have hemi_suffix appended
        """
        # Build ordered list of real parcel keys (exclude 0 and corpuscallosum)
        ordered = [
            lb for lb in sorted(gii.labeltable.labels, key=lambda x: x.key)
            if lb.key != 0 and lb.label.lower() != "corpuscallosum"
        ]
        n = len(ordered)

        # old_key -> new_key mapping
        old_to_new = {lb.key: key_offset + i + 1 for i, lb in enumerate(ordered)}
        # corpuscallosum and medial wall -> 0
        # (anything not in old_to_new stays 0)

        # Remap vertex data
        old_data = gii.darrays[0].data.copy().astype(np.int32)
        new_data = np.zeros_like(old_data)
        for old_k, new_k in old_to_new.items():
            new_data[old_data == old_k] = new_k

        # Build new label table
        def make_label(key, name, red=0, green=0, blue=0, alpha=0):
            gl = nib.gifti.GiftiLabel(key=key, red=red, green=green, blue=blue, alpha=alpha)
            gl.label = name
            return gl

        # Preserve original key=0 label (medial wall, typically "???" in GIFTI convention)
        orig_zero = next((lb for lb in gii.labeltable.labels if lb.key == 0), None)
        zero_name = orig_zero.label
        new_labels = [make_label(0, zero_name)]
        for i, lb in enumerate(ordered):
            new_key = key_offset + i + 1
            new_name = lb.label + hemi_suffix
            new_labels.append(make_label(
                new_key, new_name, lb.red, lb.green, lb.blue, lb.alpha,
            ))

        new_table = nib.gifti.GiftiLabelTable()
        new_table.labels = new_labels

        new_darr = nib.gifti.GiftiDataArray(
            data=new_data,
            intent=gii.darrays[0].intent,
            datatype="NIFTI_TYPE_INT32",
        )
        new_gii = nib.gifti.GiftiImage(darrays=[new_darr], labeltable=new_table)
        return new_gii, n

    # RH cortex: keys start at 1
    rh_gii_new, n_rh = remap_cortex_gii(rh_gii, "_rh", key_offset=0)
    # LH cortex: keys start after RH cortex + RH subcortex (7)
    lh_key_offset = n_rh + 7
    lh_gii_new, n_lh = remap_cortex_gii(lh_gii, "_lh", key_offset=lh_key_offset)

    # Subcortex key ranges
    rh_subcortex_start = n_rh + 1        # keys n_rh+1 .. n_rh+7
    lh_subcortex_start = n_rh + 8 + n_lh  # keys n_rh+8+n_lh .. n_rh+14+n_lh
    brainstem_key = n_rh + 15 + n_lh

    total = brainstem_key
    print(f"scale{scale}: N_rh={n_rh}, N_lh={n_lh}, total parcels={total}")
    print(f"Keys: RH cortex 1-{n_rh}, RH subcortex {rh_subcortex_start}-{n_rh+7}, "
          f"LH cortex {lh_key_offset+1}-{lh_key_offset+n_lh}, "
          f"LH subcortex {lh_subcortex_start}-{lh_subcortex_start+6}, "
          f"Brain-Stem {brainstem_key}")

    # Save modified GIFTI files to tmpdir
    lh_tmp = tmpdir / f"lh.cammoun2012.scale{scale}.label.gii"
    rh_tmp = tmpdir / f"rh.cammoun2012.scale{scale}.label.gii"
    nib.save(lh_gii_new, lh_tmp)
    nib.save(rh_gii_new, rh_tmp)

    # Build subcortex label volume with correct per-scale keys
    subcortex_tmp = tmpdir / f"subcortex_scale{scale}.nii.gz"
    subcortex_annot = tmpdir / f"subcortex_scale{scale}_labels.txt"
    _build_subcortex_volume_for_scale(
        rh_subcortex_start, lh_subcortex_start, brainstem_key,
        subcortex_tmp, subcortex_annot,
    )

    print(f"    Building {out_dlabel.name} ...")
    subprocess.run(
        [WB_COMMAND, "-cifti-create-dense-from-template",
         str(GREYORD), str(out_dlabel),
         "-label", "CORTEX_LEFT",  str(lh_tmp),
         "-label", "CORTEX_RIGHT", str(rh_tmp),
         "-volume-all", str(subcortex_tmp)],
        check=True,
    )
    print(f"Saved: {out_dlabel}")


def _build_subcortex_volume_for_scale(
    rh_start: int, lh_start: int, brainstem_key: int,
    out_path: Path, annot_path: Path,
) -> None:
    """
    Build the subcortex label NIfTI with keys matching the per-scale node positions.
    rh_start: first key for right subcortical (rh_start+0..rh_start+6 = 7 structures)
    lh_start: first key for left subcortical (lh_start+0..lh_start+6 = 7 structures)
    brainstem_key: key for Brain-Stem
    """
    img = nib.load(GLASSER_SUBCORTEX)
    data = img.get_fdata().astype(int)

    out = np.zeros_like(data, dtype=np.int32)
    annotation_lines = []

    for i, (src, name, (r, g, b, a)) in enumerate(SUBCORTEX_RIGHT):
        key = rh_start + i
        out[data == src] = key
        annotation_lines += [name, f"{key} {r} {g} {b} {a}"]

    for i, (src, name, (r, g, b, a)) in enumerate(SUBCORTEX_LEFT):
        key = lh_start + i
        out[data == src] = key
        annotation_lines += [name, f"{key} {r} {g} {b} {a}"]

    src, name, (r, g, b, a) = BRAIN_STEM
    out[data == src] = brainstem_key
    annotation_lines += [name, f"{brainstem_key} {r} {g} {b} {a}"]

    annot_path.write_text("\n".join(annotation_lines) + "\n")

    int_path = out_path.with_suffix("").with_suffix(".int.nii.gz")
    nib.save(nib.Nifti1Image(out, img.affine), int_path)

    subprocess.run(
        [WB_COMMAND, "-volume-label-import",
         str(int_path), str(annot_path), str(out_path)],
        check=True,
    )
    int_path.unlink(missing_ok=True)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    global WB_COMMAND  # noqa: PLW0603

    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--scales", nargs="+", default=SCALES, choices=SCALES,
                        metavar="SCALE",
                        help=f"Scales to build (default: all). Choices: {SCALES}")
    parser.add_argument("--outdir", default=str(SCRIPT_DIR),
                        help="Output directory (default: same as this script)")
    parser.add_argument("--wb-command", default=None,
                        help=f"Path to wb_command binary (default: {WB_COMMAND})")
    args = parser.parse_args()

    if args.wb_command is not None:
        WB_COMMAND = args.wb_command

    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    # Validate required files
    for label, path in [("GREYORD", GREYORD), ("GLASSER_SUBCORTEX", GLASSER_SUBCORTEX)]:
        if not Path(path).exists():
            sys.exit(f"ERROR: {label} not found at {path}")
    if not Path(WB_COMMAND).exists():
        sys.exit(f"ERROR: wb_command not found at {WB_COMMAND}")

    with tempfile.TemporaryDirectory() as tmpdir_str:
        tmpdir = Path(tmpdir_str)
        print("=== Cammoun2012 (Lausanne2008) .dlabel.nii builder ===")
        print(f"Output:   {outdir}")
        print(f"Temp:     {tmpdir}")
        print(f"Template: {GREYORD}")
        print()

        # Step 1: subcortex base volume (keys 1-15, rebuilt per-scale in step 2)
        # Only used to verify the 15 structures are present; per-scale volumes
        # are built inside build_dlabel() with correct key offsets.
        print("--- Step 1: Verifying subcortex label volume ---")
        img = nib.load(GLASSER_SUBCORTEX)
        data = img.get_fdata().astype(int)
        all_src = [s for s, _, _ in SUBCORTEX_RIGHT + SUBCORTEX_LEFT + [BRAIN_STEM]]
        missing = [s for s in all_src if not np.any(data == s)]
        if missing:
            sys.exit(f"ERROR: FreesurferSubcortex.nii missing expected labels: {missing}")
        print(f"  All 15 subcortical source labels present in FreesurferSubcortex.nii")
        print()

        # Steps 2+3: per-scale cortex + subcortex -> dlabel
        print("--- Steps 2+3: Building per-scale .dlabel.nii files ---")
        for scale in args.scales:
            print(f"\n  Scale {scale}:")
            build_dlabel(scale, None, outdir, tmpdir)

    print()
    print("=== Done ===")
    import glob
    files = sorted(glob.glob(str(outdir / "cammoun2012_scale*.dlabel.nii")))
    for f in files:
        size = os.path.getsize(f)
        print(f"  {Path(f).name}  ({size // 1024} KB)")


if __name__ == "__main__":
    main()
