#!/usr/bin/env python3
"""
Build the annotation files for Schaefer2018 (7 networks) + Tian S1 combined atlases.

For each requested resolution, writes the five files listed in Atlases/README.md to
Atlases/Schaefer/<RES>regions7networks/annotation/:
  positions, region_names_full, region_names_short, subnet_order_names, subnet_order_colors

Sources:
  - Tian rows (first 16 lines): copied from the existing 100-region annotation files
    (identical across the 100, 400 and 1000 resolutions).
  - Schaefer region names: label table of the combined .dlabel.nii in the resolution folder.
  - Schaefer coordinates: CBIG Schaefer2018_<RES>Parcels_7Networks_order_FSLMNI152_2mm.Centroid_RAS.csv
    (https://github.com/ThomasYeoLab/CBIG/tree/master/stable_projects/brain_parcellation/
     Schaefer2018_LocalGlobal/Parcellations/MNI/Centroid_coordinates)
  - Full names of abbreviations and subnetwork colors: learned from the existing 100- and
    1000-region annotation files.

Before writing, the existing 100 and 1000 annotation files are regenerated and compared; the
script stops if they do not match exactly.

Usage:
  python3 build_schaefer_tian_annotation.py <repo_root> <centroid_csv_dir> <RES> [<RES> ...]
  e.g. python3 Scripts/build_schaefer_tian_annotation.py . ~/Downloads/Centroid_coordinates 200 300
"""
import csv
import glob
import os
import sys

import nibabel as nib

KINDS = ['positions', 'region_names_full', 'region_names_short', 'subnet_order_names', 'subnet_order_colors']
NETWORK_CODES = {'Vis': 'VIS', 'SomMot': 'SM', 'DorsAttn': 'DA', 'SalVentAttn': 'VA',
                 'Limbic': 'LIM', 'Cont': 'FP', 'Default': 'DMN'}
N_TIAN = 16
REFERENCE_RESOLUTIONS = (100, 1000)


def read_existing(schaefer_dir, res):
    files = {}
    for kind in KINDS:
        path = glob.glob(f'{schaefer_dir}/{res}regions7networks/annotation/*_{kind}.txt')[0]
        files[kind] = open(path).read().splitlines()
    return files


def dlabel_names(schaefer_dir, res):
    path = glob.glob(f'{schaefer_dir}/{res}regions7networks/*.dlabel.nii')[0]
    table = nib.load(path).header.get_axis(0).label[0]
    return [table[key][0] for key in sorted(table) if key != 0]


def short_name(label):
    # '7Networks_LH_Vis_1' -> 'L_Vis_1'
    parts = label.split('_')
    assert parts[0] == '7Networks' and parts[1] in ('LH', 'RH'), label
    return '_'.join([parts[1][0]] + parts[2:])


def learn_from_references(references):
    tian = {kind: references[REFERENCE_RESOLUTIONS[0]][kind][:N_TIAN] for kind in KINDS}
    colors, full_names = {}, {}
    for files in references.values():
        for kind in KINDS:
            assert files[kind][:N_TIAN] == tian[kind], f'Tian rows differ in {kind}'
        for network, color in zip(files['subnet_order_names'][N_TIAN:], files['subnet_order_colors'][N_TIAN:]):
            assert colors.setdefault(network, color) == color
        for short, full in zip(files['region_names_short'][N_TIAN:], files['region_names_full'][N_TIAN:]):
            s, f = short.split('_'), full.split('_')
            if len(s) == 3:  # e.g. L_Vis_1: no subregion abbreviation
                assert short == full, (short, full)
                continue
            expanded = '_'.join(f[2:-1])
            assert full_names.setdefault(s[2], expanded) == expanded, (s[2], expanded, full_names[s[2]])
    return tian, colors, full_names


def generate(schaefer_dir, centroid_dir, res, tian, colors, full_names):
    labels = dlabel_names(schaefer_dir, res)
    assert len(labels) == res + N_TIAN, f'{res}: expected {res + N_TIAN} labels, found {len(labels)}'
    cortex = labels[N_TIAN:]
    centroid_csv = f'{centroid_dir}/Schaefer2018_{res}Parcels_7Networks_order_FSLMNI152_2mm.Centroid_RAS.csv'
    centroids = list(csv.DictReader(open(centroid_csv)))
    assert [row['ROI Name'] for row in centroids] == cortex, f'{res}: centroid file order differs from atlas labels'

    short = [short_name(label) for label in cortex]
    unknown = sorted({s.split('_')[2] for s in short if len(s.split('_')) == 4} - set(full_names))
    if unknown:
        sys.exit(f'{res}: no known full name for abbreviations {unknown}')
    full = [s if len(s.split('_')) == 3 else '_'.join(s.split('_')[:2] + [full_names[s.split('_')[2]], s.split('_')[3]])
            for s in short]
    networks = [NETWORK_CODES[label.split('_')[2]] for label in cortex]
    generated = {
        'positions': [f"{row['R']} {row['A']} {row['S']}" for row in centroids],
        'region_names_full': full,
        'region_names_short': short,
        'subnet_order_names': networks,
        'subnet_order_colors': [colors[network] for network in networks],
    }
    return {kind: tian[kind] + generated[kind] for kind in KINDS}


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    repo_root, centroid_dir = sys.argv[1], sys.argv[2]
    resolutions = [int(r) for r in sys.argv[3:]]
    schaefer_dir = os.path.join(repo_root, 'Atlases', 'Schaefer')

    references = {res: read_existing(schaefer_dir, res) for res in REFERENCE_RESOLUTIONS}
    tian, colors, full_names = learn_from_references(references)

    for res in REFERENCE_RESOLUTIONS:
        regenerated = generate(schaefer_dir, centroid_dir, res, tian, colors, full_names)
        for kind in KINDS:
            assert regenerated[kind] == references[res][kind], f'regenerated {res} {kind} differs from existing file'
    print(f'Existing annotation files for {REFERENCE_RESOLUTIONS} reproduced exactly.')

    for res in resolutions:
        files = generate(schaefer_dir, centroid_dir, res, tian, colors, full_names)
        out_dir = f'{schaefer_dir}/{res}regions7networks/annotation'
        os.makedirs(out_dir, exist_ok=True)
        for kind in KINDS:
            with open(f'{out_dir}/Schaefer2018_{res}Parcels_7Networks_Tian_Subcortex_S1_3T_{kind}.txt', 'w') as fh:
                fh.write('\n'.join(files[kind]) + '\n')
        print(f'Wrote {res}-region annotation files ({res + N_TIAN} lines each) to {out_dir}')


if __name__ == '__main__':
    main()
