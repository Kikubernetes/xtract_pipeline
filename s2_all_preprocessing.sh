#!/bin/bash

# This script is to preprocess DWI data for later processing. Denoise, degibbs, 
# topup(if possible) and eddy, correct b1 field bias, and make mask.
# Start after first.sh in the working directory containing "nifti_data" directory.
# Nifti files are expected to be organized by organize_nifti.sh.
#set -x

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
  maxrunning=$(($ncores - 2))
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
    Multithreads=" -nthr=$maxrunning"
fi

# If ImagePath is not set, default to the current working directory
if [[ -z $ImagePath ]] ;then
  ImagePath=$PWD
fi
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
#dim_DWI_AP=$(fslinfo DWI_AP.nii* 2>/dev/null | grep ^dim4 | awk '{print $2}')
#dim_DWI_PA=$(fslinfo DWI_PA.nii* 2>/dev/null | grep ^dim4 | awk '{print $2}')

dim_DWI_AP=$(fslval DWI_AP.nii* dim4 2>/dev/null)
dim_DWI_PA=$(fslval DWI_PA.nii* dim4 2>/dev/null)

# Exit with error message if DWI volumes are invalid
[[  -z $dim_DWI_AP && -z $dim_DWI_PA ]] && echo "Something is wrong. Check your DWI image" && exit
[[ $dim_DWI_AP -le 6 && $dim_DWI_PA -le 6 ]] && echo "Something is wrong. Check your DWI image" && exit

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

# Analyze DWI_PA if DWI_AP is not available
if [ ! -e DWI_AP.nii* ] && [ -e DWI_PA.nii* ]; then

    echo "Analyzing DWI_PA as the main dataset without topup"

    # Convert DWI_PA to MRtrix format
    mrconvert DWI_PA.nii dwi.mif -fslgrad DWI_PA.bvec DWI_PA.bval -datatype float32
    
    # Apply denoise and degibbs
    dwidenoise dwi.mif dwi_den.mif
    mrdegibbs dwi_den.mif dwi_den_unr.mif -axes 0,1
    
    # Apply eddy correction with dwifslpreproc(no TOPUP)
    echo "dwifslpreproc started at $(date)" | tee -a $ImagePath/timelog.txt
    dwifslpreproc dwi_den_unr.mif dwi_den_unr_preproc.mif \
    -pe_dir PA -rpe_none \
    -eddy_options " --slm=linear --repol --cnr_maps" \
    -topup_options $Multithreads \
    -nocleanup $Readout

# Analyze DWI_AP if DWI_PA is not available
elif [ -e DWI_AP.nii* ] && [ ! -e DWI_PA.nii* ]; then

    echo "Analyzing DWI_AP as the main dataset without topup"

    # Convert DWI_AP to MRtrix format
    mrconvert DWI_AP.nii dwi.mif -fslgrad DWI_AP.bvec DWI_AP.bval -datatype float32
    
    # Apply denoise and degibbs
    dwidenoise dwi.mif dwi_den.mif
    mrdegibbs dwi_den.mif dwi_den_unr.mif -axes 0,1
    
    # Apply eddy correction with dwifslpreproc(no TOPUP)
    echo "dwifslpreproc started at $(date)" | tee -a $ImagePath/timelog.txt
    dwifslpreproc dwi_den_unr.mif dwi_den_unr_preproc.mif \
    -pe_dir AP -rpe_none \
    -eddy_options " --slm=linear --repol --cnr_maps" \
    -topup_options $Multithreads \
    -nocleanup $Readout


# If both DWI_AP and small DWI_PA are available, analyze DWI_AP using a b0_pair for topup
elif [ -e DWI_AP.nii* ] && [ -e DWI_PA.nii* ] && [ $dim_DWI_PA -le 12 ]; then

    echo "Analyzing DWI_AP as the main dataset and using b0_pair for topup"
    
    # Convert to mif
    mrconvert DWI_AP.nii dwi.mif -fslgrad DWI_AP.bvec DWI_AP.bval -datatype float32
    
    # Apply denoise and degibbs
    dwidenoise dwi.mif dwi_den.mif
    mrdegibbs dwi_den.mif dwi_den_unr.mif -axes 0,1
    
    # Create a b0 pair image for topup correction if DWI_PA has only 1 b0 volume
    if [[  $dim_DWI_PA == 1 ]]; then
    	# Extract and average b0 volumes from DWI_AP
        dwiextract dwi_den_unr.mif - -bzero | mrmath - mean mean_b0_AP.mif -axis 3
        # Convert DWI_PA to MRtrix format and apply Gibbs ringing correction
    	mrconvert DWI_PA.nii temp01.mif -datatype float32
    	mrdegibbs temp01.mif b0_PA.mif -axes 0,1
        # Concatenate mean_b0_AP and b0_PA.mif to create b0_pair
    	mrcat mean_b0_AP.mif b0_PA.mif -axis 3 b0_pair.mif
    	rm temp*.mif
    fi
    
    # Create a b0 pair image for topup correction if DWI_PA has more than 1 b0 volume
    if [ -e DWI_PA.nii ] && [ $dim_DWI_PA -gt 1 ]; then
        # Extract and average b0 volumes from DWI_AP
    	dwiextract dwi_den_unr.mif - -bzero | mrmath - mean mean_b0_AP.mif -axis 3
        # Convert, denoise, and degibbs DWI_PA to prepare for b0 extraction
    	mrconvert DWI_PA.nii temp01.mif -fslgrad DWI_PA.bvec DWI_PA.bval -datatype float32
    	dwidenoise temp01.mif temp02.mif
    	mrdegibbs temp02.mif temp03.mif -axes 0,1
        # Extract and average b0 volumes from processed DWI_PA
    	dwiextract temp03.mif - -bzero | mrmath - mean mean_b0_PA.mif -axis 3
        # Concatenate mean b0 volumes from both directions to create b0_pair
    	mrcat mean_b0_AP.mif mean_b0_PA.mif -axis 3 b0_pair.mif
    	rm temp*.mif
    fi
    
    # Apply topup and eddy correction using dwifslpreproc
    echo "dwifslpreproc started at $(date)" | tee -a $ImagePath/timelog.txt

	dwifslpreproc dwi_den_unr.mif dwi_den_unr_preproc.mif \
	-pe_dir AP -rpe_pair \
	-se_epi b0_pair.mif \
    -eddy_options " --slm=linear --repol --cnr_maps" \
    -topup_options $Multithreads \
    -nocleanup $Readout

# If both DWI_PA and a small DWI_AP are available, analyze DWI_PA using a b0_pair for topup
elif [ -e DWI_AP.nii* ] && [ -e DWI_PA.nii* ] && [ $dim_DWI_AP -le 12 ]; then

    echo "Analize DWI_PA as main file and use b0_pair for topup"
    
    # Convert to mif format
    mrconvert DWI_PA.nii dwi.mif -fslgrad DWI_PA.bvec DWI_PA.bval -datatype float32
    
    # Apply denoising and Gibbs ringing correction
    dwidenoise dwi.mif dwi_den.mif
    mrdegibbs dwi_den.mif dwi_den_unr.mif -axes 0,1
    
    # Create a b0 pair image for topup correction if DWI_AP has only 1 volume
    if [[  $dim_DWI_AP == 1 ]]; then
    	dwiextract dwi_den_unr.mif - -bzero | mrmath - mean mean_b0_PA.mif -axis 3
    	mrconvert DWI_AP.nii temp01.mif -datatype float32
    	mrdegibbs temp01.mif b0_AP.mif -axes 0,1
    	mrcat mean_b0_PA.mif b0_AP.mif -axis 3 b0_pair.mif
    	rm temp*.mif
    fi
    
    # Create a b0 pair image for topup correction if DWI_AP has more than 1 volume
    if [ -e DWI_PA.nii ] && [ $dim_DWI_AP -gt 1 ]; then
    	dwiextract dwi_den_unr.mif - -bzero | mrmath - mean mean_b0_PA.mif -axis 3
    	mrconvert DWI_AP.nii temp01.mif -fslgrad DWI_AP.bvec DWI_AP.bval -datatype float32
    	dwidenoise temp01.mif temp02.mif
    	mrdegibbs temp02.mif temp03.mif -axes 0,1
    	dwiextract temp03.mif - -bzero | mrmath - mean mean_b0_AP.mif -axis 3
    	mrcat mean_b0_PA.mif mean_b0_AP.mif -axis 3 b0_pair.mif
    	rm temp*.mif
    fi
    
    # Apply topup and eddy correction using dwifslpreproc
    echo "dwifslpreproc started at $(date)" | tee -a $ImagePath/timelog.txt

	dwifslpreproc dwi_den_unr.mif dwi_den_unr_preproc.mif \
	-pe_dir PA -rpe_pair \
	-se_epi b0_pair.mif \
    -eddy_options " --slm=linear --repol --cnr_maps" \
    -topup_options $Multithreads \
    -nocleanup $Readout

# If both DWI_AP and DWI_PA are available and have sufficient volumes, use both datasets for analysis
elif [ -e DWI_AP.nii* ] && [ -e DWI_PA.nii* ] && [ $dim_DWI_AP -gt 12 ] && [ $dim_DWI_PA -gt 12 ]; then

    echo "Concatenating DWI_AP and DWI_PA to create a combined dataset for analysis"

    FPATH=$ImagePath
    
    # Create a list
    cd $FPATH/nifti_data/dwi
    list=$( ls *AP.bval | sed 's/.bval//g' ; ls *PA.bval | sed 's/.bval//g' )
    
    # Merge AP and PA datasets into a single DWI dataset (This part is ontributed by Dr.Nemoto)
    fslmerge -a DWI.nii.gz $list
    paste -d " " $(ls *AP.bval; ls *PA.bval) > DWI.bval
    paste -d " " $(ls *AP.bvec; ls *PA.bvec) > DWI.bvec
    
    # Record the order of merged files for future reference
    echo "Files are merged in this order." > $FPATH/dMRI_list.txt
    echo "Bvals:" >> $FPATH/dMRI_list.txt
    ( ls *AP.bval ; ls *PA.bval )  >> $FPATH/dMRI_list.txt
    echo "Bvecs:" >> $FPATH/dMRI_list.txt
    ( ls *AP.bvec ; ls *PA.bvec )  >> $FPATH/dMRI_list.txt
    echo "Image Files are merged in this order." | tee -a $FPATH/dMRI_list.txt
    echo "$list" | tee -a $FPATH/dMRI_list.txt
    
    # Move merged DWI dataset into the new DWI directory
    mkdir ../DWI && mv DWI.nii.gz DWI.bval DWI.bvec ../DWI/ && cd ../DWI
    
    # Convert to mif
    mrconvert DWI.nii.gz SR_dwi.mif -fslgrad DWI.bvec DWI.bval -datatype float32
    
    # Apply denoise and degibbs
    dwidenoise SR_dwi.mif SR_dwi_den.mif -noise SR_dwi_noise.mif
    mrdegibbs SR_dwi_den.mif SR_dwi_den_unr.mif -axes 0,1
    
    # Retrieve TotalReadoutTime from JSON file of the first DWI dataset
    json=$(echo $list | awk '{ print $1 }')
    TotalReadoutTime=`cat ../nifti_data/${json}.json | grep TotalReadoutTime | cut -d: -f2 | tr -d ','`
    
    echo "TOPUP started at $(date)" | tee -a $FPATH/timelog.txt
    # dwifslpreproc topup & eddy (if your FSL is 6.0.6 or later, you can use --nthr option)
    dwifslpreproc SR_dwi_den_unr.mif SR_dwi_den_unr_preproc.mif \
    -pe_dir AP -rpe_all \
    -topup_options $Multithreads \
    -eddy_options " --slm=linear --repol --cnr_maps" \
    -readout_time $TotalReadoutTime
    # dwifslpreproc topup & eddy (if your FSL is 6.0.5 or earlier)
    #dwifslpreproc SR_dwi_den_unr.mif SR_dwi_den_unr_preproc.mif \
    #pe_dir AP -rpe_all \
    #-eddy_options " --slm=linear" \
    #-readout_time $TotalReadoutTime
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
