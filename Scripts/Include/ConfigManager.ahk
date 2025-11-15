; ========================================
; CONFIG MANAGER - Gestion centralisée de la configuration
; ========================================
; Ce module centralise la lecture/écriture de Settings.ini avec cache et validation

; Cache de configuration
global ConfigCache := {}
global ConfigCacheTimestamp := 0
global ConfigCacheTTL := 30000  ; 30 secondes par défaut
global ConfigSettingsPath := ""

; Fonction pour déterminer le chemin vers Settings.ini
; Utilise A_ScriptDir qui pointe vers le répertoire du script principal
GetConfigSettingsPath() {
    ; Utiliser A_ScriptDir qui pointe vers le répertoire du script principal
    ; Si A_ScriptDir contient "Scripts\Include", alors Settings.ini est deux niveaux au-dessus
    if (InStr(A_ScriptDir, "Scripts\Include")) {
        return A_ScriptDir . "\..\..\Settings.ini"
    } else if (InStr(A_ScriptDir, "Scripts")) {
        return A_ScriptDir . "\..\Settings.ini"
    } else {
        ; Si A_ScriptDir est à la racine, Settings.ini devrait être dans le même répertoire
        return A_ScriptDir . "\Settings.ini"
    }
}

; Initialiser le ConfigManager
InitConfigManager() {
    global ConfigSettingsPath
    
    ; Déterminer le chemin vers Settings.ini
    if (ConfigSettingsPath = "") {
        ConfigSettingsPath := GetConfigSettingsPath()
    }
    
    ; Ne pas créer le fichier ici - laisser le script principal (PTCGPB.ahk) le faire
    ; avec toutes les valeurs nécessaires. Si le fichier existe, charger la configuration.
    if (FileExist(ConfigSettingsPath)) {
        ReloadConfig()
    }
}

; Recharger la configuration depuis le fichier
ReloadConfig() {
    global ConfigCache, ConfigCacheTimestamp, ConfigSettingsPath
    
    ; S'assurer que ConfigSettingsPath est défini
    if (ConfigSettingsPath = "") {
        ConfigSettingsPath := GetConfigSettingsPath()
    }
    
    if (!FileExist(ConfigSettingsPath)) {
        return false
    }
    
    ; Lire toutes les valeurs de la section UserSettings
    IniRead, allSettings, %ConfigSettingsPath%, UserSettings
    
    ; Parser les valeurs
    ConfigCache := {}
    Loop, Parse, allSettings, `n
    {
        line := Trim(A_LoopField)
        if (line = "" || InStr(line, "[") = 1) {
            continue
        }
        
        ; Extraire la clé et la valeur
        if (InStr(line, "=")) {
            StringSplit, parts, line, =
            key := Trim(parts1)
            value := Trim(parts2)
            ConfigCache[key] := value
        }
    }
    
    ConfigCacheTimestamp := A_TickCount
    return true
}

; Lire une valeur de configuration avec cache
; section: Section du fichier INI (par défaut "UserSettings")
; key: Clé à lire
; defaultValue: Valeur par défaut si la clé n'existe pas
; forceReload: Forcer le rechargement depuis le fichier (ignore le cache)
ReadConfig(section := "UserSettings", key := "", defaultValue := "", forceReload := false) {
    global ConfigCache, ConfigCacheTimestamp, ConfigCacheTTL, ConfigSettingsPath
    
    ; S'assurer que ConfigSettingsPath est défini
    if (ConfigSettingsPath = "") {
        ConfigSettingsPath := GetConfigSettingsPath()
    }
    
    ; Si key est vide, retourner toute la section
    if (key = "") {
        if (forceReload || (A_TickCount - ConfigCacheTimestamp) > ConfigCacheTTL) {
            ReloadConfig()
        }
        return ConfigCache
    }
    
    ; Vérifier si le cache est valide
    if (forceReload || (A_TickCount - ConfigCacheTimestamp) > ConfigCacheTTL) {
        ReloadConfig()
    }
    
    ; Lire depuis le cache ou depuis le fichier
    if (ConfigCache.HasKey(key)) {
        return ConfigCache[key]
    }
    
    ; Si pas dans le cache, lire directement depuis le fichier
    if (ConfigSettingsPath != "" && FileExist(ConfigSettingsPath)) {
        IniRead, value, %ConfigSettingsPath%, %section%, %key%, %defaultValue%
        ; Mettre en cache
        ConfigCache[key] := value
        return value
    }
    
    ; Si le fichier n'existe pas, retourner la valeur par défaut
    return defaultValue
}

; Lire une valeur booléenne
ReadConfigBool(section := "UserSettings", key := "", defaultValue := false) {
    value := ReadConfig(section, key, defaultValue ? "1" : "0")
    
    ; Convertir en booléen
    if (value = "1" || value = "true" || value = "True" || value = "TRUE" || value = "yes" || value = "Yes" || value = "YES") {
        return true
    }
    return false
}

; Lire une valeur flottante
ReadConfigFloat(section := "UserSettings", key := "", defaultValue := 0.0) {
    value := ReadConfig(section, key, defaultValue)
    ; Convertir en nombre flottant
    ; En AutoHotkey v1, on utilise + 0.0 pour forcer la conversion
    value := value + 0.0
    return value
}

; Lire une valeur entière
ReadConfigInt(section := "UserSettings", key := "", defaultValue := 0) {
    value := ReadConfig(section, key, defaultValue)
    
    ; Convertir en entier
    if value is integer
        return value
    else
        return defaultValue
}

; Lire une valeur string
ReadConfigString(section := "UserSettings", key := "", defaultValue := "") {
    return ReadConfig(section, key, defaultValue)
}

; Écrire une valeur de configuration
; section: Section du fichier INI
; key: Clé à écrire
; value: Valeur à écrire
WriteConfig(section := "UserSettings", key := "", value := "") {
    global ConfigCache, ConfigCacheTimestamp, ConfigSettingsPath
    
    if (key = "") {
        return false
    }
    
    ; S'assurer que ConfigSettingsPath est défini
    if (ConfigSettingsPath = "") {
        ConfigSettingsPath := GetConfigSettingsPath()
    }
    
    ; Écrire dans le fichier
    IniWrite, %value%, %ConfigSettingsPath%, %section%, %key%
    
    ; Mettre à jour le cache
    ConfigCache[key] := value
    ConfigCacheTimestamp := A_TickCount
    
    return true
}

; Écrire une valeur booléenne
WriteConfigBool(section := "UserSettings", key := "", value := false) {
    return WriteConfig(section, key, value ? "1" : "0")
}

; Écrire une valeur entière
WriteConfigInt(section := "UserSettings", key := "", value := 0) {
    return WriteConfig(section, key, value)
}

; Écrire une valeur string
WriteConfigString(section := "UserSettings", key := "", value := "") {
    return WriteConfig(section, key, value)
}

; Valider une valeur de configuration
; key: Clé à valider
; value: Valeur à valider
; validationType: Type de validation ("bool", "int", "string", "path", "url")
ValidateConfigValue(key, value, validationType := "string") {
    if (validationType = "bool") {
        ; Valider booléen
        if (value != "0" && value != "1" && value != "true" && value != "false" && value != "True" && value != "False") {
            return false
        }
        return true
    } else if (validationType = "int") {
        ; Valider entier
        if value is not integer
            return false
        return true
    } else if (validationType = "path") {
        ; Valider chemin (doit exister)
        if (!FileExist(value) && !FileExist(value . "\")) {
            return false
        }
        return true
    } else if (validationType = "url") {
        ; Valider URL basique
        if (!InStr(value, "http://") && !InStr(value, "https://")) {
            return false
        }
        return true
    }
    
    ; Par défaut, accepter toute valeur string
    return true
}

; Obtenir toutes les clés d'une section
GetConfigKeys(section := "UserSettings") {
    global ConfigSettingsPath
    
    ; S'assurer que ConfigSettingsPath est défini
    if (ConfigSettingsPath = "") {
        ConfigSettingsPath := GetConfigSettingsPath()
    }
    
    if (!FileExist(ConfigSettingsPath)) {
        return ""
    }
    
    IniRead, allSettings, %ConfigSettingsPath%, %section%
    
    keys := ""
    Loop, Parse, allSettings, `n
    {
        line := Trim(A_LoopField)
        if (line = "" || InStr(line, "[") = 1) {
            continue
        }
        
        if (InStr(line, "=")) {
            StringSplit, parts, line, =
            key := Trim(parts1)
            if (keys = "") {
                keys := key
            } else {
                keys := keys . "`n" . key
            }
        }
    }
    
    return keys
}

; Ne pas initialiser automatiquement - laisser le script principal (PTCGPB.ahk) le faire
; InitConfigManager() est appelé explicitement dans PTCGPB.ahk après l'inclusion

