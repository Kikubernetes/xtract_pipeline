#!/bin/bash
# このスクリプトは、NIMHのMRIデータを前処理するためのものです。
# 20241006 by Kikuko.K
set -x

# デフォルト値の設定
if [[ -z $ImagePath ]] ;then
  ImagePath=$PWD
fi
ImageID=${ImagePath##*/}
LOG_FILE="$ImagePath/timelog.txt"

# タイムスタンプ付きでメッセージをログに記録する関数
log_message() {
    local message=$1
    echo "$message at $(date)" | tee -a $LOG_FILE
}

log_message "処理開始: $ImageID"

# OSの確認
os=$(uname)
# コア数（スレッド数）の確認
if [[ $os == "Linux" ]]; then
  ncores=$(nproc)
  mem=$(cat /proc/meminfo | grep MemTotal | awk '{ printf("%d\n",$2/1024/1024) }')
elif [[ $os == "Darwin" ]]; then 
  ncores=$(sysctl -n hw.ncpu)
  mem=$(sysctl -n hw.memsize | awk '{ print $1/1024/1024/1024 }')
else
  echo "OSを検出できませんでした！"
  exit 1
fi
echo "論理コア数: $ncores "
echo "メモリ: ${mem}GB "

# maxrunningの設定
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
echo "maxrunningの設定=${maxrunning}"
# maxrunningが空の場合、dwifslpreprocでnthrオプションを省略
if [[ -z $maxrunning ]]; then
    Multithreads=""
else
    Multithreads=" --nthr=$maxrunning"
fi
# NEW_FSLフラグの確認
if [[ -z $NEW_FSL ]]; then
    :
else
    Multithreads=""
fi

# DWIデータ用のディレクトリを作成し、"nifti_data"から必要なファイルをコピー
mkdir DWI
cp nifti_data/dwi/* DWI/
cp nifti_data/anat/* DWI/
cd DWI

# DWIファイルがgz圧縮されている場合は解凍
[[ -e DWI_AP.nii.gz ]] && gunzip DWI_AP.nii.gz
[[ -e DWI_PA.nii.gz ]] && gunzip DWI_PA.nii.gz

# ヘッダーに情報をインポート
mrconvert DWI_PA.nii DWI_PA.mif -fslgrad DWI_PA.bvec DWI_PA.bval -datatype float32 -json_import DWI_PA.json 
mrconvert DWI_AP.nii DWI_AP.mif -fslgrad DWI_AP.bvec DWI_AP.bval -datatype float32 -json_import DWI_AP.json 

# データの結合
mrcat DWI_PA.mif DWI_AP.mif DWI.mif

# デノイズとGibbsリング補正の適用
dwidenoise DWI.mif temp01.mif
mrdegibbs temp01.mif temp02.mif -axes 0,1

# topupおよびeddy補正の適用（dwifslpreprocを使用）
log_message "Dwifslpreprocの開始"
dwifslpreproc temp02.mif dwi_den_unr_preproc.mif \
    -rpe_header \
    -eddy_options " --slm=linear --repol --cnr_maps" \
    -topup_options "$Multithreads" \
    -nocleanup
log_message "Dwifslpreprocの終了"
rm temp*.mif 

# ANTsを使用したb1フィールド補正の適用
dwibiascorrect ants dwi_den_unr_preproc.mif dwi_den_unr_preproc_unbiased.mif

# 最終的な補正データセットをNIfTI形式に変換
mrconvert dwi_den_unr_preproc_unbiased.mif dwi_den_unr_preproc_unbiased.nii.gz \
 -export_grad_fsl SR.bvec SR.bval

exit 0
