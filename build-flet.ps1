# Compatibility entry point. The Flet interface is now controlled entirely by V.
param([switch]$SkipDependencies)

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'build-native.ps1') -SkipDependencies:$SkipDependencies
