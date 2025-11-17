#SingleInstance Force

; Créer le lock file IMMÉDIATEMENT (AVANT les includes) pour garantir qu'il existe
; Utiliser un label qui s'exécute au démarrage
addonBaseName := "AutoRelance_Instances"
lockFile := A_Temp . "\PTCGPB_Addon_" . addonBaseName . "_Lock.txt"
currentPID := DllCall("GetCurrentProcessId")
FileDelete, %lockFile%
FileAppend, %currentPID%, %lockFile%

; Fonction pour nettoyer le lock file à la sortie (fallback)
CreateLockFileOnExit(ExitReason, ExitCode) {
    global addonBaseName
    lockFile := A_Temp . "\PTCGPB_Addon_" . addonBaseName . "_Lock.txt"
    if (FileExist(lockFile)) {
        ; Vérifier que le PID correspond avant de supprimer
        FileRead, lockPID, %lockFile%
        currentPID := DllCall("GetCurrentProcessId")
        if (lockPID = currentPID) {
            FileDelete, %lockFile%
        }
    }
    ; Nettoyer aussi via CleanupAddonLockFile si disponible (depuis Utils.ahk)
    if (IsFunc("CleanupAddonLockFile")) {
        CleanupAddonLockFile("", "")
    }
}

; Inclure ConfigManager et StateManager AVANT Utils.ahk (Utils.ahk en a besoin)
#Include %A_ScriptDir%\..\Include\ConfigManager.ahk
#Include %A_ScriptDir%\..\Include\StateManager.ahk
#Include %A_ScriptDir%\..\Include\Utils.ahk
#Include %A_ScriptDir%\..\Include\NotificationManager.ahk

; Maintenant appeler SetAddonName (qui va recréer le lock file proprement)
; Si SetAddonName existe, l'utiliser, sinon on a déjà créé le lock file
if (IsFunc("SetAddonName")) {
    SetAddonName("AutoRelance_Instances")
}

; Configuration
checkInterval := ReadConfigInt("UserSettings", "autoRelanceCheckInterval", 30000)
minTimeBeforeRelance := ReadConfigInt("UserSettings", "autoRelanceMinTime", 60)
instanceLaunchDelay := ReadConfigInt("UserSettings", "instanceLaunchDelay", 5)

; Configuration pour la détection CPU (détection d'instances figées)
enableCPUMonitoring := ReadConfigBool("UserSettings", "autoRelanceEnableCPUMonitoring", true)
minCPUThreshold := ReadConfigFloat("UserSettings", "autoRelanceMinCPUThreshold", 0.1)  ; 0.1% minimum
cpuSampleInterval := ReadConfigInt("UserSettings", "autoRelanceCPUSampleInterval", 2000)  ; 2 secondes
cpuSampleCount := ReadConfigInt("UserSettings", "autoRelanceCPUSampleCount", 3)  ; 3 échantillons

; Variables globales
instancesStatus := {}  ; Stocke le statut de chaque instance
lastCheckTime := {}    ; Stocke la dernière fois qu'on a vérifié chaque instance
relanceCount := {}     ; Compte le nombre de relances par instance
relanceHistory := {}   ; Historique des relances (pour backoff adaptatif)
errorTypes := {}       ; Types d'erreurs détectées
mumuFolder := ""

DebugLog("Addon AutoRelance_Instances demarre...")

; Initialisation
Initialize() {
    global mumuFolder, checkInterval
    
    DebugLog("Initialize - Debut de l'initialisation...")
    
    ; Utiliser ConfigManager
    totalInstances := ReadConfigInt("UserSettings", "Instances", 1)
    folderPath := ReadConfigString("UserSettings", "folderPath", "C:\Program Files\Netease")
    
    DebugLog("Initialize - Configuration lue: " . totalInstances . " instances, dossier: " . folderPath)
    
    mumuFolder := folderPath . "\MuMuPlayerGlobal-12.0"
    if !FileExist(mumuFolder)
        mumuFolder := folderPath . "\MuMu Player 12"
    
    if (!FileExist(mumuFolder)) {
        LogError("Dossier MuMu introuvable: " . mumuFolder, "AutoRelance_Instances")
        return false
    }
    
    DebugLog("Initialize - Dossier MuMu trouve: " . mumuFolder)
    
    ; Initialiser le statut de toutes les instances
    Loop, %totalInstances% {
        instanceNum := A_Index
        instancesStatus[instanceNum] := "unknown"
        lastCheckTime[instanceNum] := 0
        relanceCount[instanceNum] := 0
        relanceHistory[instanceNum] := ""
        errorTypes[instanceNum] := ""
    }
    
    DebugLog("Initialize - Statut des instances initialise pour " . totalInstances . " instances")
    
    ; Démarrer le timer de vérification
    DebugLog("Initialize - Configuration du timer avec intervalle: " . checkInterval . "ms")
    SetTimer, CheckInstancesTimer, %checkInterval%
    SetTimer, CheckInstancesTimer, On
    
    ; Première vérification immédiate
    DebugLog("Initialize - Premiere verification immediate...")
    GoSub, CheckInstancesTimer
    
    DebugLog("Initialize - Initialisation terminee avec succes, timer actif")
    return true
}

; Timer pour vérifier les instances
CheckInstancesTimer:
    CheckAllInstances()
return

; Fonction principale de vérification
CheckAllInstances() {
    global instancesStatus, lastCheckTime, checkInterval, minTimeBeforeRelance
    
    totalInstances := ReadConfigInt("UserSettings", "Instances", 1)
    
    Loop, %totalInstances% {
        instanceNum := A_Index
        CheckInstance(instanceNum)
    }
}

; Vérifie le statut d'une instance spécifique avec détection intelligente
CheckInstance(instanceNum) {
    global instancesStatus, lastCheckTime, minTimeBeforeRelance, mumuFolder, relanceCount, relanceHistory, errorTypes
    global enableCPUMonitoring, minCPUThreshold, cpuSampleInterval, cpuSampleCount
    
    scriptName := instanceNum . ".ahk"
    scriptPath := GetScriptRootDir() . "\Scripts\" . scriptName
    
    ; Vérifier si le script existe
    if (!FileExist(scriptPath)) {
        DebugLog("Instance " . instanceNum . ": Script introuvable, ignore")
        return
    }
    
    ; Détection intelligente : vérifier le processus et la fenêtre
    scriptRunning := IsScriptRunning(scriptName)
    mumuRunning := IsMumuInstanceRunning(instanceNum)
    processRunning := IsProcessRunning(scriptName)
    
    ; Détection avancée : vérifier si le processus est bloqué/zombie
    processHealthy := true
    if (processRunning) {
        processHealthy := IsProcessHealthy(scriptName)
    }
    
    ; Détection CPU : vérifier si l'instance est figée (CPU trop bas)
    cpuFrozen := false
    cpuFrozenReason := ""
    avgCPU := 0
    if (enableCPUMonitoring && scriptRunning && mumuRunning && processHealthy) {
        ; Obtenir les PIDs
        scriptPID := GetScriptProcessPID(scriptName)
        mumuPID := GetMumuProcessPID(instanceNum)
        
        ; Vérifier le CPU du script d'abord
        if (scriptPID > 0) {
            cpuMonitor := MonitorProcessCPU(scriptPID, cpuSampleInterval, cpuSampleCount, minCPUThreshold)
            if (cpuMonitor.frozen) {
                cpuFrozen := true
                cpuFrozenReason := "script_cpu_frozen (avg: " . Round(cpuMonitor.avgCPU, 2) . "%, seuil: " . minCPUThreshold . "%)"
                avgCPU := cpuMonitor.avgCPU
                LogWarning("Instance " . instanceNum . ": Script CPU figé (avg: " . Round(avgCPU, 2) . "%, seuil: " . minCPUThreshold . "%)", "AutoRelance_Instances")
            }
        }
        
        ; Vérifier le CPU de MuMu si le script semble OK
        if (!cpuFrozen && mumuPID > 0) {
            cpuMonitor := MonitorProcessCPU(mumuPID, cpuSampleInterval, cpuSampleCount, minCPUThreshold)
            if (cpuMonitor.frozen) {
                cpuFrozen := true
                cpuFrozenReason := "mumu_cpu_frozen (avg: " . Round(cpuMonitor.avgCPU, 2) . "%, seuil: " . minCPUThreshold . "%)"
                avgCPU := cpuMonitor.avgCPU
                LogWarning("Instance " . instanceNum . ": MuMu CPU figé (avg: " . Round(avgCPU, 2) . "%, seuil: " . minCPUThreshold . "%)", "AutoRelance_Instances")
            }
        }
    }
    
    currentStatus := ""
    errorType := ""
    
    if (cpuFrozen) {
        currentStatus := "cpu_frozen"
        errorType := cpuFrozenReason
    } else if (scriptRunning && mumuRunning && processHealthy) {
        currentStatus := "running"
    } else if (!scriptRunning && !mumuRunning) {
        currentStatus := "stopped"
        errorType := "both_stopped"
    } else if (!scriptRunning && mumuRunning) {
        currentStatus := "script_stopped"
        errorType := "script_crashed"
    } else if (scriptRunning && !mumuRunning) {
        currentStatus := "mumu_stopped"
        errorType := "mumu_crashed"
    } else if (!processHealthy) {
        currentStatus := "process_unhealthy"
        errorType := "process_zombie"
    }
    
    previousStatus := instancesStatus[instanceNum]
    
    ; S'assurer que errorType n'est pas vide pour le calcul du backoff
    if (errorType = "" || errorType = "unknown") {
        errorType := currentStatus
    }
    
    ; Si le statut a changé, logger et mettre à jour
    if (previousStatus != currentStatus) {
        LogInfo("Instance " . instanceNum . ": Statut change de '" . previousStatus . "' a '" . currentStatus . "' (erreur: " . errorType . ")", "AutoRelance_Instances")
        instancesStatus[instanceNum] := currentStatus
        errorTypes[instanceNum] := errorType
        
        ; Mettre à jour StateManager
        SetState("instances." . instanceNum . ".status", currentStatus)
        SetState("instances." . instanceNum . ".errorType", errorType)
        
        ; Ne PAS réinitialiser lastCheckTime automatiquement lors d'un changement de statut
        ; La relance sera gérée par la logique ci-dessous qui vérifie le temps écoulé
        ; Cela évite les relances en boucle
        ; Si on passe de "running" à un état d'erreur, lastCheckTime sera déjà à 0 (initialisation)
        ; Si on change d'un type d'erreur à un autre, on garde lastCheckTime pour éviter les relances multiples
    }
    
    ; Si l'instance est arrêtée ou problématique, vérifier si on doit la relancer
    if (currentStatus != "running") {
        currentTime := A_TickCount
        lastCheck := lastCheckTime[instanceNum]
        
        ; Utiliser errorType de l'instance stocké si disponible (plus fiable que la variable locale)
        if (errorTypes.HasKey(instanceNum) && errorTypes[instanceNum] != "") {
            errorType := errorTypes[instanceNum]
        }
        
        ; Calculer le backoff adaptatif
        backoffTime := CalculateBackoffTime(instanceNum, errorType)
        requiredTime := (minTimeBeforeRelance * 1000) + backoffTime
        
        ; Debug: logger les valeurs pour diagnostic
        DebugLog("Instance " . instanceNum . ": Backoff calcule - base: " . (minTimeBeforeRelance * 1000) . "ms, backoff: " . backoffTime . "ms, total: " . requiredTime . "ms, lastCheck: " . lastCheck . ", elapsed: " . (currentTime - lastCheck) . "ms")
        
        ; Vérifier si assez de temps s'est écoulé
        ; Protection contre les relances multiples : ne pas relancer si on a déjà relancé il y a moins de 10 secondes
        ; Cela évite les relances en boucle en cas de bug
        minRelanceInterval := 10000  ; 10 secondes minimum entre deux relances
        
        ; Calculer le temps écoulé depuis la dernière relance
        if (lastCheck > 0) {
            timeSinceLastRelance := currentTime - lastCheck
        } else {
            timeSinceLastRelance := 999999  ; Première relance, pas de limite
        }
        
        ; Vérifier si on peut relancer
        canRelance := (lastCheck = 0 || (currentTime - lastCheck) >= requiredTime) && timeSinceLastRelance >= minRelanceInterval
        
        if (canRelance) {
            LogWarning("Instance " . instanceNum . ": Detection d'un probleme (" . currentStatus . " - " . errorType . "), tentative de relance...", "AutoRelance_Instances")
            lastCheckTime[instanceNum] := currentTime
            
            ; Enregistrer dans l'historique
            FormatTime, timestamp, %A_Now%, yyyy-MM-dd HH:mm:ss
            historyEntry := timestamp . "|" . errorType . "|" . currentStatus
            if (relanceHistory[instanceNum] = "") {
                relanceHistory[instanceNum] := historyEntry
            } else {
                relanceHistory[instanceNum] := relanceHistory[instanceNum] . "`n" . historyEntry
            }
            
            ; Relancer l'instance
            success := RelanceInstance(instanceNum, errorType)
            
            if (success) {
                ; Initialiser le compteur si nécessaire
                if (!relanceCount.HasKey(instanceNum)) {
                    relanceCount[instanceNum] := 0
                }
                relanceCount[instanceNum]++
                SetState("instances." . instanceNum . ".relanceCount", relanceCount[instanceNum])
                
                ; Notification
                totalRelances := relanceCount[instanceNum]
                NotifyWarning("Instance relancée", "Instance " . instanceNum . " a été relancée (erreur: " . errorType . ", total relances: " . totalRelances . ")")
            }
        } else {
            remainingTime := (requiredTime - (currentTime - lastCheck)) / 1000
            ; S'assurer que remainingTime n'est pas négatif (peut arriver si lastCheck a été mis à jour entre-temps)
            if (remainingTime < 0) {
                remainingTime := 0
            }
            DebugLog("Instance " . instanceNum . ": Attente backoff (" . Round(remainingTime) . "s restantes)")
        }
    } else if (currentStatus = "running") {
        ; Réinitialiser le compteur si l'instance fonctionne
        lastCheckTime[instanceNum] := 0
        errorTypes[instanceNum] := ""
    }
}

; Calculer le temps de backoff adaptatif selon le type d'erreur
CalculateBackoffTime(instanceNum, errorType) {
    global relanceCount, errorTypes
    
    baseBackoff := 0
    
    ; Backoff selon le type d'erreur
    if (InStr(errorType, "cpu_frozen")) {
        baseBackoff := 60000  ; 60 secondes pour instance figée (CPU trop bas)
    } else if (errorType = "process_zombie") {
        baseBackoff := 30000  ; 30 secondes pour processus zombie
    } else if (errorType = "script_crashed") {
        baseBackoff := 15000  ; 15 secondes pour crash de script
    } else if (errorType = "mumu_crashed") {
        baseBackoff := 20000  ; 20 secondes pour crash MuMu
    } else if (errorType = "both_stopped") {
        baseBackoff := 10000  ; 10 secondes pour arrêt complet
    }
    
    ; Backoff exponentiel selon le nombre de relances
    relances := relanceCount[instanceNum]
    if (relances > 0) {
        exponentialBackoff := (relances * relances) * 5000  ; 5s, 20s, 45s, 80s...
        baseBackoff := baseBackoff + exponentialBackoff
    }
    
    ; Limiter le backoff maximum à 5 minutes
    maxBackoff := 300000
    if (baseBackoff > maxBackoff) {
        baseBackoff := maxBackoff
    }
    
    return baseBackoff
}

; Vérifie si un script AutoHotkey est en cours d'exécution
IsScriptRunning(scriptName) {
    DetectHiddenWindows, On
    WinGet, IDList, List, ahk_class AutoHotkey
    Loop %IDList%
    {
        ID := IDList%A_Index%
        WinGetTitle, ATitle, ahk_id %ID%
        if (InStr(ATitle, "\" . scriptName)) {
            return true
        }
    }
    return false
}

; Vérifie si un processus est en cours d'exécution (plus fiable que la fenêtre)
IsProcessRunning(scriptName) {
    Process, Exist, %scriptName%
    return (ErrorLevel > 0)
}

; Vérifie si un processus est sain (pas zombie/bloqué)
IsProcessHealthy(scriptName) {
    ; Vérifier si le processus répond (simplifié)
    ; En AHK, on peut vérifier si le processus existe et a une fenêtre
    Process, Exist, %scriptName%
    if (ErrorLevel = 0) {
        return false
    }
    
    ; Vérifier si une fenêtre existe pour ce processus
    DetectHiddenWindows, On
    WinGet, IDList, List, ahk_class AutoHotkey
    foundWindow := false
    Loop %IDList%
    {
        ID := IDList%A_Index%
        WinGetTitle, ATitle, ahk_id %ID%
        if (InStr(ATitle, "\" . scriptName)) {
            foundWindow := true
            break
        }
    }
    
    return foundWindow
}

; Vérifie si une instance MuMu est en cours d'exécution
IsMumuInstanceRunning(instanceNum) {
    ret := WinExist(instanceNum)
    return (ret != 0)
}

; Relance une instance avec gestion d'erreur améliorée
RelanceInstance(instanceNum, errorType := "") {
    global mumuFolder, instanceLaunchDelay
    
    scriptName := instanceNum . ".ahk"
    scriptPath := GetScriptRootDir() . "\Scripts\" . scriptName
    
    LogInfo("RelanceInstance " . instanceNum . ": Debut de la relance (erreur: " . errorType . ")", "AutoRelance_Instances")
    
    ; Tuer le script s'il existe encore
    killed := KillScript(scriptName)
    if (killed > 0) {
        LogInfo("RelanceInstance " . instanceNum . ": Script " . killed . " processus(s) tue(s)", "AutoRelance_Instances")
        SmartSleep(2000, 5000)
    } else {
        ; Essayer aussi de tuer via le processus directement (pour les processus figés)
        Process, Exist, %scriptName%
        if (ErrorLevel > 0) {
            pid := ErrorLevel
            Process, Close, %pid%
            LogInfo("RelanceInstance " . instanceNum . ": Processus script " . pid . " force ferme", "AutoRelance_Instances")
            SmartSleep(2000, 5000)
        }
    }
    
    ; Vérifier si MuMu est en cours d'exécution
    mumuRunning := IsMumuInstanceRunning(instanceNum)
    
    ; Déterminer si on doit tuer et relancer MuMu
    ; On doit tuer MuMu si : MuMu n'est pas en cours, s'il est crashé, ou s'il est figé (cpu_frozen)
    shouldKillMumu := !mumuRunning || errorType = "mumu_crashed" || InStr(errorType, "cpu_frozen") || InStr(errorType, "mumu_cpu_frozen")
    
    if (shouldKillMumu) {
        ; Tuer MuMu s'il est en cours et qu'on doit le relancer
        if (mumuRunning) {
            LogInfo("RelanceInstance " . instanceNum . ": MuMu detecte mais doit etre relance (erreur: " . errorType . "), fermeture en cours...", "AutoRelance_Instances")
            killedMumu := KillMumuInstance(instanceNum)
            if (killedMumu) {
                LogInfo("RelanceInstance " . instanceNum . ": MuMu tue avec succes", "AutoRelance_Instances")
            } else {
                LogWarning("RelanceInstance " . instanceNum . ": Echec de la fermeture de MuMu, tentative forcee...", "AutoRelance_Instances")
                ; Essayer de tuer via le PID directement
                mumuPID := GetMumuProcessPID(instanceNum)
                if (mumuPID > 0) {
                    Process, Close, %mumuPID%
                    LogInfo("RelanceInstance " . instanceNum . ": Processus MuMu " . mumuPID . " force ferme", "AutoRelance_Instances")
                }
            }
            SmartSleep(3000, 10000)
        }
        
        LogInfo("RelanceInstance " . instanceNum . ": Lancement de MuMu...", "AutoRelance_Instances")
        
        success := LaunchMumuInstance(instanceNum)
        if (!success) {
            LogError("RelanceInstance " . instanceNum . ": Echec du lancement de MuMu", "AutoRelance_Instances")
            return false
        }
        
        ; Attendre que MuMu démarre avec délai adaptatif
        sleepTime := instanceLaunchDelay * 1000
        SmartSleep(sleepTime, sleepTime * 2)
        
        ; Attendre un peu plus pour que MuMu soit complètement prêt
        SmartSleep(5000, 10000)
    } else {
        DebugLog("RelanceInstance " . instanceNum . ": MuMu deja en cours d'execution")
    }
    
    ; Vérifier que le script n'est pas déjà en cours d'exécution
    if (!IsScriptRunning(scriptName)) {
        LogInfo("RelanceInstance " . instanceNum . ": Lancement du script " . scriptName, "AutoRelance_Instances")
        Run, "%A_AhkPath%" /restart "%scriptPath%"
        SmartSleep(2000, 5000)
        
        ; Vérifier que le script a bien démarré
        SmartSleep(3000, 10000)
        if (IsScriptRunning(scriptName)) {
            LogInfo("RelanceInstance " . instanceNum . ": Script relance avec succes", "AutoRelance_Instances")
            return true
        } else {
            LogError("RelanceInstance " . instanceNum . ": Echec du lancement du script", "AutoRelance_Instances")
            return false
        }
    } else {
        DebugLog("RelanceInstance " . instanceNum . ": Script deja en cours d'execution, skip")
        return true
    }
}

; Tue un script AutoHotkey
KillScript(scriptName) {
    killed := 0
    pids := []
    
    ; Méthode 1: Via les fenêtres AutoHotkey
    DetectHiddenWindows, On
    WinGet, IDList, List, ahk_class AutoHotkey
    Loop %IDList%
    {
        ID := IDList%A_Index%
        WinGetTitle, ATitle, ahk_id %ID%
        if (InStr(ATitle, "\" . scriptName)) {
            ; Récupérer le PID avant de tuer
            WinGet, pid, PID, ahk_id %ID%
            if (pid && pid > 0) {
                pids.Push(pid)
            }
            ; Essayer de tuer via la fenêtre d'abord
            WinKill, ahk_id %ID%
            killed++
        }
    }
    
    ; Attendre un peu pour que les processus se ferment
    if (killed > 0) {
        SmartSleep(2000, 3000)
    }
    
    ; Méthode 2: Via le nom du processus directement (pour les processus figés)
    Process, Exist, %scriptName%
    if (ErrorLevel > 0) {
        pid := ErrorLevel
        
        ; Vérifier si ce PID a déjà été tué
        alreadyKilled := false
        for index, storedPID in pids {
            if (storedPID = pid) {
                alreadyKilled := true
                break
            }
        }
        
        if (!alreadyKilled || killed = 0) {
            ; Essayer Process, Close d'abord (plus propre)
            Process, Close, %pid%
            SmartSleep(1000, 2000)
            
            ; Vérifier si le processus existe toujours
            Process, Exist, %pid%
            currentPID := ErrorLevel
            if (currentPID = pid) {
                ; Le processus est figé, forcer la fermeture
                LogWarning("KillScript: Processus " . pid . " toujours actif, fermeture forcee avec taskkill...", "AutoRelance_Instances")
                ; Utiliser taskkill en dernier recours pour forcer la fermeture
                RunWait, %ComSpec% /c taskkill /F /PID %pid%, , Hide
            }
            
            if (killed = 0) {
                killed++
            }
        }
    }
    
    if (killed > 0) {
        LogInfo("KillScript: " . killed . " processus(s) " . scriptName . " tue(s)", "AutoRelance_Instances")
    }
    return killed
}

; Tue une instance MuMu spécifique
KillMumuInstance(instanceNum) {
    ; Obtenir le PID du processus MuMu pour cette instance
    mumuPID := GetMumuProcessPID(instanceNum)
    
    if (mumuPID > 0) {
        ; Essayer de tuer via la fenêtre d'abord (plus propre)
        WinKill, %instanceNum% ahk_class Qt5156QWindowIcon
        SmartSleep(2000, 3000)
        
        ; Vérifier si le processus existe toujours
        Process, Exist, %mumuPID%
        currentPID := ErrorLevel
        if (currentPID = mumuPID) {
            ; Le processus existe toujours, forcer la fermeture
            LogWarning("KillMumuInstance " . instanceNum . ": Processus " . mumuPID . " toujours actif apres WinKill, fermeture forcee...", "AutoRelance_Instances")
            Process, Close, %mumuPID%
            SmartSleep(1000, 2000)
            
            ; Vérifier à nouveau
            Process, Exist, %mumuPID%
            currentPID := ErrorLevel
            if (currentPID = mumuPID) {
                LogError("KillMumuInstance " . instanceNum . ": Impossible de fermer le processus " . mumuPID, "AutoRelance_Instances")
                return false
            }
        }
        
        LogInfo("KillMumuInstance " . instanceNum . ": Processus MuMu " . mumuPID . " tue avec succes", "AutoRelance_Instances")
        return true
    } else {
        ; Pas de PID trouvé, essayer quand même via WinKill
        WinKill, %instanceNum% ahk_class Qt5156QWindowIcon
        SmartSleep(2000, 3000)
        
        ; Vérifier si la fenêtre existe encore
        if (!WinExist(instanceNum)) {
            LogInfo("KillMumuInstance " . instanceNum . ": Fenetre MuMu fermee avec succes (PID inconnu)", "AutoRelance_Instances")
            return true
        } else {
            LogWarning("KillMumuInstance " . instanceNum . ": Impossible de fermer la fenetre MuMu", "AutoRelance_Instances")
            return false
        }
    }
}

; Lance une instance MuMu
LaunchMumuInstance(instanceNum) {
    global mumuFolder
    
    if (instanceNum = "") {
        return false
    }
    
    mumuNum := GetMumuInstanceNumFromPlayerName(instanceNum)
    if (mumuNum = "") {
        LogError("Impossible de trouver le numero MuMu pour l'instance " . instanceNum, "AutoRelance_Instances")
        return false
    }
    
    mumuExe := mumuFolder . "\shell\MuMuPlayer.exe"
    if !FileExist(mumuExe)
        mumuExe := mumuFolder . "\nx_main\MuMuNxMain.exe"
    
    if (!FileExist(mumuExe)) {
        LogError("Executable MuMu introuvable: " . mumuExe, "AutoRelance_Instances")
        return false
    }
    
    DebugLog("LaunchMumuInstance: Lancement de MuMu instance " . mumuNum . " pour script " . instanceNum)
    Run_(mumuExe, "-v " . mumuNum)
    return true
}

; Récupère le numéro MuMu à partir du nom du script
GetMumuInstanceNumFromPlayerName(scriptName) {
    global mumuFolder
    
    if (scriptName = "") {
        return ""
    }
    
    ; Parcourir tous les dossiers dans vms
    Loop, Files, %mumuFolder%\vms\*, D
    {
        folder := A_LoopFileFullPath
        configFolder := folder . "\configs"
        
        IfExist, %configFolder%
        {
            extraConfigFile := configFolder . "\extra_config.json"
            
            IfExist, %extraConfigFile%
            {
                FileRead, extraConfigContent, %extraConfigFile%
                RegExMatch(extraConfigContent, """playerName"":\s*""(.*?)""", playerName)
                if (playerName1 = scriptName) {
                    RegExMatch(A_LoopFileFullPath, "[^-]+$", mumuNum)
                    return mumuNum
                }
            }
        }
    }
    
    return ""
}

; Fonction pour exécuter sans droits administrateur
Run_(target, args:="", workdir:="") {
    try {
        ShellRun(target, args, workdir)
    } catch e {
        Run % args="" ? target : target " " args, % workdir
    }
}

ShellRun(prms*) {
    shellWindows := ComObjCreate("Shell.Application").Windows
    VarSetCapacity(_hwnd, 4, 0)
    desktop := shellWindows.FindWindowSW(0, "", 8, ComObj(0x4003, &_hwnd), 1)
    
    if ptlb := ComObjQuery(desktop
        , "{4C96BE40-915C-11CF-99D3-00AA004AE837}"
        , "{000214E2-0000-0000-C000-000000000046}")
    {
        if DllCall(NumGet(NumGet(ptlb+0)+15*A_PtrSize), "ptr", ptlb, "ptr*", psv:=0) = 0
        {
            VarSetCapacity(IID_IDispatch, 16)
            NumPut(0x46000000000000C0, NumPut(0x20400, IID_IDispatch, "int64"), "int64")
            
            DllCall(NumGet(NumGet(psv+0)+15*A_PtrSize), "ptr", psv
                , "uint", 0, "ptr", &IID_IDispatch, "ptr*", pdisp:=0)
            
            shell := ComObj(9,pdisp,1).Application
            shell.ShellExecute(prms*)
            
            ObjRelease(psv)
        }
        ObjRelease(ptlb)
    }
}

; Obtenir les statistiques de relances
GetRelanceStatistics(instanceNum) {
    global relanceCount, relanceHistory, errorTypes
    
    stats := {}
    stats.totalRelances := relanceCount[instanceNum]
    stats.lastErrorType := errorTypes[instanceNum]
    stats.history := relanceHistory[instanceNum]
    
    return stats
}

; Démarrer l'addon avec un timer
DebugLog("Script - Demarrage, configuration du timer InitTimer")
SetTimer, InitTimer, -100

; Timer d'initialisation
InitTimer:
    DebugLog("InitTimer - Label declenche, appel de Initialize()")
    if (Initialize()) {
        DebugLog("InitTimer - Initialize() termine avec succes")
        DebugLog("InitTimer - Le script va maintenant rester actif pour surveiller les instances")
        
        ; Boucle de maintien en vie
        Loop {
            SmartSleep(60000, 120000)  ; Dormir 60 secondes avec SmartSleep
        }
    } else {
        LogError("Echec de l'initialisation", "AutoRelance_Instances")
        NotifyError("Erreur AutoRelance", "Echec de l'initialisation de l'addon AutoRelance_Instances")
        ExitApp
    }
return

; Hotkey pour quitter proprement (Ctrl+Shift+X)
^+x::
    DebugLog("Hotkey Ctrl+Shift+X - Arret de l'addon")
    SetTimer, CheckInstancesTimer, Off
    ; Nettoyer le lock file avant de quitter
    CreateLockFileOnExit("", "")
    ExitApp
return

GuiClose:
    ; Nettoyer le lock file avant de quitter
    CreateLockFileOnExit("", "")
    ExitApp
return
