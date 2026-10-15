<h3>About the atlas:</h3>

This folder contains the relevant files for the Schaefer atlas, applied to the Human Connectome Project (Schaefer et al., 2018, doi: 10.1093/cercor/bhx179). This atlas was used in 5 different resolutions (100, 200, 300, 400 and 1000 regions). It was combined with the S1-version of the Tian subcortical atlas (Tian et al., 2020, doi: 10.1038/s41593-020-00711-6).

The combined cortical and subcortical atlas could directly be downloaded for the 400-region resolution from https://github.com/yetianmed/subcortex/tree/master/Group-Parcellation. For the other resolutions, it had to be constructed manually by combining the Schafer atlas in the desired resolution (https://github.com/ThomasYeoLab/CBIG/tree/master/stable_projects/brain_parcellation/Schaefer2018_LocalGlobal/Parcellations) with the subcortical atlas (also downloaded from the Tian Github page). This was performed in the following way:

<ol>
  <li>Add label file to Tian S1 subcortical atlas (in volume space):<br>
<code>wb_command -volume-label-import Tian_Subcortex_S1_3T.nii.gz Tian_Subcortex_S1_3T_labelannotation.txt Tian_Subcortex_S1_3T_labeled.nii.gz</code></li>
  
  <li>Add the labeled Tian S1 subcortical atlas to the cortical Schafer atlas in the desired resolution (100, 300 or 1000 regions):<br><code>
  wb_command -cifti-create-dense-from-template 91282_Greyordinates.dscalar.nii Schaefer2018_<em>RESOLUTION</em>Parcels_7Networks_order_Tian_Subcortex_S1_3T.dlabel.nii -cifti Schaefer2018_<em>RESOLUTION</em>Parcels_7Networks_order.dlabel.nii -volume-all Tian_Subcortex_S1_3T_labeled.nii.gz -label-collision LEGACY</code></li></ol>

Note on <code>-label-collision LEGACY</code>: the Tian labels (keys 1-16) and the Schaefer labels (keys 1-N) share key values. Connectome Workbench v1.4.2 and earlier resolved this automatically by moving the Schaefer labels to keys 17 to N+16; later versions stop with <code>ERROR: conflicting key value 1 for label '7Networks_LH_Vis_1'</code> unless <code>-label-collision LEGACY</code> is given. With this flag, Workbench v2.1.0 reproduces the 100-region atlas in this folder exactly (same label at every greyordinate, same label table and colors).

Additional resolutions (added 2026-10):

<ul>
  <li><em>200 regions</em>: <code>Schaefer2018_200Parcels_7Networks_order_Tian_Subcortex_S1.dlabel.nii</code> was downloaded as-is from https://github.com/yetianmed/subcortex/tree/master/Group-Parcellation/3T/Cortex-Subcortex. Rebuilding it with the two commands above gives an identical atlas.</li>
  <li><em>300 regions</em>: Tian provides no CIFTI file at this resolution, so <code>Schaefer2018_300Parcels_7Networks_order_Tian_Subcortex_S1_3T.dlabel.nii</code> was built with the two commands above from <code>info/Schaefer2018_300Parcels_7Networks_order.dlabel.nii</code> (CBIG, fslr32k). Its cortical labels match the CBIG file at every vertex.</li>
  <li>The 100-region atlas built here is identical to the one Tian now provides (<code>Schaefer2018_100Parcels_7Networks_order_Tian_Subcortex_S1.dlabel.nii</code>).</li>
</ul>

In all combined atlases the 16 Tian regions come first (keys 1-16), followed by the Schaefer regions.

------------------------------------------------------------------------------------------

<h3>About the annotation:</h3>

All the annotated information about the names and subnetwork membership of the regions can be found on the respective GitHub pages of the Schaefer and Tian atlases:

  <ul><li><em>Schaefer</em>: https://github.com/ThomasYeoLab/CBIG/tree/master/stable_projects/brain_parcellation/Schaefer2018_LocalGlobal/Parcellations/HCP/fslr32k/cifti for region names and subnetwork membership, and https://github.com/ThomasYeoLab/CBIG/tree/master/stable_projects/brain_parcellation/Schaefer2018_LocalGlobal/Parcellations/MNI/Centroid_coordinates for region coordinates</li>
    <li><em>Tian</em>: https://github.com/yetianmed/subcortex/tree/master/Group-Parcellation/3T/Subcortex-Only for the region names and coordinates.</li></ul>

The annotation files for 200 and 300 regions were generated with <code>Scripts/build_schaefer_tian_annotation.py</code>, which takes the names from the atlas label table and the coordinates from the CBIG <code>Schaefer2018_*Parcels_7Networks_order_FSLMNI152_2mm.Centroid_RAS.csv</code> files. The script regenerates the existing 100 and 1000 annotation files exactly.

Correction (2026-10): the cortical rows of <code>400regions7networks/annotation/..._positions.txt</code> were previously the CBIG centroids flattened in column order (each row held the x, y or z values of three consecutive regions instead of one region's x, y, z). They have been replaced with the correct CBIG centroids. The 400 <code>region_names_full</code> file still spells two abbreviations differently from the 100 and 1000 files (<code>Cing</code> instead of <code>Cingulate</code>, <code>Prefrontal_Cortex_mp</code> instead of <code>Prefrontal_Cortex_m_p</code>); this was left unchanged.
