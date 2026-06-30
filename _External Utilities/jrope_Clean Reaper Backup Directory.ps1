 # Name: Rpp-bak Cleanup Script
 # Author: Jesse Rope
 # Repository: github.com/beacomedian/JRope-Scripts
 # Licence: GPL v3
 # POWERSHELL: 
 # Version: 1.2
 # Link: https://www.jesserope.com
 # About:
    # Intended for a shared backup path across all projects
    # Keeps only the X most recent backup files for each session ID
    # Use amagalma_Backup Limit scripts if you have project-based backup locations   
 # Changelog:
    # Initial Release
    # Updated to parse file name time stamp rather than system LastWriteTime
    # Updated with user config to keep at least 1 backup per day, default TRUE 
    # Removed direct-to-recycle bin function for safety
 # TO DO:


#---------------------------------
#---------- USER CONFIG ----------
#---------------------------------

### DIRECTORIES - SET SOURCE AND DESTINATION 

# SOURCE
#$folder = "C:\Users\jesse\Desktop\backup_test" #RECOMMEND RUNNING A TEST SOURCE AND DESTINATION FIRST
$folder = "E:\Audio Projects\zRpp-bak"

# DESTINATION
$recycleBinPath = "C:\Users\jesse\Desktop\toDelete" 

# BACKUPSS to keep per session
$backupsToKeep = 5

# Keep at least one backup per day beyond the main threshold
$keepOnePerDay = $true


#---------------------------------
#-------------- MAIN -------------
#---------------------------------

### VALIDATION ###
if (-not (Test-Path $folder)) {
    Write-Output "ERROR: Source folder does not exist: $folder"
    Write-Output "Press any key to exit..."
    $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp") | Out-Null
    exit 1
}

if (-not (Test-Path $recycleBinPath)) {
    Write-Output "ERROR: Recycle bin path does not exist: $recycleBinPath"
    Write-Output "Creating directory: $recycleBinPath"
    try {
        New-Item -ItemType Directory -Path $recycleBinPath -Force -ErrorAction Stop
        Write-Output "Successfully created directory: $recycleBinPath"
    } catch {
        Write-Output "ERROR: Failed to create directory: $($_.Exception.Message)"
        Write-Output "Press any key to exit..."
        $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp") | Out-Null
        exit 1
    }
}

Write-Output "Starting cleanup..."
Write-Output "Source folder: $folder"
Write-Output "Recycle bin path: $recycleBinPath"
Write-Output "Keeping $backupsToKeep most recent backups per session"
if ($keepOnePerDay) {
    Write-Output "Also keeping at least 1 backup per day for older days"
}
Write-Output ""

### MAIN PROCESSING ###
# Get all .rpp-bak files
$files = Get-ChildItem -Path $folder -File -Filter "*.rpp-bak"

if ($files.Count -eq 0) {
    Write-Output "No .rpp-bak files found in the specified folder."
    Write-Output "Press any key to exit..."
    $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp") | Out-Null
    exit
}

Write-Output "Found $($files.Count) backup files total"
Write-Output ""

# Group files by session ID using improved pattern matching
$validFiles = @()
$invalidFiles = @()

foreach ($file in $files) {
    $filename = $file.BaseName
    
    # Pattern matching for session ID and date: sessionname-YYYY-MM-DD_HHMM
    if ($filename -match '^(.+)-(\d{4}-\d{2}-\d{2}_\d{4})$') {
        $sessionID = $matches[1]
        $dateSuffix = $matches[2]
        
        $validFiles += [PSCustomObject]@{
            File = $file
            SessionID = $sessionID
            DateSuffix = $dateSuffix
        }
    } else {
        $invalidFiles += $file
        Write-Output "WARNING: Skipping file with invalid naming pattern: $($file.Name)"
    }
}

if ($invalidFiles.Count -gt 0) {
    Write-Output "Found $($invalidFiles.Count) files with invalid naming patterns"
    Write-Output ""
}

if ($validFiles.Count -eq 0) {
    Write-Output "No valid backup files found matching the expected naming pattern."
    Write-Output "Expected pattern: sessionname-YYYY-MM-DD_HHMM.rpp-bak"
    Write-Output "Press any key to exit..."
    $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyUp") | Out-Null
    exit
}

# Group valid files by session ID
$fileGroups = $validFiles | Group-Object SessionID

Write-Output "Processing $($fileGroups.Count) unique session(s):"
Write-Output ""

$totalFilesToDelete = 0
$totalFilesDeleted = 0
$totalErrors = 0

foreach ($group in $fileGroups) {
    $sessionID = $group.Name
    $sessionFiles = $group.Group | ForEach-Object { $_.File }
    
    # Sort files by the timestamp in filename (newest first)
    $sortedFiles = $sessionFiles | Sort-Object { 
        if ($_.BaseName -match '^(.+)-(\d{4}-\d{2}-\d{2}_\d{4})$') {
            $dateStr = $matches[2]  # e.g., "2021-03-15_1055"
            # Convert to DateTime: YYYY-MM-DD_HHMM -> YYYY-MM-DD HH:MM
            $formattedDate = $dateStr -replace '_(\d{2})(\d{2})$', ' $1:$2'
            try {
                [DateTime]::ParseExact($formattedDate, 'yyyy-MM-dd HH:mm', $null)
            } catch {
                Write-Output "    WARNING: Could not parse date from filename $($_.Name), using LastWriteTime"
                $_.LastWriteTime
            }
        } else {
            $_.LastWriteTime
        }
    } -Descending
    
    Write-Output "Session: '$sessionID' - Found $($sortedFiles.Count) backup(s)"
    
    if ($sortedFiles.Count -gt $backupsToKeep) {
        # Step 1: Keep the most recent N backups
        $filesToKeep = $sortedFiles | Select-Object -First $backupsToKeep
        $remainingFiles = $sortedFiles | Select-Object -Skip $backupsToKeep
        
        # Step 2: If keepOnePerDay is enabled, preserve one backup per day from remaining files
        $additionalKeepFiles = @()
        if ($keepOnePerDay -and $remainingFiles.Count -gt 0) {
            # Group remaining files by date and keep the newest from each day
            $filesByDate = $remainingFiles | Group-Object { 
                if ($_.BaseName -match '^(.+)-(\d{4}-\d{2}-\d{2})_\d{4}$') {
                    $matches[2]  # Extract just the date part (YYYY-MM-DD)
                } else {
                    $_.LastWriteTime.ToString('yyyy-MM-dd')
                }
            }
            
            # Keep the newest file from each day
            foreach ($dateGroup in $filesByDate) {
                $newestInDay = $dateGroup.Group | Select-Object -First 1
                $additionalKeepFiles += $newestInDay
                Write-Output "  Keeping 1 backup from $($dateGroup.Name): $($newestInDay.Name)"
            }
        }
        
        # Step 3: Determine final files to delete
        $allFilesToKeep = $filesToKeep + $additionalKeepFiles
        $filesToDelete = $remainingFiles | Where-Object { $_ -notin $additionalKeepFiles }
        
        Write-Output "  Keeping $($filesToKeep.Count) most recent backup(s)"
        if ($additionalKeepFiles.Count -gt 0) {
            Write-Output "  Keeping $($additionalKeepFiles.Count) additional backup(s) (one per day)"
        }
        Write-Output "  Deleting $($filesToDelete.Count) older backup(s)"
        
        $totalFilesToDelete += $filesToDelete.Count
        
        foreach ($file in $filesToDelete) {
            # Show both timestamps for verification
            $filenameDate = "Unknown"
            if ($file.BaseName -match '^(.+)-(\d{4}-\d{2}-\d{2}_\d{4})$') {
                $filenameDate = $matches[2] -replace '_', ' '
            }
            
            try {
                Write-Output "    Moving: $($file.Name) (Created: $filenameDate, Modified: $($file.LastWriteTime.ToString('yyyy-MM-dd HH:mm')))"
                Move-Item -Path $file.FullName -Destination $recycleBinPath -Force -ErrorAction Stop
                Write-Output "    ✓ Successfully moved: $($file.Name)"
                $totalFilesDeleted++
            } catch {
                Write-Output "    ✗ ERROR moving $($file.Name): $($_.Exception.Message)"
                $totalErrors++
            }
        }
    } else {
        Write-Output "  Keeping all $($sortedFiles.Count) backup(s) (under threshold)"
    }
    
    Write-Output ""
}

# Summary
Write-Output "=== CLEANUP SUMMARY ==="
Write-Output "Total backup files processed: $($files.Count)"
Write-Output "Valid files processed: $($validFiles.Count)"
Write-Output "Invalid files skipped: $($invalidFiles.Count)"
Write-Output "Files scheduled for deletion: $totalFilesToDelete"
Write-Output "Files successfully deleted: $totalFilesDeleted"
Write-Output "Errors encountered: $totalErrors"

if ($totalErrors -gt 0) {
    Write-Output ""
    Write-Output "WARNING: Some files could not be moved. Check the errors above."
}

Write-Output ""
Write-Output "Cleanup completed. Press any key to exit..."