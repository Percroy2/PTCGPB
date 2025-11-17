#SingleInstance Force

; Créer le lock file IMMÉDIATEMENT (AVANT les includes) pour garantir qu'il existe
; Utiliser un label qui s'exécute au démarrage
addonBaseName := "ComptesRestants_Barre"
lockFile := A_Temp . "\PTCGPB_Addon_" . addonBaseName . "_Lock.txt"
currentPID := DllCall("GetCurrentProcessId")

; Protection: essayer de créer le lock file avec gestion d'erreur
; Utiliser FileAppend avec ErrorLevel pour éviter les blocages
OutputDebug, [ComptesRestants_Barre] Avant FileDelete
FileDelete, %lockFile%
OutputDebug, [ComptesRestants_Barre] Apres FileDelete, avant FileAppend
FileAppend, %currentPID%, %lockFile%
OutputDebug, [ComptesRestants_Barre] Apres FileAppend
; Ne pas bloquer si l'écriture échoue, continuer quand même

; Message de debug pour vérifier l'exécution
OutputDebug, [ComptesRestants_Barre] Avant les includes

; Inclure ConfigManager et StateManager AVANT Utils.ahk (Utils.ahk en a besoin)
#Include %A_ScriptDir%\..\Include\ConfigManager.ahk
OutputDebug, [ComptesRestants_Barre] ConfigManager charge
#Include %A_ScriptDir%\..\Include\StateManager.ahk
OutputDebug, [ComptesRestants_Barre] StateManager charge
#Include %A_ScriptDir%\..\Include\Utils.ahk
OutputDebug, [ComptesRestants_Barre] Utils charge
#Include %A_ScriptDir%\..\Include\NotificationManager.ahk
OutputDebug, [ComptesRestants_Barre] NotificationManager charge

; Configurer le timer d'initialisation de NotificationManager APRÈS l'inclusion
; pour éviter de bloquer le chargement
OutputDebug, [ComptesRestants_Barre] Avant configuration du timer InitNotificationManagerTimer
SetTimer, InitNotificationManagerTimer, -1
OutputDebug, [ComptesRestants_Barre] Timer InitNotificationManagerTimer configure

; Vérifier que les includes sont chargés (debug)
OutputDebug, [ComptesRestants_Barre] Tous les includes charges

; Maintenant appeler SetAddonName (qui va recréer le lock file proprement)
; Si SetAddonName existe, l'utiliser, sinon on a déjà créé le lock file
OutputDebug, [ComptesRestants_Barre] Avant appel SetAddonName
if (IsFunc("SetAddonName")) {
    OutputDebug, [ComptesRestants_Barre] SetAddonName existe, appel...
    SetAddonName("ComptesRestants_Barre")
    OutputDebug, [ComptesRestants_Barre] SetAddonName appele
} else {
    OutputDebug, [ComptesRestants_Barre] SetAddonName n'existe pas
}
OutputDebug, [ComptesRestants_Barre] Apres SetAddonName

; Fonction pour nettoyer le lock file à la sortie (fallback)
; Définie APRÈS les includes pour éviter les problèmes
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
}

; Configurer OnExit APRÈS les includes pour éviter les problèmes de chargement
; Le lock file est déjà créé au début, donc OnExit n'est qu'un fallback
; Utiliser un timer pour éviter de bloquer le chargement
OutputDebug, [ComptesRestants_Barre] Avant configuration du timer SetupOnExit
SetTimer, SetupOnExit, -1
OutputDebug, [ComptesRestants_Barre] Timer SetupOnExit configure

; Utiliser un goto pour sauter le label au chargement
goto SkipSetupOnExitLabel

SetupOnExit:
    ; Configurer OnExit après que tout soit chargé
    ; Note: SetAddonName a déjà configuré OnExit("CleanupAddonLockFile") via CreateAddonLockFile
    ; On va utiliser notre propre handler qui appelle aussi CleanupAddonLockFile
    OutputDebug, [ComptesRestants_Barre] SetupOnExit - Label declenche
    OnExit, OnExitHandler
    OutputDebug, [ComptesRestants_Barre] SetupOnExit - OnExit configure
return

SkipSetupOnExitLabel:
OutputDebug, [ComptesRestants_Barre] Apres SetupOnExit label

; État précédent pour mise à jour incrémentale
barsCreated := {}
instancesData := {}
previousCounts := {}  ; Pour détecter les changements
previousPositions := {}  ; Pour détecter les changements de position

; Configuration avec valeurs par défaut
updateInterval := ReadConfigInt("UserSettings", "comptesBarreUpdateInterval", 30000)
barHeight := ReadConfigInt("UserSettings", "comptesBarreHeight", 35)
barColor := ReadConfigString("UserSettings", "comptesBarreColor", "2D2D2D")
textColor := ReadConfigString("UserSettings", "comptesBarreTextColor", "FFFFFF")
fontSize := ReadConfigInt("UserSettings", "comptesBarreFontSize", 10)
fontName := ReadConfigString("UserSettings", "comptesBarreFontName", "Segoe UI")
lowAccountsThreshold := ReadConfigInt("UserSettings", "comptesBarreLowThreshold", 5)  ; Seuil pour notification

debugMode := ReadConfigBool("UserSettings", "comptesBarreDebugMode", false)
debugInstance := ReadConfigString("UserSettings", "comptesBarreDebugInstance", "1")

; Fonction helper pour le logging (avec fallback)
SafeDebugLog(message) {
    if (IsFunc("DebugLog")) {
        DebugLog(message)
    } else {
        OutputDebug, [ComptesRestants_Barre] %message%
    }
}

; Log de démarrage - après SetAddonName
SafeDebugLog("Addon ComptesRestants_Barre demarre...")
SafeDebugLog("Configuration: updateInterval=" . updateInterval . " barHeight=" . barHeight)

; Obtenir le moniteur pour une position donnée
GetMonitorForPosition(x, y) {
    SysGet, monitorCount, 80
    Loop, %monitorCount%
    {
        SysGet, monitor, Monitor, %A_Index%
        if (x >= monitorLeft && x <= monitorRight && y >= monitorTop && y <= monitorBottom) {
            return A_Index
        }
    }
    return 1  ; Par défaut, moniteur 1
}

; Créer une barre GUI avec personnalisation
CreateBarGUI(guiName, winWidth) {
    global barHeight, barColor, textColor, fontSize, fontName
    
    remainingText := GetRemainingText()
    
    Gui, %guiName%:New, +ToolWindow -Caption -Resize +LastFound +AlwaysOnTop
    Gui, %guiName%:Color, %barColor%
    Gui, %guiName%:Font, s%fontSize% c%textColor% Bold, %fontName%
    
    textY := Round((barHeight - fontSize) / 2) - 2
    ; Ne pas utiliser de variable de contrôle (vBarText) car on utilise ControlSetText avec le handle
    ; AutoHotkey assigne automatiquement Static1, Static2, etc. aux contrôles dans l'ordre de création
    Gui, %guiName%:Add, Text, x0 y%textY% w%winWidth% Left, %remainingText% [0/0]
    
    ; Barre de progression visuelle (optionnelle)
    ; Ne pas utiliser de variable de contrôle (vBarProgress) car on utilise GuiControl avec Static2
    borderY := barHeight - 2
    Gui, %guiName%:Add, Text, x0 y%borderY% w%winWidth% h2 BackgroundFF6B6B,
}

; Positionner une barre avec SmartSleep et support multi-moniteur
PositionBar(barName, barX, barY, barWidth, barHeight) {
    SafeDebugLog("PositionBar - Debut pour " . barName . " | barX=" . barX . " barY=" . barY . " barWidth=" . barWidth . " barHeight=" . barHeight)
    
    ; Vérifier que la fenêtre existe
    if (!WinExist(barName)) {
        SafeDebugLog("PositionBar - ERREUR: Fenetre " . barName . " n'existe pas!")
        return
    }
    
    ; Obtenir le moniteur approprié
    monitorIndex := GetMonitorForPosition(barX, barY)
    SysGet, monitor, Monitor, %monitorIndex%
    
    ; Ajuster la position si nécessaire (dépassement du moniteur)
    if (barX + barWidth > monitorRight) {
        barWidth := monitorRight - barX
    }
    if (barX < monitorLeft) {
        barX := monitorLeft
    }
    if (barY < monitorTop) {
        barY := monitorTop
    }
    
    ; Forcer l'affichage et le positionnement
    WinShow, %barName%
    WinSet, AlwaysOnTop, On, %barName%
    WinSet, Top,, %barName%
    
    ; Utiliser SmartSleep au lieu de multiples Sleep()
    WinMove, %barName%, , %barX%, %barY%, %barWidth%, %barHeight%
    SmartSleep(30, 100)
    
    WinShow, %barName%
    WinMove, %barName%, , %barX%, %barY%, %barWidth%, %barHeight%
    
    WinGetPos, checkX, checkY, checkW, checkH, %barName%
    SafeDebugLog("PositionBar - Position apres WinMove: x=" . checkX . " y=" . checkY . " w=" . checkW . " h=" . checkH)
    
    if (checkX != barX || checkY != barY) {
        WinGet, guiHwnd, ID, %barName%
        if (guiHwnd) {
            ; SWP_SHOWWINDOW = 0x0040, SWP_NOZORDER = 0x0004
            DllCall("SetWindowPos", "UInt", guiHwnd, "UInt", -1, "Int", barX, "Int", barY, "Int", barWidth, "Int", barHeight, "UInt", 0x0040)
            SmartSleep(50, 200)
            WinGetPos, checkX, checkY, checkW, checkH, %barName%
            SafeDebugLog("PositionBar - Position apres SetWindowPos: x=" . checkX . " y=" . checkY . " w=" . checkW . " h=" . checkH)
        }
        
        if (checkX != barX || checkY != barY) {
            Loop, 5 {
                WinMove, %barName%, , %barX%, %barY%, %barWidth%, %barHeight%
                SmartSleep(30, 100)
                WinGetPos, checkX, checkY, checkW, checkH, %barName%
                if (checkX = barX && checkY = barY) {
                    SafeDebugLog("PositionBar - Position corrigee apres " . A_Index . " tentatives")
                    break
                }
            }
        }
    }
    
    ; Forcer à nouveau l'affichage
    WinShow, %barName%
    WinSet, AlwaysOnTop, On, %barName%
    WinSet, Top,, %barName%
    
    SafeDebugLog("PositionBar - Fin pour " . barName . " | Position finale: x=" . checkX . " y=" . checkY)
}

; Créer une barre pour une instance
CreateBarForInstance(instanceName, instanceInfo) {
    global barHeight, barsCreated
    
    guiName := "AddonBar_" . instanceName
    Gui, %guiName%:Destroy
    
    ; Utiliser GetWindowPosition avec cache
    pos := GetWindowPosition(instanceName, instanceInfo)
    winX := pos.x
    winY := pos.y
    winWidth := pos.width
    winHeight := pos.height
    winID := pos.winID
    
    if (winID && (!instanceInfo.HasKey("winID") || instanceInfo.winID != winID)) {
        instanceInfo.winID := winID
        ; Mettre à jour StateManager
        SetInstancePosition(instanceName, pos)
    }
    
    SmartSleep(50, 200)
    
    if (winID && !(winX = 0 && winY = 0 && winWidth >= 200)) {
        WinGetPos, latestWinX, latestWinY, latestWinWidth, latestWinHeight, ahk_id %winID%
        if (latestWinX != "") {
            winX := latestWinX
            winY := latestWinY
            if (latestWinWidth && latestWinWidth >= 100) {
                winWidth := latestWinWidth
            }
            if (latestWinHeight && latestWinHeight >= 50) {
                winHeight := latestWinHeight
            }
        }
    }
    
    if (!ValidateCoordinates(winX, winY, winWidth)) {
        LogWarning("Coordonnees invalides pour " . instanceName . " - x=" . winX . " y=" . winY . " w=" . winWidth, "ComptesRestants_Barre")
        SafeDebugLog("CreateBarForInstance - Coordonnees invalides, abandon de la creation pour " . instanceName)
        return
    }
    
    SafeDebugLog("CreateBarForInstance - Coordonnees validees pour " . instanceName . " - x=" . winX . " y=" . winY . " w=" . winWidth)
    
    ; Support multi-moniteur
    monitorIndex := GetMonitorForPosition(winX, winY)
    SysGet, monitor, Monitor, %monitorIndex%
    
    if (winWidth > (monitorRight - monitorLeft)) {
        winWidth := monitorRight - monitorLeft
    }
    
    ; Positionner la barre AU-DESSUS de la fenêtre
    barX := winX
    barY := winY - barHeight
    
    ; Vérifier que la barre ne dépasse pas le haut du moniteur
    if (barY < monitorTop) {
        barY := monitorTop
    }
    
    if (barX < monitorLeft) {
        barX := monitorLeft
    }
    if (barX + winWidth > monitorRight) {
        winWidth := monitorRight - barX
        if (winWidth < 100) {
            barX := monitorRight - winWidth
            if (barX < monitorLeft) {
                barX := monitorLeft
                winWidth := monitorRight - monitorLeft
            }
        }
    }
    
    SafeDebugLog("CreateBarForInstance - Instance: " . instanceName . " | winX=" . winX . " winY=" . winY . " winWidth=" . winWidth . " | barX=" . barX . " barY=" . barY . " barHeight=" . barHeight)
    
    CreateBarGUI(guiName, winWidth)
    ; Créer la fenêtre mais ne pas l'afficher encore (sera affichée par PositionBar)
    Gui, %guiName%:Show, NoActivate Hide w%winWidth% h%barHeight%, AddonBar_%instanceName%
    SmartSleep(50, 200)
    
    ; Vérifier que la fenêtre a été créée
    if (!WinExist("AddonBar_" . instanceName)) {
        LogError("Impossible de creer la fenetre GUI pour " . instanceName, "ComptesRestants_Barre")
        return
    }
    
    SafeDebugLog("CreateBarForInstance - Fenetre GUI creee pour " . instanceName . ", appel de PositionBar")
    PositionBar("AddonBar_" . instanceName, barX, barY, winWidth, barHeight)
    SmartSleep(50, 200)
    
    ; Forcer l'affichage de la barre
    if (WinExist("AddonBar_" . instanceName)) {
        WinShow, AddonBar_%instanceName%
        WinSet, Top,, AddonBar_%instanceName%
        WinSet, AlwaysOnTop, On, AddonBar_%instanceName%
        
        WinGetPos, actualBarX, actualBarY, actualBarWidth, actualBarHeight, AddonBar_%instanceName%
        SafeDebugLog("Barre creee pour instance: " . instanceName . " | Position: x=" . actualBarX . " y=" . actualBarY . " | Largeur: " . actualBarWidth . " | Hauteur: " . actualBarHeight)
        
        barsCreated[instanceName] := true
        previousPositions[instanceName] := {x: actualBarX, y: actualBarY, width: actualBarWidth}
    } else {
        LogError("Barre non creee pour instance: " . instanceName . " | WinExist retourne false", "ComptesRestants_Barre")
    }
}

; Mise à jour incrémentale d'une barre (seulement si nécessaire)
UpdateBarIncremental(instanceName, instanceInfo, counts) {
    global barsCreated, barHeight, previousCounts, previousPositions, lowAccountsThreshold
    
    guiName := "AddonBar_" . instanceName
    
    ; Vérifier si la barre existe
    if (!WinExist("AddonBar_" . instanceName)) {
        if (barsCreated.HasKey(instanceName)) {
            barsCreated.Delete(instanceName)
        }
        CreateBarForInstance(instanceName, instanceInfo)
        previousCounts[instanceName] := counts
        return
    }
    
    ; Obtenir la position actuelle
    pos := GetWindowPosition(instanceName, instanceInfo)
    winX := pos.x
    winY := pos.y
    winWidth := pos.width
    
    ; Vérifier si la position a changé
    positionChanged := false
    if (!previousPositions.HasKey(instanceName)) {
        positionChanged := true
    } else {
        prevPos := previousPositions[instanceName]
        if (prevPos.x != winX || prevPos.y != winY || prevPos.width != winWidth) {
            positionChanged := true
        }
    }
    
    ; Mettre à jour la position si nécessaire
    if (positionChanged && ValidateCoordinates(winX, winY, winWidth)) {
        monitorIndex := GetMonitorForPosition(winX, winY)
        SysGet, monitor, Monitor, %monitorIndex%
        
        ; Positionner la barre AU-DESSUS de la fenêtre
        barX := winX
        barY := winY - barHeight
        barWidth := winWidth
        
        ; Vérifier que la barre ne dépasse pas le haut du moniteur
        if (barY < monitorTop) {
            barY := monitorTop
        }
        
        if (barX < monitorLeft) {
            barX := monitorLeft
        }
        if (barX + barWidth > monitorRight) {
            barWidth := monitorRight - barX
        }
        
        WinGetPos, currentBarX, currentBarY, currentBarWidth, currentBarHeight, AddonBar_%instanceName%
        if (currentBarX != barX || currentBarY != barY || currentBarWidth != barWidth) {
            Gui, %guiName%:Show, NoActivate x%barX% y%barY% w%barWidth% h%barHeight%
            WinMove, AddonBar_%instanceName%, , %barX%, %barY%, %barWidth%, %barHeight%
            WinSet, Top,, AddonBar_%instanceName%
            previousPositions[instanceName] := {x: barX, y: barY, width: barWidth}
        }
    }
    
    ; Vérifier si les comptes ont changé
    countsChanged := false
    if (!previousCounts.HasKey(instanceName)) {
        countsChanged := true
    } else {
        prevCounts := previousCounts[instanceName]
        if (prevCounts.remaining != counts.remaining || prevCounts.total != counts.total) {
            countsChanged := true
        }
    }
    
    ; Mettre à jour le texte seulement si les comptes ont changé
    if (countsChanged) {
        remainingText := GetRemainingText()
        displayText := remainingText . " [" . counts.remaining . "/" . counts.total . "]"
        
        try {
            WinGet, guiHwnd, ID, AddonBar_%instanceName%
            ControlGet, textHwnd, Hwnd,, Static1, ahk_id %guiHwnd%
            if (textHwnd) {
                ControlSetText,, %displayText%, ahk_id %textHwnd%
                
                ; Mettre à jour la barre de progression visuelle
                if (counts.total > 0) {
                    progressPercent := (counts.remaining / counts.total) * 100
                    progressWidth := Round((winWidth * progressPercent) / 100)
                    
                    ; Changer la couleur selon le pourcentage
                    progressColor := "FF6B6B"  ; Rouge par défaut
                    if (progressPercent > 50) {
                        progressColor := "4CAF50"  ; Vert
                    } else if (progressPercent > 25) {
                        progressColor := "FFC107"  ; Orange
                    }
                    
                    ; Mettre à jour la barre de progression
                    ControlGet, progressHwnd, Hwnd,, Static2, ahk_id %guiHwnd%
                    if (progressHwnd) {
                        GuiControl, %guiName%:Move, Static2, w%progressWidth%
                        GuiControl, %guiName%:+Background%progressColor%, Static2
                    }
                }
                
                previousCounts[instanceName] := counts
                
                ; Notification si comptes faibles
                if (counts.remaining <= lowAccountsThreshold && counts.remaining > 0) {
                    if (!previousCounts.HasKey(instanceName) || previousCounts[instanceName].remaining > lowAccountsThreshold) {
                        NotifyWarning("Comptes faibles", "Instance " . instanceName . ": seulement " . counts.remaining . " compte(s) restant(s)")
                    }
                }
            }
        } catch e {
            ; En AutoHotkey v1, ne pas accéder à e.message directement
            LogError("Erreur lors de la mise a jour du texte pour " . instanceName, "ComptesRestants_Barre")
            ; Recréer la barre en cas d'erreur
            barsCreated.Delete(instanceName)
            CreateBarForInstance(instanceName, instanceInfo)
        }
    }
    
    ; Mettre à jour StateManager
    SetInstanceAccounts(instanceName, counts)
}

; Mettre à jour toutes les barres
UpdateBars() {
    global instancesData, barsCreated, barHeight, debugMode, debugInstance
    
    SafeDebugLog("UpdateBars - Appel de la fonction")
    
    ; Utiliser StateManager ou détecter les instances
    instanceDataCount := 0
    if (IsObject(instancesData)) {
        for k, v in instancesData {
            instanceDataCount++
        }
    }
    
    if (!instancesData || instanceDataCount = 0) {
        SafeDebugLog("UpdateBars - instancesData vide, detection des instances...")
        instancesData := DetectInstances(debugMode, debugInstance)
        instanceCount := 0
        for k, v in instancesData {
            instanceCount++
        }
        SafeDebugLog("UpdateBars - Instances detectees: " . instanceCount)
        if (instanceCount = 0) {
            SafeDebugLog("UpdateBars - ATTENTION: Aucune instance detectee! Verifiez que les fenetres sont ouvertes.")
        }
    }
    
    ; Nettoyer les instances qui n'existent plus (créer une copie pour itération)
    instancesToCheck := {}
    for instanceName, instanceInfo in instancesData {
        instancesToCheck[instanceName] := instanceInfo
    }
    
    for instanceName, instanceInfo in instancesToCheck {
        if (instanceInfo.HasKey("winID") && instanceInfo.winID) {
            if (!WinExist("ahk_id " . instanceInfo.winID)) {
                WinGet, newWinID, ID, %instanceName% ahk_class Qt5156QWindowIcon ahk_exe MuMuPlayer.exe
                if (!newWinID) {
                    WinGet, newWinID, ID, %instanceName% ahk_class Qt5156QWindowIcon
                }
                if (newWinID && newWinID != instanceInfo.winID) {
                    SafeDebugLog("Instance " . instanceName . " a reload (winID change), mise a jour")
                    instanceInfo.winID := newWinID
                } else if (!newWinID) {
                    SafeDebugLog("Instance " . instanceName . " n'existe plus, suppression")
                    instancesData.Delete(instanceName)
                    if (barsCreated.HasKey(instanceName)) {
                        guiName := "AddonBar_" . instanceName
                        Gui, %guiName%:Destroy
                        barsCreated.Delete(instanceName)
                        previousCounts.Delete(instanceName)
                        previousPositions.Delete(instanceName)
                    }
                }
            }
        }
    }
    
    ; Supprimer les barres pour les instances qui n'existent plus
    for instanceName in barsCreated {
        if (!instancesData.HasKey(instanceName)) {
            guiName := "AddonBar_" . instanceName
            Gui, %guiName%:Destroy
            barsCreated.Delete(instanceName)
            previousCounts.Delete(instanceName)
            previousPositions.Delete(instanceName)
        }
    }
    
    ; Mettre à jour chaque instance
    for instanceName, instanceInfo in instancesData {
        SafeDebugLog("UpdateBars - Traitement instance: " . instanceName)
        counts := GetAccountCounts(instanceName)
        instanceInfo.counts := counts
        
        pos := GetWindowPosition(instanceName, instanceInfo)
        winX := pos.x
        winY := pos.y
        winWidth := pos.width
        winID := pos.winID
        
        if (winID && (!instanceInfo.HasKey("winID") || instanceInfo.winID != winID)) {
            instanceInfo.winID := winID
        }
        
        if (!ValidateCoordinates(winX, winY, winWidth)) {
            if (winX = 0 && winY = 0 && winWidth < 200) {
                SafeDebugLog("Coordonnees invalides pour " . instanceName . ", attente prochaine mise a jour")
            }
            continue
        }
        
        instanceInfo.x := winX
        instanceInfo.y := winY
        instanceInfo.width := winWidth
        instanceInfo.height := pos.height
        
        ; Créer la barre si elle n'existe pas
        if (!barsCreated.HasKey(instanceName)) {
            SafeDebugLog("UpdateBars - Creation de la barre pour instance: " . instanceName)
            CreateBarForInstance(instanceName, instanceInfo)
        } else {
            SafeDebugLog("UpdateBars - Barre existe deja pour instance: " . instanceName . ", mise a jour incrementale")
        }
        
        ; Mise à jour incrémentale
        UpdateBarIncremental(instanceName, instanceInfo, counts)
    }
}

; Initialisation
Initialize() {
    global instancesData, barsCreated, debugMode, debugInstance, updateInterval
    
    SafeDebugLog("Initialize - Fonction appelee")
    if (debugMode) {
        SafeDebugLog("Mode DEBUG active - Instance cible: " . debugInstance)
    }
    
    SmartSleep(3000, 5000)
    
    UpdateBars()
    
    instanceCount := 0
    for k, v in instancesData {
        instanceCount++
    }
    barCount := 0
    for k, v in barsCreated {
        barCount++
    }
    
    debugMsg := "Instances detectees: " . instanceCount . " | Barres creees: " . barCount
    if (instanceCount > 0) {
        for name, info in instancesData {
            debugMsg := debugMsg . " | Instance: " . name . " | Comptes: " . info.counts.remaining . "/" . info.counts.total
        }
    } else {
        debugMsg := debugMsg . " | Aucune instance Inject trouvee"
    }
    SafeDebugLog(debugMsg)
    
    barCount := 0
    for k, v in barsCreated {
        barCount++
    }
    if (barCount = 0) {
        Loop, 3 {
            SmartSleep(2000, 5000)
            UpdateBars()
            barCount := 0
            for k, v in barsCreated {
                barCount++
            }
            if (barCount > 0) {
                break
            }
        }
    }
    
    SafeDebugLog("Initialize - Configuration du timer UpdateBarsTimer avec intervalle: " . updateInterval . "ms")
    SafeDebugLog("Initialize - Timer UpdateBarsTimer configure et active")
    SetTimer, UpdateBarsTimer, %updateInterval%
}

; Log de démarrage du script
SafeDebugLog("Script - Demarrage, configuration du timer InitTimer")
OutputDebug, [ComptesRestants_Barre] Avant configuration du timer InitTimer

; Test simple pour vérifier que le script s'exécute
; Créer un fichier de test dans le répertoire temporaire
testFile := A_Temp . "\PTCGPB_ComptesRestants_Barre_Test.txt"
FileDelete, %testFile%
FileAppend, Script demarre a %A_Now%, %testFile%
OutputDebug, [ComptesRestants_Barre] Fichier de test cree

SetTimer, InitTimer, -100
OutputDebug, [ComptesRestants_Barre] Timer InitTimer configure avec delai -100ms

; Utiliser un goto pour sauter les labels au chargement et continuer l'exécution normale
goto SkipLabelsAtStart

UpdateBarsTimer:
    SafeDebugLog("UpdateBarsTimer - Timer declenche")
    OutputDebug, [ComptesRestants_Barre] UpdateBarsTimer - Timer declenche
    UpdateBars()
return

InitTimer:
    SafeDebugLog("InitTimer - Label declenche, appel de Initialize()")
    OutputDebug, [ComptesRestants_Barre] InitTimer - Label declenche, appel de Initialize()
    Initialize()
    SafeDebugLog("InitTimer - Initialize() termine")
    OutputDebug, [ComptesRestants_Barre] InitTimer - Initialize() termine
return

SkipLabelsAtStart:
OutputDebug, [ComptesRestants_Barre] Apres les labels, script pret

^+x::
    global barsCreated
    ; Nettoyer les barres GUI
    for instanceName in barsCreated {
        guiName := "AddonBar_" . instanceName
        Gui, %guiName%:Destroy
    }
    ; Nettoyer le lock file avant de quitter
    CreateLockFileOnExit("", "")
    ExitApp
return

GuiClose:
    global barsCreated
    ; Nettoyer les barres GUI
    for instanceName in barsCreated {
        guiName := "AddonBar_" . instanceName
        Gui, %guiName%:Destroy
    }
    ; Nettoyer le lock file avant de quitter
    CreateLockFileOnExit("", "")
    ExitApp
return

OnExitHandler:
    global barsCreated, addonBaseName
    ; Nettoyer les barres GUI
    if (IsObject(barsCreated)) {
        for instanceName in barsCreated {
            guiName := "AddonBar_" . instanceName
            Gui, %guiName%:Destroy
        }
    }
    ; Appeler la fonction de nettoyage du lock file
    CreateLockFileOnExit("", "")
    ; Nettoyer aussi via CleanupAddonLockFile si disponible (depuis Utils.ahk)
    if (IsFunc("CleanupAddonLockFile")) {
        CleanupAddonLockFile("", "")
    }
    ; Ne pas appeler ExitApp ici, car OnExit est déjà en cours d'exécution
return

