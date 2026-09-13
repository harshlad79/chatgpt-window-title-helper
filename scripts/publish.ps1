$ErrorActionPreference = 'Stop'
$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
if ($dotnet) { $dotnetPath = $dotnet.Source }
else { $dotnetPath = 'C:\Program Files\dotnet\dotnet.exe' }
$project = Join-Path $PSScriptRoot '..\src\ChatGPTWindowTitleHelper\ChatGPTWindowTitleHelper.csproj'
$output = Join-Path $PSScriptRoot '..\artifacts\publish\win-x64'
& $dotnetPath publish $project -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:PublishTrimmed=false -o $output
Write-Output (Join-Path $output 'ChatGPTWindowTitleHelper.exe')
