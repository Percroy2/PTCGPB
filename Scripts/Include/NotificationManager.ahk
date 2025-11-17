; ========================================
; NOTIFICATION MANAGER - Gestionnaire de notifications
; ========================================
; Ce module gère les notifications Windows, alertes sonores et amélioration Discord

; Inclure Logging.ahk (chemins relatifs pour support addons et scripts)
#Include *i %A_ScriptDir%\..\Include\Logging.ahk
#Include *i %A_ScriptDir%\Include\Logging.ahk

; Priorités de notifications
global NOTIFICATION_INFO := 0
global NOTIFICATION_WARNING := 1
global NOTIFICATION_ERROR := 2
global NOTIFICATION_CRITICAL := 3

; Configuration des notifications
global NotificationConfig := {}
NotificationConfig.enabled := true
NotificationConfig.soundEnabled := true
NotificationConfig.toastEnabled := true
NotificationConfig.discordEnabled := true
NotificationConfig.minPriority := NOTIFICATION_INFO

; Initialiser le NotificationManager
InitNotificationManager() {
    global NotificationConfig, NOTIFICATION_INFO, NOTIFICATION_WARNING, NOTIFICATION_ERROR, NOTIFICATION_CRITICAL
    
    static initialized := false
    if (initialized) {
        return
    }
    initialized := true
    
    try {
        ; Déterminer le chemin vers Settings.ini (à la racine du projet)
        settingsPath := ""
        if (InStr(A_ScriptDir, "Scripts\Include")) {
            settingsPath := A_ScriptDir . "\..\..\Settings.ini"
        } else if (InStr(A_ScriptDir, "Scripts\Addons")) {
            settingsPath := A_ScriptDir . "\..\..\Settings.ini"
        } else if (InStr(A_ScriptDir, "Scripts")) {
            settingsPath := A_ScriptDir . "\..\Settings.ini"
        } else {
            settingsPath := A_ScriptDir . "\Settings.ini"
        }
        
        if (!FileExist(settingsPath)) {
            return
        }
        
        ; Lire les paramètres de notification depuis Settings.ini
        IniRead, notificationsEnabled, %settingsPath%, UserSettings, notificationsEnabled, 1
        IniRead, notificationSoundEnabled, %settingsPath%, UserSettings, notificationSoundEnabled, 1
        IniRead, notificationToastEnabled, %settingsPath%, UserSettings, notificationToastEnabled, 1
        IniRead, notificationDiscordEnabled, %settingsPath%, UserSettings, notificationDiscordEnabled, 1
        IniRead, notificationMinPriority, %settingsPath%, UserSettings, notificationMinPriority, INFO
        
        ; Convertir les valeurs booléennes
        NotificationConfig.enabled := (notificationsEnabled = "1" || notificationsEnabled = 1 || notificationsEnabled = true)
        NotificationConfig.soundEnabled := (notificationSoundEnabled = "1" || notificationSoundEnabled = 1 || notificationSoundEnabled = true)
        NotificationConfig.toastEnabled := (notificationToastEnabled = "1" || notificationToastEnabled = 1 || notificationToastEnabled = true)
        NotificationConfig.discordEnabled := (notificationDiscordEnabled = "1" || notificationDiscordEnabled = 1 || notificationDiscordEnabled = true)
        
        StringUpper, notificationMinPriority, notificationMinPriority
        if (notificationMinPriority = "CRITICAL") {
            NotificationConfig.minPriority := NOTIFICATION_CRITICAL
        } else if (notificationMinPriority = "ERROR") {
            NotificationConfig.minPriority := NOTIFICATION_ERROR
        } else if (notificationMinPriority = "WARNING") {
            NotificationConfig.minPriority := NOTIFICATION_WARNING
        } else {
            NotificationConfig.minPriority := NOTIFICATION_INFO
        }
    } catch e {
        ; En cas d'erreur, utiliser les valeurs par défaut déjà définies
    }
}

; Envoyer une notification
; priority: NOTIFICATION_INFO (0), NOTIFICATION_WARNING (1), NOTIFICATION_ERROR (2), NOTIFICATION_CRITICAL (3)
; sound, toast, discord: optionnels, valeurs par défaut selon la priorité
Notify(title, message, priority = "", sound = "", toast = "", discord = "") {
    global NotificationConfig, NOTIFICATION_INFO, NOTIFICATION_WARNING, NOTIFICATION_ERROR, NOTIFICATION_CRITICAL
    
    if (priority = "") {
        priority := NOTIFICATION_INFO
    }
    
    if (!NotificationConfig.enabled || priority < NotificationConfig.minPriority) {
        return false
    }
    
    ; Valeurs par défaut selon la priorité
    if (sound = "") {
        sound := (priority >= NOTIFICATION_WARNING) ? true : false
    } else {
        sound := (sound = "true" || sound = 1 || sound = "1" || sound = true) ? true : false
    }
    
    if (toast = "") {
        toast := (priority >= NOTIFICATION_WARNING) ? true : false
    } else {
        toast := (toast = "true" || toast = 1 || toast = "1" || toast = true) ? true : false
    }
    
    if (discord = "") {
        discord := (priority >= NOTIFICATION_ERROR) ? true : false
    } else {
        discord := (discord = "true" || discord = 1 || discord = "1" || discord = true) ? true : false
    }
    
    ; Logger la notification
    if (IsFunc("LogError") && IsFunc("LogWarning") && IsFunc("LogInfo")) {
        if (priority = NOTIFICATION_CRITICAL) {
            LogError("NOTIFICATION CRITICAL: " . title . " - " . message)
        } else if (priority = NOTIFICATION_ERROR) {
            LogError("NOTIFICATION ERROR: " . title . " - " . message)
        } else if (priority = NOTIFICATION_WARNING) {
            LogWarning("NOTIFICATION WARNING: " . title . " - " . message)
        } else {
            LogInfo("NOTIFICATION INFO: " . title . " - " . message)
        }
    }
    
    ; Jouer un son
    if (sound && NotificationConfig.soundEnabled) {
        PlayNotificationSound(priority)
    }
    
    ; Afficher une notification toast Windows
    if (toast && NotificationConfig.toastEnabled) {
        ShowToastNotification(title, message, priority)
    }
    
    ; Envoyer à Discord
    if (discord && NotificationConfig.discordEnabled) {
        SendDiscordNotification(title, message, priority)
    }
    
    return true
}

; Jouer un son selon la priorité
PlayNotificationSound(priority) {
    global NOTIFICATION_INFO, NOTIFICATION_WARNING, NOTIFICATION_ERROR, NOTIFICATION_CRITICAL
    
    if (priority = NOTIFICATION_CRITICAL) {
        ; Son critique (système d'alerte)
        SoundPlay, *64
        Sleep, 200
        SoundPlay, *64
    } else if (priority = NOTIFICATION_ERROR) {
        ; Son d'erreur
        SoundPlay, *16
    } else if (priority = NOTIFICATION_WARNING) {
        ; Son d'avertissement
        SoundPlay, *48
    } else {
        ; Son d'information (optionnel, très discret)
        SoundPlay, *32
    }
}

global NotificationTimers := {}

; Afficher une notification toast Windows (GUI simulée pour AutoHotkey v1)
ShowToastNotification(title, message, priority) {
    global NotificationTimers
    
    static notificationCount := 0
    notificationCount++
    guiName := "Notification" . notificationCount
    bgColor := "2D2D2D"
    textColor := "FFFFFF"
    if (priority = NOTIFICATION_CRITICAL) {
        bgColor := "8B0000"  ; Rouge foncé
        textColor := "FFFFFF"
    } else if (priority = NOTIFICATION_ERROR) {
        bgColor := "DC143C"  ; Rouge
        textColor := "FFFFFF"
    } else if (priority = NOTIFICATION_WARNING) {
        bgColor := "FF8C00"  ; Orange
        textColor := "000000"
    }
    
    Gui, %guiName%:New, +ToolWindow -Caption +AlwaysOnTop +LastFound
    Gui, %guiName%:Color, %bgColor%
    Gui, %guiName%:Font, s10 Bold c%textColor%, Segoe UI
    Gui, %guiName%:Add, Text, x10 y10 w300, %title%
    Gui, %guiName%:Font, s9 Norm c%textColor%, Segoe UI
    Gui, %guiName%:Add, Text, x10 y35 w300, %message%
    
    SysGet, screenWidth, 78
    SysGet, screenHeight, 79
    notificationX := screenWidth - 330
    notificationY := 10 + (notificationCount - 1) * 120
    
    Gui, %guiName%:Show, NoActivate x%notificationX% y%notificationY% w320 h80, %guiName%
    
    closeDelay := (priority >= NOTIFICATION_ERROR) ? 10000 : 5000
    notificationInfo := {}
    notificationInfo.creationTime := A_TickCount
    notificationInfo.delay := closeDelay
    NotificationTimers[guiName] := notificationInfo
    
    if (!NotificationTimers.HasKey("_timerActive")) {
        NotificationTimers["_timerActive"] := true
        SetTimer, CloseNotificationsTimer, 1000
    }
    
    return
}

; Timer pour fermer les notifications expirées
goto SkipInitNotificationManagerTimerLabel

CloseNotificationsTimer:
    global NotificationTimers
    
    if (!IsObject(NotificationTimers)) {
        SetTimer, CloseNotificationsTimer, Off
        return
    }
    
    if (!NotificationTimers.HasKey("_timerActive")) {
        return
    }
    
    currentTime := A_TickCount
    notificationsToCheck := {}
    for guiName, notificationInfo in NotificationTimers {
        notificationsToCheck[guiName] := notificationInfo
    }
    
    for guiName, notificationInfo in notificationsToCheck {
        if (guiName = "_timerActive") {
            continue
        }
        
        if (IsObject(notificationInfo)) {
            creationTime := notificationInfo.creationTime
            delay := notificationInfo.delay
        } else {
            creationTime := notificationInfo
            delay := 5000
        }
        
        elapsed := currentTime - creationTime
        if (elapsed >= delay) {
            Gui, %guiName%:Destroy
            if (NotificationTimers.HasKey(guiName)) {
                NotificationTimers.Delete(guiName)
            }
        }
    }
    
    activeNotifications := 0
    for guiName, notificationInfo in NotificationTimers {
        if (guiName != "_timerActive") {
            activeNotifications++
        }
    }
    
    if (activeNotifications = 0) {
        NotificationTimers.Delete("_timerActive")
        SetTimer, CloseNotificationsTimer, Off
    }
return

; Envoyer une notification Discord
SendDiscordNotification(title, message, priority) {
    global NOTIFICATION_INFO, NOTIFICATION_WARNING, NOTIFICATION_ERROR, NOTIFICATION_CRITICAL
    
    emoji := ""
    if (priority = NOTIFICATION_CRITICAL) {
        emoji := "🚨"
    } else if (priority = NOTIFICATION_ERROR) {
        emoji := "❌"
    } else if (priority = NOTIFICATION_WARNING) {
        emoji := "⚠️"
    } else {
        emoji := "ℹ️"
    }
    
    discordMessage := emoji . " **" . title . "**`n" . message
    ping := (priority >= NOTIFICATION_CRITICAL)
    LogToDiscord(discordMessage, "", ping)
}

; Fonctions de convenance
NotifyInfo(title, message) {
    global NOTIFICATION_INFO
    Notify(title, message, NOTIFICATION_INFO)
}

NotifyWarning(title, message) {
    global NOTIFICATION_WARNING
    Notify(title, message, NOTIFICATION_WARNING)
}

NotifyError(title, message) {
    global NOTIFICATION_ERROR
    Notify(title, message, NOTIFICATION_ERROR)
}

NotifyCritical(title, message) {
    global NOTIFICATION_CRITICAL
    Notify(title, message, NOTIFICATION_CRITICAL)
}

; Label pour l'initialisation (appelé par timer depuis le script qui inclut ce fichier)
goto SkipInitNotificationManagerTimerLabel

InitNotificationManagerTimer:
    try {
        InitNotificationManager()
    } catch e {
        ; En cas d'erreur, continuer avec les valeurs par défaut
    }
    SetTimer, InitNotificationManagerTimer, Off
return

SkipInitNotificationManagerTimerLabel:

