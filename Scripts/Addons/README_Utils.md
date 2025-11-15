# Addon Utils - Documentation

Le fichier `Utils.ahk` contient des fonctions utilitaires partagées pour tous les addons du bot.

## Utilisation

Pour utiliser `Utils.ahk` dans votre addon, ajoutez au début de votre fichier :

```ahk
; Inclure ConfigManager et StateManager AVANT Utils.ahk (Utils.ahk en a besoin)
#Include %A_ScriptDir%\..\Include\ConfigManager.ahk
#Include %A_ScriptDir%\..\Include\StateManager.ahk
#Include %A_ScriptDir%\..\Include\Utils.ahk
#Include %A_ScriptDir%\..\Include\NotificationManager.ahk

SetAddonName("NomDeVotreAddon")
```

**Note importante** : 
- `ConfigManager.ahk` et `StateManager.ahk` doivent être inclus **AVANT** `Utils.ahk`
- `Utils.ahk` inclut automatiquement `Logging.ahk` de manière optionnelle (pour éviter les dépendances circulaires)
- `NotificationManager.ahk` peut être inclus après `Utils.ahk` si vous avez besoin des notifications

## Fonctions disponibles

### Logging

- **`SetAddonName(addonName)`** : Définit le nom de l'addon pour les logs
- **`DebugLog(message, addonName := "")`** : Log un message dans la console de debug
- **`LogError(message, addonName := "")`** : Logger un message de niveau ERROR
- **`LogWarning(message, addonName := "")`** : Logger un message de niveau WARNING
- **`LogInfo(message, addonName := "")`** : Logger un message de niveau INFO
- **`LogDebug(message, addonName := "")`** : Logger un message de niveau DEBUG

**Note** : Si `Logging.ahk` est inclus (via Utils.ahk), les fonctions `LogToFile` et `LogToDiscord` sont également disponibles.

### Configuration

- **`GetScriptRootDir()`** : Retourne le répertoire racine du projet
- **`GetLanguage()`** : Lit la langue depuis Settings.ini (retourne "FR", "EN", "IT", ou "CH")
- **`ReadSetting(section, key, defaultValue := "")`** : Lit une valeur depuis Settings.ini (utilise directement IniRead)
- **`ReadIniValue(iniFile, section, key, defaultValue := "")`** : Lit une valeur depuis un fichier INI spécifique

**ConfigManager** (doit être inclus avant Utils.ahk) fournit des fonctions type-safe :
- **`ReadConfig(section, key, defaultValue := "")`** : Lire une valeur avec cache
- **`ReadConfigBool(section, key, defaultValue := false)`** : Lire une valeur booléenne
- **`ReadConfigInt(section, key, defaultValue := 0)`** : Lire une valeur entière
- **`ReadConfigString(section, key, defaultValue := "")`** : Lire une valeur string
- **`ReadConfigFloat(section, key, defaultValue := 0.0)`** : Lire une valeur flottante
- **`WriteConfig(section, key, value)`** : Écrire une valeur

### Gestion d'état (StateManager)

StateManager permet de partager l'état entre addons :
- **`SetState(path, value, notify := true)`** : Définir une valeur dans l'état global
- **`GetState(path, defaultValue := "")`** : Obtenir une valeur de l'état global
- **`GetInstanceState(instanceName)`** : Obtenir l'état d'une instance
- **`SetInstanceState(instanceName, instanceData)`** : Définir l'état d'une instance
- **`GetInstanceAccounts(instanceName)`** : Obtenir les comptes d'une instance
- **`SetInstanceAccounts(instanceName, counts)`** : Définir les comptes d'une instance
- **`GetInstancePosition(instanceName)`** : Obtenir la position d'une instance
- **`SetInstancePosition(instanceName, position)`** : Définir la position d'une instance
- **`GetAllInstances()`** : Obtenir toutes les instances
- **`SubscribeStateEvent(eventName, callback)`** : S'abonner à un événement d'état
- **`GetStatistics()`** : Obtenir les statistiques globales
- **`SetStatistic(key, value)`** : Définir une statistique

### Détection d'instances

- **`ValidateCoordinates(winX, winY, winWidth)`** : Valide les coordonnées d'une fenêtre
- **`GetWindowPosition(instanceName, instanceInfo := "")`** : Obtient la position et les dimensions d'une fenêtre d'instance (avec cache optimisé)
  - Retourne : `{x, y, width, height, winID}`
  - **Amélioration** : Utilise maintenant un cache avec TTL pour améliorer les performances
- **`GetAccountCounts(winTitle)`** : Obtient le nombre de comptes restants et total pour une instance
  - Retourne : `{remaining, total}`
- **`DetectInstances(debugMode := false, debugInstance := "")`** : Détecte toutes les instances du bot en mode Inject (avec cache et détection incrémentale)
  - Retourne : Objet associatif `{instanceName: {counts, x, y, width, height, winID}}`
  - **Amélioration** : Utilise maintenant un cache avec détection incrémentale des changements
- **`InvalidateWindowCache(instanceName)`** : Invalider le cache d'une fenêtre spécifique
- **`InvalidateAllWindowCache()`** : Invalider tout le cache des fenêtres

### Utilitaires

- **`SmartSleep(delay, maxDelay := 5000, condition := "")`** : Sleep intelligent avec backoff exponentiel et vérification de condition

### Traduction

- **`GetRemainingText()`** : Retourne le texte "Restant" selon la langue configurée

## Exemple d'utilisation

```ahk
#SingleInstance Force

; Inclure ConfigManager et StateManager AVANT Utils.ahk
#Include %A_ScriptDir%\..\Include\ConfigManager.ahk
#Include %A_ScriptDir%\..\Include\StateManager.ahk
#Include %A_ScriptDir%\..\Include\Utils.ahk
#Include %A_ScriptDir%\..\Include\NotificationManager.ahk

SetAddonName("MonAddon")

; Obtenir la langue
lang := GetLanguage()
DebugLog("Langue detectee: " . lang)

; Utiliser le logging avec niveaux
LogInfo("Démarrage de l'addon", "MonAddon")
LogWarning("Attention: quelque chose", "MonAddon")
LogError("Erreur critique", "MonAddon")

; Utiliser ConfigManager pour lire la configuration (doit être inclus avant Utils.ahk)
instances := ReadConfigInt("UserSettings", "Instances", 1)
DebugLog("Nombre d'instances: " . instances)

; Utiliser StateManager pour partager l'état
SetInstanceAccounts("1", {remaining: 10, total: 50})
counts := GetInstanceAccounts("1")
DebugLog("Comptes instance 1: " . counts.remaining . "/" . counts.total)

; S'abonner à un événement d'état
SubscribeStateEvent("instances.1.*", "OnInstance1Change")
OnInstance1Change(path, newValue, oldValue) {
    DebugLog("Instance 1 a changé: " . path)
}

; Détecter les instances (avec cache optimisé)
instances := DetectInstances(false, "")
for instanceName, instanceInfo in instances {
    DebugLog("Instance: " . instanceName . " | Comptes: " . instanceInfo.counts.remaining . "/" . instanceInfo.counts.total)
}

; Obtenir la position d'une instance (avec cache)
pos := GetWindowPosition("1")
DebugLog("Position instance 1: x=" . pos.x . " y=" . pos.y . " w=" . pos.width)

; Utiliser SmartSleep pour des délais intelligents
SmartSleep(1000)  ; Sleep de 1 seconde
SmartSleep(2000, 5000, "CheckCondition")  ; Sleep avec condition
```

## Modules disponibles

### Logging.ahk
Système de logging unifié avec niveaux (DEBUG, INFO, WARNING, ERROR) et rotation automatique des fichiers.

### ConfigManager.ahk
Gestionnaire de configuration centralisé avec cache et validation. Fournit des fonctions type-safe pour lire/écrire Settings.ini.

### StateManager.ahk
Gestionnaire d'état global avec système d'événements/pub-sub. Permet aux addons de partager des données et de s'abonner aux changements.

### NotificationManager.ahk
Gestionnaire de notifications avec support Windows toast, alertes sonores et intégration Discord améliorée.

### BackupManager.ahk
Gestionnaire de sauvegarde automatique avec restauration après crash.

### DiagnosticMode.ahk
Mode maintenance et outils de diagnostic pour le troubleshooting.

## Notes

- Toutes les fonctions utilisent `GetScriptRootDir()` pour trouver les fichiers de configuration
- Les fonctions de détection d'instances filtrent automatiquement les fenêtres en mode Inject
- Les logs utilisent le nom de l'addon défini par `SetAddonName()`
- Le cache des positions de fenêtres améliore les performances
- DetectInstances utilise un cache avec détection incrémentale pour optimiser les performances
- `ConfigManager.ahk` et `StateManager.ahk` doivent être inclus **AVANT** `Utils.ahk` dans tous les addons

