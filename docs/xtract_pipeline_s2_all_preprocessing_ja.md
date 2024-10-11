## **xtract\_pipeline s2\_all\_preprocessing.shの解説**

スクリプトの実質的な内容をstep by stepで記載しました。
スクリプト全体を実行するのではなく、コピー＆ペーストで一つずつ確認しながら実行したい場合はこちらが参考になるかもしれません。
＊一応チェックしていますが、コピペがうまく行かない場合は全角スペースが入っていないか、引用符が正しいか（"や'のみ使用可能）ご確認ください。

### **Part 1: Image Pathの設定**

この部分では、`ImagePath`が設定されていない場合、現在のディレクトリを`ImagePath`として使用します。
```
# ImagePathが設定されていない場合、現在のディレクトリを使用する
ImagePath=$PWD
```
---

### **Part 2: 必要なファイルの確認**

ここでは、T1-weighted（T1）および拡散強調画像（DWI）のファイルが正しく存在するかを確認し、どちらかが見つからない場合は処理を終了します。
```
# 必要なファイルの存在を確認
ls $ImagePath/nifti_data/anat/T1.nii* | wc -l
ls $ImagePath/nifti_data/dwi/DWI*nii* | wc -l
```
T1が1個、DWIが1個もしくは2個ならOK.それ以外ならファイルを確認する。実際に解析に使用されるのは、「ファイル名に数字が入っていないもの」になります。

---

### **Part 3: システム情報の確認**

この部分では、システムがLinuxかmacOSかを確認し、使用できるコア数（CPUのスレッド数）やメモリ容量を取得します。
```
# システムがLinuxまたはmacOSかを確認  
uname # DarwinならMac、LinuxならLinux  
# コア数とメモリ情報を取得  
# Linuxの場合  
nproc　# Linuxのコア数  
cat /proc/meminfo | grep MemTotal | awk '{ printf("%d\n",$2/1024/1024) }' # Linuxのメモリ数  
# Macの場合  
sysctl -n hw.ncpu # Macのコア数  
sysctl -n hw.memsize | awk '{ print $1/1024/1024/1024 }　# Macのメモリ数
```
---

### **Part 4: 最大実行ジョブ数の設定**

ここでは、システムリソースに基づいて最大並列実行ジョブ数を設定します。

よほどメモリが少なくない限りはコア数−１くらいでOKです。他のジョブを並行して行う場合などは適宜調整してください。メモリが4GB以下の場合、実行には時間がかかりますがコア数に関わらず1コアの方が安全です。

仮想環境での設定

Lin4Neuro（VirtualBox上やDocker上）の場合、CPU割り当てはVirtualBoxの設定→システム画面やdocker advanced settingsで確認、変更できます。これが4なら最大実行ジョブ数は3にします。
```
maxrunning=3
```
---

### **Part 5: 前処理用データの準備**

この部分では、元のディレクトリから作業ディレクトリにファイルをコピーし、T1ファイルが必要に応じて圧縮されます。
```
# DWIデータ用のディレクトリを作成し、ファイルをコピー  
cd $ImagePath  
mkdir DWI  
cp nifti_data/dwi/* DWI/  
cp nifti_data/anat/* DWI/  
cd DWI
```
### **Part 6: 前処理用データの準備**
```
# T1ファイルが圧縮されていない場合は圧縮  
gzip T1.nii
```
---

### **Part 7: DWIファイルの解凍と前処理**

この部分では、DWIファイルが圧縮されている場合に解凍し、その後前処理を行います。
```
# DWIファイルを必要に応じて解凍  
gunzip DWI_AP.nii.gz  
gunzip DWI_PA.nii.gz
```
---

### **Part 8: 様々な前処理条件に応じたファイルの処理**

ここでは、DWIデータに異なるPE方向が含まれている場合、そのデータを前処理するための準備をします。
```
# DWIファイルのボリューム数を取得  
fslval DWI_AP.nii* dim4  
fslval DWI_PA.nii* dim4
```
---

### **Part 9: Get TotalReadoutTime**

ここでは、`TotalReadoutTime`（リードアウト時間）をJSONファイルから取得し、次の処理で使用します。DWIファイルに複数のフェーズエンコーディング（PE）方向がある場合に必要な情報です。
```
# JSONファイルからTotalReadoutTimeを取得  
cat DWI_AP.json | grep TotalReadoutTime | cut -d: -f2 | tr -d ','
```
---

## 逆のPE方向（AP、PAなど）のデータが存在するか、そのボリューム数はいくつかによって10-12のいずれかの処理を行います。

### **Part 10: Apply Preprocessing Without Topup (Single PE Direction)**

DWIデータが一方向のPE（フェーズエンコーディング）しかない場合、`topup`（位相エンコード方向の補正）なしで前処理を行います。

以下はAP方向のみ、`TotalReadoutTimeが0.04`の場合です。  
```
# DWIの一方向PEの前処理  
mrconvert DWI_AP.nii dwi.mif -fslgrad DWI_AP.bvec DWI_AP.bval -datatype float32  
dwidenoise dwi.mif dwi_den.mif  
mrdegibbs dwi_den.mif dwi_den_unr.mif -axes 0,1  
dwifslpreproc dwi_den_unr.mif dwi_den_unr_preproc.mif -pe_dir AP -rpe_none -eddy_options " --slm=linear --repol --cnr_maps" -readout_time 0.04
```

オプションの説明（Part11，12も同様です）  
-eddy_options、-topup_optionsは内部で使われているFSLのコマンドであるtopupやeddyにもともと存在するオプションを使うためのものです。下記以外にもFSLのユーザーガイドを見ると様々なオプションがあるので、必要に応じて引用符をつけて渡すことができます。注意：上記の見本のように、必ず最初の引用符のあとに半角スペースが必要です。

```
# -eddy_optionsの中身 
--slm=linear	# 軸数が少ない場合
--repol 		# 動きが一定（4SD）以上に大きいスライスを捨てて置換する
--cnr_maps		# QC用
# 中間データをチェックのために残したい場合はdwifslpreprocのオプションがあります。
-nocleanup		# 一時ディレクトリを削除しない（容量が大きいので注意）
```
---

### **Part 11: Create b0 Pair for Topup (Two PE Directions)**

DWIデータが2つのPE方向（APとPA）からなる場合、それらのb0画像ペアを作成し、`topup`を使用して補正を行います。topupは`-topup_options " --nthr=最大ジョブ数"`を使うと時間短縮できます。以下はAP方向がメインの撮像方向、最大ジョブ数が3、TotalReadoutTimeが0.04の場合です。(メインの撮像方向がPAの場合はAPとPAを入れ替えます)`

```
# AP方向のDWIの前処理 
mrconvert DWI_AP.nii dwi.mif -fslgrad DWI_AP.bvec DWI_AP.bval -datatype float32
dwidenoise dwi.mif dwi_den.mif
mrdegibbs dwi_den.mif dwi_den_unr.mif -axes 0,1

# AP方向の画像からb0ボリューム（mean_b0.mif）を抽出
dwiextract dwi_den_unr.mif - -bzero | mrmath - mean mean_b0.mif -axis 3

# PA方向のDWIの前処理 
mrconvert DWI_PA.nii temp01.mif -fslgrad DWI_PA.bvec DWI_PA.bval -datatype float32
dwidenoise temp01.mif temp02.mif
mrdegibbs temp02.mif temp03.mif -axes 0,1

# 前処理済みのPA方向のDWIからb0を抜き出して平均したmean_b0_RPE.mifを作成
dwiextract temp03.mif - -bzero | mrmath - mean mean_b0_RPE.mif -axis 3

# topup補正のためにb0ペアを作成
mrcat mean_b0.mif RPE_b0.mif -axis 3 b0_pair.mif

# dwifslpreproc
dwifslpreproc dwi_den_unr.mif dwi_den_unr_preproc.mif -pe_dir AP 　　-rpe_pair -se_epi b0_pair.mif -eddy_options " --slm=linear --repol --cnr_maps" -topup_options " --nthr=3" -readout_time 0.04
```
---

### **Part 12: Apply Preprocessing with Both PE Directions (Full Volume)**

2つのPE方向からフルボリュームのDWIデータが得られる場合、これらを結合して前処理を行います。以下のようにjsonファイルをヘッダーに読み込むことで、適切なtopupとeddyの処理が可能です。jsonファイルに十分な情報がない場合はPart11と同様にマニュアルでb0 pair画像を作成してください。
```
# DWIデータのフルボリュームの結合と前処理
mrconvert DWI_AP.nii DWI_AP.mif -fslgrad DWI_AP.bvec DWI_AP.bval -datatype float32
mrconvert DWI_PA.nii DWI_PA.mif -fslgrad DWI_PA.bvec DWI_PA.bval -datatype float32
mrcat DWI_AP.mif DWI_PA.mif DWI.mif
dwidenoise DWI.mif temp01.mif
mrdegibbs temp01.mif temp02.mif -axes 0,1
dwifslpreproc temp02.mif dwi_den_unr_preproc.mif -rpe_header -eddy_options " --slm=linear --repol --cnr_maps" -topup_options " --nthr=3" -readout_time 0.04
```
---

### **Part 13: Apply Bias Field Correction**

前処理が完了したら、`b1`バイアスフィールド補正を適用します。これは、磁場不均一性による信号強度のばらつきを補正するための処理です。
```
# b1フィールド補正の適用  
dwibiascorrect ants dwi_den_unr_preproc.mif dwi_den_unr_preproc_unbiased.mif
```
---

### **Part 14: Final NIfTI Conversion**

最後に、前処理が完了したデータをNIfTI形式に変換します。
```
# 最終的なNIfTI形式への変換  
mrconvert dwi_den_unr_preproc_unbiased.mif dwi_den_unr_preproc_unbiased.nii.gz -export_grad_fsl SR.bvec SR.bval
```
---

### **Part 15: 不要データの削除**

途中データを残しておきたくない場合は以下で削除できます。一旦削除すると復元不可能なのでよく確認してから行ってください。
```
# 不要ファイル削除  
rm temp*.mif
```