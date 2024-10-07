#!/bin/bash

# This script is to make warps for registration.
# Following files are necessary:
#    Tractography.bedpostX <== generated by bedpostx
#    nodif_brain.nii.gz <== generated by bedpsotx
#    nifti_data/org_data_Sag_T1_FSPGR-IR.nii(T1 nifti_file) <== generated by dcm2niix
# Start in the working directory named "Image ID" after bedpostX.

# get ImageID and ImagePath
if [[ -z $ImagePath ]] ;then
  ImagePath=$PWD
fi

cd $ImagePath/DWI

# Brain extraction
echo "Now running bet..."
bet T1.nii.gz T1_brain.nii.gz -f 0.2 -B

# prepare files
if [ ! -d DTI.bedpostX ]; then
    mv Tractography.bedpostX/ DTI.bedpostX/
    mv nodif_brain.nii.gz DTI.bedpostX/
fi

# registration
echo "Now running flirt..."
flirt -in DTI.bedpostX/nodif_brain \
    -ref T1_brain.nii.gz \
    -omat DTI.bedpostX/xfms/diff2str.mat \
    -searchrx -180 180 -searchry -180 180 -searchrz -180 180 \
    -dof 6 -cost normmi
   #-dof 6 -cost corratio

convert_xfm -omat DTI.bedpostX/xfms/str2diff.mat \
    -inverse DTI.bedpostX/xfms/diff2str.mat

flirt -in T1_brain.nii.gz \
    -ref /usr/local/fsl/data/standard/MNI152_T1_2mm_brain.nii.gz \
    -omat DTI.bedpostX/xfms/str2standard.mat \
    -searchrx -180 180 -searchry -180 180 -searchrz -180 180 \
    -dof 12 -cost corratio

echo "Now running fnirt..."

convert_xfm -omat DTI.bedpostX/xfms/standard2str.mat \
            -inverse DTI.bedpostX/xfms/str2standard.mat
 
convert_xfm -omat DTI.bedpostX/xfms/diff2standard.mat \
            -concat DTI.bedpostX/xfms/str2standard.mat DTI.bedpostX/xfms/diff2str.mat
 
convert_xfm -omat DTI.bedpostX/xfms/standard2diff.mat \
            -inverse DTI.bedpostX/xfms/diff2standard.mat

fnirt --in=T1.nii.gz \
    --aff=DTI.bedpostX/xfms/str2standard.mat \
    --cout=DTI.bedpostX/xfms/str2standard_warp \
    --config=T1_2_MNI152_2mm

echo "Now running invwarp..."
invwarp -w DTI.bedpostX/xfms/str2standard_warp \
        -o DTI.bedpostX/xfms/standard2str_warp \
        -r T1_brain.nii.gz 

convertwarp -o DTI.bedpostX/xfms/diff2standard_warp \
    -r /usr/local/fsl/data/standard/MNI152_T1_2mm_brain.nii.gz \
    -m DTI.bedpostX/xfms/diff2str.mat \
    -w DTI.bedpostX/xfms/str2standard_warp

convertwarp -o DTI.bedpostX/xfms/standard2diff_warp \
    -r DTI.bedpostX/nodif_brain_mask \
    -w DTI.bedpostX/xfms/standard2str_warp \
    --postmat=DTI.bedpostX/xfms/str2diff.mat

cd ..
exit
