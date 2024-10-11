# Explanation of xtract_pipeline s2_all_preprocessing.sh
### Part 1: Setting the Image Path
In this section, if ImagePath is not set, the current directory will be used as the ImagePath.
```
# If ImagePath is not set, use the current directory
ImagePath=$PWD
```
### Part 2: Verifying Necessary Files
Here, it checks if the T1-weighted (T1) and diffusion-weighted imaging (DWI) files are correctly present. If either one is missing, the process will terminate.
```
# Check if necessary files are present
ls $ImagePath/nifti_data/anat/T1.nii* | wc -l
ls $ImagePath/nifti_data/dwi/DWI*nii* | wc -l
```
If there is 1 T1 and 1 or 2 DWI files, it’s OK. Otherwise, check the files. The files actually used for analysis are the ones without numbers in the filename.

### Part 3: Checking System Information
In this section, the system checks whether it is running on Linux or macOS and retrieves the number of available cores (CPU threads) and the memory size.
```
# Check if the system is Linux or macOS
uname # Darwin indicates Mac, Linux indicates Linux
# Retrieve core count and memory information
# For Linux
nproc # Core count for Linux
cat /proc/meminfo | grep MemTotal | awk '{ printf("%d\n",$2/1024/1024) }' # Memory size for Linux
# For Mac
sysctl -n hw.ncpu # Core count for Mac
sysctl -n hw.memsize | awk '{ print $1/1024/1024/1024 } # Memory size for Mac
```
### Part 4: Setting Maximum Number of Concurrent Jobs
Here, the maximum number of parallel jobs is set based on the system's resources.

Unless the memory is very limited, setting it to core count minus 1 should be fine. Adjust accordingly if you are running other jobs in parallel. If the memory is smaller, it's safer to use just one core, regardless of the number of cores, although the execution will take longer.

For environments outside of virtual ones, check the settings above.

For Lin4Neuro (on VirtualBox or Docker), you can check or modify CPU allocations in VirtualBox settings → system or Docker advanced settings. If this is set to e.g., 4, you can set the maximum number of concurrent jobs to 3.
```
maxrunning=3
```
### Part 5: Preparing Data for Preprocessing
In this part, files are copied from the original directory to the working directory, and the T1 file is compressed if necessary.
```
# Create a directory for DWI data and copy files
cd $ImagePath
mkdir DWI
cp nifti_data/dwi/* DWI/
cp nifti_data/anat/* DWI/
cd DWI

# Compress the T1 file if it is not already compressed
gzip T1.nii
```
### Part 6: Decompressing and Preprocessing the DWI File
In this section, if the DWI file is compressed, it will be decompressed, followed by preprocessing.
```
# Decompress the DWI file if necessary
gunzip DWI_AP.nii.gz
gunzip DWI_PA.nii.gz
```
### Part 7: Processing Files Based on Various Preprocessing Conditions
Here, preparations are made for preprocessing DWI data that contains different phase encoding (PE) directions.
```
# Retrieve the number of volumes in the DWI file
fslval DWI_AP.nii* dim4
fslval DWI_PA.nii* dim4
```
Depending on whether data with the opposite PE direction (such as AP, PA, etc.) exists and the number of volumes, either process 10-12 is executed.

### Part 9: Get TotalReadoutTime
Here, TotalReadoutTime (readout time) is extracted from the JSON file to be used in subsequent processing. This information is necessary when DWI files have multiple phase encoding (PE) directions.
```
# Extract TotalReadoutTime from the JSON file
cat DWI_AP.json | grep TotalReadoutTime | cut -d: -f2 | tr -d ','
```
### Part 10: Apply Preprocessing Without Topup (Single PE Direction)
If the DWI data has only one PE (phase encoding) direction, preprocessing is performed without topup (correction for phase encoding direction).

The following is an example for the AP direction only, assuming TotalReadoutTime is 0.04.
```
# Preprocessing DWI with single PE direction
mrconvert DWI_AP.nii dwi.mif -fslgrad DWI_AP.bvec DWI_AP.bval -datatype float32
dwidenoise dwi.mif dwi_den.mif
mrdegibbs dwi_den.mif dwi_den_unr.mif -axes 0,1
dwifslpreproc dwi_den_unr.mif dwi_den_unr_preproc.mif -pe_dir AP -rpe_none -eddy_options " --slm=linear --repol --cnr_maps" -readout_time 0.04
```
#### Explanation of options (also applies to Parts 11 and 12):

The -eddy_options and -topup_options are used to pass options to the topup or eddy commands, which are part of FSL. There are various options available in the FSL user guide, and they can be passed with quotation marks as needed. Note: As shown in the example above, always include a space after the first quotation mark.

Content of -eddy_options in example:
```
--slm=linear: Recommended when the number of axes is small.  
--repol: Replaces slices when the motion exceeds 4 standard deviations.
--cnr_maps: Used for quality control (QC).
```
If you want to keep intermediate data for checking, there is an option in dwifslpreproc.
```
-nocleanup: Prevents the deletion of temporary directories (be cautious, as this takes up significant space).
```
### Part 11: Create b0 Pair for Topup (Two PE Directions)
When the DWI data consists of two phase encoding (PE) directions (AP and PA), a pair of b0 images is created, and correction is performed using topup. You can speed up topup by using the option -topup_options " --nthr=maximum number of jobs". Below is an example for DWI with AP as the primary direction, a maximum of 3 jobs, and TotalReadoutTime of 0.04 (if PA is the primary direction, swap AP and PA).
```
# Preprocessing DWI in the AP direction
mrconvert DWI_AP.nii dwi.mif -fslgrad DWI_AP.bvec DWI_AP.bval -datatype float32
dwidenoise dwi.mif dwi_den.mif
mrdegibbs dwi_den.mif dwi_den_unr.mif -axes 0,1

# Extract b0 volume (mean_b0.mif) from the AP direction images
dwiextract dwi_den_unr.mif - -bzero | mrmath - mean mean_b0.mif -axis 3

# Preprocess DWI_PA to prepare for b0 extraction
mrconvert DWI_PA.nii temp01.mif -fslgrad DWI_PA.bvec DWI_PA.bval -datatype float32
dwidenoise temp01.mif temp02.mif
mrdegibbs temp02.mif temp03.mif -axes 0,1

# Extract and average b0 volumes from processed DWI_PA
dwiextract temp03.mif - -bzero | mrmath - mean mean_b0_RPE.mif -axis 3

# Concatenate mean b0 volumes from both directions to create b0_pair
mrcat mean_b0.mif mean_b0_RPE.mif -axis 3 b0_pair.mif

# Create a b0 pair for topup correction
mrcat mean_b0.mif RPE_b0.mif -axis 3 b0_pair.mif

# dwifslpreproc
dwifslpreproc dwi_den_unr.mif dwi_den_unr_preproc.mif -pe_dir AP -rpe_pair -se_epi b0_pair.mif -eddy_options " --slm=linear --repol --cnr_maps" -topup_options " --nthr=3" -readout_time 0.04
```
### Part 12: Apply Preprocessing with Both PE Directions (Full Volume)
When full-volume DWI data is obtained from two PE directions, they are combined and preprocessing is performed. By loading the json files into the header as shown below, appropriate topup and eddy processing can be carried out. If the json file lacks sufficient information, manually create b0 pair images as described in Part 11.
```
# Combine full-volume DWI data and preprocess
mrconvert DWI_AP.nii DWI_AP.mif -fslgrad DWI_AP.bvec DWI_AP.bval -datatype float32
mrconvert DWI_PA.nii DWI_PA.mif -fslgrad DWI_PA.bvec DWI_PA.bval -datatype float32
mrcat DWI_AP.mif DWI_PA.mif DWI.mif
dwidenoise DWI.mif temp01.mif
mrdegibbs temp01.mif temp02.mif -axes 0,1
dwifslpreproc temp02.mif dwi_den_unr_preproc.mif -rpe_header -eddy_options " --slm=linear --repol --cnr_maps" -topup_options " --nthr=3" -readout_time 0.04
```
### Part 13: Apply Bias Field Correction
Once preprocessing is complete, apply the b1 bias field correction. This step corrects for signal intensity variations due to magnetic field inhomogeneities using ANTS.
```
# Apply b1 field correction
dwibiascorrect ants dwi_den_unr_preproc.mif dwi_den_unr_preproc_unbiased.mif
```
### Part 14: Final NIfTI Conversion
Finally, the preprocessed data is converted into NIfTI format.
```
# Final conversion to NIfTI format
mrconvert dwi_den_unr_preproc_unbiased.mif dwi_den_unr_preproc_unbiased.nii.gz -export_grad_fsl SR.bvec SR.bval
```
### Part 15: Deletion of Unnecessary Data
If you do not wish to keep intermediate data, you can delete it using the commands below. Be sure to confirm carefully, as deletion is irreversible.
```
# Delete unnecessary files
rm temp*.mif
```
