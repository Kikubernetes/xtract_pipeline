#!/bin/bash

# This script is to preprocess DWI data for later processing. Denoise, degibbs, 
# topup(if possible) and eddy, correct b1 field bias.
# Start after first.sh in the working directory containing "nifti_data".
# Nifti files are expected to be named and organized by ss_organize_nifti.sh.
# Rule1: Main data set needs to have more than 12 volumes ( DWI plus b0 ).
# Rule2: If main data >12 and smaller data <=12, main is used for analysis 
# and smaller data will be extracted b0 and used for only topup.
# Rule3: If both data have more than 12 volumes, both are used for analysis.
set -x

# If ImagePath is not set, default to the current working directory
if [[ -z $ImagePath ]] ;then
  ImagePath=$PWD
fi

# Verify if the necessary T1 and DWI files are present, else terminate the script
T1num=$( ls $ImagePath/nifti_data/anat/T1.nii* | wc -l )
DWInum=$( ls $ImagePath/nifti_data/dwi/DWI*nii* | wc -l )
if [ $T1num -lt 1 ] || [ $DWInum -lt 1 ]; then
    echo "Something wrong. Aborted"
    exit 1

elif [ $T1num -gt 1 ] || [ $DWInum -gt 2 ]; then
    echo "There seem many image files. Only files without numbers in their names will be used."

else
    echo "The following files are used for analysis:"
    echo "T1w: $(ls $ImagePath/nifti_data/anat/T1.nii*)"
    echo "DWI: $(ls $ImagePath/nifti_data/dwi/DWI*nii*)"
fi

# Check OS
os=$(uname)
# Check number of cores (threads)
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
  maxrunning=$(($mem - 3))
fi
if [[ $maxrunning -ge 8 ]]; then
    maxrunning=8
fi
echo "set maxrunning=${maxrunning}"

# If OLD_FSL=yes or maxrunning is empty, stop using topup_options
if [[ ! -z $OLD_FSL || -z $maxrunning ]]; then
    topo=""
    threads=""
else
    topo=" -topup_options"
    threads=" --nthr=$maxrunning"
fi

echo "Topup option : $topo $threads"

# Make directory for DWI data and copy necessary files from "nifti_data"
mkdir DWI
cp nifti_data/dwi/* DWI/
cp nifti_data/anat/* DWI/
cd DWI

# T1.nii.gz is necessary.
# Compress T1.nii if there is uncompressed version only
if [[ -e T1.nii && ! -e T1.nii.gz ]]; then
  gzip T1.nii
fi
# Ensure only the compressed version of T1 exists
if [[ -e T1.nii && -e T1.nii.gz ]]; then
  rm T1.nii
fi

# Get the number of volumes from the DWI files
dim_DWI_AP=$(fslval DWI_AP.nii* dim4 2>/dev/null)
dim_DWI_PA=$(fslval DWI_PA.nii* dim4 2>/dev/null)

# Exit with error message if DWI volumes are invalid
[[  -z $dim_DWI_AP && -z $dim_DWI_PA ]] && echo "Something is wrong. Check your DWI image" && exit 1
[[ $dim_DWI_AP -le 12 && $dim_DWI_PA -le 12 ]] && echo "Data seems too small. Aborted" && exit 1

# Retrieve TotalReadoutTime from JSON file
if [[ -e DWI_AP.json ]] ; then
    TotalReadoutTime=`cat DWI_AP.json | grep TotalReadoutTime | cut -d: -f2 | tr -d ','`
else
    TotalReadoutTime=`cat DWI_PA.json | grep TotalReadoutTime | cut -d: -f2 | tr -d ','`
fi

# If TotalReadoutTime is empty, omit the readout_time option in dwifslpreproc
if [[ -z $TotalReadoutTime ]]; then
    Readout=""
else
    Readout=" -readout_time $TotalReadoutTime"
fi

# Decompress DWI files if they are gzipped
[[ -e DWI_AP.nii.gz ]] && gunzip DWI_AP.nii.gz
[[ -e DWI_PA.nii.gz ]] && gunzip DWI_PA.nii.gz

# Define functions for preprocessing
# Function to preprocess DWI of one PE direction
one_PE() {
    local DWI=$1
    local DIR=$(echo $DWI | sed 's/^DWI_//' | sed 's/\.nii$//')
    local NAME=${DWI%%.*}
    echo "DWI of one PE direction was detected"
    echo "Analyzing $DWI without topup"

    # Convert DWI to MRtrix format
    mrconvert $DWI dwi.mif -fslgrad $NAME.bvec $NAME.bval -datatype float32
    
    # Apply denoise and degibbs
    dwidenoise dwi.mif dwi_den.mif
    mrdegibbs dwi_den.mif dwi_den_unr.mif -axes 0,1
    
    # Apply eddy correction with dwifslpreproc(no TOPUP)
    dwifslpreproc dwi_den_unr.mif dwi_den_unr_preproc.mif \
    -pe_dir $DIR -rpe_none \
    -eddy_options " --slm=linear --repol --cnr_maps" \
    -nocleanup $Readout \
    $topo "$threads"
}

# Function to preprocess DWI of two PE directions using b0 pair
b0_pair() {
    local DWI=$1
    local DIR=$(echo $DWI | sed 's/^DWI_//' | sed 's/\.nii$//')
    local NAME=${DWI%%.*}
    local RPE=$2
    local RNAME=${RPE%%.*}
    echo "DWI of two PE directions was detected"
    echo "Analyzing $1 as the main data and using b0_pair for topup"
    
    # Convert to mif
    mrconvert $DWI dwi.mif -fslgrad $NAME.bvec $NAME.bval -datatype float32
    
    # Apply denoise and degibbs
    dwidenoise dwi.mif dwi_den.mif
    mrdegibbs dwi_den.mif dwi_den_unr.mif -axes 0,1

    # Extract and average b0 volumes from $DWI
    dwiextract dwi_den_unr.mif - -bzero | mrmath - mean mean_b0.mif -axis 3
    
    # Create a b0 pair image for topup correction if $DWI_RPE has only 1 b0 volume
    if [[  $(fslval $RPE dim4) == 1 ]]; then

        # Convert DWI_RPE to MRtrix format and apply Gibbs ringing correction
    	mrconvert $RPE temp01.mif -datatype float32
    	mrdegibbs temp01.mif RPE_b0.mif -axes 0,1
        # Concatenate mean_b0_AP and b0_PA.mif to create b0_pair
    	mrcat mean_b0.mif RPE_b0.mif -axis 3 b0_pair.mif
    	rm temp*.mif
    
    # Create a b0 pair image for topup correction if DWI_PA has more than 1 b0 volume
    elif [[ $(fslval $RPE dim4) -gt 1 ]]; then

        # Convert, denoise, and degibbs DWI_PA to prepare for b0 extraction
    	mrconvert $RPE temp01.mif -fslgrad $RNAME.bvec $RNAME.bval -datatype float32
    	dwidenoise temp01.mif temp02.mif
    	mrdegibbs temp02.mif temp03.mif -axes 0,1
        # Extract and average b0 volumes from processed DWI_PA
    	dwiextract temp03.mif - -bzero | mrmath - mean mean_b0_RPE.mif -axis 3
        # Concatenate mean b0 volumes from both directions to create b0_pair
    	mrcat mean_b0.mif mean_b0_RPE.mif -axis 3 b0_pair.mif
    	rm temp*.mif
    fi
    
    # Apply topup and eddy correction using dwifslpreproc
	dwifslpreproc dwi_den_unr.mif dwi_den_unr_preproc.mif \
	-pe_dir $DIR -rpe_pair \
	-se_epi b0_pair.mif \
    -eddy_options " --slm=linear --repol --cnr_maps" \
    -nocleanup $Readout \
    $topo "$threads"
}

# Function to preprocess DWI of two PE directions using full volume
full_vol() {
    # import information to header
    local DWI1=$1
    local DWI2=$2
    local NAME1=${DWI1%%.*}
    local NAME2=${DWI2%%.*}
    mrconvert $DWI1 $NAME1.mif -fslgrad $NAME1.bvec $NAME1.bval -datatype float32 -json_import $NAME1.json 
    mrconvert $DWI2 $NAME2.mif -fslgrad $NAME2.bvec $NAME2.bval -datatype float32 -json_import $NAME2.json 

    # concatanate
    mrcat $NAME1.mif $NAME2.mif DWI.mif

    # apply denoise and degibbs
    dwidenoise DWI.mif temp01.mif
    mrdegibbs temp01.mif temp02.mif -axes 0,1

    # apply topup and eddy correction using dwifslpreproc
    dwifslpreproc temp02.mif dwi_den_unr_preproc.mif \
        -rpe_header \
        -eddy_options " --slm=linear --repol --cnr_maps" \
        -nocleanup \
        $topo "$threads"
    rm temp*.mif 
}

# Run preprocessing Depending on the type of images
#log_message "Dwifslpreproc started"
echo "dwifslpreproc finished at $(date)" | tee -a $ImagePath/timelog.txt

# analyze DWI_PA without topup if DWI_AP is not available
if [  -e DWI_AP.nii ] && [ ! -e DWI_PA.nii ]; then
    one_PE DWI_AP.nii
    
# Analyze DWI_AP without topup if DWI_PA is not available
elif [ ! -e DWI_AP.nii ] && [  -e DWI_PA.nii ]; then
    one_PE DWI_PA.nii
    
# If both DWI_AP and small DWI_PA are available, analyze DWI_AP using a b0_pair
elif [ -e DWI_AP.nii* ] && [ -e DWI_PA.nii* ] && [ $dim_DWI_PA -le 12 ]; then
    b0_pair DWI_AP.nii DWI_PA.nii
    
# If both DWI_PA and a small DWI_AP are available, analyze DWI_PA using a b0_pair for topup
elif [ -e DWI_AP.nii* ] && [ -e DWI_PA.nii* ] && [ $dim_DWI_AP -le 12 ]; then
    b0_pair DWI_PA.nii DWI_AP.nii

# If both DWI_AP and DWI_PA are available and have sufficient volumes, use both datasets for analysis
elif [ -e DWI_AP.nii* ] && [ -e DWI_PA.nii* ] && [ $dim_DWI_AP -gt 12 ] && [ $dim_DWI_PA -gt 12 ] && [ $dim_DWI_AP -ge $dim_DWI_PA ]; then
    full_vol DWI_AP.nii DWI_PA.nii

# If both DWI_AP and DWI_PA are available and have sufficient volumes, use both datasets for analysis
elif [ -e DWI_AP.nii* ] && [ -e DWI_PA.nii* ] && [ $dim_DWI_AP -gt 12 ] && [ $dim_DWI_PA -gt 12 ] && [ $dim_DWI_AP -lt $dim_DWI_PA ]; then
    full_vol DWI_PA.nii DWI_AP.nii

else 
    echo "can't detect DWI files correctly. exit before processing"
	exit 1
fi
    

echo "dwifslpreproc finished at $(date)" | tee -a $ImagePath/timelog.txt

# Apply b1 field correction using ANTs
dwibiascorrect ants dwi_den_unr_preproc.mif dwi_den_unr_preproc_unbiased.mif

# Convert the final corrected dataset to NIfTI format 
mrconvert dwi_den_unr_preproc_unbiased.mif dwi_den_unr_preproc_unbiased.nii.gz \
 -export_grad_fsl SR.bvec SR.bval

exit 0
