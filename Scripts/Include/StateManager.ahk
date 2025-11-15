; ========================================
; STATE MANAGER - Gestionnaire d'état global
; ========================================
; Ce module gère l'état global partagé entre addons avec système d'événements/pub-sub

; État global stocké
global GlobalState := {}
global StateSubscribers := {}  ; {eventName: [callback1, callback2, ...]}
global StateCache := {}  ; Cache pour les données fréquemment accédées
global StateCacheTTL := 5000  ; 5 secondes par défaut
global StateCacheTimestamps := {}

; Initialiser le StateManager
InitStateManager() {
    global GlobalState, StateSubscribers, StateCache, StateCacheTimestamps
    
    ; Ne pas initialiser plusieurs fois (idempotent)
    static initialized := false
    if (initialized) {
        return
    }
    initialized := true
    
    ; Initialiser les structures
    if (!IsObject(GlobalState)) {
        GlobalState := {}
    }
    if (!IsObject(StateSubscribers)) {
        StateSubscribers := {}
    }
    if (!IsObject(StateCache)) {
        StateCache := {}
    }
    if (!IsObject(StateCacheTimestamps)) {
        StateCacheTimestamps := {}
    }
    
    ; Initialiser les sections par défaut
    if (!GlobalState.HasKey("instances")) {
        GlobalState["instances"] := {}
    }
    if (!GlobalState.HasKey("accounts")) {
        GlobalState["accounts"] := {}
    }
    if (!GlobalState.HasKey("statistics")) {
        GlobalState["statistics"] := {}
    }
}

; Définir une valeur dans l'état global
; path: Chemin hiérarchique (ex: "instances.1.position" ou "instances.1")
; value: Valeur à définir
; notify: Notifier les subscribers (par défaut true)
SetState(path, value, notify := true) {
    global GlobalState
    
    ; Parser le chemin
    pathParts := StrSplit(path, ".")
    pathCount := pathParts.MaxIndex()
    
    ; Naviguer dans la structure
    current := GlobalState
    Loop, % pathCount - 1
    {
        part := pathParts[A_Index]
        if (!current.HasKey(part)) {
            current[part] := {}
        }
        current := current[part]
    }
    
    ; Définir la valeur
    lastPart := pathParts[pathCount]
    oldValue := current.HasKey(lastPart) ? current[lastPart] : ""
    current[lastPart] := value
    
    ; Invalider le cache pour ce chemin
    InvalidateStateCache(path)
    
    ; Notifier les subscribers
    if (notify) {
        NotifyStateChange(path, value, oldValue)
    }
    
    return true
}

; Obtenir une valeur de l'état global
; path: Chemin hiérarchique
; defaultValue: Valeur par défaut si non trouvée
GetState(path, defaultValue := "") {
    global GlobalState, StateCache, StateCacheTTL, StateCacheTimestamps
    
    ; Vérifier le cache
    if (StateCache.HasKey(path)) {
        cacheTime := StateCacheTimestamps.HasKey(path) ? StateCacheTimestamps[path] : 0
        if ((A_TickCount - cacheTime) < StateCacheTTL) {
            return StateCache[path]
        }
    }
    
    ; Parser le chemin
    pathParts := StrSplit(path, ".")
    pathCount := pathParts.MaxIndex()
    
    if (pathCount = 0) {
        return defaultValue
    }
    
    ; Naviguer dans la structure
    current := GlobalState
    Loop, % pathCount
    {
        part := pathParts[A_Index]
        if (!current.HasKey(part)) {
            ; Mettre en cache la valeur par défaut
            StateCache[path] := defaultValue
            StateCacheTimestamps[path] := A_TickCount
            return defaultValue
        }
        current := current[part]
    }
    
    ; Mettre en cache
    StateCache[path] := current
    StateCacheTimestamps[path] := A_TickCount
    
    return current
}

; Invalider le cache pour un chemin
InvalidateStateCache(path := "") {
    global StateCache, StateCacheTimestamps
    
    if (path = "") {
        ; Invalider tout le cache
        StateCache := {}
        StateCacheTimestamps := {}
    } else {
        ; Invalider seulement ce chemin et ses sous-chemins
        keysToRemove := ""
        for key, value in StateCache {
            if (InStr(key, path) = 1) {
                keysToRemove := keysToRemove . key . "`n"
            }
        }
        
        Loop, Parse, keysToRemove, `n
        {
            if (A_LoopField != "") {
                StateCache.Delete(A_LoopField)
                StateCacheTimestamps.Delete(A_LoopField)
            }
        }
    }
}

; S'abonner à un événement d'état
; eventName: Nom de l'événement (ex: "instances.*.position" ou "instances.1.*")
; callback: Fonction à appeler (peut être une fonction ou un nom de fonction)
SubscribeStateEvent(eventName, callback) {
    global StateSubscribers
    
    if (!StateSubscribers.HasKey(eventName)) {
        StateSubscribers[eventName] := ""
    }
    
    ; Ajouter le callback à la liste
    if (StateSubscribers[eventName] = "") {
        StateSubscribers[eventName] := callback
    } else {
        ; Pour AHK v1, on stocke les callbacks séparés par des virgules
        StateSubscribers[eventName] := StateSubscribers[eventName] . "," . callback
    }
}

; Se désabonner d'un événement
UnsubscribeStateEvent(eventName, callback) {
    global StateSubscribers
    
    if (!StateSubscribers.HasKey(eventName)) {
        return false
    }
    
    ; Retirer le callback (simplifié pour AHK v1)
    ; Note: En AHK v1, la gestion des listes est plus complexe
    ; On supprime simplement l'événement si c'est le seul callback
    StateSubscribers.Delete(eventName)
    return true
}

; Notifier les subscribers d'un changement
NotifyStateChange(path, newValue, oldValue := "") {
    global StateSubscribers
    
    ; Parser le chemin
    pathParts := StrSplit(path, ".")
    pathCount := pathParts.MaxIndex()
    
    ; Construire les patterns d'événements possibles
    patterns := ""
    
    ; Pattern exact
    patterns := patterns . path . "`n"
    
    ; Patterns avec wildcards
    if (pathCount >= 2) {
        ; "instances.*" pour tous les changements d'instances
        pattern := pathParts[1] . ".*"
        patterns := patterns . pattern . "`n"
        
        ; "instances.1.*" pour tous les changements d'une instance spécifique
        if (pathCount >= 3) {
            pattern := pathParts[1] . "." . pathParts[2] . ".*"
            patterns := patterns . pattern . "`n"
        }
    }
    
    ; Notifier chaque pattern correspondant
    Loop, Parse, patterns, `n
    {
        pattern := Trim(A_LoopField)
        if (pattern = "") {
            continue
        }
        
        if (StateSubscribers.HasKey(pattern)) {
            callback := StateSubscribers[pattern]
            
            ; Appeler le callback
            if (IsFunc(callback)) {
                %callback%(path, newValue, oldValue)
            } else if (IsObject(callback)) {
                callback.Call(path, newValue, oldValue)
            }
        }
    }
}

; Obtenir l'état d'une instance spécifique
GetInstanceState(instanceName) {
    return GetState("instances." . instanceName, {})
}

; Définir l'état d'une instance
SetInstanceState(instanceName, instanceData) {
    return SetState("instances." . instanceName, instanceData)
}

; Obtenir les comptes d'une instance
GetInstanceAccounts(instanceName) {
    return GetState("instances." . instanceName . ".counts", {remaining: 0, total: 0})
}

; Définir les comptes d'une instance
SetInstanceAccounts(instanceName, counts) {
    return SetState("instances." . instanceName . ".counts", counts)
}

; Obtenir la position d'une instance
GetInstancePosition(instanceName) {
    return GetState("instances." . instanceName . ".position", {x: 0, y: 0, width: 0, height: 0, winID: ""})
}

; Définir la position d'une instance
SetInstancePosition(instanceName, position) {
    return SetState("instances." . instanceName . ".position", position)
}

; Obtenir toutes les instances
GetAllInstances() {
    return GetState("instances", {})
}

; Obtenir les statistiques
GetStatistics() {
    return GetState("statistics", {})
}

; Définir une statistique
SetStatistic(key, value) {
    return SetState("statistics." . key, value)
}

; Initialiser au chargement
InitStateManager()

