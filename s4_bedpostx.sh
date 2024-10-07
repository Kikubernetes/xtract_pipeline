#!/bin/bash
# This script is for bedpostx.
# Please start in the working directory named "Image ID".
# GPU availability will be checked and utilize bedpostx_gpu if available.

# get ImageID and ImagePath, and export variables
if [[ -z $ImagePath ]] ;then
  ImagePath=$PWD
fi

cd $ImagePath/DWI

# arrange files for bedpostx and check data
mkdir ./Tractography
cp dwi_den_unr_preproc_unbiased.nii.gz ./Tractography/data.nii.gz
cp nodif_brain_mask.nii.gz ./Tractography/nodif_brain_mask.nii.gz
cp SR.bvec ./Tractography/bvecs
cp SR.bval ./Tractography/bvals
bedpostx_datacheck Tractography

# check GPU availability and run bedpostx
if lspci | grep -i nvidia -q ; then
    echo 'GPU seems available. bedpostx_gpu will be tried.'
    echo "Now running bedpostx_gpu..."
    bedpostx_gpu Tractography
else
    echo 'GPU is not available. bedpostx will be tried.'
    echo "Now running bedpostx with cpu..."
    bedpostx Tractography
fi

cd ..
exit
