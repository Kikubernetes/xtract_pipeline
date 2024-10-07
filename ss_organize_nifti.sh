#/bin/bash

# Check and organize nifti files
# 20240212 by Kiku
# Based on a script by Dr.Nemoto

# 画像が 3DT1, fMRI, DWI_AP, DWI_PA のどれかを判定
# ルールは以下の通り
# 3DT1: dim2>=120, dim3>100, and TE<6 ＊dim2(元々240)の条件を変更（180,こども）更に変更(120,coronal撮影)
# fMRI: dim4>=130 and 20<TE<40
# DWI: dim4>=6 and 50<TE<110

#set -x

# s_first.shの一部として実行する場合はImagePathは定義されている。そうでなければ入力から読み取る
[[ -z $ImagePath ]] && read -p "Please enter the path of nifti directory > " nifti_dir && cd $nifti_dir
[[ ! -z $ImagePath ]] && cd $ImagePath/nifti_data

# macのDS．store等を除去
rm -rf ._* .DS_Store

# サブディレクトリ作成
[ ! -d anat ] && mkdir anat
[ ! -d func ] && mkdir func
[ ! -d dwi ] && mkdir dwi
[ ! -d orig ] && mkdir orig

# back up
cp *.{bval,bvec,json,nii*} orig 2>/dev/null

# get dimension of every nifti
for f in *.nii*
do
    img=$(imglob $f)
    # 画像のdimension, およびTE, 位相エンコードの取得
	dim1=$(fslval $img dim1)
	dim2=$(fslval $img dim2)
	dim3=$(fslval $img dim3)
	dim4=$(fslval $img dim4)
    te=$(grep EchoTime ${img}.json |\
			 sed -e 's/"//g' -e 's/://' -e 's/,//' |\
			 awk '{ print int($2*1000) }')
    pe=$(grep \"PhaseEncodingDirection\" ${img}.json |\
			 awk '{ print $2 }' | sed -e 's/"//g' -e 's/,//')
	echo "Dimensions of $f is $dim1, $dim2, $dim3, and $dim4"

    # 3DT1
    # ファイル名を T1 に変更
    # もしファイルが2つあったら、T1, T1_02 に変更
	if [ "$dim2" -ge 120 ] && [ "$dim3" -gt 100 ] && [ "$te" -lt 6 ]; then
		echo "$f seems 3D-T1 file."
        extension="${f#*.}"
		if [ ! -e T1.nii* ]; then
			mv $f T1.${extension}
			mv ${img}.json T1.json
            echo "$f was renamed as T1.${extension}"
		else
			mv $f T1_02.${extension}
			mv ${img}.json T1_02.json
            echo "$f was renamed as T1_02.${extension}"
			echo "Warning: Two T1 files exist!"
		fi
        echo " "

    # fMRI
    # ファイル名を func に変更
    # ファイルが2つあったら、Func, Func_02 に変更
	elif [ "$dim4" -ge 130 ] && [ "$te" -gt 20 ] && [ "$te" -lt 40 ]; then
		echo "$f seems fMRI file."
        extension="${f#*.}"
        if [ ! -e Func.nii* ]; then
            mv $f Func.${extension}
            mv ${img}.json Func.json
            echo "$f was renamed as Func.${extension}"
        else
            mv $f Func_02.${extension}
            mv ${img}.json Func_02.jsonn
            echo "$f was renamed as Func_02.${extension}"
            echo "Warning: Two fMRI files exist!"
        fi
        echo " "
		
    # DWI
    # ファイル名を DWI_AP, DWI_PA に変更
    # 2つあったらDWI_AP_02に変更
	elif [ "$dim4" -gt 7 ] && [ "$te" -gt 50 ] && [ "$te" -lt 140 ]; then
		echo "$f seems DWI file."
        extension="${f#*.}"
        if [ "$pe" = "j" ]; then
             echo "Phase encoding of the DWI file is PA."
             if [ ! -e DWI_PA.nii* ]; then
                 mv $f DWI_PA.${extension}
                 mv ${img}.bval DWI_PA.bval
                 mv ${img}.bvec DWI_PA.bvec
                 mv ${img}.json DWI_PA.json
                 echo "$f was renamed as DWI_PA.${extension}"
             else
                 mv $f DWI_PA_02.${extension}
                 mv ${img}.bval DWI_PA_02.bval
                 mv ${img}.bvec DWI_PA_02.bvec
                 mv ${img}.json DWI_PA_02.json
                 echo "$f was renamed as DWI_PA_02.${extension}"
                 echo "Warning: Two DWI_PA files exist!"
             fi
             echo " "
        elif [ "$pe" = "j-" ]; then
             echo "Phase encoding of the DWI file is AP."
             echo " "
             if [ ! -e DWI_AP.nii* ]; then
                 mv $f DWI_AP.${extension}
                 mv ${img}.bval DWI_AP.bval
                 mv ${img}.bvec DWI_AP.bvec
                 mv ${img}.json DWI_AP.json
                 echo "$f was renamed as DWI_AP.${extension}"
             else
                 mv $f DWI_AP_02.${extension}
                 mv ${img}.bval DWI_AP_02.bval
                 mv ${img}.bvec DWI_AP_02.bvec
                 mv ${img}.json DWI_AP_02.json
                 echo "$f was renamed as DWI_AP_02.${extension}"
                 echo "Warning: Two DWI_AP files exist!"
             fi
             echo " "
        else
			 echo "Phase encoding cannot be decided."
			 echo "Do nothing."
        fi
	
	else
		echo "$f seems neither 3DT1, fMRI, nor DTI."
		echo " "
	fi
# forループの終了
done

mv *DWI* dwi 2>/dev/null
mv *T1* anat 2>/dev/null
mv *Func* func 2>/dev/null
tree -L 2

exit