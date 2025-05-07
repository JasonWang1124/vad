@echo off
echo 下載ONNX Runtime庫文件
echo =======================

set DOWNLOAD_URL=https://github.com/csukuangfj/onnxruntime-libs/releases/download/v1.14.0/onnxruntime-android-arm64-v8a-static_lib-1.14.0.zip
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

echo 建立自定義的libonnxruntime.so...
echo /* 創建庫檔案，要確保在Android平台加載時會提示正確的錯誤信息 */ > temp_download\custom_so.c
echo #include ^<jni.h^> >> temp_download\custom_so.c
echo #include ^<stdlib.h^> >> temp_download\custom_so.c
echo #include ^<string.h^> >> temp_download\custom_so.c
echo JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) { >> temp_download\custom_so.c
echo     return JNI_VERSION_1_6; >> temp_download\custom_so.c
echo } >> temp_download\custom_so.c

echo 需要手動下載並安裝libonnxruntime.so...
echo 請按照以下步驟操作：

echo 1. 訪問 https://github.com/csukuangfj/onnxruntime-libs/releases/download/v1.14.0/onnxruntime-android-arm64-v8a-1.14.0.zip
echo 2. 下載並解壓該文件
echo 3. 將lib目錄下的libonnxruntime.so複製到 example\android\app\src\main\jniLibs\arm64-v8a\ 目錄

echo.
echo 或者，您可以使用Android工作室(Android Studio)添加ONNX Runtime依賴：
echo.
echo 在Android項目的build.gradle中添加：
echo dependencies {
echo     implementation 'com.microsoft.onnxruntime:onnxruntime-android:^+'
echo }
echo.
echo 完成後請重新構建Android應用。 