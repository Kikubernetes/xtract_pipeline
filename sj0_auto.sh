#!/bin/bash

# このスクリプトは、Kikuko Kanekoによって作成されました。
# dcm2niix, FSLとMRtrix3のコマンドを使用します。オプションの関係でANTsも必要です。
# 一般的なdMRIデータに対して気軽に、自動的に、かつなるべく短時間で行えるシンプルな処理を目指しています。
# スクリプトの一部はABiS画像解析チュートリアルの内容に基づいていますが、作者の判断で改変しています。
# ss_organize_nifti.shについては、Dr.Nemotoが作成されたスクリプトを許可をいただいてKanekoが改変しています。
# 詳しい使用方法については、以下のusageを参照してください。
# 結果を確認しながらひとつひとつ実行したい場合はdocsフォルダをご参照ください。

Version=20241011

###---------------------変数------------------###
OLD_FSL=""
#################################################

usage() {
    cat << EOF
このスクリプトは、DICOMデータからXTRACTおよびXSTATまでの処理を行います。
一連の処理はこのスクリプトから順番に呼び出されます。
環境に応じて、可能な場合にはGPUやマルチコアを使用します。
処理過程の一部のみ実行したい場合はこのスクリプト中のSwitching areaをコメントアウトして調整してください。

まず画像ID名（例えばsub001やImage001）のディレクトリに処理したいDTIと3D TI画像を用意します。
DICOM画像、もしくはNIfTI画像のどちらかです。DICOMは前もって整理する必要はありません。
DICOMとNIFTIを混在させるのはおすすめできません。
NIfTIは直接ディレクトリ内に置きますが、BIDS形式であればanatとdwiフォルダのままでも大丈夫です。
DTIがNIfTIの場合はdcm2niixから出力されるjson, bvec, bvalファイルが揃っている必要があります。
逆位相エンコード画像はあってもなくても大丈夫です。ある場合はTOPUPを行います。

実行方法は2通りあります。
実行方法①:
関連する全てのスクリプトをPATHに含まれているディレクトリ（例えば$HOME/bin）に保存して実行権限を与えます。
（chmod 755 スクリプト名）
画像ID名ディレクトリに移動してスクリプトを実行してください。
（cd path_to_image_directory ;s0_auto.sh)
実行方法②:
このリポジトリをダウンロードします。（git cloneでもzipでも）
画像ID名ディレクトリに移動してスクリプトをフルパスで実行します。
例）
/home/kikuko/git/xtract_pipeline/s0_auto.sh v
これでバージョンが表示されれば、最後のvをとって実行します。
/home/kikuko/git/xtract_pipeline/s0_auto.sh

結果は同じディレクトリ内に出力され、DICOMファイルはその中の "org_data "というフォルダにまとめられます。

注意1: FSL 6.0.6以降を前提としています。(以下のコマンドで確認できます：cat $FSL_DIR/etc/fslversion)
6.0.5以前のバージョンをお使いの場合はスクリプトの最初にある変数を
OLD_FSL="yes" としてください。マルチスレッドを使わずにtopupを行います。
6.0.6以降であれば空欄のままにしておいてください。
注意: s2以降の処理が行われるためには、s1でファイル名と構造が正しく整理される必要があります。
初回はs1のみを実行し、意図した結果になっているかご確認ください。
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
#!/bin/bash

# 変数の取得とエクスポート
ImagePath=$PWD
ImageID=${PWD##*/}
LOG_FILE="$ImagePath/timelog.txt"
export ImageID
export ImagePath
export LOG_FILE
export NEW_FSL


# タイムスタンプ付きでメッセージをログに記録する関数
log_message() {
    local message=$1
    echo "$message at $(date)" | tee -a $LOG_FILE
}
export -f log_message

# コマンドログの設定
command_log=${ImagePath}/command.log_"$(date +%Y_%m_%d_%H_%M_%S)"
exec &> >(tee -a "$command_log")

# 各プロセスの実行時間を記録する関数を定義
timespent() {
    echo "$1 started at $(date)"  | tee -a $LOG_FILE
    startsec=$(date +%s)
    eval $1
    finishsec=$(date +%s)
    echo "$1 finished at $(date)"  | tee -a $LOG_FILE

    spentsec=$((finishsec-startsec))

    # LinuxとmacOSの両方に対応（GNU dateとBSD date）
    spenttime=$(date --date @$spentsec "+%T" -u 2> /dev/null) # Linux用
    if [[ $? != 0 ]]; then
        spenttime=$(date -u -r $spentsec +"%T") # macOS用
    fi

    if [[ $spentsec -ge 86400 ]]; then
        days=$((spentsec/86400))
        echo "処理時間は $days 日と $spenttime" | tee -a $LOG_FILE
    else 
        echo "処理時間は $spenttime" | tee -a $LOG_FILE
    fi
    echo " " >> $LOG_FILE
}

# timelog が既に存在する場合、その名前を変更する
if [[ -f $LOG_FILE ]]; then
    mv $LOG_FILE $ImagePath/timelog.txt_older_"$(date +%Y_%m_%d_%H_%M_%S)"
fi

# 開始時刻の記録
allstartsec=$(date +%s)
echo "Processing of $ImageID started at $(date)"  | tee -a $LOG_FILE
echo " " >> $LOG_FILE

#-------------------------スイッチングエリア開始-----------------------------------------------
set -e
# DICOMからNIfTIに変換
timespent s1_first.sh

# デノイズ、Gibbsリング補正、topup、eddy、バイアスフィールド補正、マスク作成
#timespent s2_all_preprocessing.sh
timespent NIMH.sh

# TBSS用のファイル準備
timespent s3_dtifit.sh

# bedpostx_gpu
timespent s4_bedpostx.sh

# 変換マップの作成
timespent s5_makingwarps.sh

# オリジナルROIファイルの作成
#timespent s_ROImaking.sh

# xtract_gpu
timespent s6_xtract.sh
#timespent xtract_baby_gpu.sh

# xstat
timespent s7_xstat.sh

#-----------------------------スイッチングエリア終了---------------------------------------------

# 終了時刻の記録
allfinishsec=$(date +%s)
echo "Processing of $ImageID finished at $(date)"  | tee -a $LOG_FILE
echo "XTRAXTパイプラインが完了しました。トラクトグラフィーを確認するには、${ImagePath}内で以下を実行してください。"
echo "xview"
echo "これはxtract_viewerのラップコマンドで、必要なファイルを自動的に探して表示してくれます。"
echo "統計情報(xstat実行結果)は DWI/XTRACT_output/stats.csv にあります。"
totaltimespent() {
    spentsec=$((allfinishsec-allstartsec))

    # LinuxとmacOSの両方に対応（GNUとBSDの日付コマンド）
    spenttime=$(date --date @$spentsec "+%T" -u 2> /dev/null) # Linux用
    if [[ $? != 0 ]]; then
        spenttime=$(date -u -r $spentsec +"%T") # macOS用
    fi

    # 処理が1日を超える場合
    if [[ $spentsec -ge 86400 ]]; then
        days=$((spentsec/86400))
        echo "総処理時間は $days 日と $spenttime" | tee -a $LOG_FILE
    else 
        echo "総処理時間は $spenttime" | tee -a $LOG_FILE
    fi
    echo " " >> $LOG_FILE
}
totaltimespent
