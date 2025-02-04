#!/bin/bash

#####################################################################################
# reogranize qsiprep outputs for brainlife
#####################################################################################

module load singularity 2> /dev/null

set -x
set -e

# outstem is the top directory that is created by qsiprep to dump all of the
# derivatives
outstem=output

# get basename for output
sub=$(jq -r '._inputs[0].meta.subject' config.json)
space=$(jq -r .output_space config.json)
xflip=$(jq -r .xflip config.json)
ses=$(jq -r '._inputs[] | select(.id == "dwi") | .meta.session' config.json)
ses=($ses)

#organize output
mkdir -p output_anat_preproc
mkdir -p output_dseg
mkdir -p output_brainmask
mkdir -p output_dwi
mkdir -p output_report

# set file paths and stems. outdir is the output dir + qsiprep, and is used to
# grab the html and figures files. outsub is the outdir + the subject stem, and
# is used to grab the anatomy and dwi data. SRCDIR is the outsub + the anat
# directory, and is used specifically to grab the appropriate t1 data. outfile
# is the subject stem, and is used to make identifying the appropriate dwi
# files easier
outdir=$outstem/qsiprep
outsub="$outdir/sub-${sub}"
SRCDIR=$outsub/anat
outfile="sub-${sub}"

# if a session tag exists, append to outsub and outfile
[ "$ses" != "null" ] && outsub=$outsub/ses-${ses[0]}
[ "$ses" != "null" ] && outfile=${outfile}_ses-${ses[0]}

# copy the appropriate anatomy data, based on space input
if [ $space == "T1w" ]; then
    cp $SRCDIR/sub-${sub}_desc-preproc_T1w.nii.gz output_anat_preproc/t1.nii.gz;
    cp $SRCDIR/sub-${sub}_dseg.nii.gz output_dseg/parc.nii.gz;
    cp $SRCDIR/sub-${sub}_desc-brain_mask.nii.gz output_brainmask/mask.nii.gz;
elif [ $space == "MNI152NLin2009cAsym" ]; then
    cp $SRCDIR/sub-${sub}_space-MNI152NLin2009cAsym_desc-preproc_T1w.nii.gz output_anat_preproc/t1.nii.gz;
    cp $SRCDIR/sub-${sub}_space-MNI152NLin2009cAsym_dseg.nii.gz output_dseg/parc.nii.gz;
    cp $SRCDIR/sub-${sub}_space-MNI152NLin2009cAsym_desc-brain_mask.nii.gz output_brainmask/mask.nii.gz;
fi

# copy dwi output to bl output dir
cp $outsub/dwi/${outfile}_space-T1w_desc-preproc_dwi.nii.gz output_dwi/dwi.nii.gz
cp $outsub/dwi/${outfile}_space-T1w_desc-preproc_dwi.bvec output_dwi/dwi.bvecs
cp $outsub/dwi/${outfile}_space-T1w_desc-preproc_dwi.bval output_dwi/dwi.bvals

# copy over report html to output dir
for html in $(cd $outstem && find -name "*.html"); do
    mkdir -p output_report/$(dirname $html)
    cp $outstem/$html output_report/$html
done

for dir in $(cd $outstem && find ./ -name figures); do
    mkdir -p output_report/$(dirname $dir)
    cp -r $outstem/$dir output_report/$(dirname $dir)
done

#rename the parent directory to confirm to brainlife html output
mv output_report/qsiprep output_report/html

#flip bvecs
if [ $xflip == "true" ]; then
    echo "flip bvecs-x to be compatible with MRtrix"
    sed -i '$s/}/,\n"bvecs_out":".\/output_dwi\/dwi.bvecs"}/' config.json #input bvecs
    singularity exec -e docker://brainlife/mcr:neurodebian1604-r2017a ./compiled/main
    rm output_dwi/dwi.bvecs #input bvecs
    cp dwi.bvecs output_dwi/dwi.bvecs #flipped bvecs
fi

# copy confounds.tsv file to regressors directory
[ ! -d ./regressors ] && mkdir -p regressors
[ ! -f ./regressors/regressors.tsv ] && cp $outsub/dwi/*_confounds.tsv ./regressors/regresors.tsv
