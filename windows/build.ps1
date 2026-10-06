$ErrorActionPreference='Stop'
$base=$PSScriptRoot
$out=Join-Path $base 'package'
$fw=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319'
$refs=@('System.dll','System.Core.dll','System.Xaml.dll','System.Net.Http.dll','System.Security.dll','System.Web.Extensions.dll','System.Drawing.dll','System.Windows.Forms.dll','WPF/WindowsBase.dll','WPF/PresentationCore.dll','WPF/PresentationFramework.dll') | ForEach-Object { '/r:'+(Join-Path $fw $_) }
foreach ($dll in @('Microsoft.Web.WebView2.Core.dll','Microsoft.Web.WebView2.Wpf.dll')) {$refs+='/r:'+(Join-Path $base "deps/$dll");Copy-Item (Join-Path $base "deps/$dll") $out -Force}
Copy-Item (Join-Path $base 'deps/WebView2Loader.dll') $out -Force
Copy-Item (Join-Path $base 'deps/LICENSE.txt') (Join-Path $out 'LICENSE-WebView2.txt') -Force
$source=(Join-Path $base 'app\OpenFlux.cs')
& (Join-Path $fw 'csc.exe') /nologo /target:winexe /platform:x64 /optimize+ /utf8output "/win32manifest:$base\app\app.manifest" "/win32icon:$out\OpenFlux.ico" "/out:$out\OpenFlux.exe" $refs $source
if ($LASTEXITCODE -ne 0) {throw 'C# build failed'}
