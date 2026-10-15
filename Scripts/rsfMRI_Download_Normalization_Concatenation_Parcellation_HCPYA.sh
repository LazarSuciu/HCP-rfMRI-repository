#!/bin/bash

# 2022/05/25
# F.Tijhuis 
# f.tijhuis@amsterdamumc.nl

# Requirements for this script
#  installed versions of: wb_command and AWS CLI (command line installer)
#  access to Connectome DB and a personal access key for the AWS S3 storage
#  configured/bucketed version of the HCP-YA database on your system (achieved using aws configure; see https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html). use your own AWS credentials for the HCP database for this (find them on db.humanconnectome.org)

# This script can be used to download HCP-YA scanning data from the server of Connectome DB and execute the recommended further preprocessing. The processing part of the script standardizes two separate scans and then concatenates them. Though we were primarily interested in concatenating resting-state scans, the script can be adapted for different purposes as well (e.g. for the concatenation of all task data).


########## Defining variables - these need to be tweaked based on where your files are ##########

# export PATH=/opt/workbench/bin_linux64:${PATH} #this needs to point to path where wb_command is installed (not needed inside the container, see container/README.md)

# The paths below can be set with environment variables (e.g. when running inside the container); the values after ":-" are the defaults
repodir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
atlasdir="${HCP_ATLAS_DIR:-${repodir}/Atlases}" #folder containing the atlases of this repository

tempfolder="${HCP_TEMP_DIR:?set HCP_TEMP_DIR}" #this is the folder where the intermediate files will be stored
outputpathhighest="${HCP_OUTPUT_DIR:?set HCP_OUTPUT_DIR}" #where you want to put the output, needs to exist

s3prefix="${HCP_S3_PREFIX:-HCP_1200}" #release folder in s3://hcp-openaccess: HCP_1200, or HCP_Retest for the retest sessions (subject IDs are the same, so use a separate HCP_OUTPUT_DIR)

subjectlist="${HCP_SUBJECT_LIST:-${repodir}/SubjectLists/HCPYoungAdultSubjectList.txt}" #this needs to point to a txt file that contains the subject id's that you want to process/download, e.g. 100206. The file we used included all subjects with rfMRI scans

declare -A atlasdict #this includes all the atlases that you want to use for parcellation and will be looped over later. The key indicates the file path to the atlas (needs to refer to a .dlabel.nii atlas) and the value describes the custom name of the output directories/files (this can be selected by you)
atlasdict=(
# ["${atlasdir}/Schaefer/100regions7networks/Schaefer2018_100Parcels_7Networks_order_Tian_Subcortex_S1_3T.dlabel.nii"]="Schaefer2018_100Parcels_7Networks_Tian_Subcortex_S1_3T"
["${atlasdir}/Schaefer/200regions7networks/Schaefer2018_200Parcels_7Networks_order_Tian_Subcortex_S1.dlabel.nii"]="Schaefer2018_200Parcels_7Networks_Tian_Subcortex_S1_3T"
["${atlasdir}/Schaefer/300regions7networks/Schaefer2018_300Parcels_7Networks_order_Tian_Subcortex_S1_3T.dlabel.nii"]="Schaefer2018_300Parcels_7Networks_Tian_Subcortex_S1_3T"
# ["${atlasdir}/Schaefer/400regions7networks/Schaefer2018_400Parcels_7Networks_order_Tian_Subcortex_S1.dlabel.nii"]="Schaefer2018_400Parcels_7Networks_Tian_Subcortex_S1_3T"
# ["${atlasdir}/Schaefer/1000regions7networks/Schaefer2018_1000Parcels_7Networks_order_Tian_Subcortex_S1_3T.dlabel.nii"]="Schaefer2018_1000Parcels_7Networks_Tian_Subcortex_S1_3T"
# ["${atlasdir}/Brainnetome/fsaverage.BN_Atlas.32k_fs_LR_246regions.dlabel.nii"]="fsaverage.BN_Atlas.32k_fs_LR_246regions"
# ["${atlasdir}/Lausanne2018/cammoun2012_scale033.dlabel.nii"]="Lausanne2018_cammoun2012_scale033"
# ["${atlasdir}/Lausanne2018/cammoun2012_scale060.dlabel.nii"]="Lausanne2018_cammoun2012_scale060"
# ["${atlasdir}/Lausanne2018/cammoun2012_scale125.dlabel.nii"]="Lausanne2018_cammoun2012_scale125"
# ["${atlasdir}/Lausanne2018/cammoun2012_scale250.dlabel.nii"]="Lausanne2018_cammoun2012_scale250"
# ["${atlasdir}/Lausanne2018/cammoun2012_scale500.dlabel.nii"]="Lausanne2018_cammoun2012_scale500"
# ["${atlasdir}/Gordon/Gordon333.32k_fs_LR_Tian_Subcortex_S1.dlabel.nii"]="Gordon333.32k_fs_LR_Tian_Subcortex_S1_3T"
# ["${atlasdir}/Glasser/Q1-Q6_RelatedValidation210.CorticalAreas_dil_Final_Final_Areas_Group_Colors_with_Atlas_ROIs2.32k_fs_LR.dlabel.nii"]="GlasserFreesurfer"
)

for item in "${!atlasdict[@]}"; do
	[ -f "$item" ] || { echo "Atlas not found: $item" >&2; exit 1; }
done
[ -f "$subjectlist" ] || { echo "Subject list not found: $subjectlist" >&2; exit 1; }
mkdir -p "$tempfolder" "$outputpathhighest"

JOBS=${JOBS:-5}  # number of subjects to process in parallel

########## Per-subject processing function ##########

process_subject() {
	local SUBJECT=$1
	local logfile="${outputpathhighest}/logs/${SUBJECT}.log"
	mkdir -p "${outputpathhighest}/logs"
	exec > "$logfile" 2>&1  # redirect all output to per-subject log

	echo "Now working on Subject ${SUBJECT}"
	echo

	for SESSION in "rfMRI_REST1" "rfMRI_REST2"
	do
		# --- Per-session existence check ---
		atlas_count=${#atlasdict[@]}
		if (( atlas_count == 0 )); then
			echo "No atlases defined; will proceed with downloading and processing."
		else
			session_exists=true
			for item in "${!atlasdict[@]}"; do
				atlasname=${atlasdict[$item]}
				expected="$outputpathhighest/${SUBJECT}/${SESSION}/${atlasname}/${SUBJECT}_${SESSION}_Atlas_MSMAll_hp2000_clean_${atlasname}_connmatrix.txt"
				if [ ! -f "$expected" ]; then
					session_exists=false
					break
				fi
			done

			if [ "$session_exists" = true ]; then
				echo "All outputs already exist for ${SUBJECT} ${SESSION}; skipping session."
				continue
			fi
		fi

		echo "Now working on Session ${SESSION}"
		echo
		echo "Starting Download of scans from Connectome DB..."

		########## Download the LR and RL scans (both phase encoding directions) from the Connectome DB server using curl ##########
		########## https://wiki.humanconnectome.org/pages/viewpage.action?pageId=77365252 ###########

		file_relative_path_lr=MNINonLinear/Results/${SESSION}_LR/${SESSION}_LR_Atlas_MSMAll_hp2000_clean.dtseries.nii
		file_relative_path_rl=MNINonLinear/Results/${SESSION}_RL/${SESSION}_RL_Atlas_MSMAll_hp2000_clean.dtseries.nii

		aws s3 cp s3://hcp-openaccess/$s3prefix/$SUBJECT/$file_relative_path_lr $tempfolder/${SUBJECT}_${SESSION}_LR_Atlas_MSMAll_hp2000_clean.dtseries.nii --only-show-errors
		aws s3 cp s3://hcp-openaccess/$s3prefix/$SUBJECT/$file_relative_path_rl $tempfolder/${SUBJECT}_${SESSION}_RL_Atlas_MSMAll_hp2000_clean.dtseries.nii --only-show-errors

		if [ -f $tempfolder/${SUBJECT}_${SESSION}_LR_Atlas_MSMAll_hp2000_clean.dtseries.nii ] && \
			[ -f $tempfolder/${SUBJECT}_${SESSION}_RL_Atlas_MSMAll_hp2000_clean.dtseries.nii ] # Script will only proceed if the session as well as both of the phase encoding directions have been properly downloaded from the server. If you also want to include subjects with only 1 phase encoding direction, you can edit this to make it more liberal (concatenation will not be necessary, demeaning and variance normalization can still be done)

		then

			mkdir -p $outputpathhighest/${SUBJECT}/${SESSION}
			outputpathsession=$outputpathhighest/${SUBJECT}/${SESSION}

			########## Preprocessing ###########

			echo "Starting demeaning, variance-normalization, and concatenating..."
			echo
			# Demean, Variance-Normalize time series from 2 different phase encoding directions individually, then concatenate them
			# https://wiki.humanconnectome.org/display/PublicData/HCP+Users+FAQ
			# https://www.humanconnectome.org/software/workbench-command/-cifti-math
			# https://www.humanconnectome.org/software/workbench-command/-cifti-merge

			for PED in "LR" "RL"
			do

				echo "Demeaning and variance normalization of ${SESSION}_${PED}..."
				wb_command -cifti-reduce $tempfolder/${SUBJECT}_${SESSION}_${PED}_Atlas_MSMAll_hp2000_clean.dtseries.nii MEAN $outputpathsession/${SUBJECT}_${SESSION}_${PED}_Atlas_MSMAll_hp2000_clean_mean.dscalar.nii
				wb_command -cifti-reduce $tempfolder/${SUBJECT}_${SESSION}_${PED}_Atlas_MSMAll_hp2000_clean.dtseries.nii STDEV $outputpathsession/${SUBJECT}_${SESSION}_${PED}_Atlas_MSMAll_hp2000_clean_stdev.dscalar.nii

				wb_command -cifti-math '((x-mean)/stdev)' $outputpathsession/${SUBJECT}_${SESSION}_${PED}_Atlas_MSMAll_hp2000_clean_demeaned_vnormalized.dtseries.nii -fixnan 0 -var x $tempfolder/${SUBJECT}_${SESSION}_${PED}_Atlas_MSMAll_hp2000_clean.dtseries.nii -var mean $outputpathsession/${SUBJECT}_${SESSION}_${PED}_Atlas_MSMAll_hp2000_clean_mean.dscalar.nii -select 1 1 -repeat -var stdev $outputpathsession/${SUBJECT}_${SESSION}_${PED}_Atlas_MSMAll_hp2000_clean_stdev.dscalar.nii -select 1 1 -repeat

				echo

			done

			echo "Concatenating ${SESSION}_LR and ${SESSION}_RL..."
			wb_command -cifti-merge $outputpathsession/${SUBJECT}_${SESSION}_Atlas_MSMAll_hp2000_clean.dtseries.nii -cifti $outputpathsession/${SUBJECT}_${SESSION}_LR_Atlas_MSMAll_hp2000_clean_demeaned_vnormalized.dtseries.nii -cifti $outputpathsession/${SUBJECT}_${SESSION}_RL_Atlas_MSMAll_hp2000_clean_demeaned_vnormalized.dtseries.nii

			echo "Done with demeaning, variance-normalization, and concatenation!"
			echo

			########## Parcellation ###########
			echo "Now starting parcellation..."

			for item in "${!atlasdict[@]}"
			do
				atlasname=${atlasdict[$item]}
				atlaspath=$item

				# 1. Parcellating the concatenated time series for the specific atlas chosen
				# https://www.humanconnectome.org/software/workbench-command/-cifti-parcellate
				# See /Atlases for the different atlases that can be used

				echo "Now parcellating time series using atlas $atlasname..."

				mkdir -p $outputpathsession/${atlasname}

				wb_command -cifti-parcellate $outputpathsession/${SUBJECT}_${SESSION}_Atlas_MSMAll_hp2000_clean.dtseries.nii $atlaspath COLUMN $outputpathsession/${atlasname}/${SUBJECT}_${SESSION}_Atlas_MSMAll_hp2000_clean_${atlasname}_timeseries.ptseries.nii

				echo "Done with parcellation for atlas $atlasname!"

				# 2. Converting the parcellated time series to a .txt file
				# https://www.humanconnectome.org/software/workbench-command/-cifti-convert

				echo "Now starting conversion of time series to .txt..."

				wb_command -cifti-convert -to-text $outputpathsession/${atlasname}/${SUBJECT}_${SESSION}_Atlas_MSMAll_hp2000_clean_${atlasname}_timeseries.ptseries.nii $outputpathsession/${atlasname}/${SUBJECT}_${SESSION}_Atlas_MSMAll_hp2000_clean_${atlasname}_timeseries.txt

				echo "Done with conversion to .txt!"
				echo

				# 3. Creating the connectivity matrix using simple Pearson correlation
				# https://www.humanconnectome.org/software/workbench-command/-cifti-correlate
				# This is optional; for some applications you may only need the time series (e.g. if you want to create the connectivity matrices in a different way. In this case, comment out section 3 and 4

				echo "Now creating connectivity matrix using Pearson correlation..."

				wb_command -cifti-correlation $outputpathsession/${atlasname}/${SUBJECT}_${SESSION}_Atlas_MSMAll_hp2000_clean_${atlasname}_timeseries.ptseries.nii $outputpathsession/${atlasname}/${SUBJECT}_${SESSION}_Atlas_MSMAll_hp2000_clean_${atlasname}_connmatrix.pconn.nii

				echo "Done with parcellation for atlas $atlasname!"

				# 4. Converting the connectivity matrix to a .txt file
				# https://www.humanconnectome.org/software/workbench-command/-cifti-convert

				echo "Now starting conversion of connectivity matrix to .txt..."

				wb_command -cifti-convert -to-text $outputpathsession/${atlasname}/${SUBJECT}_${SESSION}_Atlas_MSMAll_hp2000_clean_${atlasname}_connmatrix.pconn.nii  $outputpathsession/${atlasname}/${SUBJECT}_${SESSION}_Atlas_MSMAll_hp2000_clean_${atlasname}_connmatrix.txt

				echo "Done with conversion to .txt!"
				echo
			done

			echo "Done with parcellation"
			echo

			rm -f ${outputpathsession}/${SUBJECT}*

			echo "Done with Session $SESSION!"
			echo

		else
			echo "Session $SESSION is not complete for $SUBJECT, SKIPPING..."

		fi

	done

	# Remove only this subject's temp files — not other subjects' in-flight files
	rm -f "${tempfolder}/${SUBJECT}_"*

	echo "Done with Subject $SUBJECT!"
}

########## Looping over the subjects and the sessions ##########

now=$(date)
echo $now
echo "Starting with JOBS=$JOBS parallel subjects"
echo "Per-subject logs: ${outputpathhighest}/logs/"
echo

pids=()
failed=()

while read -r SUBJECT; do
	# Wait until a slot is free
	while (( ${#pids[@]} >= JOBS )); do
		for i in "${!pids[@]}"; do
			if ! kill -0 "${pids[$i]}" 2>/dev/null; then
				wait "${pids[$i]}" || failed+=("${pids[$i]}")
				unset 'pids[$i]'
			fi
		done
		pids=("${pids[@]}")  # reindex
		sleep 0.5
	done

	echo "[$(date +%H:%M:%S)] Launching ${SUBJECT}"
	process_subject "$SUBJECT" &
	pids+=($!)

done < "$subjectlist"

# Wait for remaining jobs
for pid in "${pids[@]}"; do
	wait "$pid" || failed+=("$pid")
done

echo
echo "Processing done!"
if (( ${#failed[@]} > 0 )); then
	echo "WARNING: ${#failed[@]} subject(s) failed. Check logs in ${outputpathhighest}/logs/"
fi

then=$(date)
echo $then
