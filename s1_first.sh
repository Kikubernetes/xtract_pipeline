#!/bin/bash
# This program is to convert DICOM to NIFTI and organize nifti_files.
# Please start in the directory containing original data named after ImageID.
# Please back up your data before processing. If back-up is not available, comment out line 44, 49 & 129.
#set -x

# Get the current directory path as ImagePath if ImagePath is not set
if [[ -z $ImagePath ]] ;then
  ImagePath=$PWD
fi

ImageID=${ImagePath##*/}
export ImageID
export ImagePath

# If BIDS structure already exists (anat and dwi directories), organize files and exit
if [ -d $ImagePath/anat ] && [ -d $ImagePath/dwi ];then

    # Create nifti_data directory and move anatomical and diffusion files into it
    mkdir nifti_data
    mv anat/* nifti_data
    mv dwi/* nifti_data

    # Organize the NIFTI files in nifti_data directory
    cd nifti_data
    ss_organize_nifti.sh
    cd ..

    # if successful exit 0 ; if not successful exit 1
    if [ "$(ls $ImagePath/nifti_data/anat/T1.nii*)" = '' ] || [ "$(ls $ImagePath/nifti_data/dwi/DWI*nii*)" = '' ]; then
        echo "Something wrong. Aborted"
        exit 1
    else
        echo "Finished."
        echo "Please check if nifti files are named and classified correctly before proceeding to next step."

        # Remove unnecessary files
        other_niftis=$(find $ImagePath/nifti_data -mindepth 1 -maxdepth 1 \
        \( -name "*.bval" -o -name "*.bvec" -o -name "*.json" -o -name "*.nii*" \) -print)

        if [ -z "$other_niftis" ];then
            :
        else
            rm $other_niftis
            :
        fi

        # Remove empty original anat and dwi directories
        rmdir $ImagePath/anat $ImagePath/dwi
        exit 0
    fi
else
    :
fi

# Define a function to search for a DICOM file in each directory
# (stop searching when the first one is found)
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
if [ "$(ls $ImagePath/nifti_data/anat/T1.nii*)" = '' ] || [ "$(ls $ImagePath/nifti_data/dwi/DWI*nii*)" = '' ]; then
    echo "Something wrong. Aborted"
    exit 1
else
    # Print completion message and prompt for verification of the output
    echo "Finished."
    echo "Please check if nifti files are named and classified correctly before proceeding to next step."

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
fi
