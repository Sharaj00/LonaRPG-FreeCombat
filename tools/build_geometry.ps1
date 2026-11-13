param([string]$Compiler='C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC\14.44.35207\bin\Hostx64\x86\cl.exe')
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$build=Join-Path $project 'output\native-geometry'
New-Item -ItemType Directory -Path $build -Force | Out-Null
$source=Join-Path $project 'src\RGSSPerformance\geometry.c'
& $Compiler /nologo /c /O2 /GS- /fp:strict "/Fo$build\geometry.obj" $source
if ($LASTEXITCODE -ne 0) { throw 'C compilation failed' }
$linker=Join-Path (Split-Path $Compiler -Parent) 'link.exe'
& $linker /nologo /DLL /NOENTRY /NODEFAULTLIB /MACHINE:X86 /DYNAMICBASE /NXCOMPAT "/OUT:$build\geometry-x86.dll" "/IMPLIB:$build\geometry.lib" '/EXPORT:lona_geometry=_lona_geometry@28' '/EXPORT:lona_geometry_abi=_lona_geometry_abi@0' "$build\geometry.obj"
if ($LASTEXITCODE -ne 0) { throw 'DLL linking failed' }
Get-FileHash -LiteralPath "$build\geometry-x86.dll"
