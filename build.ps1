[CmdletBinding(PositionalBinding=$false)]
param(
    [string] $Version,
    [string] $BuildNumber,
    [bool] $CreatePackages,
    [bool] $RunTests = $true,
    [string] $PullRequestNumber
)

if ($BuildNumber -and $BuildNumber.Length -lt 5) {
    $BuildNumber = $BuildNumber.PadLeft(5, "0")
}

function CalculateVersion() {
    if ($version) {
        return $version
    }

    $semVersion = '';
    $path = $pwd;
    while (!$semVersion) {
        if (Test-Path (Join-Path $path "semver.txt")) {
            $semVersion = Get-Content (Join-Path $path "semver.txt")
            break
        }
        if ($PSScriptRoot -eq $path) {
            break
        }
        $path = Split-Path $path -Parent
    }

    if (!$semVersion) {
        Write-Error "semver.txt was not found in $pwd or any parent directory"
        Exit 1
    }

    return "$semVersion-$BuildNumber"
}

Write-Host "Run Parameters:" -ForegroundColor Cyan
Write-Host "  Version: $Version"
Write-Host "  BuildNumber: $BuildNumber"
Write-Host "  CreatePackages: $CreatePackages"
Write-Host "  RunTests: $RunTests"
Write-Host "  Calculated Version (Global): $(CalculateVersion)"

$packageOutputFolder = "$PSScriptRoot\.nupkgs"
$projectsToBuild =
    'StackExchange.Exceptional.Shared',
    'StackExchange.Exceptional',
    'StackExchange.Exceptional.AspNetCore',
    'StackExchange.Exceptional.MySQL'

$testsToRun =
	'StackExchange.Exceptional.Tests',
	'StackExchange.Exceptional.Tests.AspNetCore'

if (!$Version -and !$BuildNumber) {
    Write-Host "ERROR: You must supply either a -Version or -BuildNumber argument. `
  Use -Version `"4.0.0`" for explicit version specification, or `
  Use -BuildNumber `"12345`" for generation using <semver.txt>-<buildnumber>" -ForegroundColor Yellow
    Exit 1
}

if ($PullRequestNumber) {
    Write-Host "Building for a pull request (#$PullRequestNumber), skipping packaging." -ForegroundColor Yellow
    $CreatePackages = $false
}

if ($RunTests) {   
    dotnet restore /ConsoleLoggerParameters:Verbosity=Quiet
    foreach ($project in $testsToRun) {
        Write-Host "Running tests: $project (all frameworks)" -ForegroundColor "Magenta"
        Push-Location ".\tests\$project"

        dotnet xunit
        if ($LastExitCode -ne 0) { 
            Write-Host "Error with tests, aborting build." -Foreground "Red"
            Pop-Location
            Exit 1
        }

        Write-Host "Tests passed!" -ForegroundColor "Green"
	    Pop-Location
    }
}

if ($CreatePackages) {
    mkdir -Force $packageOutputFolder | Out-Null
    Write-Host "Clearing existing $packageOutputFolder..." -NoNewline
    Get-ChildItem $packageOutputFolder | Remove-Item
    Write-Host "done." -ForegroundColor "Green"

    Write-Host "Building all packages" -ForegroundColor "Green"
}

foreach ($project in $projectsToBuild) {
    Write-Host "Working on $project`:" -ForegroundColor "Magenta"
	
	Push-Location ".\src\$project"

    $semVer = CalculateVersion

    Write-Host "  Restoring and packing $project... (Version:" -NoNewline -ForegroundColor "Magenta"
    Write-Host $semVer -NoNewline -ForegroundColor "Cyan"
    Write-Host ")" -ForegroundColor "Magenta"
    
    $targets = "Restore"
    if ($CreatePackages) {
        $targets += ";Pack"
    }

	dotnet msbuild "/t:$targets" "/p:Configuration=Release" "/p:Version=$semVer" "/p:PackageOutputPath=$packageOutputFolder" "/p:CI=true"

	Pop-Location

    Write-Host "Done."
    Write-Host ""
}