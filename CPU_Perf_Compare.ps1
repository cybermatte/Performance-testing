# 💡 Set via environment variables or hard-code below:
#   $env:GEEKBENCH_EMAIL   = "you@example.com"
#   $env:GEEKBENCH_LICENSE = "XXXX-XXXX-XXXX-XXXX"
$LicenseEmail = ""
$LicenseKey   = ""

<# =====================================================================
   CPU Performance Benchmark Suite v8.6
   Author: ChatGPT (for Mattias)
   Notes:
   - Uses $WorkDir = "C:\TEMP"
   - Stores all downloads, logs, and results there
   - Auto-detects presence of benchmarks, downloads if missing
   - Cinebench now uses correct CLI arguments and parses "CB ####"
===================================================================== #>

$ErrorActionPreference = "Stop"
$WorkDir = "C:\TEMP"
$ResultFile = "$WorkDir\CPU_Benchmarks.csv"
$Timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$HostName = $env:COMPUTERNAME

# ---------------------------------------------------------------------
#  Helper function to download safely
# ---------------------------------------------------------------------
function Download-File($url, $target) {
    if (-not (Test-Path $target)) {
        Write-Host "Downloading $(Split-Path $target -Leaf)..."
        try {
            Invoke-WebRequest -Uri $url -OutFile $target -UseBasicParsing
        } catch {
            Write-Warning "Failed to download $url"
        }
    }
}

# ---------------------------------------------------------------------
#  1. Geekbench 6
# ---------------------------------------------------------------------
Write-Host "`n=== Geekbench 6 ===" -ForegroundColor Yellow
$GeekDir = "$WorkDir\Geekbench6"
$GeekExe = "$GeekDir\geekbench6.exe"
$GeekLog = "$GeekDir\geekbench6.txt"

if (-not (Test-Path $GeekExe)) {
    New-Item -ItemType Directory -Force -Path $GeekDir | Out-Null
    Download-File "https://cdn.geekbench.com/Geekbench-6.3.0-WindowsSetup.exe" "$GeekDir\GeekbenchSetup.exe"
}

$GB_Single = "N/A"; $GB_Multi = "N/A"
if (Test-Path $GeekExe) {
    Write-Host "Running Geekbench 6 CPU test..." -ForegroundColor Cyan
    cmd /c "`"$GeekExe`" --cpu --no-upload > `"$GeekLog`" 2>&1"
    $txt = Get-Content $GeekLog -Raw
    $GB_Single = [regex]::Match($txt, 'Single-Core Score\s+(\d+)', 'IgnoreCase').Groups[1].Value
    $GB_Multi  = [regex]::Match($txt, 'Multi-Core Score\s+(\d+)',  'IgnoreCase').Groups[1].Value
} else {
    Write-Warning "Geekbench not available — skipping."
}

# ---------------------------------------------------------------------
#  2. 7-Zip Benchmark
# ---------------------------------------------------------------------
Write-Host "`n=== 7-Zip Benchmark ===" -ForegroundColor Yellow
$SevenZipDir = "$WorkDir\7zip"
$SevenZipExe = "$SevenZipDir\7z.exe"
$SevenZipFile = "$SevenZipDir\7z.zip"
$SevenURL = "https://www.7-zip.org/a/7z2408-x64.zip"

if (-not (Test-Path $SevenZipExe)) {
    New-Item -ItemType Directory -Force -Path $SevenZipDir | Out-Null
    Download-File $SevenURL $SevenZipFile
    if (Test-Path $SevenZipFile) { Expand-Archive $SevenZipFile -DestinationPath $SevenZipDir -Force }
}

# --- 7-Zip Benchmark Parsing (modern v24.x and legacy compatible) ---
$Seven_MIPS = "N/A"
if (Test-Path $SevenZipExe) {
    Write-Host "Running 7-Zip internal benchmark (30s)..." -ForegroundColor Cyan
    $SevenLog = "$SevenZipDir\7zip_bench.txt"
    & $SevenZipExe b > $SevenLog

    if (Test-Path $SevenLog) {
        $txt = Get-Content $SevenLog -Raw
        # Modern 7-Zip (v23–v24) — pattern: "Tot:            1108   5983  65788"
        $match = [regex]::Match($txt, 'Tot:\s+\d+\s+\d+\s+(\d+)', 'IgnoreCase')
        if ($match.Success) {
            $Seven_MIPS = $match.Groups[1].Value
        } else {
            # Legacy 7-Zip (≤ v19) — pattern: "Tot:   1087  7156  MIPS"
            $match = [regex]::Match($txt, 'Tot:\s+\d+\s+(\d+)\s+MIPS', 'IgnoreCase')
            if ($match.Success) { $Seven_MIPS = $match.Groups[1].Value }
        }
    }
} else {
    Write-Warning "7-Zip not found — skipping test."
}

$Seven_MIPS


# ---------------------------------------------------------------------
#  3. Cinebench R23
# ---------------------------------------------------------------------
Write-Host "`n=== Cinebench R23 ===" -ForegroundColor Yellow
$CineRoot = "$WorkDir\CinebenchR23"
$CineExe  = "$CineRoot\Cinebench.exe"
$CB_Single = "N/A"; $CB_Multi = "N/A"

if (Test-Path $CineExe) {
    # --- Multi-core ---
    Write-Host "Running Cinebench R23 multi-core test..." -ForegroundColor Cyan
    $CineOutMulti = "$WorkDir\Cinebench_Multi.txt"
    Start-Process -FilePath $CineExe -ArgumentList @(
        "g_CinebenchCpuXTest=true",
        "g_CinebenchMinimumTestDuration=120",
        "g_CinebenchLogFile=true"
    ) -Wait -NoNewWindow
    if (Test-Path $CineOutMulti) {
        $txt = Get-Content $CineOutMulti -Raw
        $CB_Multi = [regex]::Match($txt, "CB\s+([0-9]+\.[0-9]+)", 'IgnoreCase').Groups[1].Value
    }

    # --- Single-core ---
    Write-Host "Running Cinebench R23 single-core test..." -ForegroundColor Cyan
    $CineOutSingle = "$WorkDir\Cinebench_Single.txt"
    Start-Process -FilePath $CineExe -ArgumentList @(
        "g_CinebenchCpu1Test=true",
        "g_CinebenchMinimumTestDuration=120",
        "g_CinebenchLogFile=true"
    ) -Wait -NoNewWindow
    if (Test-Path $CineOutSingle) {
        $txt = Get-Content $CineOutSingle -Raw
        $CB_Single = [regex]::Match($txt, "CB\s+([0-9]+\.[0-9]+)", 'IgnoreCase').Groups[1].Value
    }

    if (-not $CB_Single) { $CB_Single = "N/A" }
    if (-not $CB_Multi)  { $CB_Multi  = "N/A" }

} else {
    Write-Warning "Cinebench.exe not found in $CineRoot — skipping."
}

# ---------------------------------------------------------------------
#  4. Prime95 (short stress test)
# ---------------------------------------------------------------------
Write-Host "`n=== Prime95 (short stress, 60s) ===" -ForegroundColor Yellow
$PrimeDir = "$WorkDir\Prime95"
$PrimeZip = "$PrimeDir\prime95.zip"
$PrimeExe = "$PrimeDir\prime95.exe"
$PrimeURL = "https://www.mersenne.org/ftp_root/gimps/p95v308b23.win64.zip"

if (-not (Test-Path $PrimeExe)) {
    New-Item -ItemType Directory -Force -Path $PrimeDir | Out-Null
    Download-File $PrimeURL $PrimeZip
    if (Test-Path $PrimeZip) { Expand-Archive $PrimeZip -DestinationPath $PrimeDir -Force }
}

$PrimeResult = "FAIL"
if (Test-Path $PrimeExe) {
    Write-Host "Running Prime95 for 60 seconds..." -ForegroundColor Cyan
    Start-Process -FilePath $PrimeExe -ArgumentList "-t" -WorkingDirectory $PrimeDir
    Start-Sleep -Seconds 60
    Get-Process prime95 -ErrorAction SilentlyContinue | Stop-Process
    $PrimeResult = "PASS"
} else {
    Write-Warning "Prime95 not found — skipping."
}

# ---------------------------------------------------------------------
#  5. LINPACK (Intel oneMKL)
# ---------------------------------------------------------------------
Write-Host "`n=== Intel LINPACK (oneMKL) ===" -ForegroundColor Yellow
$LinDir = "$WorkDir\w_onemklbench_p_2025.2.0_531\benchmarks_2025.2\windows\share\mkl\benchmarks\linpack"
$LinExe = "$LinDir\linpack_xeon64.exe"
$LinInput = "$LinDir\lininput_xeon64"
$LinOut = "$WorkDir\linpack_test.out"
$LinGFLOPS = "N/A"

if (Test-Path $LinExe) {
    Write-Host "Running LINPACK benchmark..." -ForegroundColor Cyan
    cmd /c "`"cd /d $LinDir && linpack_xeon64.exe < lininput_xeon64 > $LinOut`""
    if (Test-Path $LinOut) {
        $txt = Get-Content $LinOut -Raw
        $LinGFLOPS = [regex]::Matches($txt, "([0-9]+\.[0-9]+)\s*$", 'IgnoreCase') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Last 1
        if (-not $LinGFLOPS) { $LinGFLOPS = "N/A" }
    }
} else {
    Write-Warning "LINPACK not found — skipping."
}

# ---------------------------------------------------------------------
#  Write to CSV
# ---------------------------------------------------------------------
$Line = '"' + ($HostName) + '","' + ($Timestamp) + '","' +
         ($GB_Single) + '","' + ($GB_Multi) + '","' + 
         ($Seven_MIPS) + '","' + ($CB_Single) + '","' + 
         ($CB_Multi) + '","' + ($PrimeResult) + '","' + 
         ($LinGFLOPS) + '"'

if (-not (Test-Path $ResultFile)) {
    'Hostname,Timestamp,GeekbenchSingle,GeekbenchMulti,7Zip(MIPS),Cine_Single,Cine_Multi,Prime95,LINPACK_GFLOPS' | Out-File $ResultFile -Encoding utf8
}
Add-Content -Path $ResultFile -Value $Line

Write-Host "`n✅ Benchmark completed. Results saved to $ResultFile" -ForegroundColor Green

$Result = [PSCustomObject]@{
    Hostname        = $env:COMPUTERNAME
    Timestamp       = (Get-Date)
    GeekbenchSingle = $GB_Single
    GeekbenchMulti  = $GB_Multi
    "7Zip(MIPS)"    = $Seven_MIPS
    Cine_Single     = $CB_Single
    Cine_Multi      = $CB_Multi
    Prime95         = $PrimeResult
    LINPACK_GFLOPS  = $Lin_GFLOPS
}
$Result 
