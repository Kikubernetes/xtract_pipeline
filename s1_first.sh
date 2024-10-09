#!/bin/bash
# This program is to convert DICOM to NIfTI and organize nifti_files.
# NIfTI files can be organised too, but mixed condition(of DICOM and NIfTI) is not tested enough.
# Please start in the directory containing original data named after ImageID.
# Note : Always make sure to back up your data before processing.
set -x

# Get the current directory path as ImagePath if ImagePath is not set
if [[ -z $ImagePath ]] ;then
  ImagePath=$PWD
fi

ImageID=${ImagePath##*/}
export ImageID
export ImagePath

# Define a function to search for a DICOM file in each directory
# (stop searching when the first one is found and set DCM_flag on)
function dcmsearch()
    {
        # start search under the argument directory
        start_dir=$1
        
        # check all files under start_dir, make DCM_flag on if a dicom file is found
        # 'IFS= ' is to preserve leading and trailing white space in line
        # Use "-r" option in read to keep backslashes as plain text
        while IFS= read -r -d '' file; do
            # Use "file" command to check if a file is a DICOM
            # Suppress the output of grep using the "-q" option
            if file "$file" | grep -q "DICOM"; then
                echo "Found DICOM file: $file"
                DCM_flag=on
                break
            fi
        done < <(find "$start_dir" -type f -print0)
            
    }

# Search for DICOM files in the ImagePath directory

T1num=$( ls $ImagePath/nifti_data/anat/T1.nii* 2>/dev/null| wc -l )
DWInum=$( ls $ImagePath/nifti_data/dwi/DWI*nii* 2>/dev/null | wc -l )

# If BIDS structure already exists (anat and dwi directories), organize files and exit
if [[ $T1num -ge 1 && $DWInum -ge 1 ]];then

    echo "It seems files already exists and organized" 
    echo "Stop further organizing and proceed to s2"
    exit 0

fi

dcmsearch $ImagePath

if [ ! -z $DCM_flag ];then

    # Create org_data and nifti_data directories
    mkdir org_data nifti_data

    # Convert DICOM to NIFTI format using dcm2niix and store in nifti_data directory
    dcm2niix -f %d -o ./nifti_data .

    # Move existing NIFTI files (.nii, .bval, .bvec, .json) into nifti_data directory if they exist
    mv *.{bval,bvec,json,nii*} nifti_data 2>/dev/null

    # Move the DICOM files to the org_data directory
    dicom=$(find . -mindepth 1 -maxdepth 1 -path './nifti_data' -prune -o -path './org_data' -prune -o -print)
    mv $dicom org_data/

    # Organize the NIFTI files using ss_organize_nifti.sh
    cd nifti_data
    ss_organize_nifti.sh

    cd ..

else
    # Create nifti_data directory and move existing NIFTI files if they exist

    mkdir nifti_data
    mv *.{bval,bvec,json,nii*} nifti_data 2>/dev/null
    cd nifti_data
    ss_organize_nifti.sh
    cd ..

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
    # Print completion message and prompt for verification of the output
    echo "Finished."
fi

# Remove unnecessary files
other_niftis=$(find $ImagePath/nifti_data -mindepth 1 -maxdepth 1 \
\( -name "*.bval" -o -name "*.bvec" -o -name "*.json" -o -name "*.nii*" \) -print)

if [ -z "$other_niftis" ];then
    :
else
    rm $other_niftis
    :
fi

exit 0
