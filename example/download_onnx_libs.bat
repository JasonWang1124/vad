@echo off
echo 下載ONNX Runtime庫文件
echo =======================

set DOWNLOAD_URL=https://github.com/ZXB6/OnnxRuntime-Android-JNI-aar-.so/releases/download/onnxruntime-mobile-android-1.17.3/onnxruntime-mobile-android-1.17.3.zip
set TEMP_ZIP=temp_download\onnxruntime.zip
set EXTRACT_DIR=temp_download\extract

echo 創建臨時目錄...
if not exist temp_download mkdir temp_download
if not exist %EXTRACT_DIR% mkdir %EXTRACT_DIR%

echo 下載ONNX Runtime文件...
curl -L %DOWNLOAD_URL% -o %TEMP_ZIP%

echo 解壓文件...
powershell -command "Expand-Archive -Path '%TEMP_ZIP%' -DestinationPath '%EXTRACT_DIR%' -Force"

echo 確保目標目錄存在...
if not exist example\android\app\src\main\jniLibs\arm64-v8a mkdir example\android\app\src\main\jniLibs\arm64-v8a
if not exist example\android\app\src\main\jniLibs\armeabi-v7a mkdir example\android\app\src\main\jniLibs\armeabi-v7a
if not exist example\android\app\src\main\jniLibs\x86 mkdir example\android\app\src\main\jniLibs\x86
if not exist example\android\app\src\main\jniLibs\x86_64 mkdir example\android\app\src\main\jniLibs\x86_64

echo 複製.so文件到正確的位置...
powershell -command "Copy-Item -Path '%EXTRACT_DIR%\jni\arm64-v8a\libonnxruntime.so' -Destination 'example\android\app\src\main\jniLibs\arm64-v8a\' -Force"
powershell -command "Copy-Item -Path '%EXTRACT_DIR%\jni\armeabi-v7a\libonnxruntime.so' -Destination 'example\android\app\src\main\jniLibs\armeabi-v7a\' -Force" 
powershell -command "Copy-Item -Path '%EXTRACT_DIR%\jni\x86\libonnxruntime.so' -Destination 'example\android\app\src\main\jniLibs\x86\' -Force"
powershell -command "Copy-Item -Path '%EXTRACT_DIR%\jni\x86_64\libonnxruntime.so' -Destination 'example\android\app\src\main\jniLibs\x86_64\' -Force"

echo 清理臨時文件...
powershell -command "Remove-Item -Path '%TEMP_ZIP%' -Force"
powershell -command "Remove-Item -Path '%EXTRACT_DIR%' -Recurse -Force"

echo 完成！ONNX Runtime庫文件已安裝到正確位置。 