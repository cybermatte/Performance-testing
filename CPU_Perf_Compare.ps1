# 💡 Set via environment variables or hard-code below:
#   $env:GEEKBENCH_EMAIL   = "you@example.com"
#   $env:GEEKBENCH_LICENSE = "XXXX-XXXX-XXXX-XXXX"
$LicenseEmail = ""
$LicenseKey   = ""

<#
.SYNOPSIS
    Comprehensive CPU benchmark & stress suite for Windows.
.DESCRIPTION
    Runs Geekbench, 7-Zip, Cinebench R23, Prime95, and optionally LINPACK.
    Logs results to C:\CPU_Benchmarks.csv
#>

# ==============================
# SETTINGS
# ==============================
$LogFile      = "C:\CPU_Benchmarks.csv"
$WorkDir      = "$env:TEMP\CPU_Benchmark"
$GeekbenchUrl = "https://cdn.geekbench.com/Geekbench-6.3.0-Windows.zip"
$SevenZipUrl  = "https://www.7-zip.org/a/7z2408-x64.exe"
$CinebenchUrl = "https://download.maxon.net/cinebench/CinebenchR23.zip"
$Prime95Url   = "https://www.mersenne.org/ftp_root/gimps/p95v308b17.win64.zip"
$LinpackUrl   = "https://www.dropbox.com/s/iw1lpnzz3e5hsc4/linpack_xeon64.zip?dl=1" # example mirror

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
    Invoke-WebRequest -Uri $GeekbenchUrl -OutFile "$WorkDir\geekbench.zip"
    Expand-Archive "$WorkDir\geekbench.zip" -DestinationPath "$WorkDir\Geekbench" -Force
}

# ==============================
# Download 7-Zip
# ==============================
if (!(Test-Path "$WorkDir\7z.exe")) {
    Write-Host "Downloading 7-Zip..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $SevenZipUrl -OutFile "$WorkDir\7zsetup.exe"
    Start-Process -FilePath "$WorkDir\7zsetup.exe" -ArgumentList "/S /D=$WorkDir" -Wait
}

# ==============================
# Download Cinebench R23
# ==============================
if (!(Test-Path "$WorkDir\Cinebench\Cinebench.exe")) {
    Write-Host "Downloading Cinebench R23..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $CinebenchUrl -OutFile "$WorkDir\Cinebench.zip"
    Expand-Archive "$WorkDir\Cinebench.zip" -DestinationPath "$WorkDir\Cinebench" -Force
}

# ==============================
# Download Prime95
# ==============================
if (!(Test-Path "$WorkDir\prime95\prime95.exe")) {
    Write-Host "Downloading Prime95..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $Prime95Url -OutFile "$WorkDir\prime95.zip"
    Expand-Archive "$WorkDir\prime95.zip" -DestinationPath "$WorkDir\prime95" -Force
}

# ==============================
# Optional LINPACK
# ==============================
if (!(Test-Path "$WorkDir\linpack")) {
    Write-Host "Downloading LINPACK (optional)..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $LinpackUrl -OutFile "$WorkDir\linpack.zip"
    Expand-Archive "$WorkDir\linpack.zip" -DestinationPath "$WorkDir\linpack" -Force
}

# ==============================
# Run Geekbench 6
# ==============================
Write-Host "`n=== Running Geekbench 6 (offline) ===" -ForegroundColor Yellow
$GeekExe = (Get-ChildItem "$WorkDir\Geekbench" -Filter "geekbench6*.exe" | Select-Object -First 1).FullName
$GeekLog = "$WorkDir\geekbench_output.txt"

Write-Host "Unlocking license..."
& $GeekExe --unlock $env:GEEKBENCH_EMAIL $env:GEEKBENCH_LICENSE | Out-Null

$startTime = Get-Date
& $GeekExe --cpu --no-upload | Tee-Object -FilePath $GeekLog
$endTime = Get-Date
$GB_Duration = [math]::Round(($endTime - $startTime).TotalSeconds,2)

$GeekOutput = Get-Content $GeekLog -Raw
$GB_Single = [regex]::Match($GeekOutput, "Single[-\s]?Core\s+Score[:\s]+(\d+)", 'IgnoreCase').Groups[1].Value
$GB_Multi  = [regex]::Match($GeekOutput, "Multi[-\s]?Core\s+Score[:\s]+(\d+)",  'IgnoreCase').Groups[1].Value

# ==============================
# Run 7-Zip benchmark
# ==============================
Write-Host "`n=== Running 7-Zip benchmark ===" -ForegroundColor Yellow
$SevenLog = "$WorkDir\7zip_output.txt"
& "$WorkDir\7z.exe" b | Tee-Object -FilePath $SevenLog | Out-Null
$SevenOutput = Get-Content $SevenLog -Raw
$Z_MIPS = [regex]::Match($SevenOutput, "Tot:\s+(\d+)", 'IgnoreCase').Groups[1].Value

# ==============================
# Run Cinebench R23
# ==============================
Write-Host "`n=== Running Cinebench R23 ===" -ForegroundColor Yellow
$CineExe = "$WorkDir\Cinebench\Cinebench.exe"
$CineLog = "$WorkDir\cinebench_output.txt"
Start-Process -FilePath $CineExe -ArgumentList "-cb_cpux -single -nogui" -Wait -RedirectStandardOutput $CineLog
$CineOutput = Get-Content $CineLog -Raw
$CB_Single = [regex]::Match($CineOutput, "CPU \(Single Core\)\s*:\s*(\d+)", 'IgnoreCase').Groups[1].Value
$CB_Multi  = [regex]::Match($CineOutput, "CPU \(Multi Core\)\s*:\s*(\d+)", 'IgnoreCase').Groups[1].Value

# ==============================
# Run Prime95 stress (short)
# ==============================
Write-Host "`n=== Running Prime95 (short stress test, 60 s) ===" -ForegroundColor Yellow
Start-Process -FilePath "$WorkDir\prime95\prime95.exe" -ArgumentList "-t" -WindowStyle Hidden
Start-Sleep -Seconds 60
Get-Process prime95 -ErrorAction SilentlyContinue | Stop-Process -Force

# ==============================
# Optional LINPACK run (short)
# ==============================
Write-Host "`n=== Running LINPACK (short run) ===" -ForegroundColor Yellow
$LinpackExe = Get-ChildItem "$WorkDir\linpack" -Filter "*.exe" | Select-Object -First 1
if ($LinpackExe) {
    Start-Process -FilePath $LinpackExe.FullName -ArgumentList "" -Wait -RedirectStandardOutput "$WorkDir\linpack_output.txt"
    $LinOutput = Get-Content "$WorkDir\linpack_output.txt" -Raw
    $Lin_GFLOPS = [regex]::Match($LinOutput, "Performance:\s+([\d\.]+)\s+GFLOPS", 'IgnoreCase').Groups[1].Value
} else { $Lin_GFLOPS = "N/A" }

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
    "Server,Date,CPU,Cores,Geek_Single,Geek_Multi,7Zip_MIPS,Cine_Single,Cine_Multi,LINPACK_GFLOPS,Duration_s" |
        Out-File $LogFile -Encoding UTF8
}
"$Server,$Date,$CPU,$Cores,$GB_Single,$GB_Multi,$Z_MIPS,$CB_Single,$CB_Multi,$Lin_GFLOPS,$GB_Duration" |
    Out-File $LogFile -Append -Encoding UTF8

Write-Host "`n✅ Benchmark suite complete for $Server" -ForegroundColor Green
Write-Host "Geekbench 6 Single:   $GB_Single"
Write-Host "Geekbench 6 Multi:    $GB_Multi"
Write-Host "7-Zip MIPS:           $Z_MIPS"
Write-Host "Cinebench R23 Single: $CB_Single"
Write-Host "Cinebench R23 Multi:  $CB_Multi"
Write-Host "LINPACK GFLOPS:       $Lin_GFLOPS"
Write-Host "Results saved to $LogFile" -ForegroundColor Cyan
