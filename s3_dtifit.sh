#!/bin/bash
# This script runs dtifit on preprocessed images to generate FA, MD, L1, V1, and other diffusion parameter images.
# It also prepares the necessary directories for further processing steps, such as TBSS, bedpostx, and FMRIB_to_FA.
# After running preprocessing, start in the working directory named "Image ID" 
# that contains the "DWI" directory with the following files:
#	dwi_den_unr_preproc_unbiased.nii.gz
#	mask_den_unr_preproc_unb.nii.gz
#	SR.bval
#	SR.bvec

# Set default values
if [[ -z $ImagePath ]] ;then
  ImagePath=$PWD
fi

# Move to the working directory
cd $ImagePath/DWI

# Create mask from b0 images
dwiextract dwi_den_unr_preproc_unbiased.mif - -bzero | mrmath - mean mean_b0.mif -axis 3
mrconvert mean_b0.mif mean_b0.nii.gz
bet mean_b0.nii.gz nodif_brain.nii.gz -f 0.3 -R -m

# Run dtifit
echo "Now fitting the image..."
dtifit \
 --bvals=SR.bval \
 --bvecs=SR.bvec \
 --data=dwi_den_unr_preproc_unbiased.nii.gz \
 --mask=nodif_brain_mask.nii.gz \
 --out=SR

# Move dtifit output files to the "map" directory
mkdir ../map
mv SR_??.nii.gz ../map/


