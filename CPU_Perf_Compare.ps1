<#
.SYNOPSIS
    Runs CPU benchmarks (Geekbench + 7-Zip) and logs results for comparison.
.DESCRIPTION
    Offline-compatible version using Geekbench Pro license key via $LicenseKey variable.
#>

# ==============================
# SETTINGS
# ==============================
$LogFile = "C:\CPU_Benchmarks.csv"
$WorkDir = "$env:TEMP\CPU_Benchmark"
$GeekbenchUrl = "https://cdn.geekbench.com/Geekbench-6.3.0-Windows.zip"
$SevenZipUrl = "https://www.7-zip.org/a/7z2408-x64.exe"

# 💡 Insert your license key here or inject via environment variable
# Example: $env:GEEKBENCH_LICENSE = "XXXX-XXXX-XXXX-XXXX"
$LicenseKey = ""
if (-not $LicenseKey) {
    $LicenseKey = "YOUR-LICENSE-KEY-HERE"
}
# ==============================

function Ensure-Directory {
    param ($Path)
    if (!(Test-Path $Path)) { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
}

Ensure-Directory $WorkDir
Set-Location $WorkDir

# ==============================
# Download Geekbench
# ==============================
if (!(Test-Path "$WorkDir\Geekbench\geekbench6.exe")) {
    Write-Host "Downloading Geekbench..." -ForegroundColor Cyan
    $zip = "$WorkDir\geekbench.zip"
    Invoke-WebRequest -Uri $GeekbenchUrl -OutFile $zip -UseBasicParsing
    Expand-Archive $zip -DestinationPath "$WorkDir\Geekbench" -Force
}

# ==============================
# Apply license (offline mode)
# ==============================
if ($LicenseKey -and !(Test-Path "$WorkDir\Geekbench\geekbench.license")) {
    Write-Host "Applying Geekbench license..." -ForegroundColor Cyan
    Set-Content -Path "$WorkDir\Geekbench\geekbench.license" -Value $LicenseKey -Encoding ASCII
}

# ==============================
# Download 7-Zip
# ==============================
if (!(Test-Path "$WorkDir\7z.exe")) {
    Write-Host "Downloading 7-Zip..." -ForegroundColor Cyan
    $exe = "$WorkDir\7zsetup.exe"
    Invoke-WebRequest -Uri $SevenZipUrl -OutFile $exe -UseBasicParsing
    Start-Process -FilePath $exe -ArgumentList "/S /D=$WorkDir" -Wait
}

# ==============================
# Run Geekbench (offline)
# ==============================
Write-Host "`n=== Running Geekbench 6 (offline mode) ===" -ForegroundColor Yellow
$GeekLog = "$WorkDir\geekbench_output.txt"

# Detect binary
$GeekExe = if (Test-Path "$WorkDir\Geekbench\geekbench6.exe") {
    "$WorkDir\Geekbench\geekbench6.exe"
} elseif (Test-Path "$WorkDir\Geekbench\geekbench6_x64.exe") {
    "$WorkDir\Geekbench\geekbench6_x64.exe"
} elseif (Test-Path "$WorkDir\Geekbench\geekbench6_x86.exe") {
    "$WorkDir\Geekbench\geekbench6_x86.exe"
} else {
    throw "Geekbench executable not found."
}

$startTime = Get-Date
Write-Host "Executing: $GeekExe --upload 0"
& $GeekExe --upload 0 | Tee-Object -FilePath $GeekLog
$endTime = Get-Date
$duration = [math]::Round(($endTime - $startTime).TotalSeconds,2)

# Parse Geekbench output
$GeekOutput = Get-Content $GeekLog -Raw
$Single = [regex]::Match($GeekOutput, "Single-Core Score:\s+(\d+)").Groups[1].Value
$Multi  = [regex]::Match($GeekOutput, "Multi-Core Score:\s+(\d+)").Groups[1].Value
if (-not $Single) { $Single = "N/A" }
if (-not $Multi)  { $Multi  = "N/A" }

# ==============================
# Run 7-Zip benchmark
# ==============================
Write-Host "`n=== Running 7-Zip benchmark ===" -ForegroundColor Yellow
$SevenLog = "$WorkDir\7zip_output.txt"
& "$WorkDir\7z.exe" b | Tee-Object -FilePath $SevenLog | Out-Null

$SevenOutput = Get-Content $SevenLog -Raw
$Mips = [regex]::Match($SevenOutput, "Tot:\s+(\d+)").Groups[1].Value
if (-not $Mips) { $Mips = "N/A" }

# ==============================
# Collect system info
# ==============================
$Server = $env:COMPUTERNAME
$Date = Get-Date -Format "yyyy-MM-dd HH:mm"
$Cores = (Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum

# ==============================
# Write to CSV
# ==============================
if (!(Test-Path $LogFile)) {
    "Server,Date,Cores,Geekbench_Single,Geekbench_Multi,7Zip_MIPS,Duration_s" | Out-File $LogFile -Encoding UTF8
}
"$Server,$Date,$Cores,$Single,$Multi,$Mips,$duration" | Out-File $LogFile -Append -Encoding UTF8

Write-Host "`n✅ Benchmark complete for $Server" -ForegroundColor Green
Write-Host "Geekbench Single-Core: $Single"
Write-Host "Geekbench Multi-Core:  $Multi"
Write-Host "7-Zip Total MIPS:      $Mips"
Write-Host "Duration: $duration s"
Write-Host "Results saved to $LogFile" -ForegroundColor Cyan
