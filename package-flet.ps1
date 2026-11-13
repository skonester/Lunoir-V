# Compatibility entry point for the native V portable package.
param([switch]$Zip, [switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'package-native.ps1') -Zip:$Zip -SkipBuild:$SkipBuild
