// Controls noted from the reference app's pages, one DSL line each (see SettingsItem.parse).
// Only short labels are kept; every explanatory text is written by hand elsewhere.
extension SettingsPageContent {
    static let energy: [String: [String]] = [
        "keepawake": [
            #"L|Gardez le Mac éveillé à la demande"#,
            #"L|Le Mac suit ses règles d’énergie normales"#,
            #"T|Garder éveillé"#,
            #"L|Durée par défaut"#,
            #"S|Durée par défaut|15 minutes;30 minutes;1 heure;2 heures;4 heures;8 heures;Indéfinie|"#,
            #"L|Automatisation"#,
            #"S|Automatisation|Écran externe;Secteur;Applications|"#,
            #"T|Suspendre lorsque le Mac est verrouillé"#,
            #"T|Garder éveillé à l’ouverture de Mac Island"#,
            #"T|Faire un clic droit sur l’icône de la barre des menus pour basculer « Garder éveillé »"#,
            #"T|Afficher le temps restant à côté de l’icône"#,
            #"T|Autoriser l’écran à s’éteindre"#,
            #"T|Déplacer légèrement le pointeur"#,
            #"L|Intervalle"#,
            #"P|Intervalle|1 min"#,
            #"L|Icône active"#,
            #"S|Icône active|Mac Island;Café;Œil;Lune;Ampoule|Œil"#,
            #"L|Couleur de l’icône active"#,
            #"S|Couleur de l’icône active|Orange;Vert;Bleu;Violet;Rose;Sans couleur|Rose"#,
            #"P|Désactiver lorsque la batterie passe sous|10%"#,
            #"T|Continuer écran rabattu"#,
            #"T|Assombrir complètement l’écran"#,
        ],
        "displays": [
            #"L|Luminosité et alimentation de tous les écrans"#,
            #"T|Contrôler les écrans"#,
            #"D|Écran Retina intégré|0.2678358852863312"#,
            #"B|Au moins un écran doit rester allumé."#,
        ],
        "extrabrightness": [
            #"L|Luminosité supplémentaire sur les écrans XDR"#,
            #"T|Luminosité extra"#,
        ],
        "btsleep": [
            #"T|Couper le Bluetooth quand le Mac se met en veille"#,
        ],
    ]
}
