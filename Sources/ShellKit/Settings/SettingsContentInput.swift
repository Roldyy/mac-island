// Controls noted from the reference app's pages, one DSL line each (see SettingsItem.parse).
// Only short labels are kept; every explanatory text is written by hand elsewhere.
extension SettingsPageContent {
    static let input: [String: [String]] = [
        "scrollreverse": [
            #"T|Inverser le défilement vertical"#,
            #"T|Inverser le défilement horizontal"#,
        ],
        "hscroll": [
            #"T|Défilement horizontal avec une touche"#,
        ],
        "middleclick": [
            #"T|Le clic à trois doigts devient un clic du milieu"#,
        ],
        "focusfollows": [
            #"T|Le focus suit la souris"#,
        ],
        "smoothscroll": [
            #"T|Défilement fluide"#,
        ],
        "linearscroll": [
            #"T|Défilement linéaire"#,
        ],
        "noaccel": [
            #"T|Désactiver l’accélération de la souris"#,
        ],
        "sidebuttons": [
            #"T|Utiliser les boutons latéraux pour Précédent et Suivant"#,
        ],
        "mouseshortcuts": [
            #"T|Utiliser les boutons supplémentaires comme raccourcis"#,
            #"T|Changer d’espace en faisant glisser un bouton"#,
        ],
        "clickfilter": [
            #"T|Filtre de clics"#,
        ],
        "quitprotect": [
            #"H|⌘Q"#,
            #"T|Protéger ce raccourci"#,
            #"L|Mode de confirmation"#,
            #"P|Mode de confirmation|Maintenir pour confirmer"#,
            #"L|Durée de maintien"#,
            #"B|250 ms"#,
            #"D|800|800"#,
            #"B|2 s"#,
            #"L|Applications"#,
            #"P|Applications|Toutes les applications"#,
            #"T|Afficher le retour visuel"#,
            #"H|⌘W"#,
            #"T|Protéger ce raccourci"#,
            #"L|Mode de confirmation"#,
            #"P|Mode de confirmation|Maintenir pour confirmer"#,
            #"L|Durée de maintien"#,
            #"B|250 ms"#,
            #"D|800|800"#,
            #"B|2 s"#,
            #"L|Applications"#,
            #"P|Applications|Toutes les applications"#,
            #"T|Afficher le retour visuel"#,
        ],
        "debounce": [
            #"H|Debounce"#,
            #"T|Filtrer les touches doublées"#,
            #"L|Fenêtre globale"#,
            #"N|5 ms"#,
            #"H|Touches spécifiques"#,
            #"P|Touche|Touche"#,
            #"N|5 ms"#,
            #"B|Ajouter une touche"#,
        ],
        "superkey": [
            #"H|Touche super"#,
            #"T|Utiliser cette touche comme touche Super"#,
            #"L|Touche à maintenir"#,
            #"P|Touche à maintenir|Verr. Maj"#,
            #"S|Maintenez|Shift;Control;Option;Command|"#,
            #"H|Un appui seul"#,
        ],
        "snippets": [
            #"T|Activer les extraits de texte"#,
            #"H|Menu rapide des extraits"#,
            #"T|Ouvrir les extraits depuis un menu"#,
            #"B|Ajouter un extrait"#,
        ],
    ]
}
