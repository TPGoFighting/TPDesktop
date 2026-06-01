# UTF-8 with BOM
# TPDesktop One-Key Deploy Script v2.8.0
# Based on ZenDesktop by Lanbo (Enhanced by TP)

$ErrorActionPreference = "Stop"

# Log setup
$logFile = Join-Path $PSScriptRoot "deploy_log.txt"
$dateStr = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"TPDesktop Deploy Log - $dateStr" | Out-File -FilePath $logFile -Encoding utf8

function Write-Log($msg, $color = "White") {
    Write-Host $msg -ForegroundColor $color
    $msg | Out-File -FilePath $logFile -Append -Encoding utf8
}

Write-Log "============================================================" "Cyan"
Write-Log "   TPDesktop Premium Theme - One-Key Deploy v2.8.0" "Cyan"
Write-Log "   Based on ZenDesktop by Lanbo (Enhanced by TP)" "Cyan"
Write-Log "============================================================" "Cyan"
Write-Log "   4 independent local mods, no conflict with originals" "Yellow"
Write-Log "============================================================" "Cyan"
Write-Log ""

# -----------------------------------------------------------------
# Step 1: Detect Windhawk
# -----------------------------------------------------------------
Write-Log "[1/7] Detecting Windhawk..." "Green"

$windhawkMods = "C:\ProgramData\Windhawk\ModsSource"
$windhawkIsPortable = $false
$windhawkDir = ""
$windhawkFound = $false

# Check portable in script directory
if (Test-Path "$PSScriptRoot\Windhawk\windhawk.exe") {
    $windhawkDir = "$PSScriptRoot\Windhawk"
    $windhawkMods = "$windhawkDir\AppData\ModsSource"
    $windhawkIsPortable = $true
    $windhawkFound = $true
    Write-Log "      [OK] Portable Windhawk detected (Windhawk\windhawk.exe)" "Gray"
}
elseif (Test-Path "$PSScriptRoot\windhawk.exe") {
    $windhawkDir = $PSScriptRoot
    $windhawkMods = "$windhawkDir\AppData\ModsSource"
    $windhawkIsPortable = $true
    $windhawkFound = $true
    Write-Log "      [OK] Portable Windhawk detected (same folder)" "Gray"
}
else {
    # Check service
    $service = Get-Service -Name Windhawk -ErrorAction SilentlyContinue
    if ($service -ne $null) {
        $windhawkFound = $true
        Write-Log "      [OK] Windhawk Service detected" "Gray"
    }
    elseif (Test-Path "C:\Program Files\Windhawk\windhawk.exe") {
        $windhawkFound = $true
        Write-Log "      [OK] Windhawk Program Files detected" "Gray"
    }
    elseif (Test-Path "C:\ProgramData\Windhawk") {
        $windhawkFound = $true
        Write-Log "      [OK] Windhawk AppData folder detected" "Gray"
    }
}

if (-not $windhawkFound) {
    # Check setup files in current folder
    $setup = Get-ChildItem -Path $PSScriptRoot -Filter "windhawk_setup*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($setup -ne $null) {
        Write-Log "[INFO] Windhawk not installed. Found setup file: $($setup.Name) - launching installer..." "Yellow"
        Start-Process -FilePath $setup.FullName -Wait
        Start-Sleep -Seconds 3
        # Recheck
        if (Test-Path "C:\Program Files\Windhawk\windhawk.exe") {
            $windhawkFound = $true
            Write-Log "      [OK] Windhawk successfully installed and verified" "Gray"
        }
    }
}

if (-not $windhawkFound) {
    Write-Log "[ERROR] Windhawk not found! Please install from https://windhawk.net" "Red"
    Write-Log "Please press Enter to exit." "Yellow"
    Read-Host
    exit 1
}

# Ensure ModsSource directory exists
if (-not (Test-Path $windhawkMods)) {
    New-Item -ItemType Directory -Path $windhawkMods -Force | Out-Null
}
Write-Log "      ModsSource Path: $windhawkMods" "Gray"
Write-Log ""

# -----------------------------------------------------------------
# Step 2: Stop Windhawk
# -----------------------------------------------------------------
Write-Log "[2/7] Stopping Windhawk to release locks..." "Green"
Stop-Service -Name Windhawk -Force -ErrorAction SilentlyContinue
Stop-Process -Name windhawk, windhawk-x64-helper, windhawk-x86-helper -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Write-Log "      [OK] Windhawk service and helper processes stopped" "Gray"
Write-Log ""

# -----------------------------------------------------------------
# Step 3: Disable original conflicting mods
# -----------------------------------------------------------------
Write-Log "[3/7] Disabling original mods to prevent conflicts..." "Green"
$regBase = "HKLM:\SOFTWARE\Windhawk\Engine\Mods"

if (-not (Test-Path $regBase)) {
    New-Item -Path $regBase -Force | Out-Null
}

$conflicts = @("windows-11-taskbar-styler", "windows-11-start-menu-styler")
foreach ($mod in $conflicts) {
    $modPath = "$regBase\$mod"
    if (-not (Test-Path $modPath)) {
        New-Item -Path $modPath -Force | Out-Null
    }
    Set-ItemProperty -Path $modPath -Name "Disabled" -Value 1 -Type DWord -Force | Out-Null
}
Write-Log "      [OK] Original mods disabled" "Gray"
Write-Log ""

# -----------------------------------------------------------------
# Step 4: Copy mod sources (with ACL fix)
# -----------------------------------------------------------------
Write-Log "[4/7] Deploying local mod sources..." "Green"

# Try granting permissions to ModsSource folder first
try {
    takeown /f $windhawkMods /r /d y | Out-Null
    icacls $windhawkMods /grant "Administrators:(OI)(CI)F" /t /q | Out-Null
} catch {
    Write-Log "      [WARN] Perms adjustment on ModsSource completed with warnings" "Yellow"
}

$filesToCopy = @(
    "local@zen-taskbar-acrylic.wh.cpp",
    "local@zen-startmenu-acrylic.wh.cpp",
    "local@zen-desktop-toggle-icons.wh.cpp",
    "local@zen-fileexplorer-transparent.wh.cpp"
)

$copySuccess = $true
foreach ($file in $filesToCopy) {
    $srcFile = Join-Path $PSScriptRoot $file
    $destFile = Join-Path $windhawkMods $file
    
    if (-not (Test-Path $srcFile)) {
        Write-Log "      [ERROR] Source file not found: $file" "Red"
        $copySuccess = $false
        continue
    }
    
    # Try copying with standard Copy-Item first
    try {
        Copy-Item -Path $srcFile -Destination $destFile -Force -ErrorAction Stop
        Write-Log "      [OK] Deployed $file" "Gray"
    } catch {
        # Fallback to robocopy
        $rc = robocopy $PSScriptRoot $windhawkMods $file /IS /IT /NFL /NDL /NJH /NJS
        if ($rc -ge 8) {
            Write-Log "      [ERROR] Failed to deploy $file via robocopy" "Red"
            $copySuccess = $false
        } else {
            Write-Log "      [OK] Deployed $file (robocopy fallback)" "Gray"
        }
    }
}

if (-not $copySuccess) {
    Write-Log "[ERROR] Mod deployment failed. Check permissions or antivirus." "Red"
    Write-Log "Please press Enter to exit." "Yellow"
    Read-Host
    exit 1
}
Write-Log ""

# -----------------------------------------------------------------
# Step 5: Register mods in Registry
# -----------------------------------------------------------------
Write-Log "[5/7] Registering mods..." "Green"

$modsSettings = @{
    "local@zen-taskbar-acrylic" = @{
        "Disabled" = 0
        "LoggingEnabled" = 0
        "Include" = "explorer.exe"
        "Exclude" = ""
        "Architecture" = "x86-64"
        "Version" = "2.7.0"
        "LibraryFileName" = ""
        "Settings" = @{
            "theme" = "TranslucentTaskbar"
        }
    }
    "local@zen-startmenu-acrylic" = @{
        "Disabled" = 0
        "LoggingEnabled" = 0
        "Include" = "StartMenuExperienceHost.exe|SearchHost.exe|SearchApp.exe"
        "Exclude" = ""
        "Architecture" = "x86-64"
        "Version" = "2.7.0"
        "LibraryFileName" = ""
        "Settings" = @{
            "theme" = "TranslucentStartMenu"
        }
    }
    "local@zen-desktop-toggle-icons" = @{
        "Disabled" = 1
        "LoggingEnabled" = 0
        "Include" = "explorer.exe"
        "Exclude" = ""
        "Architecture" = ""
        "Version" = "2.7.0"
        "LibraryFileName" = ""
    }
    "local@zen-fileexplorer-transparent" = @{
        "Disabled" = 0
        "LoggingEnabled" = 0
        "Include" = "explorer.exe"
        "Exclude" = ""
        "Architecture" = "x86-64"
        "Version" = "2.1.0"
        "LibraryFileName" = ""
        "Settings" = @{
            "transparencyMode" = "blur"
            "blurOpacity" = 19
            "blurColor" = "#FFFFFF"
            "textColorMode" = "default"
            "applyToNavPane" = 1
            "applyToCommandBar" = 1
        }
    }
}

try {
    foreach ($modName in $modsSettings.Keys) {
        $modKeyPath = "$regBase\$modName"
        if (-not (Test-Path $modKeyPath)) {
            New-Item -Path $modKeyPath -Force | Out-Null
        }
        
        $properties = $modsSettings[$modName]
        foreach ($propName in $properties.Keys) {
            if ($propName -eq "Settings") {
                $settingsKeyPath = "$modKeyPath\Settings"
                if (-not (Test-Path $settingsKeyPath)) {
                    New-Item -Path $settingsKeyPath -Force | Out-Null
                }
                $subProperties = $properties["Settings"]
                foreach ($subPropName in $subProperties.Keys) {
                    $val = $subProperties[$subPropName]
                    if ($val -is [int] -or $val -is [uint32] -or $val -is [long]) {
                        Set-ItemProperty -Path $settingsKeyPath -Name $subPropName -Value $val -Type DWord -Force | Out-Null
                    } else {
                        Set-ItemProperty -Path $settingsKeyPath -Name $subPropName -Value $val -Type String -Force | Out-Null
                    }
                }
            } else {
                $val = $properties[$propName]
                if ($val -is [int] -or $val -is [uint32] -or $val -is [long]) {
                    Set-ItemProperty -Path $modKeyPath -Name $propName -Value $val -Type DWord -Force | Out-Null
                } else {
                    Set-ItemProperty -Path $modKeyPath -Name $propName -Value $val -Type String -Force | Out-Null
                }
            }
        }
    }
    
    # Enable compile locally setting
    $settingsPath = "HKLM:\SOFTWARE\Windhawk\Settings"
    if (-not (Test-Path $settingsPath)) {
        New-Item -Path $settingsPath -Force | Out-Null
    }
    Set-ItemProperty -Path $settingsPath -Name "AlwaysCompileModsLocally" -Value 1 -Type DWord -Force | Out-Null
    
    Write-Log "      [OK] Registry entries created successfully" "Gray"
} catch {
    Write-Log "      [WARN] Registry registration had errors: $_" "Yellow"
    Write-Log "      This could happen if antivirus (Huorong/360) blocked registry access." "Yellow"
}
Write-Log ""

# -----------------------------------------------------------------
# Step 6: Start Windhawk
# -----------------------------------------------------------------
Write-Log "[6/7] Starting Windhawk..." "Green"
$serviceStarted = $false
try {
    $service = Get-Service -Name Windhawk -ErrorAction SilentlyContinue
    if ($service -ne $null) {
        Start-Service -Name Windhawk -ErrorAction Stop
        Write-Log "      [OK] Windhawk service started successfully" "Gray"
        $serviceStarted = $true
    }
} catch {
    Write-Log "      [WARN] Failed to start Windhawk service. Trying tray executable..." "Yellow"
}

if (-not $serviceStarted) {
    $trayPaths = @(
        "C:\Program Files\Windhawk\windhawk.exe",
        "$PSScriptRoot\Windhawk\windhawk.exe"
    )
    $launched = $false
    foreach ($p in $trayPaths) {
        if (Test-Path $p) {
            Start-Process -FilePath $p -ArgumentList "-tray-only"
            Write-Log "      [OK] Started Windhawk tray process from $p" "Gray"
            $launched = $true
            break
        }
    }
    if (-not $launched) {
        Write-Log "      [WARN] Could not automatically start Windhawk. Please launch it manually." "Yellow"
    }
}
Write-Log ""

# -----------------------------------------------------------------
# Step 7: Print complete
# -----------------------------------------------------------------
Write-Log "============================================================" "Cyan"
Write-Log "    DEPLOY COMPLETE!" "Cyan"
Write-Log "============================================================" "Cyan"
Write-Log "    Windhawk will compile the 4 mods in the background (~60 sec)." "White"
Write-Log "    You can open the Windhawk UI to check compilation progress." "White"
Write-Log ""
Write-Log "    Deployed Mods:" "Yellow"
Write-Log "      1. ZenDesktop: Taskbar Acrylic Styler" "White"
Write-Log "      2. ZenDesktop: Start Menu Acrylic Styler" "White"
Write-Log "      3. ZenDesktop: Double Click to Hide Icons (Disabled by default)" "White"
Write-Log "      4. ZenDesktop: File Explorer Transparent Background" "White"
Write-Log ""
Write-Log "    Log file saved to: $logFile" "Gray"
Write-Log "============================================================" "Cyan"
Write-Log "Press Enter to exit..." "Yellow"
Read-Host
