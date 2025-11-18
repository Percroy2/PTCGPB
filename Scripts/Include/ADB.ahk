global adbPort, adbShell, adbPath
global AdbCacheEnabled, AdbCacheTTL, AdbBatchEnabled, AdbConnectionPoolSize, AdbPerformanceLogging
#Include *i %A_LineFile%\..\Gdip_All.ahk

;-------------------------------------------------------------------------------
; Cache des résultats de commandes ADB fréquentes
;-------------------------------------------------------------------------------
GetCachedAdbResult(command, ttl := 5000) {
    static AdbCommandCache := Object()
    static AdbCommandTimestamps := Object()
    
    ; Vérifier si le cache est activé
    if (!AdbCacheEnabled) {
        return ""
    }
    
    ; Vérifier si la commande est dans le cache
    if (AdbCommandCache.HasKey(command) && AdbCommandTimestamps.HasKey(command)) {
        cacheTime := AdbCommandTimestamps[command]
        cacheAge := A_TickCount - cacheTime
        
        ; Si le cache est encore valide, retourner le résultat
        if (cacheAge < ttl) {
            return AdbCommandCache[command]
        } else {
            ; Cache expiré, supprimer
            AdbCommandCache.Delete(command)
            AdbCommandTimestamps.Delete(command)
        }
    }
    
    return ""
}

SetCachedAdbResult(command, result, ttl := 5000) {
    static AdbCommandCache := Object()
    static AdbCommandTimestamps := Object()
    
    ; Vérifier si le cache est activé
    if (!AdbCacheEnabled) {
        return
    }
    
    ; Vérifier si la commande est "cacheable" (read-only)
    if (IsAdbCommandCacheable(command)) {
        AdbCommandCache[command] := result
        AdbCommandTimestamps[command] := A_TickCount
    }
}

ClearAdbCommandCache() {
    static AdbCommandCache := Object()
    static AdbCommandTimestamps := Object()
    
    AdbCommandCache := Object()
    AdbCommandTimestamps := Object()
}

IsAdbCommandCacheable(command) {
    ; Liste des commandes read-only qui peuvent être mises en cache
    cacheablePatterns := ["getprop", "pm list", "dumpsys", "cat ", "ls ", "stat ", "df ", "ps ", "id ", "whoami"]
    
    for index, pattern in cacheablePatterns {
        if (InStr(command, pattern)) {
            return true
        }
    }
    
    return false
}

;-------------------------------------------------------------------------------
; Commandes batch pour réduire les appels ADB
;-------------------------------------------------------------------------------
adbExecuteBatch(commandsArray) {
    global adbShell, adbPath, adbPort, AdbPerformanceLogging, AdbBatchEnabled
    
    ; Vérifier si le tableau est vide
    if (!AdbBatchEnabled || !commandsArray || !commandsArray.MaxIndex()) {
        return []
    }
    
    startTime := A_TickCount
    
    ; Utiliser le shell persistant si disponible
    if (IsObject(adbShell) && adbShell.Status = 0) {
        return adbExecuteBatchShell(commandsArray)
    } else {
        ; Fallback vers CmdRet pour chaque commande
        results := []
        for index, command in commandsArray {
            deviceAddress := "127.0.0.1:" . adbPort
            fullCommand := """" . adbPath . """ -s " . deviceAddress . " shell " . command
            result := CmdRet(fullCommand)
            results.Push(result)
        }
        return results
    }
}

adbExecuteBatchShell(commandsArray) {
    global adbShell
    
    results := []
    batchCommand := ""
    
    ; Construire la commande batch avec séparateur &&
    for index, command in commandsArray {
        if (batchCommand != "") {
            batchCommand .= " && "
        }
        ; Ajouter un marqueur unique pour chaque commande
        marker := "echo BATCH_MARKER_" . index
        batchCommand .= command . " && " . marker
    }
    
    ; Ajouter un marqueur final
    batchCommand .= " && echo BATCH_DONE"
    
    try {
        adbEnsureShell()
        adbShell.StdIn.WriteLine(batchCommand)
        
        ; Lire les résultats
        startTick := A_TickCount
        currentResult := ""
        currentIndex := 1
        
        while (A_TickCount - startTick) < 30000 { ; Timeout de 30 secondes
            if (adbShell.Status != 0) {
                throw Exception("ADB shell terminated during batch execution.")
            }
            
            elapsed := A_TickCount - startTick
            
            ; Protection: éviter ReadLine() si stream terminé et pas de résultat après 500ms
            if (elapsed > 500 && currentResult = "" && currentIndex <= commandsArray.MaxIndex()) {
                if (adbShell.StdOut.AtEndOfStream) {
                    results.Push("")
                    currentResult := ""
                    currentIndex++
                    continue
                }
            }
            
            if !adbShell.StdOut.AtEndOfStream {
                if (elapsed < 100 && currentResult = "" && currentIndex = 1) {
                    Sleep, 50
                    continue
                }
                
                line := adbShell.StdOut.ReadLine()
                
                if (InStr(line, "BATCH_DONE")) {
                    ; Dernier résultat
                    if (currentResult != "") {
                        results.Push(Trim(currentResult))
                    }
                    break
                } else if (InStr(line, "BATCH_MARKER_")) {
                    ; Marqueur trouvé, sauvegarder le résultat précédent
                    if (currentResult != "") {
                        results.Push(Trim(currentResult))
                    }
                    currentResult := ""
                    currentIndex++
                } else {
                    ; Ligne de résultat
                    if (currentResult != "") {
                        currentResult .= "`n"
                    }
                    currentResult .= line
                }
            } else {
                Sleep, 50
            }
        }
        
        ; S'assurer que tous les résultats sont collectés
        commandsCount := commandsArray.MaxIndex() ? commandsArray.MaxIndex() : 0
        resultsCount := results.MaxIndex() ? results.MaxIndex() : 0
        while (resultsCount < commandsCount) {
            results.Push("")
            resultsCount++
        }
        
    } catch e {
        errorMessage := IsObject(e) ? e.Message : e
        LogToFile("ADB batch error: " . errorMessage, "ADB.txt")
        ; Retourner des résultats vides en cas d'erreur
        commandsCount := commandsArray.MaxIndex() ? commandsArray.MaxIndex() : 0
        resultsCount := results.MaxIndex() ? results.MaxIndex() : 0
        while (resultsCount < commandsCount) {
            results.Push("")
            resultsCount++
        }
    }
    
    ; Logger les performances batch
    if (AdbPerformanceLogging && IsFunc("LogAdbPerformance")) {
        duration := A_TickCount - startTime
        commandsCount := commandsArray.MaxIndex() ? commandsArray.MaxIndex() : 0
        LogAdbPerformance("Batch[" . commandsCount . " commands]", "Batch", duration)
        if (IsFunc("GetAdbPerformanceStats")) {
            static AdbPerformanceStats := Object()
            if (!AdbPerformanceStats.HasKey("batchCommands")) {
                AdbPerformanceStats.batchCommands := 0
            }
            AdbPerformanceStats.batchCommands += commandsCount
        }
    }
    
    return results
}

adbWriteRawBatch(commandsArray) {
    global adbShell
    
    ; Vérifier si le tableau est vide
    if (!AdbBatchEnabled || !commandsArray || !commandsArray.MaxIndex()) {
        return false
    }
    
    try {
        adbEnsureShell()
        
        ; Écrire toutes les commandes en une seule fois avec séparateur &&
        batchCommand := ""
        for index, command in commandsArray {
            if (batchCommand != "") {
                batchCommand .= " && "
            }
            batchCommand .= command
        }
        
        adbShell.StdIn.WriteLine(batchCommand)
        return true
    } catch e {
        errorMessage := IsObject(e) ? e.Message : e
        LogToFile("ADB write batch error: " . errorMessage, "ADB.txt")
        adbShell := ""
        return false
    }
}

;-------------------------------------------------------------------------------
; Pool de connexions ADB réutilisables
;-------------------------------------------------------------------------------
InitializeAdbConnectionPool(size := 3) {
    static AdbConnectionPool := Object()
    static AdbConnectionPoolInitialized := false
    global adbPath, adbPort, Debug
    
    if (AdbConnectionPoolInitialized) {
        return
    }
    
    poolSize := AdbConnectionPoolSize ? AdbConnectionPoolSize : size
    if (poolSize < 1) {
        poolSize := 1
    }
    if (poolSize > 10) {
        poolSize := 10 ; Limiter à 10 connexions max
    }
    
    AdbConnectionPool := Object()
    
    Loop %poolSize% {
        try {
            connection := ComObjCreate("WScript.Shell").Exec(adbPath . " -s 127.0.0.1:" . adbPort . " shell")
            Sleep, 500
            if (connection.Status = 0) {
                connection.StdIn.WriteLine("su")
                Sleep, 200
                AdbConnectionPool.Push({connection: connection, inUse: false, lastUsed: A_TickCount})
            }
        } catch e {
            errorMessage := IsObject(e) ? e.Message : e
            LogToFile("ADB pool initialization error: " . errorMessage, "ADB.txt")
        }
    }
    
    AdbConnectionPoolInitialized := true
    poolCount := AdbConnectionPool.MaxIndex() ? AdbConnectionPool.MaxIndex() : 0
    LogToFile("ADB connection pool initialized with " . poolCount . " connections", "ADB.txt")
}

GetAdbConnectionFromPool() {
    static AdbConnectionPool := Object()
    global adbPath, adbPort, Debug
    
    ; Initialiser le pool si nécessaire
    if (!AdbConnectionPool.MaxIndex()) {
        InitializeAdbConnectionPool()
    }
    
    ; Chercher une connexion disponible
    ; Collecter les indices à supprimer (on ne peut pas modifier pendant l'itération)
    deadIndices := []
    for index, poolEntry in AdbConnectionPool {
        if (!poolEntry.inUse && IsObject(poolEntry.connection)) {
            ; Vérifier la santé de la connexion
            if (poolEntry.connection.Status = 0) {
                poolEntry.inUse := true
                poolEntry.lastUsed := A_TickCount
                return poolEntry.connection
            } else {
                ; Connexion morte, marquer pour suppression
                deadIndices.Push(index)
            }
        }
    }
    ; Supprimer les connexions mortes
    for index, deadIndex in deadIndices {
        AdbConnectionPool.Delete(deadIndex)
    }
    
    ; Aucune connexion disponible, en créer une nouvelle
    try {
        connection := ComObjCreate("WScript.Shell").Exec(adbPath . " -s 127.0.0.1:" . adbPort . " shell")
        Sleep, 500
        if (connection.Status = 0) {
            connection.StdIn.WriteLine("su")
            Sleep, 200
            poolEntry := {connection: connection, inUse: true, lastUsed: A_TickCount}
            AdbConnectionPool.Push(poolEntry)
            return connection
        }
    } catch e {
        errorMessage := IsObject(e) ? e.Message : e
        LogToFile("ADB pool connection creation error: " . errorMessage, "ADB.txt")
    }
    
    ; Fallback vers la connexion globale
    return ""
}

ReturnAdbConnectionToPool(connection) {
    static AdbConnectionPool := Object()
    
    if (!IsObject(connection)) {
        return
    }
    
    ; Trouver l'entrée dans le pool et la marquer comme disponible
    for index, poolEntry in AdbConnectionPool {
        if (poolEntry.connection = connection) {
            poolEntry.inUse := false
            poolEntry.lastUsed := A_TickCount
            
            ; Vérifier la santé de la connexion
            if (poolEntry.connection.Status != 0) {
                ; Connexion morte, la retirer du pool
                AdbConnectionPool.Delete(index)
            }
            return
        }
    }
}

CleanupAdbConnectionPool() {
    static AdbConnectionPool := Object()
    
    for index, poolEntry in AdbConnectionPool {
        if (IsObject(poolEntry.connection)) {
            try {
                poolEntry.connection.Terminate()
            } catch e {
                ; Ignorer les erreurs de nettoyage
            }
        }
    }
    
    AdbConnectionPool := Object()
    LogToFile("ADB connection pool cleaned up", "ADB.txt")
}

;-------------------------------------------------------------------------------
; Wrapper intelligent pour exécution ADB avec optimisation automatique
;-------------------------------------------------------------------------------
adbExecute(command, useCache := true, usePool := true) {
    global adbShell, adbPath, adbPort, AdbCacheEnabled, AdbCacheTTL, AdbConnectionPoolSize
    
    startTime := A_TickCount
    cacheTTL := AdbCacheTTL ? AdbCacheTTL : 5000
    method := "Shell"
    result := ""
    
    ; Générer un marqueur unique pour cette commande
    Random, randomNum, 1000, 9999
    marker := "EXEC_MARKER_" . A_TickCount . "_" . randomNum
    
    ; 1. Vérifier le cache si activé
    if (useCache && AdbCacheEnabled) {
        cachedResult := GetCachedAdbResult(command, cacheTTL)
        if (cachedResult != "") {
            if (IsFunc("LogAdbPerformance")) {
                LogAdbPerformance(command, "Cache", A_TickCount - startTime)
            }
            return cachedResult
        }
    }
    
    ; 2. Utiliser le pool de connexions si activé
    if (usePool && AdbConnectionPoolSize && AdbConnectionPoolSize > 0) {
        if (IsFunc("LogToFile")) {
            LogToFile("[ADB] adbExecute: Attempting to use connection pool for: " . SubStr(command, 1, 50), "ADB.txt")
        }
        poolConnection := GetAdbConnectionFromPool()
        if (IsObject(poolConnection) && poolConnection.Status = 0) {
            if (IsFunc("LogToFile")) {
                LogToFile("[ADB] adbExecute: Got connection from pool, executing command", "ADB.txt")
            }
            try {
                ; Envoyer la commande suivie d'un marqueur pour détecter la fin
                fullCommand := command . " && echo " . marker
                if (IsFunc("LogToFile")) {
                    LogToFile("[ADB] adbExecute (Pool): Sending command with marker: " . SubStr(fullCommand, 1, 80), "ADB.txt")
                }
                poolConnection.StdIn.WriteLine(fullCommand)
                
                ; Attendre la réponse avec le marqueur
                startTick := A_TickCount
                timeout := 10000  ; 10 secondes max
                markerFound := false
                linesRead := 0
                lastStreamCheck := A_TickCount
                
                while (A_TickCount - startTick) < timeout {
                    if (poolConnection.Status != 0) {
                        if (IsFunc("LogToFile")) {
                            LogToFile("[ADB] adbExecute (Pool): Connection terminated (Status: " . poolConnection.Status . ")", "ADB.txt")
                        }
                        throw Exception("ADB pool connection terminated.")
                    }
                    
                    elapsed := A_TickCount - startTick
                    
                    ; Protection: Ne jamais appeler ReadLine() si elapsed > 300ms et aucune ligne lue
                    ; ReadLine() est bloquant et ne peut pas être interrompu
                    if (elapsed > 300 && linesRead = 0 && !markerFound) {
                        if (IsFunc("LogToFile")) {
                            LogToFile("[ADB] adbExecute (Pool): No output after 300ms, assuming command completed", "ADB.txt")
                        }
                        markerFound := true
                        break
                    }
                    
                    ; Lire depuis le stream seulement si elapsed <= 300ms (évite le blocage)
                    if (!poolConnection.StdOut.AtEndOfStream && elapsed <= 300) {
                        if (elapsed < 100 && linesRead = 0) {
                            Sleep, 50
                            continue
                        }
                        
                        try {
                            line := poolConnection.StdOut.ReadLine()
                            linesRead++
                            if (IsFunc("LogToFile") && linesRead <= 5) {
                                LogToFile("[ADB] adbExecute (Pool): Read line " . linesRead . ": " . SubStr(line, 1, 100), "ADB.txt")
                            }
                            if (InStr(line, marker)) {
                                markerFound := true
                                if (IsFunc("LogToFile")) {
                                    LogToFile("[ADB] adbExecute (Pool): Marker found after " . elapsed . "ms, " . linesRead . " lines read", "ADB.txt")
                                }
                                break
                            } else if (InStr(line, "BATCH_MARKER_") || InStr(line, "BATCH_DONE")) {
                                continue
                            } else {
                                result .= line . "`n"
                            }
                            lastStreamCheck := A_TickCount
                        } catch e {
                            if (elapsed > 500 && linesRead = 0) {
                                if (IsFunc("LogToFile")) {
                                    LogToFile("[ADB] adbExecute (Pool): ReadLine error, assuming completed: " . e.Message, "ADB.txt")
                                }
                                markerFound := true
                                break
                            }
                            Sleep, 50
                        }
                    } else {
                        Sleep, 50
                    }
                }
                
                if (!markerFound) {
                    elapsed := A_TickCount - startTick
                    if (IsFunc("LogToFile")) {
                        LogToFile("[ADB] adbExecute (Pool): No marker found after " . elapsed . "ms, lines read: " . linesRead, "ADB.txt")
                    }
                    ; Fallback: considérer terminé si pas de résultat après timeout
                    if (result = "" && elapsed >= 2000) {
                        markerFound := true
                    } else if (elapsed >= timeout) {
                        markerFound := true
                    }
                }
                
                ; Si le marqueur a été trouvé, la commande est terminée (même si result est vide)
                if (markerFound) {
                    result := Trim(result)
                    method := "Pool"
                    ReturnAdbConnectionToPool(poolConnection)
                    if (IsFunc("LogToFile")) {
                        LogToFile("[ADB] adbExecute (Pool): Command completed - " . SubStr(command, 1, 50), "ADB.txt")
                    }
                    ; Sortir de la fonction ici pour éviter les fallbacks inutiles
                    goto adbExecute_end
                } else {
                    ; Marqueur non trouvé, continuer vers les fallbacks
                    result := ""
                }
            } catch e {
                errorMessage := IsObject(e) ? e.Message : e
                LogToFile("ADB pool execution error: " . errorMessage, "ADB.txt")
                ReturnAdbConnectionToPool(poolConnection)
                ; Fallback vers shell persistant
                result := ""
            }
        }
    }
    
    ; 3. Utiliser le shell persistant si disponible
    if (result = "" && IsObject(adbShell) && adbShell.Status = 0) {
        if (IsFunc("LogToFile")) {
            LogToFile("[ADB] adbExecute: Using persistent shell for: " . SubStr(command, 1, 50), "ADB.txt")
        }
        try {
            ; Envoyer la commande suivie d'un marqueur pour détecter la fin
            adbShell.StdIn.WriteLine(command . " && echo " . marker)
            
            ; Attendre la réponse avec le marqueur
            startTick := A_TickCount
            timeout := 10000  ; 10 secondes max
            markerFound := false
            
            while (A_TickCount - startTick) < timeout {
                if (adbShell.Status != 0) {
                    throw Exception("ADB shell terminated.")
                }
                if !adbShell.StdOut.AtEndOfStream {
                    line := adbShell.StdOut.ReadLine()
                    if (InStr(line, marker)) {
                        ; Marqueur trouvé, la commande est terminée
                        markerFound := true
                        break
                    } else if (InStr(line, "BATCH_MARKER_") || InStr(line, "BATCH_DONE")) {
                        ; Ignorer les marqueurs batch
                        continue
                    } else {
                        ; Ligne de résultat
                        result .= line . "`n"
                    }
                } else {
                    Sleep, 50
                }
            }
            
            if (!markerFound && result = "") {
                ; Pas de marqueur et pas de résultat, peut-être une commande sans sortie qui s'est terminée
                ; Attendre un peu plus pour être sûr
                Sleep, 200
            }
            
            ; Si le marqueur a été trouvé, la commande est terminée (même si result est vide)
            if (markerFound) {
                result := Trim(result)
                method := "Shell"
                if (IsFunc("LogToFile")) {
                    LogToFile("[ADB] adbExecute (Shell): Command completed - " . SubStr(command, 1, 50), "ADB.txt")
                }
                ; Sortir de la fonction ici pour éviter les fallbacks inutiles
                goto adbExecute_end
            } else {
                ; Marqueur non trouvé, continuer vers les fallbacks
                result := ""
            }
        } catch e {
            errorMessage := IsObject(e) ? e.Message : e
            LogToFile("ADB shell execution error: " . errorMessage, "ADB.txt")
            adbShell := ""
            result := ""
        }
    }
    
    ; 4. Si aucune méthode n'a fonctionné, initialiser le shell et réessayer
    if (result = "") {
        if (IsFunc("LogToFile")) {
            LogToFile("[ADB] adbExecute: No result, initializing shell and retrying", "ADB.txt")
        }
        try {
            adbEnsureShell()
            if (IsObject(adbShell) && adbShell.Status = 0) {
                ; Réessayer avec le shell
                adbShell.StdIn.WriteLine(command . " && echo " . marker)
                
                startTick := A_TickCount
                timeout := 10000
                markerFound := false
                
                while (A_TickCount - startTick) < timeout {
                    if (adbShell.Status != 0) {
                        throw Exception("ADB shell terminated.")
                    }
                    if !adbShell.StdOut.AtEndOfStream {
                        line := adbShell.StdOut.ReadLine()
                        if (InStr(line, marker)) {
                            markerFound := true
                            break
                        } else if (InStr(line, "BATCH_MARKER_") || InStr(line, "BATCH_DONE")) {
                            continue
                        } else {
                            result .= line . "`n"
                        }
                    } else {
                        Sleep, 50
                    }
                }
                
                if (!markerFound && result = "") {
                    Sleep, 200
                }
                
                ; Si le marqueur a été trouvé, la commande est terminée
                if (markerFound) {
                    result := Trim(result)
                    method := "Shell"
                } else {
                    throw Exception("Failed to receive marker from ADB command.")
                }
            } else {
                throw Exception("Failed to initialize ADB shell.")
            }
        } catch e {
            errorMessage := IsObject(e) ? e.Message : e
            LogToFile("ADB execute failed after retry: " . errorMessage, "ADB.txt")
            throw Exception("ADB command execution failed: " . errorMessage)
        }
    }
    
    adbExecute_end:
    ; 5. Mettre en cache le résultat si applicable
    if (useCache && AdbCacheEnabled && result != "") {
        SetCachedAdbResult(command, result, cacheTTL)
    }
    
    ; 6. Logger les performances
    if (IsFunc("LogAdbPerformance")) {
        LogAdbPerformance(command, method, A_TickCount - startTime)
    }
    
    return result
}

;-------------------------------------------------------------------------------
; Logging et métriques de performance ADB
;-------------------------------------------------------------------------------
LogAdbPerformance(command, method, duration) {
    static AdbPerformanceStats := Object()
    global AdbPerformanceLogging
    
    ; Vérifier si le logging est activé
    if (!AdbPerformanceLogging) {
        return
    }
    
    ; Initialiser les statistiques si nécessaire
    if (!AdbPerformanceStats.HasKey("totalCommands")) {
        AdbPerformanceStats.totalCommands := 0
        AdbPerformanceStats.cacheHits := 0
        AdbPerformanceStats.poolCommands := 0
        AdbPerformanceStats.shellCommands := 0
        AdbPerformanceStats.cmdRetCommands := 0
        AdbPerformanceStats.totalDuration := 0
        AdbPerformanceStats.batchCommands := 0
    }
    
    ; Mettre à jour les statistiques
    AdbPerformanceStats.totalCommands++
    AdbPerformanceStats.totalDuration += duration
    
    if (method = "Cache") {
        AdbPerformanceStats.cacheHits++
    } else if (method = "Pool") {
        AdbPerformanceStats.poolCommands++
    } else if (method = "Shell") {
        AdbPerformanceStats.shellCommands++
    } else if (method = "CmdRet") {
        AdbPerformanceStats.cmdRetCommands++
    }
    
    ; Logger la performance individuelle
    if (IsFunc("LogToFile")) {
        LogToFile("[ADB Performance] Command: " . SubStr(command, 1, 50) . " | Method: " . method . " | Duration: " . duration . "ms", "ADB_Performance.txt")
    }
}

GetAdbPerformanceStats() {
    static AdbPerformanceStats := Object()
    
    if (!AdbPerformanceStats.HasKey("totalCommands") || AdbPerformanceStats.totalCommands = 0) {
        return {totalCommands: 0, cacheHitRate: 0, avgDuration: 0, poolRate: 0, shellRate: 0, cmdRetRate: 0}
    }
    
    cacheHitRate := (AdbPerformanceStats.cacheHits / AdbPerformanceStats.totalCommands) * 100
    poolRate := (AdbPerformanceStats.poolCommands / AdbPerformanceStats.totalCommands) * 100
    shellRate := (AdbPerformanceStats.shellCommands / AdbPerformanceStats.totalCommands) * 100
    cmdRetRate := (AdbPerformanceStats.cmdRetCommands / AdbPerformanceStats.totalCommands) * 100
    avgDuration := AdbPerformanceStats.totalDuration / AdbPerformanceStats.totalCommands
    
    ; AutoHotkey v1 ne supporte pas les objets multi-lignes, créer l'objet sur une seule ligne
    return {totalCommands: AdbPerformanceStats.totalCommands, cacheHits: AdbPerformanceStats.cacheHits, cacheHitRate: Round(cacheHitRate, 2), poolCommands: AdbPerformanceStats.poolCommands, poolRate: Round(poolRate, 2), shellCommands: AdbPerformanceStats.shellCommands, shellRate: Round(shellRate, 2), cmdRetCommands: AdbPerformanceStats.cmdRetCommands, cmdRetRate: Round(cmdRetRate, 2), avgDuration: Round(avgDuration, 2), batchCommands: AdbPerformanceStats.batchCommands}
}

ResetAdbPerformanceStats() {
    static AdbPerformanceStats := Object()
    
    AdbPerformanceStats.totalCommands := 0
    AdbPerformanceStats.cacheHits := 0
    AdbPerformanceStats.poolCommands := 0
    AdbPerformanceStats.shellCommands := 0
    AdbPerformanceStats.cmdRetCommands := 0
    AdbPerformanceStats.totalDuration := 0
    AdbPerformanceStats.batchCommands := 0
}

KillADBProcesses() {
    ; Use AHK's Process command to close adb.exe
    Process, Close, adb.exe
    ; Fallback to taskkill for robustness
    RunWait, %ComSpec% /c taskkill /IM adb.exe /F /T,, Hide
}

findAdbPorts(baseFolder := "C:\Program Files\Netease") {
    global scriptName

    ; Initialize variables
    mumuFolder = %baseFolder%\MuMuPlayerGlobal-12.0\vms\*
    if !FileExist(mumuFolder)
        mumuFolder = %baseFolder%\MuMu Player 12\vms\*

    if !FileExist(mumuFolder){
        MsgBox, 16, , Can't Find MuMu, try old MuMu installer in Discord #announcements, otherwise double check your folder path setting!`nDefault path is C:\Program Files\Netease
        ExitApp
    }
    ; Loop through all directories in the base folder
    Loop, Files, %mumuFolder%, D  ; D flag to include directories only
    {
        folder := A_LoopFileFullPath
        configFolder := folder "\configs"  ; The config folder inside each directory

        ; Check if config folder exists
        IfExist, %configFolder%
        {
            ; Define paths to vm_config.json and extra_config.json
            vmConfigFile := configFolder "\vm_config.json"
            extraConfigFile := configFolder "\extra_config.json"

            ; Check if vm_config.json exists and read adb host port
            IfExist, %vmConfigFile%
            {
                FileRead, vmConfigContent, %vmConfigFile%
                ; Parse the JSON for adb host port
                RegExMatch(vmConfigContent, """host_port"":\s*""(\d+)""", adbHostPort)
                adbPort := adbHostPort1  ; Capture the adb host port value
            }

            ; Check if extra_config.json exists and read playerName
            IfExist, %extraConfigFile%
            {
                FileRead, extraConfigContent, %extraConfigFile%
                ; Parse the JSON for playerName
                RegExMatch(extraConfigContent, """playerName"":\s*""(.*?)""", playerName)
                if(playerName1 = scriptName) {
                    return adbPort
                }
            }
        }
    }
}

ConnectAdb(folderPath := "C:\Program Files\Netease") {
    adbPort := findAdbPorts(folderPath)

    adbPath := folderPath . "\MuMuPlayerGlobal-12.0\shell\adb.exe"

    if !FileExist(adbPath) ;if international mumu file path isn't found look for chinese domestic path
        adbPath := folderPath . "\MuMu Player 12\shell\adb.exe"
    if !FileExist(adbPath) ;MuMu Player 12 v5 supported
        adbPath := folderPath . "\MuMuPlayerGlobal-12.0\nx_main\adb.exe"
    if !FileExist(adbPath) ;MuMu Player 12 v5 supported
        adbPath := folderPath . "\MuMu Player 12\nx_main\adb.exe"

    if !FileExist(adbPath)
        MsgBox Check folder path! It must contain the MuMuPlayer12 folder! `nDefault is C:\Program Files\Netease

    if(!adbPort) {
        Msgbox, Invalid port... Check the common issues section in the readme/github guide.
        ExitApp
    }

    MaxRetries := 5
    RetryCount := 0
    connected := false
    ip := "127.0.0.1:" . adbPort ; Specify the connection IP:port

    CreateStatusMessage("Connecting to ADB...",,,, false)

    Loop %MaxRetries% {
        ; Attempt to connect using CmdRet
        connectionResult := CmdRet(adbPath . " connect " . ip)

        ; Check for successful connection in the output
        if InStr(connectionResult, "connected to " . ip) {
            connected := true
            CreateStatusMessage("ADB connected successfully.",,,, false)
            
            ; Initialiser le pool de connexions si activé
            if (AdbConnectionPoolSize && AdbConnectionPoolSize > 0 && IsFunc("InitializeAdbConnectionPool")) {
                InitializeAdbConnectionPool()
            }
            
            return true
        } else {
            RetryCount++
            CreateStatusMessage("ADB connection failed.`nRetrying (" . RetryCount . "/" . MaxRetries . ")...",,,, false)
            Sleep, 2000
        }
    }

    if !connected {
        if (Debug)
            CreateStatusMessage("Failed to connect to ADB after multiple retries. Please check your emulator and port settings.")
        else
            CreateStatusMessage("Failed to connect to ADB.",,,, false)
        Reload
    }
}

DisableBackgroundServices() {
    global adbPath, adbPort

    if (!adbPath || !adbPort)
        return

    commands := []
    commands.Push("pm disable-user --user 0 ""com.google.android.gms/.chimera.PersistentIntentOperationService""")
    commands.Push("pm disable-user --user 0 ""com.google.android.gms/com.google.android.location.reporting.service.ReportingAndroidService""")
    commands.Push("pm disable-user --user 0 com.mumu.store")

    ; Utiliser le batch si activé, sinon fallback vers méthode classique
    if (AdbBatchEnabled) {
        results := adbExecuteBatch(commands)
        for index, result in results {
            LogToFile("DisableService result (" . commands[index] . "): " . result, "ADB.txt")
        }
    } else {
        deviceAddress := "127.0.0.1:" . adbPort
        for index, command in commands {
            fullCommand := """" . adbPath . """ -s " . deviceAddress . " shell " . command
            result := CmdRet(fullCommand)
            LogToFile("DisableService result (" . command . "): " . result, "ADB.txt")
        }
    }
}

CmdRet(sCmd, callBackFuncObj := "", encoding := "") {
    static HANDLE_FLAG_INHERIT := 0x00000001, flags := HANDLE_FLAG_INHERIT
        , STARTF_USESTDHANDLES := 0x100, CREATE_NO_WINDOW := 0x08000000

    ; Vérifier le cache avant d'exécuter la commande
    cacheTTL := AdbCacheTTL ? AdbCacheTTL : 5000
    cachedResult := GetCachedAdbResult(sCmd, cacheTTL)
    if (cachedResult != "") {
        return cachedResult
    }

   (encoding = "" && encoding := "cp" . DllCall("GetOEMCP", "UInt"))
   DllCall("CreatePipe", "PtrP", hPipeRead, "PtrP", hPipeWrite, "Ptr", 0, "UInt", 0)
   DllCall("SetHandleInformation", "Ptr", hPipeWrite, "UInt", flags, "UInt", HANDLE_FLAG_INHERIT)

   VarSetCapacity(STARTUPINFO , siSize :=    A_PtrSize*4 + 4*8 + A_PtrSize*5, 0)
   NumPut(siSize              , STARTUPINFO)
   NumPut(STARTF_USESTDHANDLES, STARTUPINFO, A_PtrSize*4 + 4*7)
   NumPut(hPipeWrite          , STARTUPINFO, A_PtrSize*4 + 4*8 + A_PtrSize*3)
   NumPut(hPipeWrite          , STARTUPINFO, A_PtrSize*4 + 4*8 + A_PtrSize*4)

   VarSetCapacity(PROCESS_INFORMATION, A_PtrSize*2 + 4*2, 0)

   if !DllCall("CreateProcess", "Ptr", 0, "Str", sCmd, "Ptr", 0, "Ptr", 0, "UInt", true, "UInt", CREATE_NO_WINDOW
                              , "Ptr", 0, "Ptr", 0, "Ptr", &STARTUPINFO, "Ptr", &PROCESS_INFORMATION)
   {
      DllCall("CloseHandle", "Ptr", hPipeRead)
      DllCall("CloseHandle", "Ptr", hPipeWrite)
      throw "CreateProcess is failed"
   }
   DllCall("CloseHandle", "Ptr", hPipeWrite)
   VarSetCapacity(sTemp, 4096), nSize := 0
   while DllCall("ReadFile", "Ptr", hPipeRead, "Ptr", &sTemp, "UInt", 4096, "UIntP", nSize, "UInt", 0) {
      sOutput .= stdOut := StrGet(&sTemp, nSize, encoding)
      ( callBackFuncObj && callBackFuncObj.Call(stdOut) )
   }
   DllCall("CloseHandle", "Ptr", NumGet(PROCESS_INFORMATION))
   DllCall("CloseHandle", "Ptr", NumGet(PROCESS_INFORMATION, A_PtrSize))
   DllCall("CloseHandle", "Ptr", hPipeRead)
   
   ; Mettre en cache le résultat si la commande est cacheable
   SetCachedAdbResult(sCmd, sOutput, cacheTTL)
   
   Return sOutput
}

initializeAdbShell() {
    global adbShell, adbPath, adbPort, Debug
    RetryCount := 0
    MaxRetries := 10
    BackoffTime := 1000  ; Initial backoff time in milliseconds
    MaxBackoff := 5000   ; Prevent excessive waiting

    Loop {
        try {
            if (!adbShell || adbShell.Status != 0) {
                adbShell := ""  ; Reset before reattempting

                ; Validate adbPath and adbPort
                if (!FileExist(adbPath)) {
                    throw Exception("ADB path is invalid: " . adbPath)
                }
                if (adbPort < 0 || adbPort > 65535) {
                    throw Exception("ADB port is invalid: " . adbPort)
                }

                ; Attempt to start adb shell
                adbShell := ComObjCreate("WScript.Shell").Exec(adbPath . " -s 127.0.0.1:" . adbPort . " shell")

                ; Ensure adbShell is running before sending 'su'
                Sleep, 500
                if (adbShell.Status != 0) {
                    throw Exception("Failed to start ADB shell.")
                }

                try {
                    adbShell.StdIn.WriteLine("su")
                } catch e2 {
                    throw Exception("Failed to elevate shell: " . (IsObject(e2) ? e2.Message : e2))
                }
            }

            ; If adbShell is running, break loop
            if (adbShell.Status = 0) {
                break
            }
        } catch e {
            errorMessage := IsObject(e) ? e.Message : e
            RetryCount++
            LogToFile("ADB Shell Error: " . errorMessage, "ADB.txt")

            if (RetryCount >= MaxRetries) {
                if (Debug)
                    CreateStatusMessage("Failed to connect to shell after multiple attempts: " . errorMessage)
                else
                    CreateStatusMessage("Failed to connect to shell. Pausing.",,,, false)
                Pause
            }
        }

        Sleep, BackoffTime
        BackoffTime := Min(BackoffTime + 1000, MaxBackoff)  ; Limit backoff time
    }
}

adbEnsureShell() {
    global adbShell, AdbConnectionPoolSize
    
    ; Utiliser le pool si activé et configuré
    if (AdbConnectionPoolSize && AdbConnectionPoolSize > 0) {
        poolConnection := GetAdbConnectionFromPool()
        if (IsObject(poolConnection) && poolConnection.Status = 0) {
            adbShell := poolConnection
            return
        }
    }
    
    ; Fallback vers la connexion globale
    if (!IsObject(adbShell) || adbShell.Status != 0) {
        adbShell := ""
        initializeAdbShell()
    }
}

adbWriteRaw(command) {
    global adbShell
    retries := 0
    MaxRetries := 3

    Loop {
        adbEnsureShell()
        try {
            adbShell.StdIn.WriteLine(command)
            return true
        } catch e {
            errorMessage := IsObject(e) ? e.Message : e
            retries++
            LogToFile("ADB write error: " . errorMessage, "ADB.txt")
            adbShell := ""
            if (retries >= MaxRetries)
                throw e
            Sleep, 300
        }
    }
}

waitadb(expectedMarkers := 1) {
    global adbShell
    retries := 0
    MaxRetries := 3
    
    ; Timeout adaptatif basé sur le nombre de marqueurs attendus
    timeout := 6000 + (expectedMarkers * 1000)
    if (timeout > 30000)
        timeout := 30000

    Loop {
        adbEnsureShell()
        try {
            adbWriteRaw("echo done")
            startTick := A_TickCount
            markersFound := 0
            
            while (A_TickCount - startTick) < timeout {
                if (adbShell.Status != 0)
                    throw Exception("ADB shell terminated while waiting.")
                if !adbShell.StdOut.AtEndOfStream {
                    line := adbShell.StdOut.ReadLine()
                    if (line = "done") {
                        markersFound++
                        if (markersFound >= expectedMarkers)
                            return
                    } else if (InStr(line, "BATCH_MARKER_") || InStr(line, "BATCH_DONE")) {
                        ; Ignorer les marqueurs batch dans waitadb standard
                        continue
                    }
                } else {
                    Sleep, 50
                }
            }
            throw Exception("Timeout while waiting for ADB response.")
        } catch e {
            errorMessage := IsObject(e) ? e.Message : e
            retries++
            LogToFile("waitadb error: " . errorMessage, "ADB.txt")
            adbShell := ""
            if (retries >= MaxRetries)
                throw e
            Sleep, 300
        }
    }
}

adbClick(X, Y) {
    static clickCommands := Object()
    static convX := 540/277, convY := 960/489, offset := -44

    key := X << 16 | Y

    if (!clickCommands.HasKey(key)) {
        clickCommands[key] := "input tap " . Round(X * convX) . " " . Round((Y + offset) * convY)
    }
    adbWriteRaw(clickCommands[key])
}

adbInput(name) {
    adbWriteRaw("input text " . name)
    waitadb()
}

adbInputEvent(event) {
    if InStr(event, " ") {
        ; If the event uses a space, we use keycombination
        adbWriteRaw("input keycombination " . event)
    } else {
        ; It's a single key event (e.g., "67")
        adbWriteRaw("input keyevent " . event)
    }
    waitadb()
}

; Simulates a swipe gesture on an Android device, swiping from one X/Y-coordinate to another.
adbSwipe(params) {
    adbWriteRaw("input swipe " . params)
    waitadb()
}

; Simulates a touch gesture on an Android device to scroll in a controlled way.
; Not currently supported.
adbGesture(params) {
    ; Example params (a 2-second hold-drag from a lower to an upper Y-coordinate): 0 2000 138 380 138 90 138 90
    adbWriteRaw("input touchscreen gesture " . params)
    waitadb()
}

; Takes a screenshot of an Android device using ADB and saves it to a file.
adbTakeScreenshot(outputFile) {
    ; Percroy Optimization
    global winTitle, adbPort, adbPath
    
    static pTokenLocal := 0
    if (!pTokenLocal) {
        pTokenLocal := Gdip_Startup()
    }
    
    hwnd := WinExist(winTitle)
    if (!hwnd) {
        deviceAddress := "127.0.0.1:" . adbPort
        command := """" . adbPath . """ -s " . deviceAddress . " exec-out screencap -p > """ .  outputFile . """"
        RunWait, %ComSpec% /c "%command%", , Hide
        return
    }

    pBitmap := Gdip_BitmapFromHWND(hwnd)

    if (!pBitmap || pBitmap = "") {
        deviceAddress := "127.0.0.1:" . adbPort
        command := """" . adbPath . """ -s " . deviceAddress . " exec-out screencap -p > """ .  outputFile . """"
        RunWait, %ComSpec% /c "%command%", , Hide
        return
    }

    SplitPath, outputFile, , outputDir
    if (outputDir && !FileExist(outputDir)) {
        FileCreateDir, %outputDir%
    }
    
    result := Gdip_SaveBitmapToFile(pBitmap, outputFile)
    
    Gdip_DisposeImage(pBitmap)
    
    if (!result || result = -1) {
        deviceAddress := "127.0.0.1:" . adbPort
        command := """" . adbPath . """ -s " . deviceAddress . " exec-out screencap -p > """ .  outputFile . """"
        RunWait, %ComSpec% /c "%command%", , Hide
        return
    }
}
