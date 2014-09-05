properties {
  $pesterHome = ".\Packages\Pester.2.1.0\tools"
  $pester = "${pesterHome}\bin\pester.bat"
  $chocolateyHome = ".\Packages\chocolatey.0.9.8.27\tools\chocolateyInstall"
  $chocolatey = "${chocolateyHome}\chocolatey.ps1"
  $testOutput = ".\Test.xml"
  $outputDir = ".\Output"
  $outputPackageDir = "${outputDir}\Packages"
  $outputModuleManifestDir = "${outputDir}\ModuleManifests"
  $modulesDir = ".\Modules\SEEK - Modules"
  $dscResourcesRoot = Join-Path $env:ProgramFiles "WindowsPowerShell\Modules"
  $version = "1.0.0"
  $buildNumber = $null
}

task default -depends Clean, UnitTest, IntegrationTest

task Package -depends Clean {
  if ($buildNumber) {
    $version = "${version}.${buildNumber}"
  }
  if (-not (Test-Path $outputPackageDir)) {
    New-Item -ItemType directory -Path $outputPackageDir
  }
  Get-ChildItem *.nuspec -Recurse | Foreach-Object {
    Update-ModuleManifestVersion -Path $_.DirectoryName -Version $version -OutputDir $outputModuleManifestDir
    # chocolatey pack expects a package name argument only, quotes are necessary to inject the additional OutputDir argument
    exec { & $chocolatey pack """$($_.FullName)"" -OutputDir $(Resolve-Path $outputPackageDir) -Version $version" }
  }
}

task EnableDeveloperMode {
  Get-ChildItem $modulesDir -attributes Directory | Foreach-Object {
    $linkPath = "$dscResourcesRoot\$($_.Name)"
    $targePath = $_.FullName
    if (Test-Path $linkPath) {
      cmd /c rmdir $linkPath
    }
    cmd /c mklink /j $linkPath $targePath
  }
}

task DisableDeveloperMode {
  Get-ChildItem $modulesDir -attributes Directory | Foreach-Object {
    $linkPath = Resolve-Path "$dscResourcesRoot\$($_.Name)"
    if (Test-Path $linkPath) {
      cmd /c rmdir $linkPath
    }
  }
}

task Install -depends Package {
  exec { & $chocolatey install seek-dsc -source $(Resolve-Path $outputPackageDir) }
}

task Reinstall {
  exec { & $chocolatey install seek-dsc -source $(Resolve-Path $outputPackageDir) -force }
}

task Uninstall {
  $packageNames = Get-ChildItem *.nuspec -Recurse | Foreach-Object { $_.Basename }
  & $chocolatey uninstall @packageNames
}

task UnitTest {
  Invoke-Tests -Path .\Tests\Unit
}

task IntegrationTest {
  Invoke-Tests -Path .\Tests\Integration
}

task E2ETest -depends FlushCache {
  Invoke-Tests -Path .\Tests\E2E
}

task Test {
  Invoke-Tests -Path $testPath -TestName $testName
}

task FlushCache {
  Restart-Service winmgmt -force
}

task Clean {
  if (Test-Path $testOutput) {
    Remove-Item $testOutput
  }
  if (Test-Path $outputDir) {
    Remove-Item $outputDir -Recurse -Force
  }
}

function Invoke-Tests {
  param (
    [parameter(Mandatory = $true)]
    [string]$Path,

    [string]$TestName
  )

  if ($TestName) {
    exec { & $pester -Path $Path -TestName $TestName }
  }
  else {
    exec { & $pester -Path $Path }
  }
}

function Update-ModuleManifestVersion {
  param (
    [parameter(Mandatory = $true)]
    [string]$Path,

    [parameter(Mandatory = $true)]
    [string]$OutputDir,

    [parameter(Mandatory = $true)]
    [string]$Version
  )

  if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType directory -Path $OutputDir
  }

  Get-ChildItem -Path $Path -Filter *.psd1 | Foreach-Object {
    $updatedModuleManifestPath = "${OutputDir}\$($_.Name)"
    (Get-Content($_.FullName)) | ForEach-Object {$_ -replace "ModuleVersion\s+=\s+'[\d\.]+'", "ModuleVersion = '$Version'"} | Set-Content($updatedModuleManifestPath)
  }
}