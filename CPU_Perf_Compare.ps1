# 💡 Set via environment variables or hard-code below:
#   $env:GEEKBENCH_EMAIL   = "you@example.com"
#   $env:GEEKBENCH_LICENSE = "XXXX-XXXX-XXXX-XXXX"
$LicenseEmail = "mattias.lundgren"
$LicenseKey   = ""


<#
.SYNOPSIS
    Runs Geekbench 6 and 7-Zip CPU benchmarks, logs results for comparison.
.DESCRIPTION
    Uses Geekbench 6 Pro license (--unlock) and --no-upload for fully offline runs.
#>

# ==============================
# SETTINGS
# ==============================
$LogFile      = "C:\CPU_Benchmarks.csv"
$WorkDir      = "$env:TEMP\CPU_Benchmark"
$GeekbenchUrl = "https://cdn.geekbench.com/Geekbench-6.3.0-Windows.zip"
$SevenZipUrl  = "https://www.7-zip.org/a/7z2408-x64.exe"

# 💡 Supply via environment variables or edit here
#   $env:GEEKBENCH_EMAIL   = "you@example.com"
#   $env:GEEKBENCH_LICENSE = "XXXX-XXXX-XXXX-XXXX"
$LicenseEmail = $env:GEEKBENCH_EMAIL
$LicenseKey   = $env:GEEKBENCH_LICENSE
if (-not $LicenseEmail) { $LicenseEmail = "YOUR-EMAIL-HERE" }
if (-not $LicenseKey)   { $LicenseKey   = "YOUR-LICENSE-KEY-HERE" }

# ==============================
function Ensure-Directory { param ($Path)
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
# Download 7-Zip
# ==============================
if (!(Test-Path "$WorkDir\7z.exe")) {
    Write-Host "Downloading 7-Zip..." -ForegroundColor Cyan
    $exe = "$WorkDir\7zsetup.exe"
    Invoke-WebRequest -Uri $SevenZipUrl -OutFile $exe -UseBasicParsing
    Start-Process -FilePath $exe -ArgumentList "/S /D=$WorkDir" -Wait
}

# ==============================
# Run Geekbench 6 (unlock + no-upload)
# ==============================
Write-Host "`n=== Running Geekbench 6 (offline) ===" -ForegroundColor Yellow
$GeekLog = "$WorkDir\geekbench_output.txt"

# Detect binary
$GeekExe = if (Test-Path "$WorkDir\Geekbench\geekbench6.exe") {
    "$WorkDir\Geekbench\geekbench6.exe"
} elseif (Test-Path "$WorkDir\Geekbench\geekbench6_x64.exe") {
    "$WorkDir\Geekbench\geekbench6_x64.exe"
} elseif (Test-Path "$WorkDir\Geekbench\geekbench6_x86.exe") {
    "$WorkDir\Geekbench\geekbench6_x86.exe"
} else { throw "Geekbench executable not found." }

# --- Unlock license ---
Write-Host "Unlocking Geekbench license for $LicenseEmail..." -ForegroundColor Cyan
& $GeekExe --unlock $LicenseEmail $LicenseKey | Out-Null

# --- Run CPU benchmark fully offline ---
$startTime = Get-Date
Write-Host "Executing: $GeekExe --cpu --no-upload"
& $GeekExe --cpu --no-upload | Tee-Object -FilePath $GeekLog
$endTime = Get-Date
$duration = [math]::Round(($endTime - $startTime).TotalSeconds,2)

# --- Parse Geekbench output ---
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
$Date   = Get-Date -Format "yyyy-MM-dd HH:mm"
$CPU    = (Get-CimInstance Win32_Processor | Select-Object -First 1 -ExpandProperty Name)
$Cores  = (Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum

# ==============================
# Write to CSV
# ==============================
if (!(Test-Path $LogFile)) {
    "Server,Date,CPU,Cores,Geekbench_Single,Geekbench_Multi,7Zip_MIPS,Duration_s" | Out-File $LogFile -Encoding UTF8
}
"$Server,$Date,$CPU,$Cores,$Single,$Multi,$Mips,$duration" | Out-File $LogFile -Append -Encoding UTF8

Write-Host "`n✅ Benchmark complete for $Server" -ForegroundColor Green
Write-Host "Geekbench Single-Core: $Single"
Write-Host "Geekbench Multi-Core:  $Multi"
Write-Host "7-Zip Total MIPS:      $Mips"
Write-Host "Duration: $duration s"
Write-Host "Results saved to $LogFile" -ForegroundColor Cyan
