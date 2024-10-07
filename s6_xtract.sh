#!/bin/bash

# This script is to run xtract_gpu.
# Prepare following files in the working directory:
#         DTI.bedpostX/xfms/diff2standard.mat etc.
#         map/SR_FA.nii.gz
# Please start in the working directory named "Image ID".

# get ImageID and ImagePath, and export variables
if [[ -z $ImagePath ]] ;then
  ImagePath=$PWD
fi
BPX_DIR='DTI.bedpostX'


cd $ImagePath
# copy file and go into DWI
cp map/SR_FA.nii.gz DWI/
cd DWI

# check GPU availability and set gpu flag
if lspci | grep -i nvidia -q ; then
    echo 'GPU seems available. Xtract by GPU will be tried.'
    echo "Now running xtract_gpu..."
    GPU_FLAG=" -gpu"

else
    echo 'GPU is not available. Xtract by CPU will be tried.'
    echo "Now running xtract with cpu..."
    GPU_FLAG=""
fi

# xtract
xtract -bpx $BPX_DIR -out XTRACT_output -species HUMAN \
    -stdwarp $BPX_DIR/xfms/standard2diff_warp $BPX_DIR/xfms/diff2standard_warp -native $GPU_FLAG


# viewing tracts
#xtract_viewer -dir XTRACT_output -brain SR_FA.nii.gz
exit 0
