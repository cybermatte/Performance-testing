# 💡 Set via environment variables or hard-code below:
#   $env:GEEKBENCH_EMAIL   = "you@example.com"
#   $env:GEEKBENCH_LICENSE = "XXXX-XXXX-XXXX-XXXX"
$LicenseEmail = ""
$LicenseKey   = ""

<#
.SYNOPSIS
    Comprehensive CPU benchmark & stress suite for Windows.
.DESCRIPTION
    Runs Geekbench, 7-Zip, Cinebench R23, Prime95, and Intel LINPACK (oneMKL).
    Uses local archives from C:\Temp.
    Logs results to C:\CPU_Benchmarks.csv
#>

# ==============================
# SETTINGS
# ==============================
$LogFile      = "C:\CPU_Benchmarks.csv"
$WorkDir      = "$env:TEMP\CPU_Benchmark"
$GeekbenchUrl = "https://cdn.geekbench.com/Geekbench-6.3.0-Windows.zip"
$SevenZipUrl  = "https://www.7-zip.org/a/7z2408-x64.exe"
$Prime95Url   = "https://www.mersenne.org/ftp_root/gimps/p95v308b17.win64.zip"

# Local archives (manual)
$CineZipLocal    = "C:\Temp\CinebenchR23.zip"
$LinpackZipLocal = "C:\Temp\w_onemklbench_p_2025.2.0_531.zip"

function Ensure-Directory { param ($Path)
    if (!(Test-Path $Path)) { New-Item -ItemType Directory -Force -Path $Path | Out-Null }
}
Ensure-Directory $WorkDir
Set-Location $WorkDir

# ==============================
# Download tools (if missing)
# ==============================
if (!(Test-Path "$WorkDir\Geekbench\geekbench6.exe")) {
    Write-Host "Downloading Geekbench..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $GeekbenchUrl -OutFile "$WorkDir\geekbench.zip"
    Expand-Archive "$WorkDir\geekbench.zip" -DestinationPath "$WorkDir\Geekbench" -Force
}

if (!(Test-Path "$WorkDir\7z.exe")) {
    Write-Host "Downloading 7-Zip..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $SevenZipUrl -OutFile "$WorkDir\7zsetup.exe"
    Start-Process -FilePath "$WorkDir\7zsetup.exe" -ArgumentList "/S /D=$WorkDir" -Wait
}

if (!(Test-Path "$WorkDir\prime95\prime95.exe")) {
    Write-Host "Downloading Prime95..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $Prime95Url -OutFile "$WorkDir\prime95.zip"
    Expand-Archive "$WorkDir\prime95.zip" -DestinationPath "$WorkDir\prime95" -Force
}

# ==============================
# Cinebench (from local ZIP)
# ==============================
Write-Host "`n=== Preparing Cinebench R23 ===" -ForegroundColor Yellow
$CineDest = "$WorkDir\Cinebench"
$CB_Single = "N/A"
$CB_Multi  = "N/A"

if (Test-Path $CineZipLocal) {
    Write-Host "Found local Cinebench archive: $CineZipLocal" -ForegroundColor Green
    Ensure-Directory $CineDest
    if (!(Get-ChildItem $CineDest -Recurse -Filter "Cinebench.exe" -ErrorAction SilentlyContinue)) {
        Write-Host "Extracting CinebenchR23.zip to $CineDest..." -ForegroundColor Cyan
        Expand-Archive -Path $CineZipLocal -DestinationPath $CineDest -Force
    }

    $CineExe = (Get-ChildItem "$CineDest" -Filter "Cinebench.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).FullName
    $CineLog = "$WorkDir\cinebench_output.txt"

    if ($CineExe -and (Test-Path $CineExe)) {
        Write-Host "Found Cinebench at: $CineExe" -ForegroundColor Green
        Start-Process -FilePath $CineExe -ArgumentList "-cb_cpux -single -nogui" -Wait -RedirectStandardOutput $CineLog
        $CineOutput = Get-Content $CineLog -Raw
        $CB_Single = [regex]::Match($CineOutput, "CPU \(Single Core\)\s*:\s*(\d+)", 'IgnoreCase').Groups[1].Value
        $CB_Multi  = [regex]::Match($CineOutput, "CPU \(Multi Core\)\s*:\s*(\d+)", 'IgnoreCase').Groups[1].Value
        if (-not $CB_Single) { $CB_Single = "N/A" }
        if (-not $CB_Multi)  { $CB_Multi  = "N/A" }
    } else {
        Write-Warning "Cinebench.exe not found after extraction — skipping Cinebench test."
    }
} else {
    Write-Warning "Local CinebenchR23.zip not found in C:\Temp — skipping Cinebench test."
}

# ==============================
# LINPACK (Intel oneMKL)
# ==============================
Write-Host "`n=== Preparing Intel LINPACK (oneMKL) ===" -ForegroundColor Yellow
$LinpackRoot = "$WorkDir\linpack"
$Lin_GFLOPS  = "N/A"

if (Test-Path $LinpackZipLocal) {
    Write-Host "Found local Intel oneMKL archive: $LinpackZipLocal" -ForegroundColor Green
    Ensure-Directory $LinpackRoot

    if (-not (Get-ChildItem $LinpackRoot -Recurse -Filter "linpack_xeon64.exe" -ErrorAction SilentlyContinue)) {
        Write-Host "Extracting Intel oneMKL ZIP to $LinpackRoot..." -ForegroundColor Cyan
        Expand-Archive -Path $LinpackZipLocal -DestinationPath $LinpackRoot -Force
    }

    $LinExe = Get-ChildItem $LinpackRoot -Recurse -ErrorAction SilentlyContinue `
        -Include "linpack_xeon64.exe","xlinpack_xeon64.exe" | Select-Object -First 1

    if ($LinExe) {
        $LinDir = Split-Path $LinExe.FullName -Parent
        $LinOut = "$WorkDir\linpack_output.txt"
        Write-Host "Found LINPACK at: $($LinExe.FullName)" -ForegroundColor Green

        Push-Location $LinDir
        Start-Process -FilePath $LinExe.FullName -Wait -RedirectStandardOutput $LinOut
        Pop-Location

        if (Test-Path $LinOut) {
            $LinOutput = Get-Content $LinOut -Raw
            $Lin_GFLOPS = ([regex]::Match($LinOutput, "GFLOPS\s*=\s*([\d\.]+)", 'IgnoreCase').Groups[1].Value)
            if (-not $Lin_GFLOPS) {
                $Lin_GFLOPS = ([regex]::Match($LinOutput, "Performance:\s*([\d\.]+)\s*GFLOPS", 'IgnoreCase').Groups[1].Value)
            }
            if (-not $Lin_GFLOPS) { $Lin_GFLOPS = "N/A" }
        } else {
            Write-Warning "LINPACK did not produce output — check permissions or binary compatibility."
        }
    } else {
        Write-Warning "LINPACK executable not found after extraction — skipping test."
    }
} else {
    Write-Warning "Local Intel LINPACK ZIP not found in C:\Temp — skipping LINPACK test."
}

# ==============================
# Geekbench 6
# ==============================
Write-Host "`n=== Running Geekbench 6 (offline) ===" -ForegroundColor Yellow
$GeekExe = (Get-ChildItem "$WorkDir\Geekbench" -Filter "geekbench6*.exe" -Recurse | Select-Object -First 1).FullName
$GeekLog = "$WorkDir\geekbench_output.txt"
$GB_Single = "N/A"; $GB_Multi = "N/A"; $GB_Duration = 0

if ($GeekExe) {
    Write-Host "Unlocking Geekbench license..." -ForegroundColor Cyan
    & $GeekExe --unlock $env:GEEKBENCH_EMAIL $env:GEEKBENCH_LICENSE | Out-Null
    $startTime = Get-Date
    & $GeekExe --cpu --no-upload | Tee-Object -FilePath $GeekLog
    $endTime = Get-Date
    $GB_Duration = [math]::Round(($endTime - $startTime).TotalSeconds,2)
    $GeekOutput = Get-Content $GeekLog -Raw
    $GB_Single = [regex]::Match($GeekOutput, "Single[-\s]?Core\s+Score[:\s]+(\d+)", 'IgnoreCase').Groups[1].Value
    $GB_Multi  = [regex]::Match($GeekOutput, "Multi[-\s]?Core\s+Score[:\s]+(\d+)",  'IgnoreCase').Groups[1].Value
} else {
    Write-Warning "Geekbench executable not found — skipping."
}

# ==============================
# 7-Zip
# ==============================
Write-Host "`n=== Running 7-Zip benchmark ===" -ForegroundColor Yellow
$Z_MIPS = "N/A"
if (Test-Path "$WorkDir\7z.exe") {
    $SevenLog = "$WorkDir\7zip_output.txt"
    & "$WorkDir\7z.exe" b | Tee-Object -FilePath $SevenLog | Out-Null
    $SevenOutput = Get-Content $SevenLog -Raw
    $Z_MIPS = [regex]::Match($SevenOutput, "Tot:\s+(\d+)", 'IgnoreCase').Groups[1].Value
} else {
    Write-Warning "7-Zip not found — skipping benchmark."
}

# ==============================
# Prime95 (short stress)
# ==============================
Write-Host "`n=== Running Prime95 (short stress test, 60 s) ===" -ForegroundColor Yellow
if (Test-Path "$WorkDir\prime95\prime95.exe") {
    Start-Process -FilePath "$WorkDir\prime95\prime95.exe" -ArgumentList "-t" -WindowStyle Hidden
    Start-Sleep -Seconds 60
    Get-Process prime95 -ErrorAction SilentlyContinue | Stop-Process -Force
} else {
    Write-Warning "Prime95 not found — skipping stress test."
}

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

# ==============================
# Summary
# ==============================
Write-Host "`n✅ Benchmark suite complete for $Server" -ForegroundColor Green
Write-Host ""
Write-Host ("{0,-20}{1,10}" -f "Geekbench 6 Single:", $GB_Single)
Write-Host ("{0,-20}{1,10}" -f "Geekbench 6 Multi:", $GB_Multi)
Write-Host ("{0,-20}{1,10}" -f "7-Zip MIPS:", $Z_MIPS)
Write-Host ("{0,-20}{1,10}" -f "Cinebench Single:", $CB_Single)
Write-Host ("{0,-20}{1,10}" -f "Cinebench Multi:", $CB_Multi)
Write-Host ("{0,-20}{1,10}" -f "LINPACK GFLOPS:", $Lin_GFLOPS)
Write-Host ("{0,-20}{1,10}" -f "Duration (s):", $GB_Duration)
Write-Host "`nResults saved to $LogFile" -ForegroundColor Cyan

# Display short summary table (if multiple servers tested)
if (Test-Path $LogFile) {
    Write-Host "`n=== Summary of all recorded results ===" -ForegroundColor Yellow
    Import-Csv $LogFile | Sort-Object -Property Geek_Multi -Descending | Format-Table Server, Geek_Multi, Cine_Multi, LINPACK_GFLOPS, CPU -AutoSize
}

