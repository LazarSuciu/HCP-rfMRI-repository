# Apptainer / Singularity container for the HCP-YA rfMRI pipeline

`hcp-rfmri.def` builds an image with:

- Connectome Workbench **2.1.0** (`wb_command`). This version produced the existing FC outputs. The original repository never recorded which version it used.
- AWS CLI **2.31.36**
- This repository's `Scripts/`, `Atlases/` and `SubjectLists/`, copied to `/opt/HCP-rfMRI-repository`. An image therefore matches the commit it was built from. Rebuild it after changing the atlas list in the script.

Both downloads are checked against fixed SHA-256 sums during the build. The build's `%test` section checks that `wb_command` finds all of its shared libraries and reports version 2.1.0.

## Build

From the repository root:

```bash
apptainer build hcp-rfmri.sif container/hcp-rfmri.def
```

`singularity build` works the same way. Building needs about 300 MB of free space for the image, plus the build cache.

## Run

The runscript runs `Scripts/rsfMRI_Download_Normalization_Concatenation_Parcellation_HCPYA.sh` with the atlases inside the image:

```bash
HCP_TEMP_DIR=/scratch/hcp/temp \
HCP_OUTPUT_DIR=/data/hcp/rfMRI/out \
HCP_SUBJECT_LIST=/data/hcp/subjects.txt \
JOBS=8 \
apptainer run --bind /scratch,/data hcp-rfmri.sif
```

| Variable | Required | Default |
|---|---|---|
| `HCP_TEMP_DIR` | yes | (none) |
| `HCP_OUTPUT_DIR` | yes | (none) |
| `HCP_SUBJECT_LIST` | no | `SubjectLists/HCPYoungAdultSubjectList.txt` in the image |
| `HCP_ATLAS_DIR` | no | `Atlases/` in the image |
| `HCP_S3_PREFIX` | no | `HCP_1200`; set to `HCP_Retest` for the retest sessions |
| `JOBS` | no | 5 (subjects processed in parallel) |

- Environment variables set on the host are passed into the container automatically.
- `$HOME` is bound by default, so the AWS credentials in `~/.aws` are used to read `s3://hcp-openaccess`. On a cluster where `$HOME` is not bound, add `--bind ~/.aws`, or pass `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`.
- Bind every host folder that the paths above point to (`--bind`).
- Scratch space: each subject's session uses about 2.6 GB in `HCP_TEMP_DIR` and `HCP_OUTPUT_DIR` while it is processed (two ~440 MB downloads, their normalized copies and the concatenated series). Multiply by `JOBS`.

### Retest sessions

`SubjectLists/HCPYoungAdultRetestSubjectList.txt` lists the 45 subjects in `s3://hcp-openaccess/HCP_Retest` (checked 2026-10-15). All 45 have resting-state data. Two have only one complete session: 341834 is missing `rfMRI_REST1_RL`, so only REST2 is processed; 627549 has only REST1. The script skips incomplete sessions by itself. Retest subjects have the same IDs as their first session, so give them their own output folder:

```bash
HCP_S3_PREFIX=HCP_Retest \
HCP_SUBJECT_LIST=/opt/HCP-rfMRI-repository/SubjectLists/HCPYoungAdultRetestSubjectList.txt \
HCP_TEMP_DIR=/scratch/hcp/temp_retest HCP_OUTPUT_DIR=/data/hcp/rfMRI/out_retest \
apptainer run --bind /scratch,/data hcp-rfmri.sif
```

The atlases to parcellate with are set in `atlasdict` at the top of the script. To use a different selection without rebuilding, edit a copy of the script and run it with `apptainer exec`. Point `HCP_ATLAS_DIR` at the image's atlases (or at a bound copy):

```bash
HCP_ATLAS_DIR=/opt/HCP-rfMRI-repository/Atlases HCP_TEMP_DIR=... HCP_OUTPUT_DIR=... \
apptainer exec hcp-rfmri.sif bash my_copy_of_the_script.sh
```
