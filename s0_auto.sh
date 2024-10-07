#!/bin/bash

# This script is written by Kikuko Kaneko based on the 8th to 11th ABIS tutorial.
# Some part is contributed by Dr.Nemoto.
# See usage below for descriptions and usage of the scripts.
Version=20241005

###---------------------Variables------------------###
NEW_FSL=""
#######################################################

usage() {
    cat << EOF
This script processes DICOM data from DICOM to XTRACT and XSTAT.
It utilizes GPU and multicore processing when available.
To execute only specific parts of the process, modify the "Switching area" in the script.
Place DICOM files (DTI and 3DT1) or NIFTI files in a directory named with an image ID (e.g., sub001 or Image001).
Reversed phase encoding images can be included but are not required.
Save all relevant scripts in a directory included in the PATH (e.g., $HOME/bin) and grant execute permissions 
(e.g., chmod 755 script_name).
Navigate to the image directory and execute the script. (e.g., cd path_to_image_directory; s0_auto.sh)
The output will be saved in the same directory, with DICOM files organized in a folder named "org_data".
Note 1: This script assumes FSL version 6.0.6 or later. If you are using version 6.0.5 or earlier, 
set the variable at the beginning of the script to NEW_FSL="no". This will perform topup without multithreading. 
If using version 6.0.6 or later, leave it empty.
Note 2: Proper naming and structure of files in step s1 is required for subsequent steps (from s2 onwards)
to function correctly. Please run s1 first and verify the output before proceeding.

このスクリプトは、DICOMデータからXTRACTおよびXSTATまでの処理を行います。
環境に応じて、可能な場合にはGPUやマルチコアを使用します。
処理過程の一部のみ実行したい場合はこのスクリプト中のSwitching areaで調整してください。
画像ID名（例えばsub001やImage001）のディレクトリにDICOMファイル（DTIと3DT1）もしくはNIFTIファイルを用意して下さい。
逆位相エンコード画像はあってもなくても大丈夫です。
関連する全てのスクリプトをPATHに含まれているディレクトリ（例えば$HOME/bin）に保存して実行権限を与えます。
（chmod 755 スクリプト名）
画像ID名ディレクトリに移動してスクリプトを実行してください。
（cd path_to_image_directory ;s0_auto.sh)
結果は同じディレクトリ内に出力され、dicomファイルはその中の "org_data "というフォルダにまとめられます。
注意1: FSL 6.0.6以降を前提としています。6.0.5以前のバージョンをお使いの場合はスクリプトの最初にある変数を
NEW_FSL="no" としてください。マルチスレッドを使わずにtopupを行います。6.0.6以降であれば空欄のままにしておいてください。
注意: s2以降の処理が行われるためには、s1でファイル名と構造が正しく整理される必要があります。初回はs1のみを実行し、
意図した結果になっているかご確認ください。
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
