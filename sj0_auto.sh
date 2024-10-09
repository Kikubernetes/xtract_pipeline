#!/bin/bash

# このスクリプトは、第8回から第11回のABISチュートリアルに基づいてKikuko Kanekoによって作成されました。
# 一部はDr. Nemotoが貢献しています。
# スクリプトの説明と使用方法については、以下の使用法を参照してください。
Version=20241005

###---------------------変数------------------###
NEW_FSL=""
#######################################################

usage() {
    cat << EOF
このスクリプトは、DICOMデータからXTRACTおよびXSTATまでの処理を行います。
可能な場合には、GPUとマルチコア処理を利用します。
処理の特定の部分のみを実行するには、スクリプト内の「Switching area」を変更してください。
DICOMファイル（DTIと3DT1）またはNIFTIファイルを、画像ID（例：sub001やImage001）で名前付けられたディレクトリに配置してください。
逆位相エンコード画像はあってもなくても構いません。
関連するすべてのスクリプトをPATHに含まれているディレクトリ（例：$HOME/bin）に保存し、実行権限を付与してください
（例：chmod 755 script_name）。
画像ディレクトリに移動し、スクリプトを実行します。（例：cd path_to_image_directory; s0_auto.sh）
出力は同じディレクトリに保存され、DICOMファイルは「org_data」というフォルダに整理されます。
注意1：このスクリプトはFSLバージョン6.0.6以降を前提としています。バージョン6.0.5以前を使用している場合は、
スクリプトの先頭にある変数をNEW_FSL="no"に設定してください。これにより、マルチスレッドを使用せずにtopupを実行します。
6.0.6以降を使用する場合は空のままにしてください。
注意：後続の処理（s2以降）が正しく動作するためには、s1でファイルの名前と構造が正しく整理されている必要があります。
まずs1を実行し、出力が意図したとおりか確認してください。
EOF
}

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
echo "DTIパイプラインが完了しました。トラクトグラフィーを確認するには、「xview」スクリプトを被験者ディレクトリにコピーし、\
ディレクトリを変更してxviewを実行してください。統計情報は DWI/XTRACT_output/stats.csv にあります。"
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
