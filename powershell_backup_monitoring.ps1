# Definition des dossiers et variables
$DossierCible       = "C:\test\"
$DossierArchive     = "C:\archive\"
$DossierArchiveTemp = "C:\archivetemp\"
$Date               = Get-Date -Format "ddMMyyyy_HHmmss"
$DossierZip         = "$DossierArchiveTemp\Backup_$Date.zip"
$DossierZip2        = "$DossierArchive\Backup_$Date.zip"
$LogDirectory       = "$DossierArchive\Logs"
[int]$ZipFileLimit  = 4

# Codes de statut Zabbix
$EN_COURS     = 0  # Script commence
$ERR_NON_CRIT = 1  # Erreur non critique
$ERR_CRITIQUE = 2  # Erreur critique
$TERMINE_OK   = 3  # Fin sans erreur

# S'assurer que le dossier/fichier Zabbix existent
$ZbxFolder = "C:\ZabbixStatus"
$ZbxFile   = "C:\ZabbixStatus\backup_status.txt"
if (-not (Test-Path $ZbxFolder)) { New-Item -ItemType Directory -Path $ZbxFolder | Out-Null }

# valeur neutre au 1er run
if (-not (Test-Path $ZbxFile))   { "9" | Out-File $ZbxFile -Encoding UTF8 }

# Definition de l'encodage des Out-File du script
$PSDefaultParameterValues['Out-File:Encoding'] = 'UTF8'

# Definition du repertoire pour les logs
if (!(Test-Path $LogDirectory))
{
    Write-Host "Dossier log introuvable, creation du dossier..."
    New-Item -ItemType Directory -Path $LogDirectory | Out-Null
}
else
{
    Write-Host "Dossier de logs present"
}

# S'assurer que le dossier d'archives existe aussi
if (!(Test-Path $DossierArchive))
{
    New-Item -ItemType Directory -Path $DossierArchive | Out-Null
}
else
{
    Write-Host "Dossier d'archive present"
}

$LogFile = "$LogDirectory\BackupLog_$Date.txt"
Start-Transcript -Path $LogFile -Append

# Informer Zabbix que le script est en execution
Write-Host "Envoi de l'info de l'execution du script a Zabbix"
$EN_COURS | Out-File $ZbxFile

# Verifier si le dossier cible existe et n'est pas vide
if (-not (Test-Path $DossierCible))
{
    Write-Host "Le dossier n'existe pas : $DossierCible"
    $ERR_NON_CRIT > $ZbxFile
    exit
}
if (-not (Get-ChildItem -Path $DossierCible))
{
    Write-Host "Le dossier est vide : $DossierCible"
    $ERR_NON_CRIT > $ZbxFile
    exit
}
 
# Verifier que le dossier d'Archive temporaire est present
if (!(Test-Path $DossierArchiveTemp))
{
    Write-Host "Le dossier d'archive temporaire introuvable, creation "
    New-Item -ItemType Directory -Path $DossierArchiveTemp | Out-Null
}
else
{
    Write-Host "Dossier d'archive temporaire present"
}

# Calcule du hash avant deplacement du DossierCible
Write-Host "Debut du calcule du hash 1"
$Hash1 = (Get-FileHash -Algorithm SHA256 -Path "$DossierCible*" -ErrorAction SilentlyContinue |
          Sort-Object Path | ForEach-Object Hash) -join ''
Write-Host "Fin du calcule du hash 1"

# Copie du $DossierCible vers le dossier archive temporaire
Write-Host "Debut de copie de $DossierCible vers le dossier archive temporaire"
Copy-Item "$DossierCible*" $DossierArchiveTemp -Recurse -Force
Write-Host "Fin de copie de $DossierCible vers le dossier archive temporaire"

# Calcule du hash apres deplacement du DossierCible
Write-Host "Debut du calcule du hash 2"
$Hash2 = (Get-FileHash -Algorithm SHA256 -Path "$DossierArchiveTemp*" -ErrorAction SilentlyContinue |
          Sort-Object Path | ForEach-Object Hash) -join ''
Write-Host "Fin du calcule du hash 2"

# Comparaison des hash
Write-Host "Debut de la comparaison des hash 1 et 2"
if ($Hash1 -ne $Hash2)
{
    Write-Host "Erreur d'integrite du dossier"
    $ERR_CRITIQUE > $ZbxFile
    exit
}
else 
{
    # Supression du contenu non archive restant du DossierCible
    Write-Host "Integrite du contenu verifiee"
    Remove-Item -Path "$DossierCible*" -Recurse -Force -ErrorAction SilentlyContinue
}

# Verification de la suppression de contenu de $DossierCible
Write-Host "Debut de verification de la suppression de contenu de $DossierCible"
if (Get-ChildItem -Path $DossierCible -ErrorAction SilentlyContinue)
{
    Write-Host "Contenu toujours present dans $DossierCible, 2e tentative de suppression..."
    Remove-Item -Path "$DossierCible*" -Recurse -Force -ErrorAction SilentlyContinue
}
if (Get-ChildItem -Path $DossierCible -ErrorAction SilentlyContinue)
{
    Write-Host "Tentatives de suppression du contenu du $DossierCible echouees"
    $ERR_NON_CRIT > $ZbxFile
}
else
{
    Write-Host "Le dossier $DossierCible a bien ete supprime"
}

# Compresser le contenu du dossier archive temporaire avec 7zip
Write-Host "Compression du dossier archive temporaire avec 7zip"
$SevenZipPath = "C:\Program Files\7-Zip\7z.exe"
if (!(Test-Path $SevenZipPath))
{
    Write-Host "7zip n'est pas trouve a l'emplacement specifie : $SevenZipPath. Arret du script."
    $ERR_CRITIQUE > $ZbxFile
    exit
}
& "$SevenZipPath" a -tzip $DossierZip "$DossierArchiveTemp\*" > $null 2>&1
if ($LastExitCode -ne 0)
{
    Write-Host "Erreur lors de la compression avec 7zip. Arret du script."
    $ERR_CRITIQUE > $ZbxFile
    exit
}
else
{
    Write-Host "Archivage du $DossierZip terminee"
}

# Deplacement du dossier .zip vers le dossier archive
Write-Host "Debut du deplacement du dossier .zip vers le dossier archive"
Move-Item "$DossierZip" $DossierArchive -Force
Write-Host "Fin du deplacement du dossier .zip vers le dossier archive"

# Calcule du hash apres deplacement du dossier .zip (hash du fichier zip lui-meme)
Write-Host "Debut du calcule du hash 1"
$Hash3 = (Get-FileHash -Algorithm SHA256 -Path $DossierZip2).hash
Write-Host "Fin du calcule du hash 1"

# Comparaison des "super-hash"
Write-Host "Debut comparaison des super-hash"
if (-not $Hash3) 
{
    Write-Host "Impossible de calculer le hash du zip (fichier introuvable)"
    $ERR_NON_CRIT > $ZbxFile
} 
else
{
    Write-Host "Hash du zip calcule : $Hash3"
}
Write-Host "Fin comparaison des super-hash"

# Supression du contenu du dossier temporaire
Remove-Item -Path "$DossierArchiveTemp\*" -Recurse -Force -ErrorAction SilentlyContinue

# Verification de la suppression de contenu de $DossierArchiveTemp
if (Get-ChildItem -Path $DossierArchiveTemp -ErrorAction SilentlyContinue)
{
    Write-Host "Contenu toujours present dans $DossierArchiveTemp, 2e tentative de suppression..."
    Remove-Item -Path "$DossierArchiveTemp\*" -Recurse -Force -ErrorAction SilentlyContinue
}
if (Get-ChildItem -Path $DossierArchiveTemp -ErrorAction SilentlyContinue)
{
    Write-Host "Tentatives de suppression du contenu du $DossierArchiveTemp echouees"
    $ERR_NON_CRIT > $ZbxFile
}
 
# Recuperer tous les fichiers .zip presents dans le dossier d'archive et les trier par date de creation
Write-Host "Debut du triage d'archive"
$zipFiles = Get-ChildItem -Path $DossierArchive -Filter *.zip | Sort-Object CreationTime
 
# Si le nombre d'archives est superieur ou egal a 5, supprimer les plus anciens pour n'en conserver que 4
if ($ZipFiles.Count -gt $ZipFileLimit)
{
    # Calculer combien de fichiers doivent etre supprimes pour garder 4 archives
    $filesToDeleteCount = $ZipFiles.Count - $ZipFileLimit
    # Selectionner les plus anciens
    $filesToDelete = $zipFiles | Select-Object -First $filesToDeleteCount
    foreach ($file in $filesToDelete)
    {
         Remove-Item $file.FullName -Force
         Write-Host "Archive supprimee: $($file.Name)"
    }
}
Write-Host "Fin du triage d'archive"

# Confirmer la bonne execution du script sans erreur critique a Zabbix
Write-Host "Mise à jour du fichier Zabbix_Status"
if ($Status -eq 0)
{
    Write-Host "Archivage termine sans erreur"
    $TERMINE_OK | Out-File $ZbxFile
}

Stop-Transcript
