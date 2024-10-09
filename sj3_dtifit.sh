#!/bin/bash
# このスクリプトは、前処理済みの画像に対して dtifit を実行し、FA、MD、L1、V1、その他の拡散パラメータ画像を生成します。
# また、TBSS、bedpostxなどの処理のために必要なディレクトリを準備します。
# 前処理を実行した後に、「Image ID」という名前の作業ディレクトリ内で開始してください。
# 作業ディレクトリには以下のファイルを含む「DWI」ディレクトリが必要です:
#   dwi_den_unr_preproc_unbiased.nii.gz
#   mask_den_unr_preproc_unb.nii.gz
#   SR.bval
#   SR.bvec

# デフォルト値を設定
if [[ -z $ImagePath ]] ;then
  ImagePath=$PWD
fi

# 作業ディレクトリに移動
cd $ImagePath/DWI

# b0 画像からマスクを作成
dwiextract dwi_den_unr_preproc_unbiased.mif - -bzero | mrmath - mean mean_b0.mif -axis 3
mrconvert mean_b0.mif mean_b0.nii.gz
bet mean_b0.nii.gz nodif_brain.nii.gz -f 0.3 -R -m

# dtifit の実行
echo "画像のフィッティングを開始します..."
dtifit \
 --bvals=SR.bval \
 --bvecs=SR.bvec \
 --data=dwi_den_unr_preproc_unbiased.nii.gz \
 --mask=nodif_brain_mask.nii.gz \
 --out=SR

# dtifit の出力ファイルを「map」ディレクトリに移動
mkdir ../map
mv SR_??.nii.gz ../map/
