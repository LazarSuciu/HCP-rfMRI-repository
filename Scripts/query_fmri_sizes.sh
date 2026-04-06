#!/bin/bash
subjectlist="/home/lazar-suciu/Downloads/repeated_10_scale_33/subjects.csv"
total_bytes=0
fmri_bytes=0
freesurfer_bytes=0

# FreeSurfer files needed by compute_MIND (default features CT,MC,Vol,SD,SA + aparc parcellation)
FS_SURF_SUFFIXES=("thickness" "volume" "area" "curv" "sulc")
FS_PARCELLATION="aparc"

query_size() {
    local key="$1"
    aws s3 ls "$key" 2>/dev/null | awk '{print $3}' | tail -1
}

while read SUBJECT; do
    SUBJECT=$(echo "$SUBJECT" | tr -d '[:space:]')
    [ -z "$SUBJECT" ] && continue

    # # rsfMRI: 4 files (REST1+REST2 x LR+RL)
    # for SESSION in "rfMRI_REST1" "rfMRI_REST2"; do
    #     for PED in "LR" "RL"; do
    #         key="s3://hcp-openaccess/HCP_1200/$SUBJECT/MNINonLinear/Results/${SESSION}_${PED}/${SESSION}_${PED}_Atlas_MSMAll_hp2000_clean.dtseries.nii"
    #         size=$(query_size "$key")
    #         if [ -n "$size" ]; then
    #             fmri_bytes=$((fmri_bytes + size))
    #         else
    #             echo "MISSING fMRI: $key"
    #         fi
    #     done
    # done

    # FreeSurfer surf files: lh/rh x 5 suffixes = 10 files
    for HEMI in "lh" "rh"; do
        for SUFFIX in "${FS_SURF_SUFFIXES[@]}"; do
            key="s3://hcp-openaccess/HCP_1200/$SUBJECT/T1w/$SUBJECT/surf/${HEMI}.${SUFFIX}"
            size=$(query_size "$key")
            if [ -n "$size" ]; then
                freesurfer_bytes=$((freesurfer_bytes + size))
            else
                echo "MISSING FS surf: $key"
            fi
        done
    done

    # FreeSurfer annotation files: lh/rh x parcellation = 2 files
    for HEMI in "lh" "rh"; do
        key="s3://hcp-openaccess/HCP_1200/$SUBJECT/T1w/$SUBJECT/label/${HEMI}.${FS_PARCELLATION}.annot"
        size=$(query_size "$key")
        if [ -n "$size" ]; then
            freesurfer_bytes=$((freesurfer_bytes + size))
        else
            echo "MISSING FS label: $key"
        fi
    done

done < <(tr ',' '\n' < "$subjectlist")

total_bytes=$((fmri_bytes + freesurfer_bytes))

echo ""
echo "=== Size Summary ==="
# echo "rsfMRI (dtseries.nii):    $(echo "scale=2; $fmri_bytes / 1073741824" | bc) GB"
echo "FreeSurfer (surf+label):  $(echo "scale=2; $freesurfer_bytes / 1073741824" | bc) GB"
echo "Total:                    $(echo "scale=2; $total_bytes / 1073741824" | bc) GB"