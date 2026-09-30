<#
.SYNOPSIS
    Interactive CLI tool to generate a standardized DDX template note
    with per-field confirmation and edit verification.
#>

Clear-Host
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "         DDX Template Generator           " -ForegroundColor Cyan
Write-Host "==========================================`n" -ForegroundColor Cyan

# Helper function for single-line inputs with confirmation & edit loop
function Get-ConfirmedSingleLineInput {
    param (
        [string]$PromptText
    )
    while ($true) {
        $val = Read-Host $PromptText
        Write-Host "  -> Entered: " -NoNewline -ForegroundColor DarkGray
        Write-Host "$val" -ForegroundColor White

        $confirm = Read-Host "  Is this correct? ([Y]/n)"
        if ([string]::IsNullOrWhiteSpace($confirm) -or $confirm -match '^[Yy]$') {
            return $val
        }
        Write-Host "  Re-entering field...`n" -ForegroundColor Yellow
    }
}

# Helper function for multi-line inputs with confirmation & edit loop
function Get-ConfirmedMultiLineInput {
    param (
        [string]$PromptText
    )
    while ($true) {
        Write-Host "$PromptText (Type or paste text; press [Enter] on an empty line to finish):" -ForegroundColor Yellow
        $lines = [System.Collections.Generic.List[string]]::new()
        while ($true) {$inputLine = Read-Host
            if ([string]::IsNullOrWhiteSpace($inputLine) -and$lines.Count -gt 0) {
                break
            }
            if (-not [string]::IsNullOrWhiteSpace($inputLine)) {
                $lines.Add($inputLine)
            }
        }
        $result =$lines -join "`r`n"

        Write-Host "`n  --- Entered Value Preview ---" -ForegroundColor DarkGray
        Write-Host $result -ForegroundColor White
        Write-Host "  -----------------------------" -ForegroundColor DarkGray

        $confirm = Read-Host "  Is this correct? ([Y]/n)"
        if ([string]::IsNullOrWhiteSpace($confirm) -or $confirm -match '^[Yy]$') {
            return $result
        }
        Write-Host "  Re-entering multi-line field...`n" -ForegroundColor Yellow
    }
}

# --- Prompt Questions Sequentially With Verification ---

Write-Host "--- SCOPE DETAILS ---" -ForegroundColor DarkCyan
$IssueDesc       = Get-ConfirmedSingleLineInput -PromptText "1. [Issue Description]"
$BusinessImpact  = Get-ConfirmedSingleLineInput -PromptText "2. [Business Impact]"
$ExpectedOutcome = Get-ConfirmedSingleLineInput -PromptText "3. [Expected Outcome]"

Write-Host "`n--- CASE SUMMARY ---" -ForegroundColor DarkCyan
$Environment     = Get-ConfirmedMultiLineInput -PromptText "4. [Environment]"
$Troubleshooting = Get-ConfirmedMultiLineInput -PromptText "5. [Troubleshooting]"

Write-Host "`n--- ACTION PLAN ---" -ForegroundColor DarkCyan
$CaseStatus  = Get-ConfirmedSingleLineInput -PromptText "6. Case Status (<who>)"
$NextAction  = Get-ConfirmedSingleLineInput -PromptText "7. Next Action (<what/why>)"
$NextContact = Get-ConfirmedSingleLineInput -PromptText "8. Next Contact (<when>)"

# --- Build Template Output ---

$ddxLines = @(
    "SCOPE:",
    "[Issue Description]: $IssueDesc",
    "[Business Impact]: $BusinessImpact",
    "[Expected Outcome]: $ExpectedOutcome",
    "+++++++++++++++++++++++++++",
    "CASE SUMMARY",
    "[Environment]:",
    "$Environment",
    "",
    "[Troubleshooting]:",
    "$Troubleshooting",
    " ",
    "",
    "ACTION PLAN",
    "Case Status: $CaseStatus",
    "Next Action: $NextAction",
    "Next Contact: $NextContact"
)

$ddxContent =$ddxLines -join "`r`n"

# Display formatted DDX
Write-Host "`n================ DDX OUTPUT ================" -ForegroundColor Green
Write-Host $ddxContent -ForegroundColor White
Write-Host "============================================`n" -ForegroundColor Green

# Automatically copy to clipboard
try {
    Set-Clipboard -Value $ddxContent
    Write-Host "[OK] DDX template copied to clipboard." -ForegroundColor Green
} catch {
    Write-Warning "Could not access clipboard directly in this session host."
}

# Optional: Prompt to save to a local text file
$saveChoice = Read-Host "Do you want to save this to a .txt file? (Y/N)"
if ($saveChoice -match '^[Yy]$') {
    $defaultFilename = "DDX_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $fileName = Read-Host "Enter filename (Press [Enter] for default: $defaultFilename)"
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $fileName =$defaultFilename
    }
    if (-not $fileName.EndsWith(".txt")) {
        $fileName += ".txt"
    }

    $outPath = Join-Path -Path (Get-Location) -ChildPath$fileName
    Set-Content -Path $outPath -Value$ddxContent -Encoding utf8
    Write-Host "[OK] File saved to: $outPath" -ForegroundColor Green
}