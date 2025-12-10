# PowerShell Backup Monitoring

This project automates the archiving of backup files and the integrity check of those backups, with monitoring integration in **Zabbix**.  
The script is designed to be run on a Windows server (for example via Task Scheduler) and to give a clear status for each run.

---

## Tools Used

- **PowerShell** (Windows, `Get-FileHash`, `Start-Transcript`, etc.)
- **7-Zip CLI** (`7z.exe`) for compression
- **Zabbix** (reads a status file to trigger alerts)
- **Windows Task Scheduler** (optional, to run the script on a schedule)

---

## Requirements

- Windows host with **PowerShell 5.1+**
- **7-Zip** installed and accessible at  
  `C:\Program Files\7-Zip\7z.exe`  
  (or update the `$SevenZipPath` variable in the script)
- Read/Write permissions on:
  - `$DossierCible` – source folder containing the backups to archive  
  - `$DossierArchive` – final archive folder  
  - `$DossierArchiveTemp` – temporary archive folder  
  - `C:\ZabbixStatus` – folder that stores the Zabbix status file
- A Zabbix item that reads `C:\ZabbixStatus\backup_status.txt`  
  (for example with `vfs.file.contents`) and triggers based on the codes below.

---

## Zabbix Status Codes

The script uses a small numeric protocol to report its state to Zabbix:

- `0` – **EN_COURS**: script currently running  
- `1` – **ERR_NON_CRIT**: non-critical error (for example: folders not empty after cleanup)  
- `2` – **ERR_CRITIQUE**: critical error (integrity failure, compression error, etc.)  
- `3` – **TERMINE_OK**: script finished successfully  
- `9` – neutral value used only for the very first run (file initialization)

These values are written to `backup_status.txt` and can be used in Zabbix triggers.

---

## How the Script Works

### 1. Initialization & Logging

At the top of the script:

- Paths and variables are defined:  
  - `$DossierCible` – source directory containing the backups  
  - `$DossierArchive` – directory where final ZIP archives are stored  
  - `$DossierArchiveTemp` – temporary working directory  
  - `$LogDirectory` – directory where log files are stored  
  - `$ZipFileLimit` – maximum number of archives to keep (4)
- The Zabbix folder and status file are created if they do not exist.  
  The status file is initialized with `9` on the very first run.
- Default encoding for `Out-File` is set to UTF-8.
- The archive and log directories are created if missing.
- A transcript is started with `Start-Transcript`, writing a log file named  
  `BackupLog_<date>.txt` in the `Logs` directory.

### 2. Notifying Zabbix (Script Start)

- As soon as the transcript is started, the script writes `0` (**EN_COURS**) to  
  `backup_status.txt` to indicate that a backup/archiving run is in progress.

### 3. Pre-Checks on the Source Folder

Before touching any data:

- The script verifies that `$DossierCible` exists.  
  - If the folder does not exist, it writes `1` (**ERR_NON_CRIT**) and exits.
- It then checks that the folder is **not empty**.  
  - If the folder is empty, it also writes `1` and exits.
- The temporary archive folder `$DossierArchiveTemp` is checked and created if needed.

### 4. Integrity Check Before and After Copy

To ensure that the backups are not corrupted during the move:

1. **Hash before copy**  
   - A combined **SHA256 hash** (`$Hash1`) of all files in `$DossierCible` is computed  
     using `Get-FileHash` (paths sorted and concatenated).
2. **Copy to temporary archive folder**  
   - All files from `$DossierCible` are copied to `$DossierArchiveTemp`.
3. **Hash after copy**  
   - A second combined hash (`$Hash2`) is computed on `$DossierArchiveTemp`.
4. **Comparison**  
   - If `$Hash1` and `$Hash2` are **different**, the script considers this a critical
     integrity error, writes `2` (**ERR_CRITIQUE**) to the status file and exits.
   - If they match, the integrity of the copied data is confirmed.

### 5. Cleanup of Source Folder

Once integrity is confirmed:

- The original files in `$DossierCible` are deleted.
- The script verifies that the folder is really empty; if not, it tries a second deletion.
- If, after the second attempt, files are still present, it writes `1` (**ERR_NON_CRIT**)  
  to the status file and continues (non-blocking issue).

### 6. Compression with 7-Zip

The temporary archive folder is then compressed:

- The script checks that `7z.exe` exists at `$SevenZipPath`.  
  - If not found, it writes `2` (**ERR_CRITIQUE**) and exits.
- The command  
  `7z a -tzip Backup_<date>.zip "<TempFolder>\*"`  
  is executed to create a ZIP archive in `$DossierArchiveTemp`.
- If 7-Zip returns a non-zero exit code, the script logs the error, writes `2` and exits.
- On success, the ZIP file is moved from `$DossierArchiveTemp` to `$DossierArchive`.

### 7. Hash of the Final Archive

To have a final integrity reference:

- A SHA256 hash (`$Hash3`) of the resulting ZIP archive is computed.
- If the hash cannot be calculated (file missing), the script writes `1` (**ERR_NON_CRIT**).
- Otherwise the hash is logged in the transcript for future checks.

### 8. Cleanup of Temporary Folder

After the archive is created:

- All files in `$DossierArchiveTemp` are deleted.
- The script checks that the folder is empty and, if necessary, tries a second cleanup.
- If cleanup still fails, `1` (**ERR_NON_CRIT**) is written to the status file.

### 9. Archive Rotation (Retention)

To avoid unlimited disk usage:

- The script lists all `.zip` files in `$DossierArchive`, sorted by creation date.
- If the number of archives is **greater than** `$ZipFileLimit` (4):
  - It calculates how many old files must be deleted.
  - The oldest archives are removed until only `$ZipFileLimit` remain.
- Each deleted archive is logged in the transcript.

### 10. Final Status for Zabbix

At the very end:

- If no critical error has occurred, the script updates `backup_status.txt` with  
  `3` (**TERMINE_OK**) to indicate a successful run.
- The transcript is stopped with `Stop-Transcript`.

---

## Usage

1. Edit the variables at the top of `powershell_backup_monitoring.ps1`  
   to match your paths and environment.
2. Make sure `7z.exe` is installed and adjust `$SevenZipPath` if needed.
3. Configure a Zabbix item and triggers based on `backup_status.txt`.
4. Optionally, create a scheduled task to run the script at the desired frequency.

This gives you an automated, monitored backup archiving process with clear status
feedback in Zabbix and detailed logs for troubleshooting.
