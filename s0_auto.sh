#!/bin/bash

# This script is written by Kikuko Kaneko.
# Some part is contributed by Dr.Nemoto.
# It uses commands from dcm2niix, FSL and MRtrix3. ANTs is also required due to certain options.
# Some parts of the script are based on the ABiS image analysis tutorial, but have been
# modified at the author's discretion.
# See usage below for descriptions and detailed description of the scripts.

Version=20241011

###---------------------Variables------------------###
OLD_FSL=""
#######################################################

usage() {
    cat << EOF
This script processes data from DICOM to XTRACT and XSTAT.
The series of processes are sequentially invoked from this script.
Depending on the environment, it utilizes GPU and multicore processing if possible.
If you only want to run part of the process, adjust by commenting out the Switching area in this script.

First, prepare the DTI and 3D TI images you want to process in a directory named after the image ID 
(for example, sub001 or Image001).
These can be either DICOM or NIfTI images. DICOM images do not need to be organized in advance.
Mixing DICOM and NIfTI is not recommended.
Place NIfTI files in the directory; if in BIDS format, keeping them in the anat and dwi folders is also fine.
For DTI in NIfTI format, ensure that the json, bvec, and bval files output from dcm2niix are available.
Phase encoding reverse images are optional; if available, TOPUP will be performed.

There are two ways to execute:
Method 1:
Save all related scripts in a directory included in your PATH (e.g., $HOME/bin) and give them 
permission to be exrcuted (i.e.chmod 755 script_name).
Move to the image ID directory and run the script.
(cd path_to_image_directory; s0_auto.sh)
Method 2:
Download this repository (via git clone or zip).
Move to the image ID directory and run the script with the full path.
Example:
/home/kikuko/git/xtract_pipeline/s0_auto.sh v
If this displays the version, remove the final 'v' to execute.
/home/kikuko/git/xtract_pipeline/s0_auto.sh

Results are saved in the same directory, and DICOM files are organized in a folder named "org_data."

Note 1: Assumes FSL version 6.0.6 or later. (Check with the command: cat $FSL_DIR/etc/fslversion)
If you are using a version prior to 6.0.5, please set the variable at the beginning of the script to
OLD_FSL="yes" to use TOPUP without multithreading.
If using version 6.0.6 or later, leave it blank.
Note 2: Files and structures must be correctly organized by s1 for further processing.
Run only s1 initially and verify that the results are as intended.
EOF
}

if [[ $1 == h ]]; then
    usage
    exit 0
fi

if [[ $1 == v ]]; then
    echo "The Version of this script is: $Version"
    exit 0
fi

# get ImageID and ImagePath, and export variables
ImagePath=$PWD
ImageID=${PWD##*/}
LOG_FILE="$ImagePath/timelog.txt"
export ImageID
export ImagePath
export LOG_FILE
export NEW_FSL


# Function to log messages with timestamp
log_message() {
    local message=$1
    echo "$message at $(date)" | tee -a $LOG_FILE
}
export -f log_message

# command log
command_log=${ImagePath}/command.log_"$(date +%Y_%m_%d_%H_%M_%S)"
exec &> >(tee -a "$command_log")

# define a function to record timelog of each process

timespent() {
    echo "$1 started at $(date)"  | tee -a $LOG_FILE
    startsec=$(date +%s)
    eval $1
    finishsec=$(date +%s)
    echo "$1 finished at $(date)"  | tee -a $LOG_FILE

    spentsec=$((finishsec-startsec))

    # Support for both linux and mac date commands (i.e., GNU date and BSD date)
    spenttime=$(date --date @$spentsec "+%T" -u 2> /dev/null) # for linux
    if [[ $? != 0 ]]; then
        spenttime=$(date -u -r $spentsec +"%T") # for mac
    fi

    if [[ $spentsec -ge 86400 ]]; then
        days=$((spentsec/86400))
        echo "Time spent was $days day(s) and $spenttime" | tee -a $LOG_FILE
    else 
        echo "Time spent was $spenttime" | tee -a $LOG_FILE
    fi
    echo " " >> $LOG_FILE
}

# If timelog already exists in ImagePath, rename it.
if [[ -f $LOG_FILE ]]; then
    mv $LOG_FILE $ImagePath/timelog.txt_older_"$(date +%Y_%m_%d_%H_%M_%S)"
fi

# record the start time
allstartsec=$(date +%s)
echo "Processing of $ImageID started at $(date)"  | tee -a $LOG_FILE
echo " " >> $LOG_FILE

#-------------------------Switching area start-----------------------------------------------
set -e
# convert dicom to nifti 
timespent s1_first.sh

# denoise, degibbs, topup, eddy, biasfieldcorrection, and make mask
#timespent s2_all_preprocessing.sh
timespent NIMH.sh

# prepare files for TBSS
timespent s3_dtifit.sh

# bedpostx
timespent s4_bedpostx.sh

# create warps
timespent s5_makingwarps.sh

# create original ROI files
#timespent s_ROImaking.sh

# xtract
timespent s6_xtract.sh
#timespent xtract_baby_gpu.sh

# xstat
timespent s7_xstat.sh

#-----------------------------Switching area end---------------------------------------------

# record the finish time
allfinishsec=$(date +%s)
echo "Processing of $ImageID finished at $(date)"  | tee -a $LOG_FILE
echo "Pipeline finished. To check the tractography, copy "xview" script into the subject directory, \
change directories and run xview. Statistics is in DWI/XTRACT_output/stats.csv."
totaltimespent() {
    spentsec=$((allfinishsec-allstartsec))

    # Support for both linux and mac date commands (i.e., GNU and BSD date)
    spenttime=$(date --date @$spentsec "+%T" -u 2> /dev/null) # for linux
    if [[ $? != 0 ]]; then
        spenttime=$(date -u -r $spentsec +"%T") # for mac
    fi
    # processing maybe over 1day
    if [[ $spentsec -ge 86400 ]]; then
        days=$((spentsec/86400))
        echo "Total time spent was $days day(s) and $spenttime" | tee -a $LOG_FILE
    else 
        echo "Total time spent was $spenttime" | tee -a $LOG_FILE
    fi
    echo " " >> $LOG_FILE
}
totaltimespent
