$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$framework = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319"
$out = Join-Path $root "LenSwitcher.exe"

& $csc /nologo /target:winexe /optimize+ `
    /out:"$out" `
    /reference:"$framework\System.Windows.Forms.dll" `
    /reference:"$framework\System.Drawing.dll" `
    /reference:"$framework\System.IO.Compression.dll" `
    /reference:"$framework\System.IO.Compression.FileSystem.dll" `
    /resource:"$root\len-switcher.ahk,len-switcher.ahk" `
    "$root\launcher\LenSwitcher.cs"

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Write-Host "Built $out"
