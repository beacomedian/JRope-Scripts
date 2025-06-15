# Name: Peak Files Cleanup Script
# Author: Jesse Rope
# Repository: github.com/beacomedian/JRope-Scripts
# Licence: GPL v3
# POWERSHELL: 
# Version: 1.0
# Link: https://www.jesserope.com
# About:
    # Deletes .reapeaks files older than X months based on modification date
    # Works recursively through all subfolders
    # Optionally sends files directly to Recycle Bin or intermediary folder for safety




#---------------------------------
#---------- USER CONFIG ----------
#---------------------------------

### DIRECTORIES - SET SOURCE AND DESTINATION 

# SOURCE
#$folder = "C:\Users\jesse\Desktop\test" #RECOMMEND RUNNING A TEST SOURCE AND DESTINATION FIRST
$folder = "E:\Audio Projects\zPeaks"

# MONTHS - Delete files older than this many months
$monthsOld = 12

# RECYCLE BIN - Set to $true to send to Recycle Bin, $false to use alternate path
$useRecycleBin = $true

# ALTERNATE PATH (only used if $useRecycleBin is $false)
$alternatePath = "C:\Users\jesse\Desktop\toDelete"


#---------------------------------
#-------------- MAIN -------------
#---------------------------------

# Add Windows Shell COM object for Recycle Bin functionality
Add-Type -AssemblyName Microsoft.VisualBasic

### VALIDATION ###
if (-not (Test-Path $folder)) {
    Write-Output "ERROR: Source folder does not exist: $folder"
    Write-Output "Press any key to exit..."
    $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp") | Out-Null
    exit 1
}

if (-not $useRecycleBin) {
    if (-not (Test-Path $alternatePath)) {
        Write-Output "ERROR: Alternate path does not exist: $alternatePath"
        Write-Output "Creating directory: $alternatePath"
        try {
            New-Item -ItemType Directory -Path $alternatePath -Force -ErrorAction Stop
            Write-Output "Successfully created directory: $alternatePath"
        } catch {
            Write-Output "ERROR: Failed to create directory: $($_.Exception.Message)"
            Write-Output "Press any key to exit..."
            $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp") | Out-Null
            exit 1
        }
    }
}

Write-Output "Starting peak files cleanup..."
Write-Output "Source folder: $folder"
if ($useRecycleBin) {
    Write-Output "Destination: Windows Recycle Bin"
} else {
    Write-Output "Destination: $alternatePath"
}
Write-Output "Deleting .reapeaks files older than $monthsOld months"
Write-Output ""

### MAIN PROCESSING ###
# Calculate cutoff date
$cutoffDate = (Get-Date).AddMonths(-$monthsOld)
Write-Output "Cutoff date: $($cutoffDate.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Output "Files modified before this date will be deleted."
Write-Output ""

# Get all .reapeaks files recursively
$files = Get-ChildItem -Path $folder -File -Filter "*.reapeaks" -Recurse

if ($files.Count -eq 0) {
    Write-Output "No .reapeaks files found in the specified folder and subfolders."
    Write-Output "Press any key to exit..."
    $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp") | Out-Null
    exit
}

Write-Output "Found $($files.Count) .reapeaks files total"
Write-Output ""

# Filter files older than cutoff date
$filesToDelete = $files | Where-Object { $_.LastWriteTime -lt $cutoffDate }

if ($filesToDelete.Count -eq 0) {
    Write-Output "No .reapeaks files found older than $monthsOld months."
    Write-Output "All files are within the retention period."
    Write-Output "Press any key to exit..."
    $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp") | Out-Null
    exit
}

Write-Output "Found $($filesToDelete.Count) files to delete (older than $monthsOld months)"
Write-Output "Keeping $($files.Count - $filesToDelete.Count) files (within retention period)"
Write-Output ""

# Process files for deletion
$totalFilesDeleted = 0
$totalErrors = 0

foreach ($file in $filesToDelete) {
    try {
        $relativePath = $file.FullName.Substring($folder.Length + 1)
        Write-Output "Deleting: $relativePath (Modified: $($file.LastWriteTime.ToString('yyyy-MM-dd HH:mm')))"
        
        if ($useRecycleBin) {
            # Send to Recycle Bin using Windows Shell
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($file.FullName, 'OnlyErrorDialogs', 'SendToRecycleBin')
            Write-Output "✓ Successfully sent to Recycle Bin: $($file.Name)"
        } else {
            # Move to alternate path
            Move-Item -Path $file.FullName -Destination $alternatePath -Force -ErrorAction Stop
            Write-Output "✓ Successfully moved: $($file.Name)"
        }
        
        $totalFilesDeleted++
    } catch {
        Write-Output "✗ ERROR processing $($file.Name): $($_.Exception.Message)"
        $totalErrors++
    }
}

# Summary
Write-Output ""
Write-Output "=== CLEANUP SUMMARY ==="
Write-Output "Total .reapeaks files found: $($files.Count)"
Write-Output "Files older than $monthsOld months: $($filesToDelete.Count)"
Write-Output "Files successfully deleted: $totalFilesDeleted"
Write-Output "Errors encountered: $totalErrors"
Write-Output "Files retained: $($files.Count - $filesToDelete.Count)"

if ($totalErrors -gt 0) {
    Write-Output ""
    Write-Output "WARNING: Some files could not be moved. Check the errors above."
}

Write-Output ""
Write-Output "Cleanup completed. Press any key to exit..."