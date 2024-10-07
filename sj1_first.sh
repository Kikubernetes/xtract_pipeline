#!/bin/bash
# このプログラムは DICOM を NIFTI に変換し、NIFTI ファイルを整理するものです。
# 画像 ID の名前が付けられたオリジナルのデータがあるディレクトリで開始してください。
# 処理を開始する前にデータのバックアップを取ってください。バックアップが取れない場合は、44行目、49行目、および129行目をコメントアウトしてください。
#set -x

# ImagePath が設定されていない場合は、現在のディレクトリパスを ImagePath として取得
if [[ -z $ImagePath ]] ;then
  ImagePath=$PWD
fi

ImageID=${ImagePath##*/}
export ImageID
export ImagePath

# BIDS 構造（anat および dwi ディレクトリ）が既に存在する場合、ファイルを整理して終了
if [ -d $ImagePath/anat ] && [ -d $ImagePath/dwi ];then

    # nifti_data ディレクトリを作成し、解剖および拡散ファイルを移動
    mkdir nifti_data
    mv anat/* nifti_data
    mv dwi/* nifti_data

    # nifti_data ディレクトリ内の NIFTI ファイルを整理
    cd nifti_data
    ss_organize_nifti.sh
    cd ..

    # 正常に完了した場合は終了 0；失敗した場合は終了 1
    if [ "$(ls $ImagePath/nifti_data/anat/T1.nii*)" = '' ] || [ "$(ls $ImagePath/nifti_data/dwi/DWI*nii*)" = '' ]; then
        echo "何か問題が発生しました。中止します。"
        exit 1
    else
        echo "完了しました。"
        echo "次のステップに進む前に、NIFTI ファイルが正しく名前付けされ、分類されているか確認してください。"

        # 不要なファイルを削除
        other_niftis=$(find $ImagePath/nifti_data -mindepth 1 -maxdepth 1 \
        \( -name "*.bval" -o -name "*.bvec" -o -name "*.json" -o -name "*.nii*" \) -print)

        if [ -z "$other_niftis" ];then
            :
        else
            rm $other_niftis
            :
        fi

        # 元の空の anat および dwi ディレクトリを削除
        rmdir $ImagePath/anat $ImagePath/dwi
        exit 0
    fi
else
    :
fi

# 各ディレクトリで DICOM ファイルを検索する関数を定義
# （最初のファイルが見つかった時点で検索を停止）
function dcmsearch()
    {
        # 引数で指定されたディレクトリ以下で検索を開始
        start_dir=$1
        
        # start_dir 以下のすべてのファイルをチェックし、DICOM ファイルが見つかったら DCM_flag をオンにする
        # 'IFS= ' は行の先頭および末尾の空白を保持するため
        # read の "-r" オプションはバックスラッシュをそのままにする
        while IFS= read -r -d '' file; do
            # "file" コマンドを使って DICOM ファイルかどうかを確認
            # grep の "-q" オプションは出力を抑制する
            if file "$file" | grep -q "DICOM"; then
                echo "DICOM ファイルを発見: $file"
                DCM_flag=on
                break
            fi
        done < <(find "$start_dir" -type f -print0)
            
    }

# ImagePath ディレクトリで DICOM ファイルを検索

dcmsearch $ImagePath

if [ ! -z $DCM_flag ];then

    # org_data および nifti_data ディレクトリを作成
    mkdir org_data nifti_data

    # dcm2niix を使用して DICOM を NIFTI フォーマットに変換し、nifti_data ディレクトリに保存
    dcm2niix -f %d -o ./nifti_data .

    # 既存の NIFTI ファイル（.nii, .bval, .bvec, .json）を nifti_data ディレクトリに移動（存在する場合）
    mv *.{bval,bvec,json,nii*} nifti_data 2>/dev/null

    # DICOM ファイルを org_data ディレクトリに移動
    dicom=$(find . -mindepth 1 -maxdepth 1 -path './nifti_data' -prune -o -path './org_data' -prune -o -print)
    mv $dicom org_data/

    # ss_organize_nifti.sh を使用して NIFTI ファイルを整理
    cd nifti_data
    ss_organize_nifti.sh

    cd ..

else
    # nifti_data ディレクトリを作成し、既存の NIFTI ファイルを移動（存在する場合）
    mkdir nifti_data
    mv *.{bval,bvec,json,nii*} nifti_data 2>/dev/null
    cd nifti_data
    ss_organize_nifti.sh
    cd ..

fi

# 必要な T1 および DWI ファイルが存在するか確認し、存在しない場合はスクリプトを終了
if [ "$(ls $ImagePath/nifti_data/anat/T1.nii*)" = '' ] || [ "$(ls $ImagePath/nifti_data/dwi/DWI*nii*)" = '' ]; then
    echo "何か問題が発生しました。中止します。"
    exit 1
else
    # 処理完了メッセージを表示し、出力の確認を促す
    echo "完了しました。"
    echo "次のステップに進む前に、NIFTI ファイルが正しく名前付けされ、分類されているか確認してください。"

    # 不要なファイルを削除
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
