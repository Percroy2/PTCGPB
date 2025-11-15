#SingleInstance Force

; Créer le lock file IMMÉDIATEMENT (AVANT les includes) pour garantir qu'il existe
; Utiliser un label qui s'exécute au démarrage
addonBaseName := "Dashboard_Statistiques"
lockFile := A_Temp . "\PTCGPB_Addon_" . addonBaseName . "_Lock.txt"
currentPID := DllCall("GetCurrentProcessId")
FileDelete, %lockFile%
FileAppend, %currentPID%, %lockFile%

; Fonction pour créer le lock file à la sortie (fallback)
; Définie APRÈS les includes pour éviter les problèmes
CreateLockFileOnExit(ExitReason, ExitCode) {
    global addonBaseName
    lockFile := A_Temp . "\PTCGPB_Addon_" . addonBaseName . "_Lock.txt"
    if (!FileExist(lockFile)) {
        currentPID := DllCall("GetCurrentProcessId")
        FileAppend, %currentPID%, %lockFile%
    }
}

; Configurer OnExit APRÈS les includes pour éviter les problèmes de chargement
; Le lock file est déjà créé au début, donc OnExit n'est qu'un fallback
; Utiliser un timer pour éviter de bloquer le chargement
SetTimer, SetupOnExit, -1

SetupOnExit:
    ; Configurer OnExit après que tout soit chargé
    OnExit, OnExitHandler
return

OnExitHandler:
    ; Appeler la fonction de nettoyage
    CreateLockFileOnExit("", "")
    ; Ne pas appeler ExitApp ici, car OnExit est déjà en cours d'exécution
return

; Inclure ConfigManager et StateManager AVANT Utils.ahk (Utils.ahk en a besoin)
#Include %A_ScriptDir%\..\Include\ConfigManager.ahk
#Include %A_ScriptDir%\..\Include\StateManager.ahk
#Include %A_ScriptDir%\..\Include\Utils.ahk
#Include %A_ScriptDir%\..\Include\NotificationManager.ahk

; Maintenant appeler SetAddonName (qui va recréer le lock file proprement)
; Si SetAddonName existe, l'utiliser, sinon on a déjà créé le lock file
if (IsFunc("SetAddonName")) {
    SetAddonName("Dashboard_Statistiques")
}

; Configuration
updateInterval := ReadConfigInt("UserSettings", "dashboardUpdateInterval", 30000)
dashboardWidth := ReadConfigInt("UserSettings", "dashboardWidth", 450)
dashboardHeight := ReadConfigInt("UserSettings", "dashboardHeight", 600)
enableExport := ReadConfigBool("UserSettings", "dashboardEnableExport", true)
enablePrediction := ReadConfigBool("UserSettings", "dashboardEnablePrediction", true)

; Variables globales
global controlHwnds
startTime := A_TickCount
sessionStartTime := A_Now
dashboardX := 0
dashboardY := 0

; Historique des statistiques (pour prédiction et export)
global StatsHistory := {}
global StatsHistoryMaxSize := 100  ; Garder les 100 dernières entrées

; Prédiction de fin de session
global PredictionData := {}
PredictionData.lastUpdate := 0
PredictionData.estimatedEndTime := ""
PredictionData.estimatedRemainingTime := ""

DebugLog("Addon Dashboard_Statistiques demarre...")

; Formater une durée en texte lisible
FormatTime(duration) {
    hours := Floor(duration / 3600)
    minutes := Floor((duration - (hours * 3600)) / 60)
    seconds := Floor(duration - (hours * 3600) - (minutes * 60))
    
    if (hours > 0) {
        return hours . "h " . minutes . "m " . seconds . "s"
    } else if (minutes > 0) {
        return minutes . "m " . seconds . "s"
    } else {
        return seconds . "s"
    }
}

; Obtenir le nombre de comptes traités pour une instance
GetProcessedAccounts(instanceName) {
    scriptDir := GetScriptRootDir()
    saveDir := scriptDir . "\Accounts\Saved\" . instanceName
    usedAccountsLog := saveDir . "\used_accounts.txt"
    
    processedCount := 0
    if (FileExist(usedAccountsLog)) {
        FileRead, content, %usedAccountsLog%
        if (content) {
            lines := StrSplit(content, "`n", "`r")
            lineCount := lines.MaxIndex()
            Loop, %lineCount% {
                line := Trim(lines[A_Index])
                if (StrLen(line) > 0) {
                    processedCount++
                }
            }
        }
    }
    
    return processedCount
}

; Obtenir le nombre total de comptes pour une instance
GetTotalAccounts(instanceName) {
    scriptDir := GetScriptRootDir()
    saveDir := scriptDir . "\Accounts\Saved\" . instanceName
    listFile := saveDir . "\list.txt"
    
    totalCount := 0
    if (FileExist(listFile)) {
        FileRead, content, %listFile%
        if (content) {
            lines := StrSplit(content, "`n", "`r")
            lineCount := lines.MaxIndex()
            Loop, %lineCount% {
                line := Trim(lines[A_Index])
                if (StrLen(line) >= 5 && InStr(line, "xml")) {
                    totalCount++
                }
            }
        }
    }
    
    return totalCount
}

; Obtenir le nombre de comptes valides pour une instance
GetValidAccounts(instanceName) {
    scriptDir := GetScriptRootDir()
    godPacksDir := scriptDir . "\Accounts\GodPacks"
    
    validCount := 0
    Loop, Files, %godPacksDir%\*_%instanceName%_Valid_*.xml
    {
        validCount++
    }
    
    return validCount
}

; Obtenir le nombre de comptes invalides pour une instance
GetInvalidAccounts(instanceName) {
    scriptDir := GetScriptRootDir()
    godPacksDir := scriptDir . "\Accounts\GodPacks"
    
    invalidCount := 0
    Loop, Files, %godPacksDir%\*_%instanceName%_Invalid_*.xml
    {
        invalidCount++
    }
    
    return invalidCount
}

; Calculer les statistiques
CalculateStatistics() {
    global startTime, sessionStartTime, StatsHistory, StatsHistoryMaxSize
    
    instances := DetectInstances(false, "")
    totalProcessed := 0
    totalRemaining := 0
    totalValid := 0
    totalInvalid := 0
    totalAccounts := 0
    instancesStats := {}
    
    instanceCount := 0
    for k, v in instances {
        instanceCount++
    }
    
    for instanceName, instanceInfo in instances {
        processed := GetProcessedAccounts(instanceName)
        remaining := instanceInfo.counts.remaining
        total := instanceInfo.counts.total
        valid := GetValidAccounts(instanceName)
        invalid := GetInvalidAccounts(instanceName)
        
        totalProcessed += processed
        totalRemaining += remaining
        totalValid += valid
        totalInvalid += invalid
        totalAccounts += total
        
        instancesStats[instanceName] := {}
        instancesStats[instanceName].processed := processed
        instancesStats[instanceName].remaining := remaining
        instancesStats[instanceName].total := total
        instancesStats[instanceName].valid := valid
        instancesStats[instanceName].invalid := invalid
    }
    
    elapsedSeconds := (A_TickCount - startTime) / 1000
    elapsedHours := elapsedSeconds / 3600
    
    accountsPerHour := 0
    if (elapsedHours > 0) {
        accountsPerHour := Round(totalProcessed / elapsedHours, 2)
    }
    
    successRate := 0
    if (totalProcessed > 0) {
        successRate := Round((totalValid / totalProcessed) * 100, 1)
    }
    
    failureRate := 0
    if (totalProcessed > 0) {
        failureRate := Round((totalInvalid / totalProcessed) * 100, 1)
    }
    
    avgTimePerAccount := 0
    if (totalProcessed > 0 && elapsedSeconds > 0) {
        avgTimePerAccount := Round(elapsedSeconds / totalProcessed, 0)
    }
    
    ; Prédiction de fin de session
    estimatedEndTime := ""
    estimatedRemainingTime := ""
    if (enablePrediction && accountsPerHour > 0 && totalRemaining > 0) {
        remainingHours := totalRemaining / accountsPerHour
        estimatedRemainingSeconds := Round(remainingHours * 3600)
        estimatedRemainingTime := FormatTime(estimatedRemainingSeconds)
        
        ; Calculer l'heure de fin estimée
        EnvAdd, estimatedEndTimestamp, %estimatedRemainingSeconds%, Seconds
        FormatTime, estimatedEndTime, %estimatedEndTimestamp%, HH:mm:ss
    }
    
    result := {}
    result.elapsedTime := FormatTime(elapsedSeconds)
    result.accountsPerHour := accountsPerHour
    result.successRate := successRate
    result.failureRate := failureRate
    result.avgTimePerAccount := FormatTime(avgTimePerAccount)
    result.totalProcessed := totalProcessed
    result.totalRemaining := totalRemaining
    result.totalValid := totalValid
    result.totalInvalid := totalInvalid
    result.totalAccounts := totalAccounts
    result.instancesStats := instancesStats
    result.instanceCount := instanceCount
    result.estimatedEndTime := estimatedEndTime
    result.estimatedRemainingTime := estimatedRemainingTime
    result.timestamp := A_Now
    
    ; Ajouter à l'historique
    if (!IsObject(StatsHistory)) {
        StatsHistory := {}
    }
    
    historySize := 0
    for k, v in StatsHistory {
        historySize++
    }
    
    if (historySize >= StatsHistoryMaxSize) {
        ; Supprimer la plus ancienne entrée
        oldestKey := ""
        oldestTime := ""
        for k, v in StatsHistory {
            if (oldestTime = "" || v.timestamp < oldestTime) {
                oldestTime := v.timestamp
                oldestKey := k
            }
        }
        if (oldestKey != "") {
            StatsHistory.Delete(oldestKey)
        }
    }
    
    ; Ajouter la nouvelle entrée
    FormatTime, historyKey, %A_Now%, yyyyMMdd_HHmmss
    StatsHistory[historyKey] := result
    
    ; Mettre à jour StateManager
    SetState("statistics.totalProcessed", totalProcessed)
    SetState("statistics.totalRemaining", totalRemaining)
    SetState("statistics.totalValid", totalValid)
    SetState("statistics.totalInvalid", totalInvalid)
    SetState("statistics.accountsPerHour", accountsPerHour)
    SetState("statistics.successRate", successRate)
    SetState("statistics.failureRate", failureRate)
    SetState("statistics.estimatedEndTime", estimatedEndTime)
    
    return result
}

; Variable globale pour limiter les exports fréquents
global LastExportTime := 0
global MinExportInterval := 60000  ; Minimum 60 secondes entre deux exports

; Exporter les statistiques en CSV
ExportStatisticsToCSV(filePath := "") {
    global StatsHistory, LastExportTime, MinExportInterval
    
    ; Protection contre les exports trop fréquents
    currentTime := A_TickCount
    if (LastExportTime > 0 && (currentTime - LastExportTime) < MinExportInterval) {
        remainingSeconds := Round((MinExportInterval - (currentTime - LastExportTime)) / 1000)
        LogWarning("Export CSV refuse - trop frequent (attendre " . remainingSeconds . "s)", "Dashboard_Statistiques")
        NotifyInfo("Export CSV", "Export refuse - trop frequent (attendre " . remainingSeconds . " secondes)")
        return ""
    }
    
    if (filePath = "") {
        scriptDir := GetScriptRootDir()
        FormatTime, timestamp, %A_Now%, yyyyMMdd_HHmmss
        filePath := scriptDir . "\Exports\statistics_" . timestamp . ".csv"
    }
    
    ; Créer le répertoire s'il n'existe pas
    SplitPath, filePath, , exportDir
    if (!FileExist(exportDir)) {
        FileCreateDir, %exportDir%
    }
    
    ; Nettoyer les anciens fichiers CSV (garder seulement les 10 plus récents)
    CleanOldExportFiles(exportDir, "statistics_*.csv", 10)
    
    ; En-têtes CSV
    csvContent := "Timestamp,Total Processed,Total Remaining,Total Valid,Total Invalid,Accounts Per Hour,Success Rate,Failure Rate,Estimated End Time,Estimated Remaining Time`n"
    
    ; Données
    historyCount := 0
    for historyKey, stats in StatsHistory {
        csvLine := stats.timestamp . "," . stats.totalProcessed . "," . stats.totalRemaining . "," . stats.totalValid . "," . stats.totalInvalid . "," . stats.accountsPerHour . "," . stats.successRate . "," . stats.failureRate . "," . stats.estimatedEndTime . "," . stats.estimatedRemainingTime . "`n"
        csvContent := csvContent . csvLine
        historyCount++
    }
    
    ; Si l'historique est vide, calculer les statistiques actuelles et les exporter
    if (historyCount = 0) {
        DebugLog("ExportStatisticsToCSV - Historique vide, calcul des statistiques actuelles...")
        currentStats := CalculateStatistics()
        if (currentStats) {
            csvLine := currentStats.timestamp . "," . currentStats.totalProcessed . "," . currentStats.totalRemaining . "," . currentStats.totalValid . "," . currentStats.totalInvalid . "," . currentStats.accountsPerHour . "," . currentStats.successRate . "," . currentStats.failureRate . "," . currentStats.estimatedEndTime . "," . currentStats.estimatedRemainingTime . "`n"
            csvContent := csvContent . csvLine
            historyCount := 1
            DebugLog("ExportStatisticsToCSV - Statistiques actuelles calculees et ajoutees")
        }
    }
    
    ; Écrire le fichier seulement s'il y a des données
    if (historyCount > 0) {
        FileDelete, %filePath%
        FileAppend, %csvContent%, %filePath%
        LastExportTime := currentTime
        LogInfo("Statistiques exportees en CSV: " . filePath . " (" . historyCount . " entree(s))", "Dashboard_Statistiques")
        return filePath
    } else {
        LogWarning("Export CSV refuse - aucune donnee disponible", "Dashboard_Statistiques")
        NotifyInfo("Export CSV", "Aucune donnee disponible pour l'export")
        return ""
    }
}

; Nettoyer les anciens fichiers d'export (garder seulement les N plus récents)
CleanOldExportFiles(exportDir, pattern, keepCount := 10) {
    if (!FileExist(exportDir)) {
        return
    }
    
    ; Récupérer tous les fichiers correspondant au pattern
    files := []
    Loop, Files, %exportDir%\%pattern%
    {
        files.Push({name: A_LoopFileName, fullPath: A_LoopFileFullPath, modified: A_LoopFileTimeModified})
    }
    
    ; Si on a plus de fichiers que keepCount, supprimer les plus anciens
    fileCount := 0
    for index, file in files {
        fileCount++
    }
    
    if (fileCount > keepCount) {
        ; Trier les fichiers par date de modification (plus récent en premier)
        ; En AHK v1, on utilise Loop avec A_Index au lieu de for avec :=
        sortedFiles := []
        
        ; Ajouter le premier fichier
        if (fileCount > 0) {
            firstAdded := false
            for index, file in files {
                if (!firstAdded) {
                    sortedFiles.Push(file)
                    firstAdded := true
                    break
                }
            }
        }
        
        ; Insérer les autres fichiers triés par date
        firstSkipped := false
        for index, file in files {
            if (!firstSkipped) {
                firstSkipped := true
                continue  ; On a déjà ajouté le premier
            }
            
            ; Trouver la position d'insertion (tri par date décroissante)
            inserted := false
            
            ; Compter les fichiers déjà triés
            sortedCount := 0
            for sortedIndex, sortedFile in sortedFiles {
                sortedCount++
            }
            
            ; Chercher où insérer ce fichier
            Loop, %sortedCount% {
                sortedIndex := A_Index
                sortedFile := sortedFiles[sortedIndex]
                if (file.modified > sortedFile.modified) {
                    ; Insérer avant sortedFile
                    tempArray := []
                    
                    ; Copier les éléments avant la position d'insertion
                    Loop, % (sortedIndex - 1) {
                        tempArray.Push(sortedFiles[A_Index])
                    }
                    
                    ; Ajouter le nouveau fichier
                    tempArray.Push(file)
                    
                    ; Copier les éléments restants
                    Loop, % (sortedCount - sortedIndex + 1) {
                        tempArray.Push(sortedFiles[sortedIndex + A_Index - 1])
                    }
                    
                    sortedFiles := tempArray
                    inserted := true
                    break
                }
            }
            if (!inserted) {
                sortedFiles.Push(file)
            }
        }
        
        ; Supprimer les fichiers les plus anciens
        deletedCount := 0
        
        ; Compter les fichiers triés
        sortedCount := 0
        for sortedIndex, sortedFile in sortedFiles {
            sortedCount++
        }
        
        ; Supprimer les fichiers au-delà de keepCount
        Loop, %sortedCount% {
            sortedIndex := A_Index
            if (sortedIndex > keepCount) {
                sortedFile := sortedFiles[sortedIndex]
                ; Extraire fullPath dans une variable locale (AHK v1 ne permet pas sortedFile.fullPath directement dans FileDelete)
                filePathToDelete := sortedFile.fullPath
                fileNameToDelete := sortedFile.name
                FileDelete, %filePathToDelete%
                deletedCount++
                LogInfo("Ancien fichier d'export supprime: " . fileNameToDelete, "Dashboard_Statistiques")
            }
        }
        
        if (deletedCount > 0) {
            LogInfo("Nettoyage des exports: " . deletedCount . " ancien(s) fichier(s) supprime(s) (gardes: " . keepCount . ")", "Dashboard_Statistiques")
        }
    }
}

; Exporter les statistiques en JSON (simplifié pour AHK v1)
ExportStatisticsToJSON(filePath := "") {
    global StatsHistory, LastExportTime, MinExportInterval
    
    ; Protection contre les exports trop fréquents
    currentTime := A_TickCount
    if (LastExportTime > 0 && (currentTime - LastExportTime) < MinExportInterval) {
        remainingSeconds := Round((MinExportInterval - (currentTime - LastExportTime)) / 1000)
        LogWarning("Export JSON refuse - trop frequent (attendre " . remainingSeconds . "s)", "Dashboard_Statistiques")
        NotifyInfo("Export JSON", "Export refuse - trop frequent (attendre " . remainingSeconds . " secondes)")
        return ""
    }
    
    if (filePath = "") {
        scriptDir := GetScriptRootDir()
        FormatTime, timestamp, %A_Now%, yyyyMMdd_HHmmss
        filePath := scriptDir . "\Exports\statistics_" . timestamp . ".json"
    }
    
    ; Créer le répertoire s'il n'existe pas
    SplitPath, filePath, , exportDir
    if (!FileExist(exportDir)) {
        FileCreateDir, %exportDir%
    }
    
    ; Nettoyer les anciens fichiers JSON (garder seulement les 10 plus récents)
    CleanOldExportFiles(exportDir, "statistics_*.json", 10)
    
    ; Compter les entrées dans l'historique
    historyCount := 0
    for historyKey, stats in StatsHistory {
        historyCount++
    }
    
    ; Si l'historique est vide, calculer les statistiques actuelles et les exporter
    if (historyCount = 0) {
        DebugLog("ExportStatisticsToJSON - Historique vide, calcul des statistiques actuelles...")
        currentStats := CalculateStatistics()
        if (currentStats) {
            ; Ajouter temporairement les statistiques actuelles à l'historique pour l'export
            FormatTime, tempKey, %A_Now%, yyyyMMdd_HHmmss
            StatsHistory[tempKey] := currentStats
            historyCount := 1
            DebugLog("ExportStatisticsToJSON - Statistiques actuelles calculees et ajoutees")
        }
    }
    
    ; Vérifier qu'il y a des données avant d'exporter
    if (historyCount = 0) {
        LogWarning("Export JSON refuse - aucune donnee disponible", "Dashboard_Statistiques")
        NotifyInfo("Export JSON", "Aucune donnee disponible pour l'export")
        return ""
    }
    
    ; JSON simplifié (format basique pour AHK v1)
    jsonContent := "{`n"
    jsonContent := jsonContent . "  ""timestamp"": """ . A_Now . """,`n"
    jsonContent := jsonContent . "  ""statistics"": [`n"
    
    firstEntry := true
    for historyKey, stats in StatsHistory {
        if (!firstEntry) {
            jsonContent := jsonContent . ",`n"
        }
        firstEntry := false
        
        jsonContent := jsonContent . "    {`n"
        jsonContent := jsonContent . "      ""timestamp"": """ . stats.timestamp . """,`n"
        jsonContent := jsonContent . "      ""totalProcessed"": " . stats.totalProcessed . ",`n"
        jsonContent := jsonContent . "      ""totalRemaining"": " . stats.totalRemaining . ",`n"
        jsonContent := jsonContent . "      ""totalValid"": " . stats.totalValid . ",`n"
        jsonContent := jsonContent . "      ""totalInvalid"": " . stats.totalInvalid . ",`n"
        jsonContent := jsonContent . "      ""accountsPerHour"": " . stats.accountsPerHour . ",`n"
        jsonContent := jsonContent . "      ""successRate"": " . stats.successRate . ",`n"
        jsonContent := jsonContent . "      ""failureRate"": " . stats.failureRate . ",`n"
        jsonContent := jsonContent . "      ""estimatedEndTime"": """ . stats.estimatedEndTime . """,`n"
        jsonContent := jsonContent . "      ""estimatedRemainingTime"": """ . stats.estimatedRemainingTime . """`n"
        jsonContent := jsonContent . "    }"
    }
    
    jsonContent := jsonContent . "`n  ]`n"
    jsonContent := jsonContent . "}`n"
    
    ; Écrire le fichier
    FileDelete, %filePath%
    FileAppend, %jsonContent%, %filePath%
    LastExportTime := currentTime
    
    LogInfo("Statistiques exportees en JSON: " . filePath . " (" . historyCount . " entrees)", "Dashboard_Statistiques")
    return filePath
}

; Créer le dashboard
CreateDashboard() {
    global dashboardWidth, dashboardHeight, dashboardX, dashboardY, controlHwnds, enablePrediction
    
    controlHwnds := {}
    
    DebugLog("CreateDashboard - Creation de la fenetre GUI...")
    Gui, Dashboard:New, +ToolWindow -Caption +LastFound +AlwaysOnTop
    Gui, Dashboard:Color, 1E1E1E
    Gui, Dashboard:Font, s10 cFFFFFF Bold, Segoe UI
    Gui, Dashboard:Add, Text, x10 y10 w430 Center, Dashboard Statistiques
    
    Gui, Dashboard:Font, s8 cFFFFFF Norm, Segoe UI
    yPos := 40
    
    Gui, Dashboard:Add, Text, x10 y%yPos% w430, Temps d'execution: 
    yPos += 25
    
    Gui, Dashboard:Add, Text, x10 y%yPos% w430, Comptes traites/heure: 
    yPos += 25
    
    Gui, Dashboard:Add, Text, x10 y%yPos% w430, Vitesse moyenne: 
    yPos += 25
    
    Gui, Dashboard:Add, Text, x10 y%yPos% w430, Taux de succes: 
    yPos += 25
    
    Gui, Dashboard:Add, Text, x10 y%yPos% w430, Taux d'echec: 
    yPos += 35
    
    Gui, Dashboard:Add, Text, x10 y%yPos% w430, Total traites: 
    yPos += 25
    
    Gui, Dashboard:Add, Text, x10 y%yPos% w430, Total restants: 
    yPos += 25
    
    Gui, Dashboard:Add, Text, x10 y%yPos% w430, Valides: 
    yPos += 25
    
    Gui, Dashboard:Add, Text, x10 y%yPos% w430, Invalides: 
    yPos += 35
    
    ; Prédiction de fin de session (si activée)
    if (enablePrediction) {
        Gui, Dashboard:Font, s9 cFFFFFF Bold, Segoe UI
        Gui, Dashboard:Add, Text, x10 y%yPos% w430, Prediction:
        yPos += 25
        
        Gui, Dashboard:Font, s8 cFFFFFF Norm, Segoe UI
        Gui, Dashboard:Add, Text, x10 y%yPos% w430, Temps restant estime: 
        yPos += 25
        
        Gui, Dashboard:Add, Text, x10 y%yPos% w430, Heure de fin estimee: 
        yPos += 35
    }
    
    Gui, Dashboard:Font, s9 cFFFFFF Bold, Segoe UI
    Gui, Dashboard:Add, Text, x10 y%yPos% w430, Comptes par instance:
    yPos += 25
    
    Gui, Dashboard:Font, s8 cFFFFFF Norm, Segoe UI
    Gui, Dashboard:Add, Text, x10 y%yPos% w430 vInstancesList,
    yPos += 50
    
    ; Boutons d'export
    if (enableExport) {
        Gui, Dashboard:Font, s8 cFFFFFF Norm, Segoe UI
        Gui, Dashboard:Add, Button, x10 y%yPos% w100 h25 gExportCSV, Export CSV
        Gui, Dashboard:Add, Button, x120 y%yPos% w100 h25 gExportJSON, Export JSON
        yPos += 35
    }
    
    ; Ajuster la hauteur du dashboard
    dashboardHeight := yPos + 20
    
    SysGet, screenWidth, 78
    SysGet, screenHeight, 79
    
    dashboardX := screenWidth - dashboardWidth - 10
    dashboardY := 10
    
    Gui, Dashboard:Show, x%dashboardX% y%dashboardY% w%dashboardWidth% h%dashboardHeight%, Dashboard_Statistiques
    SmartSleep(100, 200)
    
    WinGet, guiHwnd, ID, Dashboard_Statistiques
    if (guiHwnd) {
        ; Récupérer les handles des contrôles
        ControlGet, tempHwnd, Hwnd,, Static2, ahk_id %guiHwnd%
        controlHwnds["TimeElapsed"] := tempHwnd
        ControlGet, tempHwnd, Hwnd,, Static3, ahk_id %guiHwnd%
        controlHwnds["AccountsPerHour"] := tempHwnd
        ControlGet, tempHwnd, Hwnd,, Static4, ahk_id %guiHwnd%
        controlHwnds["AvgTime"] := tempHwnd
        ControlGet, tempHwnd, Hwnd,, Static5, ahk_id %guiHwnd%
        controlHwnds["SuccessRate"] := tempHwnd
        ControlGet, tempHwnd, Hwnd,, Static6, ahk_id %guiHwnd%
        controlHwnds["FailureRate"] := tempHwnd
        ControlGet, tempHwnd, Hwnd,, Static7, ahk_id %guiHwnd%
        controlHwnds["TotalProcessed"] := tempHwnd
        ControlGet, tempHwnd, Hwnd,, Static8, ahk_id %guiHwnd%
        controlHwnds["TotalRemaining"] := tempHwnd
        ControlGet, tempHwnd, Hwnd,, Static9, ahk_id %guiHwnd%
        controlHwnds["TotalValid"] := tempHwnd
        ControlGet, tempHwnd, Hwnd,, Static10, ahk_id %guiHwnd%
        controlHwnds["TotalInvalid"] := tempHwnd
        
        if (enablePrediction) {
            ControlGet, tempHwnd, Hwnd,, Static12, ahk_id %guiHwnd%
            controlHwnds["EstimatedRemainingTime"] := tempHwnd
            ControlGet, tempHwnd, Hwnd,, Static13, ahk_id %guiHwnd%
            controlHwnds["EstimatedEndTime"] := tempHwnd
        }
        
        ControlGet, tempHwnd, Hwnd,, Static14, ahk_id %guiHwnd%
        controlHwnds["InstancesList"] := tempHwnd
        
        DebugLog("CreateDashboard - HWND recuperes")
    } else {
        LogError("CreateDashboard - ERREUR: guiHwnd non trouve", "Dashboard_Statistiques")
    }
    
    DebugLog("CreateDashboard - Fenetre affichee a x=" . dashboardX . " y=" . dashboardY)
}

; Mettre à jour le dashboard
UpdateDashboard() {
    global controlHwnds, enablePrediction
    
    dashboardHwnd := WinExist("Dashboard_Statistiques")
    if (!dashboardHwnd) {
        DebugLog("UpdateDashboard - Dashboard n'existe pas encore")
        return
    }
    
    stats := CalculateStatistics()
    
    lang := GetLanguage()
    timeLabel := (lang = "FR") ? "Temps d'execution: " : (lang = "IT") ? "Tempo di esecuzione: " : (lang = "CH") ? "运行时间: " : "Execution time: "
    accountsPerHourLabel := (lang = "FR") ? "Comptes traites/heure: " : (lang = "IT") ? "Account processati/ora: " : (lang = "CH") ? "每小时处理账户: " : "Accounts processed/hour: "
    avgTimeLabel := (lang = "FR") ? "Vitesse moyenne: " : (lang = "IT") ? "Velocita media: " : (lang = "CH") ? "平均速度: " : "Average speed: "
    successRateLabel := (lang = "FR") ? "Taux de succes: " : (lang = "IT") ? "Tasso di successo: " : (lang = "CH") ? "成功率: " : "Success rate: "
    failureRateLabel := (lang = "FR") ? "Taux d'echec: " : (lang = "IT") ? "Tasso di fallimento: " : (lang = "CH") ? "失败率: " : "Failure rate: "
    totalProcessedLabel := (lang = "FR") ? "Total traites: " : (lang = "IT") ? "Total processati: " : (lang = "CH") ? "总处理: " : "Total processed: "
    totalRemainingLabel := (lang = "FR") ? "Total restants: " : (lang = "IT") ? "Total rimanenti: " : (lang = "CH") ? "总剩余: " : "Total remaining: "
    validLabel := (lang = "FR") ? "Valides: " : (lang = "IT") ? "Validi: " : (lang = "CH") ? "有效: " : "Valid: "
    invalidLabel := (lang = "FR") ? "Invalides: " : (lang = "IT") ? "Non validi: " : (lang = "CH") ? "无效: " : "Invalid: "
    estimatedRemainingLabel := (lang = "FR") ? "Temps restant estime: " : (lang = "IT") ? "Tempo rimanente stimato: " : (lang = "CH") ? "预计剩余时间: " : "Estimated remaining time: "
    estimatedEndLabel := (lang = "FR") ? "Heure de fin estimee: " : (lang = "IT") ? "Ora di fine stimata: " : (lang = "CH") ? "预计结束时间: " : "Estimated end time: "
    
    if (WinExist("Dashboard_Statistiques") && controlHwnds.HasKey("TimeElapsed")) {
        ; Mettre à jour les contrôles
        ; En AutoHotkey v1, on ne peut pas utiliser controlHwnds["key"] directement dans une commande
        ; Il faut d'abord extraire la valeur dans une variable locale
        if (controlHwnds.HasKey("TimeElapsed")) {
            timeElapsedHwnd := controlHwnds["TimeElapsed"]
            ControlSetText,, % timeLabel . stats.elapsedTime, ahk_id %timeElapsedHwnd%
        }
        if (controlHwnds.HasKey("AccountsPerHour")) {
            accountsPerHourHwnd := controlHwnds["AccountsPerHour"]
            ControlSetText,, % accountsPerHourLabel . stats.accountsPerHour, ahk_id %accountsPerHourHwnd%
        }
        if (controlHwnds.HasKey("AvgTime")) {
            avgTimeHwnd := controlHwnds["AvgTime"]
            ControlSetText,, % avgTimeLabel . stats.avgTimePerAccount . " / compte", ahk_id %avgTimeHwnd%
        }
        if (controlHwnds.HasKey("SuccessRate")) {
            successRateHwnd := controlHwnds["SuccessRate"]
            ControlSetText,, % successRateLabel . stats.successRate . "%", ahk_id %successRateHwnd%
        }
        if (controlHwnds.HasKey("FailureRate")) {
            failureRateHwnd := controlHwnds["FailureRate"]
            ControlSetText,, % failureRateLabel . stats.failureRate . "%", ahk_id %failureRateHwnd%
        }
        if (controlHwnds.HasKey("TotalProcessed")) {
            totalProcessedHwnd := controlHwnds["TotalProcessed"]
            ControlSetText,, % totalProcessedLabel . stats.totalProcessed, ahk_id %totalProcessedHwnd%
        }
        if (controlHwnds.HasKey("TotalRemaining")) {
            totalRemainingHwnd := controlHwnds["TotalRemaining"]
            ControlSetText,, % totalRemainingLabel . stats.totalRemaining, ahk_id %totalRemainingHwnd%
        }
        if (controlHwnds.HasKey("TotalValid")) {
            totalValidHwnd := controlHwnds["TotalValid"]
            ControlSetText,, % validLabel . stats.totalValid, ahk_id %totalValidHwnd%
        }
        if (controlHwnds.HasKey("TotalInvalid")) {
            totalInvalidHwnd := controlHwnds["TotalInvalid"]
            ControlSetText,, % invalidLabel . stats.totalInvalid, ahk_id %totalInvalidHwnd%
        }
        
        ; Prédiction
        if (enablePrediction) {
            if (controlHwnds.HasKey("EstimatedRemainingTime")) {
                estimatedRemainingTimeHwnd := controlHwnds["EstimatedRemainingTime"]
                if (stats.estimatedRemainingTime != "") {
                    ControlSetText,, % estimatedRemainingLabel . stats.estimatedRemainingTime, ahk_id %estimatedRemainingTimeHwnd%
                } else {
                    ControlSetText,, % estimatedRemainingLabel . "N/A", ahk_id %estimatedRemainingTimeHwnd%
                }
            }
            if (controlHwnds.HasKey("EstimatedEndTime")) {
                estimatedEndTimeHwnd := controlHwnds["EstimatedEndTime"]
                if (stats.estimatedEndTime != "") {
                    ControlSetText,, % estimatedEndLabel . stats.estimatedEndTime, ahk_id %estimatedEndTimeHwnd%
                } else {
                    ControlSetText,, % estimatedEndLabel . "N/A", ahk_id %estimatedEndTimeHwnd%
                }
            }
        }
        
        ; Liste des instances
        instancesText := ""
        for instanceName, instanceStats in stats.instancesStats {
            instancesText := instancesText . instanceName . ": " . instanceStats.processed . " traites, " . instanceStats.remaining . " restants`n"
        }
        
        if (instancesText = "") {
            instancesText := (lang = "FR") ? "Aucune instance detectee" : (lang = "IT") ? "Nessuna istanza rilevata" : (lang = "CH") ? "未检测到实例" : "No instances detected"
        }
        
        if (controlHwnds.HasKey("InstancesList")) {
            instancesListHwnd := controlHwnds["InstancesList"]
            ControlSetText,, % instancesText, ahk_id %instancesListHwnd%
        }
    }
}

; Initialisation
Initialize() {
    global updateInterval
    
    DebugLog("Initialize - DEBUT de la fonction")
    
    if (WinExist("Dashboard_Statistiques")) {
        DebugLog("Initialize - Dashboard existe deja, destruction de l'ancien...")
        Gui, Dashboard:Destroy
        SmartSleep(500, 1000)
    }
    
    SmartSleep(2000, 3000)
    
    DebugLog("Initialize - Creation du dashboard...")
    CreateDashboard()
    DebugLog("Initialize - Dashboard cree, mise a jour des statistiques...")
    UpdateDashboard()
    DebugLog("Initialize - Dashboard initialise et timer configure (intervalle: " . updateInterval . "ms)")
    
    SetTimer, UpdateDashboardTimer, %updateInterval%
    DebugLog("Initialize - FIN de la fonction")
}

; Handlers pour les boutons d'export
ExportCSV:
    ; Forcer un calcul des statistiques avant l'export pour s'assurer qu'il y a des données
    stats := CalculateStatistics()
    filePath := ExportStatisticsToCSV()
    if (filePath != "") {
        NotifyInfo("Export CSV", "Statistiques exportees: " . filePath)
    } else {
        ; Le message d'erreur est déjà affiché par ExportStatisticsToCSV
    }
return

ExportJSON:
    ; Forcer un calcul des statistiques avant l'export pour s'assurer qu'il y a des données
    stats := CalculateStatistics()
    filePath := ExportStatisticsToJSON()
    if (filePath != "") {
        NotifyInfo("Export JSON", "Statistiques exportees: " . filePath)
    } else {
        ; Le message d'erreur est déjà affiché par ExportStatisticsToJSON
    }
return

DebugLog("Script - Demarrage, configuration du timer InitTimer")
SetTimer, UpdateDashboardTimer, Off
SetTimer, InitTimer, -100

; Utiliser un goto pour sauter les labels au chargement et continuer l'exécution normale
goto SkipLabelsAtStart

UpdateDashboardTimer:
    UpdateDashboard()
return

InitTimer:
    DebugLog("InitTimer - Label declenche, appel de Initialize()")
    Initialize()
    DebugLog("InitTimer - Initialize() termine")
return

SkipLabelsAtStart:
; Script prêt

^+d::
    Gui, Dashboard:Destroy
    ExitApp
return

GuiClose:
    ExitApp
return

