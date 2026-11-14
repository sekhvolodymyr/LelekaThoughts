param([string]$FlutterSdk='', [string]$AndroidSdk='', [string]$JavaHome='')
$ErrorActionPreference='Stop'
if($AndroidSdk){$AndroidSdk=(Resolve-Path -LiteralPath $AndroidSdk).Path;$env:ANDROID_HOME=$AndroidSdk;$env:ANDROID_SDK_ROOT=$AndroidSdk}
if($JavaHome){$JavaHome=(Resolve-Path -LiteralPath $JavaHome).Path;$env:JAVA_HOME=$JavaHome;$env:PATH="$JavaHome/bin;$env:PATH"}
$flutter=if($FlutterSdk){Join-Path (Resolve-Path -LiteralPath $FlutterSdk).Path 'bin/flutter.bat'}else{(Get-Command flutter -ErrorAction Stop).Source}
Push-Location (Split-Path $PSScriptRoot -Parent)
try{
 & $flutter pub get
 if($LASTEXITCODE -ne 0){throw 'Dependency resolution failed'}
 & $flutter analyze --no-fatal-infos
 if($LASTEXITCODE -ne 0){throw 'Dart analysis failed'}
 & $flutter test
 if($LASTEXITCODE -ne 0){throw 'Flutter tests failed'}
 & $flutter build apk --release
 if($LASTEXITCODE -ne 0){throw 'Android build failed'}
 Get-FileHash -LiteralPath 'build/app/outputs/flutter-apk/app-release.apk' -Algorithm SHA256
}finally{Pop-Location}
