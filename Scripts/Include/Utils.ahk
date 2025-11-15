;===============================================================================
; Utils.ahk - Utility Functions
;===============================================================================
; This file contains general-purpose utility functions used throughout the bot.
; These functions handle:
;   - Delays and timing
;   - File operations (read, download)
;   - Date/time calculations
;   - Array sorting and comparison
;   - Settings migration
;   - Mission checking logic
;   - MuMu version detection
;   - Addon utilities (logging, configuration, instance detection)
;
; Dependencies: Logging.ahk, ConfigManager.ahk, StateManager.ahk (for addon functions)
; Used by: Multiple modules throughout 1.ahk and addons
;===============================================================================

;-------------------------------------------------------------------------------
; Delay - Configurable delay based on global Delay setting
;-------------------------------------------------------------------------------
Delay(n) {
    global Delay
    msTime := Delay * n
    Sleep, msTime
}

;-------------------------------------------------------------------------------
; MonthToDays - Convert month number to days elapsed in year
;-------------------------------------------------------------------------------
MonthToDays(year, month) {
    static DaysInMonths := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    days := 0
    Loop, % month - 1 {
        days += DaysInMonths[A_Index]
    }
    if (month > 2 && IsLeapYear(year))
        days += 1
    return days
}

;-------------------------------------------------------------------------------
; IsLeapYear - Check if a year is a leap year
;-------------------------------------------------------------------------------
IsLeapYear(year) {
    return (Mod(year, 4) = 0 && Mod(year, 100) != 0) || Mod(year, 400) = 0
}

;-------------------------------------------------------------------------------
; DownloadFile - Download file from URL to local path
;-------------------------------------------------------------------------------
DownloadFile(url, filename) {
    url := url  ; Change to your hosted .txt URL "https://pastebin.com/raw/vYxsiqSs"
    RegRead, proxyEnabled, HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings, ProxyEnable
	RegRead, proxyServer, HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings, ProxyServer
    localPath = %A_ScriptDir%\..\%filename% ; Change to the folder you want to save the file
    errored := false
    try {
        whr := ComObjCreate("WinHttp.WinHttpRequest.5.1")
        if (proxyEnabled)
			whr.SetProxy(2, proxyServer)
        whr.Open("GET", url, true)
        whr.Send()
        whr.WaitForResponse()
        ids := whr.ResponseText
    } catch {
        errored := true
    }
    if(!errored) {
        FileDelete, %localPath%
        FileAppend, %ids%, %localPath%
    }
    return !errored
}

;-------------------------------------------------------------------------------
; ReadFile - Read text file and return cleaned array of values
;-------------------------------------------------------------------------------
ReadFile(filename, numbers := false) {
    FileRead, content, %A_ScriptDir%\..\%filename%.txt

    if (!content)
        return false

    values := []
    for _, val in StrSplit(Trim(content), "`n") {
        cleanVal := RegExReplace(val, "[^a-zA-Z0-9]") ; Remove non-alphanumeric characters
        if (cleanVal != "")
            values.Push(cleanVal)
    }

    return values.MaxIndex() ? values : false
}

;-------------------------------------------------------------------------------
; MigrateDeleteMethod - Migrate old delete method names to new format
;-------------------------------------------------------------------------------
MigrateDeleteMethod(oldMethod) {
    if (oldMethod = "13 Pack") {
        return "Create Bots (13P)"
    } else if (oldMethod = "Inject") {
        return "Inject 13P+"
    } else if (oldMethod = "Inject for Reroll") {
        return "Inject Wonderpick 96P+"
    } else if (oldMethod = "Inject Missions") {
        return "Inject 13P+"
    }
    return oldMethod
}

;-------------------------------------------------------------------------------
; getChangeDateTime - Calculate the server reset time in local timezone
;-------------------------------------------------------------------------------
getChangeDateTime() {
	offset := A_Now
	currenttimeutc := A_NowUTC
	EnvSub, offset, %currenttimeutc%, Hours   ;offset from local timezone to UTC

    resetTime := SubStr(A_Now, 1, 8) "060000" ;today at 6am [utc] zero seconds is the reset time at UTC
	resetTime += offset, Hours                ;reset time in local timezone

	;find the closest reset time
	currentTime := A_Now
	timeToReset := resetTime
	EnvSub, timeToReset, %currentTime%, Hours
	if(timeToReset > 12) {
		resetTime += -1, Days
	} else if (timeToReset < -12) {
		resetTime += 1, Days
	}

    return resetTime
}

;-------------------------------------------------------------------------------
; checkShouldDoMissions - Determine if missions should be executed
;-------------------------------------------------------------------------------
checkShouldDoMissions() {
    global beginnerMissionsDone, deleteMethod, injectMethod, loadedAccount, friendIDs, friendID, accountOpenPacks, maxAccountPackNum, verboseLogging

    if (beginnerMissionsDone) {
        return false
    }

    if (deleteMethod = "Create Bots (13P)") {
        return (!friendIDs && friendID = "" && accountOpenPacks < maxAccountPackNum) || (friendIDs || friendID != "")
    }
    else if (deleteMethod = "Inject Missions") {
        IniRead, skipMissions, %A_ScriptDir%\..\Settings.ini, UserSettings, skipMissionsInjectMissions, 0
        if (skipMissions = 1) {
            ; if(verboseLogging)
                ; LogToFile("Skipping missions for Inject Missions method (user setting)")
            return false
        }
        ; if(verboseLogging)
            ; LogToFile("Executing missions for Inject Missions method (user setting enabled)")
        return true
    }
    else if (deleteMethod = "Inject 13P+" || deleteMethod = "Inject Wonderpick 96P+") {
        ; if(verboseLogging)
            ; LogToFile("Skipping missions for " . deleteMethod . " method - missions only run for 'Inject Missions'")
        return false
    }
    else {
        ; For non-injection methods (like regular delete methods)
        return (!friendIDs && friendID = "" && accountOpenPacks < maxAccountPackNum) || (friendIDs || friendID != "")
    }
}

;-------------------------------------------------------------------------------
; isMuMuv5 - Detect if MuMu Player version 5 is being used
;-------------------------------------------------------------------------------
isMuMuv5(){
    global folderPath
    mumuFolder := folderPath . "\MuMuPlayerGlobal-12.0"
    if !FileExist(mumuFolder)
        mumuFolder := folderPath . "\MuMu Player 12"
    if FileExist(mumuFolder . "\nx_main")
        return true
    return false
}

;===============================================================================
; Array Sorting Functions
;===============================================================================

;-------------------------------------------------------------------------------
; SortArraysByProperty - Sort multiple parallel arrays by a property
;-------------------------------------------------------------------------------
SortArraysByProperty(fileNames, fileTimes, packCounts, property, ascending) {
    n := fileNames.MaxIndex()

    ; Create an array of indices for sorting
    indices := []
    Loop, %n% {
        indices.Push(A_Index)
    }

    ; Sort the indices based on the specified property
    if (property == "time") {
        if (ascending) {
            ; Sort by time ascending
            Sort(indices, Func("CompareIndicesByTimeAsc").Bind(fileTimes))
        } else {
            ; Sort by time descending
            Sort(indices, Func("CompareIndicesByTimeDesc").Bind(fileTimes))
        }
    } else if (property == "packs") {
        if (ascending) {
            ; Sort by pack count ascending
            Sort(indices, Func("CompareIndicesByPacksAsc").Bind(packCounts))
        } else {
            ; Sort by pack count descending
            Sort(indices, Func("CompareIndicesByPacksDesc").Bind(packCounts))
        }
    }

    ; Create temporary arrays for sorted values
    sortedFileNames := []
    sortedFileTimes := []
    sortedPackCounts := []

    ; Populate sorted arrays based on sorted indices
    Loop, %n% {
        idx := indices[A_Index]
        sortedFileNames.Push(fileNames[idx])
        sortedFileTimes.Push(fileTimes[idx])
        sortedPackCounts.Push(packCounts[idx])
    }

    ; Copy sorted values back to original arrays
    Loop, %n% {
        fileNames[A_Index] := sortedFileNames[A_Index]
        fileTimes[A_Index] := sortedFileTimes[A_Index]
        packCounts[A_Index] := sortedPackCounts[A_Index]
    }
}

;-------------------------------------------------------------------------------
; Sort - Helper function to sort an array using a custom comparison function
;-------------------------------------------------------------------------------
Sort(array, compareFunc) {
    QuickSort(array, 1, array.MaxIndex(), compareFunc)
    return array
}

;-------------------------------------------------------------------------------
; QuickSort - Iterative quicksort implementation
;-------------------------------------------------------------------------------
QuickSort(array, left, right, compareFunc) {
    ; Create a manual stack to avoid deep recursion
    stack := []
    stack.Push([left, right])

    ; Process all partitions iteratively
    while (stack.Length() > 0) {
        current := stack.Pop()
        currentLeft := current[1]
        currentRight := current[2]

        if (currentLeft < currentRight) {
            ; Use middle element as pivot
            pivotIndex := Floor((currentLeft + currentRight) / 2)
            pivotValue := array[pivotIndex]

            ; Move pivot to end
            temp := array[pivotIndex]
            array[pivotIndex] := array[currentRight]
            array[currentRight] := temp

            ; Move all elements smaller than pivot to the left
            storeIndex := currentLeft
            i := currentLeft
            while (i < currentRight) {
                if (compareFunc.Call(array[i], array[currentRight]) < 0) {
                    ; Swap elements
                    temp := array[i]
                    array[i] := array[storeIndex]
                    array[storeIndex] := temp
                    storeIndex++
                }
                i++
            }

            ; Move pivot to its final place
            temp := array[storeIndex]
            array[storeIndex] := array[currentRight]
            array[currentRight] := temp

            ; Push the larger partition first (optimization)
            if (storeIndex - currentLeft < currentRight - storeIndex) {
                stack.Push([storeIndex + 1, currentRight])
                stack.Push([currentLeft, storeIndex - 1])
            } else {
                stack.Push([currentLeft, storeIndex - 1])
                stack.Push([storeIndex + 1, currentRight])
            }
        }
    }
}

;===============================================================================
; Comparison Functions for Sorting
;===============================================================================

CompareIndicesByTimeAsc(times, a, b) {
    timeA := times[a]
    timeB := times[b]
    return timeA < timeB ? -1 : (timeA > timeB ? 1 : 0)
}

CompareIndicesByTimeDesc(times, a, b) {
    timeA := times[a]
    timeB := times[b]
    return timeB < timeA ? -1 : (timeB > timeA ? 1 : 0)
}

CompareIndicesByPacksAsc(packs, a, b) {
    packsA := packs[a]
    packsB := packs[b]
    return packsA < packsB ? -1 : (packsA > packsB ? 1 : 0)
}

CompareIndicesByPacksDesc(packs, a, b) {
    packsA := packs[a]
    packsB := packs[b]
    return packsB < packsA ? -1 : (packsB > packsA ? 1 : 0)
}

;===============================================================================
; ADDON UTILITIES - Fonctions utilitaires pour les addons
;===============================================================================
; Les fonctions suivantes sont utilisées par les addons
; Elles nécessitent Logging.ahk, ConfigManager.ahk et StateManager.ahk

; Inclure les dépendances pour les fonctions addon
; NOTE: ConfigManager.ahk et StateManager.ahk doivent être inclus AVANT Utils.ahk
; dans les scripts qui utilisent Utils.ahk (comme les addons).
; Logging.ahk est inclus de manière optionnelle car il peut créer une dépendance circulaire
#Include *i Logging.ahk

; Variable globale pour le nom de l'addon (sera définie par chaque addon)
global addonUtils_AddonName := "Addon"

; ========================================
; FONCTIONS DE LOGGING POUR ADDONS
; ========================================

; Initialise le nom de l'addon pour les logs
; Doit être appelée au début de chaque addon
SetAddonName(addonName) {
    global addonUtils_AddonName
    addonUtils_AddonName := addonName
    
    ; Créer le fichier de verrouillage pour cet addon
    CreateAddonLockFile(addonName)
}

; Crée un fichier de verrouillage pour l'addon pour éviter les doublons
; Le fichier contient le PID du processus et est utilisé par LoadAddons() pour détecter si l'addon est déjà en cours
CreateAddonLockFile(addonName) {
    try {
        ; Extraire le nom de base (sans extension)
        addonBaseName := StrReplace(addonName, ".ahk", "")
        
        ; Créer le chemin du fichier de verrouillage
        lockFile := A_Temp . "\PTCGPB_Addon_" . addonBaseName . "_Lock.txt"
        
        ; Obtenir le PID du processus actuel
        currentPID := DllCall("GetCurrentProcessId")
        
        ; Créer le fichier de verrouillage avec le PID
        FileDelete, %lockFile%  ; Supprimer l'ancien s'il existe (au cas où)
        FileAppend, %currentPID%, %lockFile%
        
        ; Vérifier que le fichier a bien été créé
        if (!FileExist(lockFile)) {
            ; Log l'erreur si LogToFile est disponible
            if (IsFunc("LogToFile")) {
                LogToFile("[Addons] ERREUR: Impossible de créer le lock file pour " . addonName . " à " . lockFile, "Addons_Launch.log")
            }
            return false
        }
        
        ; Nettoyer le fichier de verrouillage à la fermeture du script
        OnExit("CleanupAddonLockFile")
        
        return true
    } catch e {
        ; Log l'erreur si LogToFile est disponible
        if (IsFunc("LogToFile")) {
            LogToFile("[Addons] ERREUR: Exception lors de la création du lock file pour " . addonName . ": " . e.Message, "Addons_Launch.log")
        }
        return false
    }
}

; Nettoie le fichier de verrouillage à la fermeture de l'addon
CleanupAddonLockFile(ExitReason, ExitCode) {
    global addonUtils_AddonName
    
    if (addonUtils_AddonName != "") {
        addonBaseName := StrReplace(addonUtils_AddonName, ".ahk", "")
        lockFile := A_Temp . "\PTCGPB_Addon_" . addonBaseName . "_Lock.txt"
        
        ; Vérifier que le PID dans le fichier correspond toujours au processus actuel
        if (FileExist(lockFile)) {
            FileRead, lockPID, %lockFile%
            currentPID := DllCall("GetCurrentProcessId")
            
            ; Ne supprimer que si c'est notre propre verrou
            if (lockPID = currentPID) {
                FileDelete, %lockFile%
            }
        }
    }
}

; Log un message dans la console de debug
; Utilise LogToFile qui existe dans Logging.ahk
; Rétro-compatible avec l'ancien système (OutputDebug)
DebugLog(message, addonName := "") {
    global addonUtils_AddonName
    if (addonName = "") {
        addonName := addonUtils_AddonName
    }
    
    ; Utiliser LogToFile avec un fichier de log spécifique pour les addons
    logMessage := "[" . addonName . "] " . message
    if (IsFunc("LogToFile")) {
        LogToFile(logMessage, "Addons_" . addonName . ".log")
    }
    
    ; Aussi envoyer à OutputDebug pour compatibilité avec les débogueurs
    OutputDebug, % "[" . addonName . "] " . message
}

; Fonctions de logging avec niveaux (compatibles avec le système de logging unifié)
; Ces fonctions utilisent LogToFile avec des préfixes de niveau
LogError(message, addonName := "") {
    global addonUtils_AddonName
    if (addonName = "") {
        addonName := addonUtils_AddonName
    }
    logMessage := "[ERROR] [" . addonName . "] " . message
    if (IsFunc("LogToFile")) {
        LogToFile(logMessage, "Addons_" . addonName . ".log")
    }
    OutputDebug, % "[ERROR] [" . addonName . "] " . message
}

LogWarning(message, addonName := "") {
    global addonUtils_AddonName
    if (addonName = "") {
        addonName := addonUtils_AddonName
    }
    logMessage := "[WARNING] [" . addonName . "] " . message
    if (IsFunc("LogToFile")) {
        LogToFile(logMessage, "Addons_" . addonName . ".log")
    }
    OutputDebug, % "[WARNING] [" . addonName . "] " . message
}

LogInfo(message, addonName := "") {
    global addonUtils_AddonName
    if (addonName = "") {
        addonName := addonUtils_AddonName
    }
    logMessage := "[INFO] [" . addonName . "] " . message
    if (IsFunc("LogToFile")) {
        LogToFile(logMessage, "Addons_" . addonName . ".log")
    }
    OutputDebug, % "[INFO] [" . addonName . "] " . message
}

LogDebug(message, addonName := "") {
    global addonUtils_AddonName
    if (addonName = "") {
        addonName := addonUtils_AddonName
    }
    logMessage := "[DEBUG] [" . addonName . "] " . message
    if (IsFunc("LogToFile")) {
        LogToFile(logMessage, "Addons_" . addonName . ".log")
    }
    OutputDebug, % "[DEBUG] [" . addonName . "] " . message
}

; ========================================
; FONCTIONS DE CONFIGURATION POUR ADDONS
; ========================================

; Retourne le répertoire racine du projet (2 niveaux au-dessus de Scripts/Addon)
GetScriptRootDir() {
    return A_ScriptDir . "\..\.."
}

; Lit la langue depuis Settings.ini
; Retourne "FR", "EN", "IT", ou "CH"
GetLanguage() {
    static currentLanguage := ""
    
    if (currentLanguage != "") {
        return currentLanguage
    }
    
    ; Lire la langue directement depuis Settings.ini
    ; (GetLanguage peut être appelé avant que ConfigManager soit initialisé)
    ; Calculer le chemin vers Settings.ini
    ; Si on est dans Scripts\Include, remonter de 2 niveaux
    ; Sinon, utiliser A_ScriptDir directement
    if (InStr(A_LineFile, "Scripts\Include")) {
        settingsPath := RegExReplace(A_LineFile, "\\[^\\]+$", "") . "\..\..\Settings.ini"
    } else {
        settingsPath := A_ScriptDir . "\Settings.ini"
    }
    IniRead, clientLanguage, %settingsPath%, UserSettings, clientLanguage, en
    StringLower, clientLanguage, clientLanguage
    
    if (clientLanguage = "fr" || clientLanguage = "français" || clientLanguage = "french") {
        currentLanguage := "FR"
    } else if (clientLanguage = "it" || clientLanguage = "italiano" || clientLanguage = "italian") {
        currentLanguage := "IT"
    } else if (clientLanguage = "ch" || clientLanguage = "zh" || clientLanguage = "中文" || clientLanguage = "chinese") {
        currentLanguage := "CH"
    } else {
        currentLanguage := "EN"
    }
    
    return currentLanguage
}

; Lit une valeur depuis Settings.ini
ReadSetting(section, key, defaultValue := "") {
    ; Lire directement depuis Settings.ini (peut être appelé avant que ConfigManager soit initialisé)
    ; Calculer le chemin vers Settings.ini
    if (InStr(A_LineFile, "Scripts\Include")) {
        settingsPath := RegExReplace(A_LineFile, "\\[^\\]+$", "") . "\..\..\Settings.ini"
    } else {
        settingsPath := A_ScriptDir . "\Settings.ini"
    }
    IniRead, value, %settingsPath%, %section%, %key%, %defaultValue%
    return value
}

; Lit une valeur depuis un fichier INI spécifique
; Note: Pour les fichiers INI autres que Settings.ini, on utilise encore IniRead directement
ReadIniValue(iniFile, section, key, defaultValue := "") {
    if (FileExist(iniFile)) {
        IniRead, value, %iniFile%, %section%, %key%, %defaultValue%
        return value
    }
    
    return defaultValue
}

; ========================================
; FONCTIONS DE DÉTECTION D'INSTANCES
; ========================================

; Cache des positions de fenêtres
global WindowPositionCache := {}
global WindowPositionCacheTimestamps := {}
global WindowPositionCacheTTL := 2000  ; 2 secondes par défaut

; Valide les coordonnées d'une fenêtre
ValidateCoordinates(winX, winY, winWidth) {
    if (winX = "" || winY = "" || !winWidth || winWidth < 50) {
        return false
    }
    if (winX = 0 && winY = 0 && winWidth < 200) {
        return false
    }
    return true
}

; Invalider le cache d'une fenêtre spécifique
InvalidateWindowCache(instanceName) {
    global WindowPositionCache, WindowPositionCacheTimestamps
    
    if (WindowPositionCache.HasKey(instanceName)) {
        WindowPositionCache.Delete(instanceName)
    }
    if (WindowPositionCacheTimestamps.HasKey(instanceName)) {
        WindowPositionCacheTimestamps.Delete(instanceName)
    }
}

; Invalider tout le cache des fenêtres
InvalidateAllWindowCache() {
    global WindowPositionCache, WindowPositionCacheTimestamps
    WindowPositionCache := {}
    WindowPositionCacheTimestamps := {}
}

; Obtient la position et les dimensions d'une fenêtre d'instance
; Retourne un objet avec {x, y, width, height, winID}
; Utilise un cache avec TTL pour améliorer les performances
GetWindowPosition(instanceName, instanceInfo := "") {
    global WindowPositionCache, WindowPositionCacheTimestamps, WindowPositionCacheTTL
    
    ; Vérifier le cache d'abord
    if (WindowPositionCache.HasKey(instanceName)) {
        cacheTime := WindowPositionCacheTimestamps.HasKey(instanceName) ? WindowPositionCacheTimestamps[instanceName] : 0
        if ((A_TickCount - cacheTime) < WindowPositionCacheTTL) {
            cached := WindowPositionCache[instanceName]
            
            ; Vérifier que la fenêtre existe toujours avec le même winID
            if (cached.HasKey("winID") && cached.winID) {
                cachedWinID := cached.winID
                if (WinExist("ahk_id " . cachedWinID)) {
                    ; Vérifier rapidement si la position a changé (détection de mouvement)
                    WinGetPos, currentX, currentY, currentW, currentH, ahk_id %cachedWinID%
                    if (currentX = cached.x && currentY = cached.y && currentW = cached.width && currentH = cached.height) {
                        return cached
                    }
                }
            }
        }
    }
    
    ; Cache invalide ou inexistant, récupérer la position
    winX := ""
    winY := ""
    winWidth := ""
    winHeight := ""
    winID := ""
    
    WinGet, winID, ID, %instanceName% ahk_class Qt5156QWindowIcon ahk_exe MuMuPlayer.exe
    if (winID) {
        WinGetPos, tempX, tempY, tempW, tempH, ahk_id %winID%
        if (tempX != "" && tempY != "" && tempW >= 200) {
            winX := tempX
            winY := tempY
            winWidth := tempW
            winHeight := tempH
        }
    }
    
    if (!winID || winX = "") {
        WinGet, winID, ID, %instanceName% ahk_class Qt5156QWindowIcon
        if (winID) {
            WinGetPos, tempX, tempY, tempW, tempH, ahk_id %winID%
            if (tempX != "" && tempY != "" && tempW >= 200) {
                winX := tempX
                winY := tempY
                winWidth := tempW
                winHeight := tempH
            }
        }
    }
    
    if ((winX = "" || winWidth < 200) && !(winX = 0 && winY = 0 && winWidth >= 200) && instanceInfo && instanceInfo.HasKey("winID") && instanceInfo.winID) {
        winID := instanceInfo.winID
        WinGetPos, tempX, tempY, tempW, tempH, ahk_id %winID%
        if (tempX != "" && tempY != "" && tempW >= 200) {
            winX := tempX
            winY := tempY
            winWidth := tempW
            winHeight := tempH
        }
    }
    
    if ((winX = "" || winY = "") && !(winX = 0 && winY = 0 && winWidth >= 200) && instanceInfo) {
        if (instanceInfo.HasKey("x") && instanceInfo.HasKey("y")) {
            winX := instanceInfo.x
            winY := instanceInfo.y
            winWidth := instanceInfo.width
            winHeight := instanceInfo.height
        }
    }
    
    result := {x: winX, y: winY, width: winWidth, height: winHeight, winID: winID}
    
    ; Mettre en cache si valide
    if (ValidateCoordinates(winX, winY, winWidth)) {
        WindowPositionCache[instanceName] := result
        WindowPositionCacheTimestamps[instanceName] := A_TickCount
        
    }
    
    return result
}

; Obtient le nombre de comptes restants et total pour une instance
; Retourne un objet avec {remaining, total}
GetAccountCounts(winTitle) {
    scriptDir := GetScriptRootDir()
    saveDir := scriptDir . "\Accounts\Saved\" . winTitle
    listCurrentFile := saveDir . "\list_current.txt"
    listFile := saveDir . "\list.txt"
    
    remaining := 0
    total := 0
    
    if (FileExist(listCurrentFile)) {
        FileRead, fileContent, %listCurrentFile%
        if (fileContent) {
            fileLines := StrSplit(fileContent, "`n", "`r")
            Loop, % fileLines.MaxIndex() {
                currentLine := Trim(fileLines[A_Index])
                if (StrLen(currentLine) >= 5 && InStr(currentLine, "xml")) {
                    remaining++
                }
            }
        }
    }
    
    if (FileExist(listFile)) {
        FileRead, fileContent, %listFile%
        if (fileContent) {
            fileLines := StrSplit(fileContent, "`n", "`r")
            Loop, % fileLines.MaxIndex() {
                currentLine := Trim(fileLines[A_Index])
                if (StrLen(currentLine) >= 5 && InStr(currentLine, "xml")) {
                    total++
                }
            }
        }
    } else if (FileExist(listCurrentFile)) {
        total := remaining
    }
    
    return {remaining: remaining, total: total}
}

; Cache pour DetectInstances
global DetectInstancesCache := {}
global DetectInstancesCacheTimestamp := 0
global DetectInstancesCacheTTL := 5000  ; 5 secondes
global DetectInstancesLastWindowHandles := {}

; Détecte toutes les instances du bot en mode Inject
; Retourne un objet associatif {instanceName: {counts, x, y, width, height, winID}}
; Utilise un cache avec détection incrémentale pour améliorer les performances
DetectInstances(debugMode := false, debugInstance := "") {
    global DetectInstancesCache, DetectInstancesCacheTimestamp, DetectInstancesCacheTTL, DetectInstancesLastWindowHandles
    
    instances := {}
    scriptDir := GetScriptRootDir()
    debugInfo := ""
    
    ; Vérifier le cache
    cacheValid := false
    if (DetectInstancesCacheTimestamp > 0 && (A_TickCount - DetectInstancesCacheTimestamp) < DetectInstancesCacheTTL) {
        ; Vérifier si les handles de fenêtres ont changé (détection incrémentale)
        currentHandles := ""
        DetectHiddenWindows, On
        WinGet, mumuWindows, List, ahk_class Qt5156QWindowIcon
        Loop, %mumuWindows%
        {
            winID := mumuWindows%A_Index%
            if (winID) {
                currentHandles := currentHandles . winID . ","
            }
        }
        
        ; Comparer avec les handles précédents
        if (currentHandles = DetectInstancesLastWindowHandles) {
            ; Aucun changement, utiliser le cache (créer une copie)
            cacheValid := true
            instances := {}
            for k, v in DetectInstancesCache {
                instances[k] := v
            }
        } else {
            ; Handles ont changé, mettre à jour
            DetectInstancesLastWindowHandles := currentHandles
        }
    }
    
    ; Si le cache n'est pas valide, détecter toutes les instances
    if (!cacheValid) {
        DetectHiddenWindows, On
    
    WinGet, mumuWindows, List, ahk_class Qt5156QWindowIcon
    WinGet, mumuWindows2, List, ahk_exe MuMuPlayer.exe
    WinGet, ahkWindowsList, List, ahk_class AutoHotkey
    
    ahkWindows := 0
    Loop, %mumuWindows%
    {
        winID := mumuWindows%A_Index%
        if (winID) {
            ahkWindows := ahkWindows + 1
            ahkWindows%ahkWindows% := winID
        }
    }
    
    Loop, %mumuWindows2%
    {
        winID := mumuWindows2%A_Index%
        if (winID) {
            alreadyAdded := false
            Loop, %ahkWindows%
            {
                if (ahkWindows%A_Index% = winID) {
                    alreadyAdded := true
                    break
                }
            }
            if (!alreadyAdded) {
                ahkWindows := ahkWindows + 1
                ahkWindows%ahkWindows% := winID
            }
        }
    }
    
    Loop, %ahkWindowsList%
    {
        winID := ahkWindowsList%A_Index%
        if (winID) {
            WinGetTitle, winTitleTest, ahk_id %winID%
            if (!InStr(winTitleTest, "AddonBar") && !InStr(winTitleTest, "ComptesRestants") && !InStr(winTitleTest, "Monitor") && !InStr(winTitleTest, "PTCGPB.ahk")) {
                ahkWindows := ahkWindows + 1
                ahkWindows%ahkWindows% := winID
            }
        }
    }
    
    allTitles := ""
    Loop, %ahkWindows%
    {
        winID := ahkWindows%A_Index%
        WinGetTitle, winTitleFull, ahk_id %winID%
        WinGetPos, winX, winY, winWidth, winHeight, ahk_id %winID%
        
        if ((winX = 0 && winY = 0) || !winX || !winY) {
            Sleep, 100
            WinGetPos, winX, winY, winWidth, winHeight, ahk_id %winID%
        }
        
        if (winTitleFull = "") {
            allTitles := allTitles . "(Titre vide - ID: " . winID . ")`n"
            continue
        } else {
            allTitles := allTitles . winTitleFull . " (ID: " . winID . ")`n"
        }
        
        if (InStr(winTitleFull, "AddonBar") || InStr(winTitleFull, "ComptesRestants") || InStr(winTitleFull, "Monitor") || InStr(winTitleFull, "PTCGPB.ahk")) {
            continue
        }
        
        WinGetClass, winClass, ahk_id %winID%
        WinGet, winProcess, ProcessName, ahk_id %winID%
        
        winTitle := ""
        if (InStr(winTitleFull, "\")) {
            SplitPath, winTitleFull, fileName
            winTitle := StrReplace(fileName, ".ahk", "")
            winTitle := RegExReplace(winTitle, " - .*$", "")
        } else {
            winTitle := winTitleFull
        }
        
        isMuMuWindow := (winProcess = "MuMuPlayer.exe" || winClass = "Qt5156QWindowIcon")
        
        isBotInstance := false
        if (winTitle = "1" || winTitle = "2" || winTitle = "3" || winTitle = "4" || winTitle = "5" || winTitle = "6" || winTitle = "7" || winTitle = "8" || winTitle = "9" || winTitle = "10") {
            isBotInstance := true
        }
        else if (winTitle = "Main" || RegExMatch(winTitle, "^Main\d+$")) {
            isBotInstance := true
        }
        else if (StrLen(winTitle) <= 10 && RegExMatch(winTitle, "^\d+$")) {
            isBotInstance := true
        }
        
        if (isBotInstance) {
            deleteMethod := ""
            
            settingsFile := scriptDir . "\Settings.ini"
            if (FileExist(settingsFile)) {
                IniRead, deleteMethod, %settingsFile%, UserSettings, deleteMethod, ""
            }
            
            if (!deleteMethod || deleteMethod = "") {
                iniFile := scriptDir . "\Scripts\" . winTitle . ".ini"
                if (FileExist(iniFile)) {
                    IniRead, deleteMethod, %iniFile%, UserSettings, deleteMethod, ""
                }
            }
            
            debugInfo := debugInfo . "Titre extrait: " . winTitle . " | Settings.ini existe: " . (FileExist(settingsFile) ? "Oui" : "Non") . " | deleteMethod: " . (deleteMethod ? deleteMethod : "(vide)") . "`n"
            
            if (deleteMethod && InStr(deleteMethod, "Inject")) {
                if (debugMode && winTitle != debugInstance) {
                    continue
                }
                
                counts := GetAccountCounts(winTitle)
                
                if (isMuMuWindow && (winX = 0 && winY = 0)) {
                    WinGet, parentWinID, ID, %winTitle% ahk_class Qt5156QWindowIcon
                    if (parentWinID && parentWinID != winID) {
                        WinGetPos, parentX, parentY, parentW, parentH, ahk_id %parentWinID%
                        if (parentX != 0 || parentY != 0) {
                            winX := parentX
                            winY := parentY
                            winWidth := parentW
                            winHeight := parentH
                            winID := parentWinID
                        }
                    }
                    if (winX = 0 && winY = 0) {
                        WinGet, altWinID, ID, %winTitle% ahk_exe MuMuPlayer.exe
                        if (altWinID) {
                            WinGetPos, altX, altY, altW, altH, ahk_id %altWinID%
                            if (altX != 0 || altY != 0) {
                                winX := altX
                                winY := altY
                                winWidth := altW
                                winHeight := altH
                                winID := altWinID
                            }
                        }
                    }
                }
                
                if (instances.HasKey(winTitle) && isMuMuWindow) {
                    instances[winTitle] := {counts: counts, x: winX, y: winY, width: winWidth, height: winHeight, winID: winID}
                } else if (!instances.HasKey(winTitle)) {
                    instances[winTitle] := {counts: counts, x: winX, y: winY, width: winWidth, height: winHeight, winID: winID}
                }
                
                if (debugMode) {
                    DebugLog("Mode DEBUG: Instance detectee: " . winTitle . " | Position: x=" . winX . " y=" . winY . " | Taille: w=" . winWidth . " h=" . winHeight . " | Comptes: " . counts.remaining . "/" . counts.total)
                }
            }
        }
    }
    }
    
    allTitlesClean := StrReplace(allTitles, "`n", " | ")
    debugInfoClean := StrReplace(debugInfo, "`n", " | ")
    instanceCount := 0
    for k, v in instances {
        instanceCount++
    }
    DebugLog("Fenetres AutoHotkey trouvees: " . allTitlesClean . " | Debug deleteMethod: " . debugInfoClean . " | Instances Inject detectees: " . instanceCount)
    
    ; Mettre à jour le cache (créer une copie)
    DetectInstancesCache := {}
    for k, v in instances {
        DetectInstancesCache[k] := v
    }
    DetectInstancesCacheTimestamp := A_TickCount
    
    
    return instances
}

; ========================================
; FONCTIONS UTILITAIRES POUR ADDONS
; ========================================

; SmartSleep - Sleep intelligent avec backoff exponentiel
; delay: Délai de base en millisecondes
; maxDelay: Délai maximum (par défaut 5000ms)
; condition: Fonction de condition pour arrêter plus tôt (optionnel)
SmartSleep(delay, maxDelay := 5000, condition := "") {
    if (delay <= 0) {
        return
    }
    
    ; Limiter le délai maximum
    if (delay > maxDelay) {
        delay := maxDelay
    }
    
    ; Si une condition est fournie, vérifier périodiquement
    if (condition != "" && IsFunc(condition)) {
        ; Vérifier toutes les 100ms max, ou delay/10 si plus petit
        checkInterval := delay / 10
        if (checkInterval > 100) {
            checkInterval := 100
        }
        elapsed := 0
        
        while (elapsed < delay) {
            Sleep, %checkInterval%
            elapsed := elapsed + checkInterval
            
            ; Vérifier la condition
            if (%condition%()) {
                return
            }
        }
    } else {
        ; Sleep normal
        Sleep, %delay%
    }
}

; ========================================
; FONCTIONS DE TRADUCTION
; ========================================

; Retourne le texte "Restant" selon la langue
GetRemainingText() {
    lang := GetLanguage()
    
    if (lang = "FR") {
        return "Restant"
    } else if (lang = "IT") {
        return "Rimanenti"
    } else if (lang = "CH") {
        return "剩余"
    } else {
        return "Remaining"
    }
}

; ========================================
; SURVEILLANCE CPU - Détection d'instances figées
; ========================================

; Obtient l'utilisation CPU d'un processus par son PID
; Retourne le pourcentage CPU (0-100) ou -1 en cas d'erreur
GetProcessCPUUsage(pid) {
    if (!pid || pid <= 0) {
        return -1
    }
    
    ; Utiliser WMI pour obtenir l'utilisation CPU
    ; Note: En AutoHotkey v1, on utilise ComObjGet pour accéder à WMI
    try {
        wmi := ComObjGet("winmgmts:")
        query := "SELECT PercentProcessorTime FROM Win32_PerfRawData_PerfProc_Process WHERE IDProcess = " . pid
        processes := wmi.ExecQuery(query)
        
        cpuUsage := 0
        for process in processes {
            ; PercentProcessorTime est en 1/100 de seconde, donc on divise par le nombre de cœurs
            ; Pour simplifier, on utilise une méthode basique avec un échantillon
            cpuUsage := process.PercentProcessorTime
            break
        }
        
        ; Si on ne trouve pas le processus, retourner -1
        if (cpuUsage = 0 && !process) {
            return -1
        }
        
        ; Convertir en pourcentage approximatif
        ; Note: Cette méthode nécessite deux échantillons pour être précise
        ; Pour l'instant, on retourne une valeur basique
        return cpuUsage
    } catch e {
        ; Si WMI échoue, utiliser une méthode alternative avec PowerShell
        return GetProcessCPUUsagePS(pid)
    }
}

; Méthode de secours utilisant WMIC pour obtenir l'utilisation CPU
GetProcessCPUUsageWMIC(pid) {
    if (!pid || pid <= 0) {
        return -1
    }
    
    ; Utiliser WMIC pour obtenir l'utilisation CPU
    ; Note: WMIC est déprécié mais fonctionne encore sur Windows 10
    wmicCommand := "wmic process where processid=" . pid . " get PercentProcessorTime /value"
    
    try {
        ; Créer un fichier temporaire pour la sortie
        tempFile := A_Temp . "\cpu_usage_" . pid . ".txt"
        FileDelete, %tempFile%
        
        ; Exécuter WMIC et rediriger la sortie
        RunWait, %ComSpec% /c "%wmicCommand% > %tempFile%", , Hide
        
        ; Lire le fichier
        FileRead, output, %tempFile%
        FileDelete, %tempFile%
        
        ; Parser la sortie (format: PercentProcessorTime=XX)
        RegExMatch(output, "PercentProcessorTime=(\d+)", match)
        if (match1) {
            return match1
        }
    } catch e {
        ; Si WMIC échoue, retourner -1
        return -1
    }
    
    return -1
}

; Surveille l'utilisation CPU d'un processus sur une période donnée
; Retourne la moyenne CPU et détecte si le processus est figé
; pid: PID du processus à surveiller
; sampleInterval: Intervalle entre les échantillons en millisecondes (défaut: 1000)
; sampleCount: Nombre d'échantillons (défaut: 3)
; minCPUThreshold: Seuil minimum CPU en pourcentage pour considérer le processus comme actif (défaut: 0.1)
MonitorProcessCPU(pid, sampleInterval := 1000, sampleCount := 3, minCPUThreshold := 0.1) {
    if (!pid || pid <= 0) {
        return {frozen: true, avgCPU: 0, reason: "invalid_pid"}
    }
    
    ; Vérifier que le processus existe
    Process, Exist, %pid%
    if (ErrorLevel = 0) {
        return {frozen: true, avgCPU: 0, reason: "process_not_found"}
    }
    
    ; Collecter des échantillons CPU
    cpuSamples := []
    totalCPU := 0
    validSamples := 0
    
    ; Premier échantillon (référence) - initialiser la mesure
    ; La première mesure peut retourner 0 si c'est le premier échantillon pour ce PID
    firstSample := GetProcessCPUUsageSimple(pid)
    
    ; Attendre l'intervalle avant de prendre les échantillons réels
    ; Cela permet à GetProcessCPUUsageSimple d'avoir deux échantillons pour calculer un pourcentage
    Sleep, %sampleInterval%
    
    ; Prendre les échantillons
    Loop, %sampleCount% {
        cpuSample := GetProcessCPUUsageSimple(pid)
        if (cpuSample >= 0) {
            cpuSamples.Push(cpuSample)
            totalCPU += cpuSample
            validSamples++
        }
        if (A_Index < sampleCount) {
            Sleep, %sampleInterval%
        }
    }
    
    ; Calculer la moyenne
    if (validSamples = 0) {
        return {frozen: true, avgCPU: 0, reason: "no_samples"}
    }
    
    avgCPU := totalCPU / validSamples
    
    ; Vérifier si le processus est figé
    frozen := (avgCPU < minCPUThreshold)
    reason := frozen ? "cpu_too_low" : "active"
    
    return {frozen: frozen, avgCPU: avgCPU, samples: cpuSamples, reason: reason}
}

; Méthode simplifiée pour obtenir l'utilisation CPU d'un processus
; Utilise WMI via ComObjGet pour obtenir le pourcentage CPU directement
; Note: Cette méthode nécessite deux appels espacés pour être précise
; Pour la première mesure, on retourne 0 et on attend avant la deuxième mesure
GetProcessCPUUsageSimple(pid) {
    if (!pid || pid <= 0) {
        return -1
    }
    
    ; Utiliser WMI pour obtenir l'utilisation CPU en pourcentage
    ; Win32_PerfFormattedData_PerfProc_Process donne directement un pourcentage
    ; Cette classe nécessite deux échantillons espacés pour être précise
    static lastPIDs := {}  ; Stocker le dernier PID mesuré et sa valeur
    static lastCPUs := {}  ; Stocker la dernière valeur CPU pour chaque PID
    static lastTimes := {}  ; Stocker le dernier temps de mesure pour chaque PID
    
    try {
        wmi := ComObjGet("winmgmts:")
        query := "SELECT PercentProcessorTime FROM Win32_PerfFormattedData_PerfProc_Process WHERE IDProcess = " . pid
        processes := wmi.ExecQuery(query)
        
        cpuPercent := 0
        found := false
        for process in processes {
            ; PercentProcessorTime est un pourcentage (0-100) sur un seul cœur
            ; Pour obtenir l'utilisation totale, il faut diviser par le nombre de cœurs
            ; Mais pour la détection de gel, on peut utiliser la valeur directement
            cpuPercent := process.PercentProcessorTime
            found := true
            break
        }
        
        if (found) {
            ; Convertir en nombre et retourner
            cpuPercent := cpuPercent + 0.0
            
            ; Stocker la dernière valeur pour ce PID
            lastCPUs[pid] := cpuPercent
            lastTimes[pid] := A_TickCount
            
            return cpuPercent
        } else {
            ; Processus non trouvé dans WMI
            return -1
        }
    } catch e {
        ; Si WMI échoue, utiliser PowerShell comme fallback
        return GetProcessCPUUsagePS(pid)
    }
    
    return -1
}

; Méthode alternative utilisant PowerShell avec Get-Counter
GetProcessCPUUsagePS(pid) {
    if (!pid || pid <= 0) {
        return -1
    }
    
    ; Utiliser PowerShell avec Get-Counter pour obtenir l'utilisation CPU
    ; Cette méthode nécessite deux échantillons, donc on utilise une méthode statique pour stocker les valeurs
    static lastSampleTime := {}
    static lastCPUValue := {}
    
    currentTime := A_TickCount
    
    ; Vérifier si on a déjà un échantillon précédent (minimum 1 seconde d'intervalle)
    if (lastSampleTime.HasKey(pid) && lastCPUValue.HasKey(pid)) {
        timeDiff := (currentTime - lastSampleTime[pid]) / 1000.0  ; En secondes
        if (timeDiff < 1.0) {
            ; Trop tôt, retourner la dernière valeur
            return lastCPUValue[pid]
        }
    }
    
    ; Obtenir le temps CPU total du processus via PowerShell
    psCommand := "(Get-Process -Id " . pid . " -ErrorAction SilentlyContinue | Select-Object -ExpandProperty CPU)"
    
    ; Créer un fichier temporaire pour la sortie
    tempFile := A_Temp . "\cpu_" . pid . "_" . A_TickCount . ".txt"
    FileDelete, %tempFile%
    
    ; Exécuter PowerShell et rediriger la sortie
    RunWait, %ComSpec% /c powershell -Command "%psCommand% > %tempFile%", , Hide
    
    ; Lire le fichier
    FileRead, psOutput, %tempFile%
    FileDelete, %tempFile%
    
    if (psOutput) {
        ; Nettoyer la sortie
        psOutput := RegExReplace(psOutput, "\s+", "")
        psOutput := RegExReplace(psOutput, "\r\n", "")
        cpuSeconds := psOutput + 0.0  ; Convertir en nombre
        
        ; Si on a un échantillon précédent, calculer le pourcentage
        if (lastSampleTime.HasKey(pid) && lastCPUValue.HasKey(pid)) {
            timeDiff := (currentTime - lastSampleTime[pid]) / 1000.0  ; En secondes
            if (timeDiff > 0) {
                cpuDiff := cpuSeconds - lastCPUValue[pid]
                ; Le temps CPU est en secondes, donc on calcule le pourcentage
                ; cpuPercent = (cpuDiff / timeDiff) * 100
                cpuPercent := (cpuDiff / timeDiff) * 100
                
                ; Limiter à 0-100%
                if (cpuPercent < 0) {
                    cpuPercent := 0
                } else if (cpuPercent > 100) {
                    cpuPercent := 100
                }
                
                ; Mettre à jour les valeurs
                lastSampleTime[pid] := currentTime
                lastCPUValue[pid] := cpuSeconds
                
                return cpuPercent
            }
        } else {
            ; Premier échantillon, stocker la valeur
            lastSampleTime[pid] := currentTime
            lastCPUValue[pid] := cpuSeconds
            return 0  ; Pas encore de pourcentage calculable
        }
    }
    
    return -1
}

; Obtient le PID d'un processus MuMu à partir du nom de l'instance
; Retourne le PID du processus MuMuPlayer.exe associé à l'instance
GetMumuProcessPID(instanceNum) {
    ; Chercher la fenêtre MuMu pour cette instance
    ; L'instance est identifiée par son numéro (1, 2, 3, etc.)
    ret := WinExist(instanceNum)
    if (ret) {
        WinGet, pid, PID, ahk_id %ret%
        if (pid && pid > 0) {
            ; Vérifier que le processus est bien MuMuPlayer.exe
            WinGet, processName, ProcessName, ahk_id %ret%
            if (processName = "MuMuPlayer.exe" || InStr(processName, "MuMu")) {
                return pid
            }
        }
    }
    
    ; Si on ne trouve pas via WinExist, chercher via la classe de fenêtre MuMu
    ; MuMu utilise généralement Qt5156QWindowIcon comme classe de fenêtre
    DetectHiddenWindows, On
    WinGet, winList, List, %instanceNum% ahk_class Qt5156QWindowIcon
    Loop, %winList%
    {
        winID := winList%A_Index%
        if (winID) {
            WinGet, pid, PID, ahk_id %winID%
            if (pid && pid > 0) {
                ; Vérifier que le processus est bien MuMuPlayer.exe
                WinGet, processName, ProcessName, ahk_id %winID%
                if (processName = "MuMuPlayer.exe" || InStr(processName, "MuMu")) {
                    return pid
                }
            }
        }
    }
    
    ; Si on ne trouve toujours pas, chercher via MuMuPlayer.exe en comparant les fenêtres
    ; On cherche tous les processus MuMuPlayer.exe et on essaie de trouver celui qui correspond à l'instance
    Process, Exist, MuMuPlayer.exe
    if (ErrorLevel > 0) {
        ; Il y a au moins un processus MuMuPlayer.exe
        ; Chercher la fenêtre avec le titre correspondant à l'instance
        DetectHiddenWindows, On
        WinGet, allWindows, List, ahk_exe MuMuPlayer.exe
        Loop, %allWindows%
        {
            winID := allWindows%A_Index%
            if (winID) {
                WinGetTitle, winTitle, ahk_id %winID%
                ; Vérifier si le titre de la fenêtre correspond à l'instance
                if (winTitle = instanceNum || InStr(winTitle, instanceNum)) {
                    WinGet, pid, PID, ahk_id %winID%
                    if (pid && pid > 0) {
                        return pid
                    }
                }
            }
        }
    }
    
    ; Si on ne trouve toujours pas, retourner 0
    return 0
}

; Obtient le PID d'un script AutoHotkey à partir de son nom
GetScriptProcessPID(scriptName) {
    DetectHiddenWindows, On
    WinGet, IDList, List, ahk_class AutoHotkey
    Loop %IDList%
    {
        ID := IDList%A_Index%
        WinGetTitle, ATitle, ahk_id %ID%
        if (InStr(ATitle, "\" . scriptName)) {
            WinGet, pid, PID, ahk_id %ID%
            if (pid) {
                return pid
            }
        }
    }
    
    ; Si on ne trouve pas via la fenêtre, chercher via le processus
    Process, Exist, %scriptName%
    if (ErrorLevel > 0) {
        return ErrorLevel
    }
    
    return 0
}
