// Controls noted from the reference app's pages, one DSL line each (see SettingsItem.parse).
// Only short labels are kept; every explanatory text is written by hand elsewhere.
extension SettingsPageContent {
    static let apps: [String: [String]] = [
        "appupdates": [
            #"H|Mises à jour des apps"#,
            #"L|Pas encore vérifié"#,
            #"H|Vérifier en arrière-plan"#,
            #"S|Vérifier en arrière-plan|Désactivé;Chaque jour;Chaque semaine|Désactivé"#,
            #"T|Me prévenir quand une app a une mise à jour"#,
            #"H|Sources"#,
            #"T|Inclure les apps Homebrew"#,
            #"T|Inclure les apps de l’App Store"#,
            #"T|Inclure les autres apps installées"#,
            #"T|Afficher dans le panneau"#,
        ],
        "cleaner": [
            #"B|Analyser"#,
            #"L|Nettoyage automatique"#,
            #"P|Nettoyage automatique|Désactivé"#,
            #"L|Captures d’écran oubliées"#,
            #"P|Captures d’écran oubliées|Après 30 jours"#,
            #"T|Téléchargements WhatsApp"#,
        ],
        "homebrew": [
            #"F|"#,
            #"P||Casks"#,
            #"S||Rechercher;Actualiser;Mettre à jour Homebrew|"#,
            #"S||Tous 56;Casks 9;Formules 47|Tous 56"#,
            #"L|Mises à jour"#,
            #"T|Regrouper les dépendances"#,
            #"L|Finaliser la configuration de Terminal"#,
            #"S|Finaliser la configuration de Terminal|Configurer Terminal;Actualiser|"#,
            #"L|Installés"#,
            #"S|56|ExtraDock, 4.2.7;GitHub Desktop, 3.6.8-c5923f66;Highball, 0.10.22;Microsoft Excel, 16.114.26102031;Microsoft OneNote, 16.114.26102031;Microsoft Outlook, 16.114.26101123;Microsoft PowerPoint, 16.114.26102031;Microsoft Word, 16.114.26102031;Mac Island, 3.4.1;bash-completion, 1.3_3;cmake, 4.4.0;Dépendances: ffmpeg;ffmpeg, 8.1.2_1;gh, 2.96.0;git-lfs, 3.8.1;Dépendances: node;node, 25.9.0_2;Dépendances: pipx;pipx, 1.13.0;Dépendances: powershell;powershell, 7.6.4;Dépendances: python@3.12;python@3.12, 3.12.14;Dépendances: python@3.14;python@3.14, 3.14.5;uv, 0.13.1|"#,
            #"L|Détails du paquet"#,
        ],
        "uninstaller": [
            #"L|ou choisissez-en une à analyser"#,
            #"B|Choisir une app…"#,
            #"T|Afficher dans la barre de commandes"#,
        ],
        "forcequit": [
            #"T|Activer Forcer à quitter"#,
            #"T|Afficher dans la Barre de Commandes"#,
            #"L|Processus : 581"#,
            #"B|Actualiser"#,
            #"F|"#,
            #"S||Processus;CPU;Mémoire;PID|"#,
        ],
        "ports": [
            #"B|Actualiser"#,
            #"F|"#,
        ],
    ]
}
