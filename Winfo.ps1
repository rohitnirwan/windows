# Requires Administrator privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Please launch PowerShell as Administrator to run this triage tool."
    exit
}

Clear-Host

# Enforce uniform UTF-8 encoding across console and output
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding           = [System.Text.Encoding]::UTF8

# Save directly in current working location
$currentDir = (Get-Location).Path
$stamp      = Get-Date -Format "yyyyMMdd_HHmmss"
$reportFile = Join-Path $currentDir "Triage_$($env:COMPUTERNAME)_$stamp.txt"
$gpHtmlFile = Join-Path $currentDir "GPResult_$($env:COMPUTERNAME)_$stamp.html"

# Initialize report file with clean UTF-8 encoding
Set-Content -Path $reportFile -Value "" -Encoding utf8

Write-Host "======================================================" -ForegroundColor Green
Write-Host " Starting Windows Directory Services & Network Triage " -ForegroundColor Green
Write-Host " Text Report : $reportFile" -ForegroundColor Green
Write-Host " GP HTML File: $gpHtmlFile" -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green

function Add-ReportSection {
    param (
        [string]$Title,
        [scriptblock]$Task
    )
    Write-Host "Collecting: $Title..." -ForegroundColor Cyan
    $border = "================================================================================"
    
    Add-Content -Path $reportFile -Value "`r`n$border`r`n$Title`r`n$border`r`n" -Encoding utf8
    
    try {
        $captured = & $Task 2>&1
        if ($null -ne $captured) {
            $textOutput = [string]::Join("`r`n", @($captured))
            Add-Content -Path $reportFile -Value $textOutput -Encoding utf8
        }
    } catch {
        Add-Content -Path $reportFile -Value "Error collecting section: $_" -Encoding utf8
    }
}

# 1. System Info & Hardware
Add-ReportSection -Title "SYSTEM INFORMATION" -Task {
    cmd.exe /c systeminfo
}

# 2. Domain & DC Discovery
Add-ReportSection -Title "DIRECTORY SERVICES AND DC RESOLUTION" -Task {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    "Joined Domain: $($cs.Domain)"
    "Domain Role: $($cs.DomainRole)"
    "`n--- NLTEST DSGETDC ---"
    cmd.exe /c "nltest /dsgetdc:$($cs.Domain)"
    "`n--- NLTEST DCLIST ---"
    cmd.exe /c "nltest /dclist:$($cs.Domain)"
}

# 3. Logged-On User & Group Tokens
Add-ReportSection -Title "USER CONTEXT AND TOKEN GROUPS" -Task {
    "--- Active Sessions (QUSER) ---"
    cmd.exe /c quser 2>&1
    "`n--- Current User Token (WHOAMI /USER) ---"
    cmd.exe /c whoami /user
    "`n--- Token Group SIDs and Names (WHOAMI /GROUPS) ---"
    cmd.exe /c "whoami /groups /fo table"
    "`n--- Local Administrators ---"
    $admins = Get-LocalGroupMember -Group "Administrators" -ErrorAction SilentlyContinue
    if ($admins) {$admins.ForEach({ "$($_.Name) | Principal: $($_.PrincipalSource) | Class: $($_.ObjectClass)" })
    }
}

# 4. Group Policy Results (Console Dump + HTML file in same folder)
Add-ReportSection -Title "GROUP POLICY RESULTS" -Task {
    "Generating interactive GPResult HTML report..."
    try {
        cmd.exe /c "gpresult /h `"$gpHtmlFile`" /f"
        "GPResult HTML successfully saved to: $gpHtmlFile"
    } catch {
        "Could not create HTML report: $_"
    }

    "`n--- Plaintext GPResult (Verbose) ---"
    cmd.exe /c "gpresult /v"
}

# 5. Network Configuration & Adapters
Add-ReportSection -Title "NETWORK INTERFACES AND IPCONFIG" -Task {
    "--- IPCONFIG /ALL ---"
    cmd.exe /c "ipconfig /all"
    "`n--- Network Adapters ---"
    $nics = Get-NetAdapter$nics.ForEach({ "$($_.Name) | Desc: $($_.InterfaceDescription) | Status: $($_.Status) | Speed: $($_.LinkSpeed) | MAC: $($_.MacAddress) | Driver: $($_.DriverVersion)" })
    "`n--- DNS Client Servers ---"
    $dns = Get-DnsClientServerAddress
    $dns.ForEach({ "Interface $($_.InterfaceIndex) [$($_.InterfaceAlias)]: $($_.ServerAddresses -join ', ')" })
}

# 6. Routing Table & ARP
Add-ReportSection -Title "ROUTING TABLE AND ARP" -Task {
    "--- Route Print ---"
    cmd.exe /c "route print"
    "`n--- ARP Cache ---"
    cmd.exe /c "arp -a"
}

# 7. Minifilter Drivers (FLTMC)
Add-ReportSection -Title "FILE SYSTEM MINIFILTERS (FLTMC)" -Task {
    "--- Filters ---"
    cmd.exe /c "fltmc filters"
    "`n--- Instances ---"
    cmd.exe /c "fltmc instances"
}

# 8. Installed Software Applications
Add-ReportSection -Title "INSTALLED THIRD-PARTY APPLICATIONS" -Task {
    $keys = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $apps = Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue
    $validApps = $apps.Where({ $_.DisplayName -and (-not $_.SystemComponent) })
    $validApps.ForEach({
        "$($_.DisplayName) | Version: $($_.DisplayVersion) | Publisher: $($_.Publisher) | Date: $($_.InstallDate)"
    })
}

# 9. Hotfix & Patch History
Add-ReportSection -Title "WINDOWS HOTFIXES" -Task {
    $hotfixes = Get-HotFix
    $hotfixes.ForEach({
        "$($_.HotFixID) | InstalledBy: $($_.InstalledBy) | InstalledOn: $($_.InstalledOn) | Desc: $($_.Description)"
    })
}

# 10. Active Ports and Owning Processes
Add-ReportSection -Title "ACTIVE PORTS AND PROCESSES (NETSTAT)" -Task {
    cmd.exe /c "netstat -ano -b"
}

# 11. Services Inventory (Running, Stopped, Third-Party)
Add-ReportSection -Title "SERVICES INVENTORY" -Task {
    $svcs = Get-CimInstance -ClassName Win32_Service

    "=== RUNNING SERVICES ==="
    $running = $svcs.Where({ $_.State -eq "Running" })
    $running.ForEach({
        "$($_.Name) | $($_.DisplayName) | StartMode: $($_.StartMode) | Account: $($_.StartName)"
    })

    "`n=== STOPPED SERVICES ==="
    $stopped = $svcs.Where({$_.State -ne "Running" })
    $stopped.ForEach({
        "$($_.Name) | $($_.DisplayName) | State: $($_.State) | StartMode: $($_.StartMode)"
    })

    "`n=== NON-SYSTEM32 THIRD-PARTY SERVICES ==="
    $thirdParty = $svcs.Where({ $_.PathName -notmatch "C:\\Windows\\System32" -and $_.PathName -notmatch "C:\\Windows\\SysWOW64" })
    $thirdParty.ForEach({
        "$($_.Name) | State: $($_.State) | Path: $($_.PathName)"
    })
}

Write-Host "`n======================================================" -ForegroundColor Green
Write-Host " Data collection finished successfully." -ForegroundColor Green
Write-Host " Text Output  : $reportFile" -ForegroundColor Green
Write-Host " GPResult HTML: $gpHtmlFile" -ForegroundColor Green
Write-Host "======================================================" -ForegroundColor Green