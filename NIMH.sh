#!/bin/bash
# This script is to preprocess NIMH MRI data
# 20241006 by Kikuko.K
set -x

# Set default values
if [[ -z $ImagePath ]] ;then
  ImagePath=$PWD
fi
ImageID=${ImagePath##*/}
LOG_FILE="$ImagePath/timelog.txt"

# Function to log messages with timestamp
log_message() {
    local message=$1
    echo "$message at $(date)" | tee -a $LOG_FILE
}

log_message "Processing of $ImageID started"

#Check OS
os=$(uname)
#Check number of cores (threads)
if [[ $os == "Linux" ]]; then
  ncores=$(nproc)
  mem=$(cat /proc/meminfo | grep MemTotal | awk '{ printf("%d\n",$2/1024/1024) }')
elif [[ $os == "Darwin" ]]; then 
  ncores=$(sysctl -n hw.ncpu)
  mem=$(sysctl -n hw.memsize | awk '{ print $1/1024/1024/1024 }')
else
  echo "Cannot detect your OS!"
  exit 1
fi
echo "logical cores: $ncores "
echo "memory: ${mem}GB "

# set maxrunning
if [[ $ncores -eq 1 ]]; then
  maxrunning=1
elif [[ $ncores -le $mem ]]; then
  maxrunning=$(($ncores - 1))
else
  maxrunning=$(($mem - 4))
fi
if [[ $maxrunning -ge 8 ]]; then
    maxrunning=8
fi
echo "set maxrunning=${maxrunning}"
# If maxrunning is empty, omit the nthr option in dwifslpreproc
if [[ -z $maxrunning ]]; then
    Multithreads=""
else
    Multithreads=" --nthr=$maxrunning"
fi
# Check NEW_FSL flag
if [[ -z $NEW_FSL ]]; then
    :
else
    Multithreads=""
fi

# Make directory for DWI data and copy necessary files from "nifti_data"
mkdir DWI
cp nifti_data/dwi/* DWI/
cp nifti_data/anat/* DWI/
cd DWI

# Decompress DWI files if they are gzipped
[[ -e DWI_AP.nii.gz ]] && gunzip DWI_AP.nii.gz
[[ -e DWI_PA.nii.gz ]] && gunzip DWI_PA.nii.gz

# import information to header
mrconvert DWI_PA.nii DWI_PA.mif -fslgrad DWI_PA.bvec DWI_PA.bval -datatype float32 -json_import DWI_PA.json 
mrconvert DWI_AP.nii DWI_AP.mif -fslgrad DWI_AP.bvec DWI_AP.bval -datatype float32 -json_import DWI_AP.json 

# concatanate
mrcat DWI_PA.mif DWI_AP.mif DWI.mif

# apply denoise and degibbs
dwidenoise DWI.mif temp01.mif
mrdegibbs temp01.mif temp02.mif -axes 0,1

# Apply topup and eddy correction using dwifslpreproc
log_message "Dwifslpreproc started"
dwifslpreproc temp02.mif dwi_den_unr_preproc.mif \
    -rpe_header \
    -eddy_options " --slm=linear --repol --cnr_maps" \
    -topup_options "$Multithreads" \
    -nocleanup
log_message "Dwifslpreproc finished"
rm temp*.mif 


# Apply b1 field correction using ANTs
dwibiascorrect ants dwi_den_unr_preproc.mif dwi_den_unr_preproc_unbiased.mif

# Convert the final corrected dataset to NIfTI format 
mrconvert dwi_den_unr_preproc_unbiased.mif dwi_den_unr_preproc_unbiased.nii.gz \
 -export_grad_fsl SR.bvec SR.bval

exit 0
