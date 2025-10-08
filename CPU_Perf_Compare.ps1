# 💡 Set via environment variables or hard-code below:
#   $env:GEEKBENCH_EMAIL   = "you@example.com"
#   $env:GEEKBENCH_LICENSE = "XXXX-XXXX-XXXX-XXXX"
$LicenseEmail = ""
$LicenseKey   = ""

<#
    CPU_Perf_Compare_v8.5.ps1
    ---------------------------------------------------------
    Comprehensive CPU benchmark suite:
      • Geekbench 6
      • 7-Zip Benchmark (24.08)
      • Cinebench R23 (CSV parser)
      • Prime95 short stress
      • Intel LINPACK (oneMKL)
#>

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

# Global paths
$WorkDir   = "C:\TEMP"
$ResultCSV = "$WorkDir\CPU_Performance_Results.csv"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

function Ensure-Directory($path) {
    if (-not (Test-Path $path)) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
}

# =====================================================================
# 1. Geekbench 6
# =====================================================================
Write-Host "`n=== Geekbench 6 ===" -ForegroundColor Yellow
$GeekURL  = "https://cdn.geekbench.com/Geekbench-6.3.0-Windows.zip"
$GeekZip  = "$WorkDir\Geekbench6.zip"
$GeekRoot = "$WorkDir\Geekbench6"
$GeekExe  = "$GeekRoot\geekbench6.exe"

if (-not (Test-Path $GeekExe)) {
    Write-Host "Downloading Geekbench 6..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $GeekURL -OutFile $GeekZip -UseBasicParsing
    Ensure-Directory $GeekRoot
    Expand-Archive -Path $GeekZip -DestinationPath $GeekRoot -Force
}

if (Test-Path $GeekExe) {
    $GeekLog = "$WorkDir\geekbench6.txt"
    & $GeekExe --cpu --no-upload | Tee-Object -FilePath $GeekLog
    $GB_Single = [regex]::Match((Get-Content $GeekLog -Raw), 'Single-Core Score\s+(\d+)', 'IgnoreCase').Groups[1].Value
    $GB_Multi  = [regex]::Match((Get-Content $GeekLog -Raw), 'Multi-Core Score\s+(\d+)',  'IgnoreCase').Groups[1].Value
} else {
    Write-Warning "Geekbench not found — skipping."
    $GB_Single = $GB_Multi = "N/A"
}

# =====================================================================
# 2. 7-Zip Benchmark (24.08)
# =====================================================================
Write-Host "`n=== 7-Zip Benchmark ===" -ForegroundColor Yellow
$SevenURL = "https://www.7-zip.org/a/7z2408-x64.exe"
$SevenInstaller = "$WorkDir\7z2408-x64.exe"
$SevenRoot = "$WorkDir\7zip"
$SevenExe = "$SevenRoot\7z.exe"

if (-not (Test-Path $SevenExe)) {
    Write-Host "Downloading and installing 7-Zip..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $SevenURL -OutFile $SevenInstaller -UseBasicParsing
    Start-Process -FilePath $SevenInstaller -ArgumentList "/S /D=$SevenRoot" -Wait
}

$Seven_MIPS = "N/A"
if (Test-Path $SevenExe) {
    $SevenLog = "$WorkDir\7zip.txt"
    & $SevenExe b -bb3 | Tee-Object -FilePath $SevenLog

    # Robust parser (confirmed with 7-Zip 24.08)
    if (Test-Path $SevenLog) {
        $SevenText = Get-Content $SevenLog -Raw
        $match = [regex]::Match($SevenText, 'Tot:.*?(\d{4,6})\s*$', 'Multiline,IgnoreCase')
        if ($match.Success) {
            $Seven_MIPS = $match.Groups[1].Value
        } else {
            $last = [regex]::Matches($SevenText, '(\d{4,6})\s*MIPS') | Select-Object -Last 1
            if ($last) { $Seven_MIPS = $last.Groups[1].Value }
        }
        if (-not $Seven_MIPS) { $Seven_MIPS = "N/A" }
    }
} else {
    Write-Warning "7-Zip executable not found — skipping."
}

# =====================================================================
# 3. Cinebench R23
# =====================================================================
Write-Host "`n=== Cinebench R23 ===" -ForegroundColor Yellow
$CineZipLocal = "$WorkDir\CinebenchR23.zip"
$CineRoot     = "$WorkDir\CinebenchR23"
$CineExe      = "$CineRoot\Cinebench.exe"

if (-not (Test-Path $CineExe)) {
    if (Test-Path $CineZipLocal) {
        Write-Host "Extracting existing Cinebench archive..." -ForegroundColor Cyan
        Expand-Archive -Path $CineZipLocal -DestinationPath $CineRoot -Force
    } else {
        Write-Warning "CinebenchR23.zip not found in $WorkDir — place it manually."
    }
}

$CB_Single = "N/A"
$CB_Multi  = "N/A"

if (Test-Path $CineExe) {
    Write-Host "Running Cinebench R23 multi-core test..." -ForegroundColor Cyan
    Start-Process -FilePath $CineExe -ArgumentList "g_CinebenchCpuXTest=true g_CinebenchLogFile=true" -Wait

    Write-Host "Running Cinebench R23 single-core test..." -ForegroundColor Cyan
    Start-Process -FilePath $CineExe -ArgumentList "g_CinebenchCpu1Test=true g_CinebenchLogFile=true" -Wait

    $CineCSV = "$env:USERPROFILE\Documents\CinebenchR23\cb_ranking.csv"
    if (Test-Path $CineCSV) {
        $csvText = Get-Content $CineCSV -Raw
        $CB_Single = [regex]::Match($csvText, 'Single Core.*?,(\d+)', 'IgnoreCase').Groups[1].Value
        $CB_Multi  = [regex]::Match($csvText, 'Multi Core.*?,(\d+)', 'IgnoreCase').Groups[1].Value
    }
} else {
    Write-Warning "Cinebench executable not found — skipping."
}

# =====================================================================
# 4. Prime95
# =====================================================================
Write-Host "`n=== Prime95 (short stress, 60 s) ===" -ForegroundColor Yellow
$PrimeURL  = "https://download.mersenne.ca/gimps/v30/30.19/p95v3019b20.win64.zip"
$PrimeZip  = "$WorkDir\Prime95.zip"
$PrimeRoot = "$WorkDir\Prime95"
$PrimeExe  = "$PrimeRoot\prime95.exe"

if (-not (Test-Path $PrimeExe)) {
    Write-Host "Downloading Prime95..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $PrimeURL -OutFile $PrimeZip -UseBasicParsing
    Ensure-Directory $PrimeRoot
    Expand-Archive -Path $PrimeZip -DestinationPath $PrimeRoot -Force
}

if (Test-Path $PrimeExe) {
    Start-Process -FilePath $PrimeExe -ArgumentList "-t" -WorkingDirectory $PrimeRoot
    Start-Sleep -Seconds 60
    Get-Process prime95 -ErrorAction SilentlyContinue | Stop-Process -Force
    $PrimeResult = "PASS"
} else {
    Write-Warning "Prime95 not found — skipping."
    $PrimeResult = "N/A"
}

# =====================================================================
# 5. Intel LINPACK
# =====================================================================
Write-Host "`n=== Intel LINPACK (oneMKL) ===" -ForegroundColor Yellow
$LinpackRoot = "C:\Temp\w_onemklbench_p_2025.2.0_531\benchmarks_2025.2\windows\share\mkl\benchmarks\linpack"
$LinExe = "$LinpackRoot\linpack_xeon64.exe"

if (-not (Test-Path $LinExe)) {
    Write-Warning "LINPACK executable not found — skipping."
    $Lin_GFLOPS = "N/A"
} else {
    $LinInput = "$LinpackRoot\lininput_xeon64"
    if (-not (Test-Path $LinInput)) {
@"
Intel(R) LINPACK data file
Sample benchmark run
5
1000 2000 3000 4000 5000
1000 2008 3000 4008 5000
4 4 2 1 1
4 4 4 4 4
"@ | Set-Content -NoNewline -Path $LinInput
    }

    Push-Location $LinpackRoot
    Start-Process -FilePath "cmd.exe" -ArgumentList '/c "linpack_xeon64.exe lininput_xeon64 > linpack_xeon64.out"' -NoNewWindow -Wait
    Pop-Location

    $LinResultFile = "$LinpackRoot\linpack_xeon64.out"
    if (Test-Path $LinResultFile) {
        $LinOutput = Get-Content $LinResultFile -Raw
        $perfBlock = [regex]::Match($LinOutput, 'Performance\s+Summary.*?(?=End\s+of\s+tests)', 'Singleline,IgnoreCase').Value
        if ($perfBlock) {
            $numbers = [regex]::Matches($perfBlock, '\b\d+\.\d+\b') | ForEach-Object { [double]$_.Value }
            $Lin_GFLOPS = ($numbers | Measure-Object -Maximum).Maximum
        } else { $Lin_GFLOPS = "N/A" }
    } else {
        Write-Warning "LINPACK output not found."
        $Lin_GFLOPS = "N/A"
    }
}

# =====================================================================
# 6. Write Results
# =====================================================================
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
$Result | Export-Csv -Path $ResultCSV -Append -NoTypeInformation -Encoding UTF8
Write-Host "`n✅ Results written to $ResultCSV" -ForegroundColor Cyan
$Result
