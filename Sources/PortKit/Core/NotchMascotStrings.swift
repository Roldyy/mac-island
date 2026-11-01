// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct NotchMascotStrings {
    let title: String
    let hint: String
    let visits: String
    let visitsHint: String
    let style: String
    let minimal: String
    let robot: String
    let shape: String
    let ball: String
    let egg: String
    let squircle: String
    let pill: String
    let color: String
    let pearl: String
    let mint: String
    let peach: String
    let lilac: String
    let lemon: String
    let rose: String
    let commandBar: String
    let commandBarHint: String
    let opensAs: String
    let droplet: String
    let openIsland: String
    /// The Settings preview, for VoiceOver, and what clicking it does.
    let preview: String
    let previewHint: String
    /// Which side of the camera it rests on.
    let side: String
    let left: String
    let right: String
    /// How often it strolls through the island.
    let frequency: String
    let rare: String
    let normal: String
    let frequent: String
    let sky: String
    /// One line for the Features page.
    let hubDescription: String
    let appearance: String
    let behavior: String
    /// Whether it comes out to react to what happens.
    let reactions: String
    let reactionsHint: String
    /// Whether it hides in the island once nothing happens for a while.
    let hidesWhenIdle: String
    let hidesWhenIdleHint: String
    /// The Settings button that has it say hello in the island now.
    let sayHi: String
    let sayHiHint: String
    /// The moments the Settings preview can act out.
    let momentsTitle: String
    let visitMoment: String
    let timerStarted: String
    let downloadFailed: String
    let unlocked: String
    /// How to pet it, and that it dozes off.
    let petTip: String
    /// Said on its page while the Dynamic Island is off.
    let livesInIsland: String
    /// More words a search finds its page by.
    let keywords: String

    func style(_ style: NotchMascotStyle) -> String {
        style == .robot ? robot : minimal
    }

    func shape(_ shape: NotchMascotShape) -> String {
        switch shape {
        case .ball: return ball
        case .egg: return egg
        case .squircle: return squircle
        case .pill: return pill
        }
    }

    func palette(_ palette: NotchMascotPalette) -> String {
        switch palette {
        case .pearl: return pearl
        case .mint: return mint
        case .peach: return peach
        case .lilac: return lilac
        case .lemon: return lemon
        case .rose: return rose
        case .sky: return sky
        }
    }

    func commandBarStyle(_ style: NotchCommandBarStyle) -> String {
        style == .island ? openIsland : droplet
    }

    func side(_ side: NotchMascotSide) -> String {
        side == .right ? right : left
    }

    /// A moment's name. Those the island already names elsewhere say it the
    /// same way here.
    func moment(_ moment: NotchMascotMoment, language: AppLanguage) -> String {
        switch moment {
        case .visit: return visitMoment
        case .timerStarted: return timerStarted
        case .timeIsUp: return FeatureStrings.notchActivities(language).finished
        case .music: return FeatureStrings.radialMenu(language).mediaNowPlaying
        case .agents: return FeatureStrings.notchAgents(language).title
        case .eventStarts: return FeatureStrings.notchCalendar(language).ongoing
        case .downloadFinished: return FeatureStrings.notchFiles(language).completed
        case .downloadFailed: return downloadFailed
        case .screenshot: return FeatureStrings.screenshot(language).pageTitle
        case .micMuted: return Strings.localized(language).micMutedHUD
        case .keepAwake: return Strings.localized(language).keepAwakeTitle
        case .charging: return FeatureStrings.notch(language).charging
        case .lowBattery: return FeatureStrings.notch(language).lowBattery
        case .unlocked: return unlocked
        }
    }

    /// What a search finds its page by, besides its name.
    var searchKeywords: [String] {
        [hint, visits, reactions, hidesWhenIdle, style, robot, shape, color, side, frequency, commandBar, keywords]
    }

    func frequency(_ frequency: NotchMascotVisitFrequency) -> String {
        switch frequency {
        case .rare: return rare
        case .normal: return normal
        case .frequent: return frequent
        }
    }
}

extension FeatureStrings {
    static func notchMascot(_ language: AppLanguage) -> NotchMascotStrings {
        switch language {
        case .enUS: return NotchMascotStrings(
            title: "Companion",
            hint: "A little friend who lives in the Dynamic Island. It rests there when nothing else is showing, and comes out over music and activities to say hello and react to what happens.",
            visits: "Appear now and then",
            visitsHint: "Every few minutes it passes through the island with a short animation.",
            style: "Style", minimal: "Minimal", robot: "Robot",
            shape: "Shape", ball: "Ball", egg: "Egg", squircle: "Rounded square", pill: "Pill",
            color: "Color", pearl: "Pearl", mint: "Mint", peach: "Peach", lilac: "Lilac", lemon: "Lemon", rose: "Rose",
            commandBar: "Command Bar in the island",
            commandBarHint: "With the shortcut, the Command Bar comes out of the island with the companion as its face. It reacts while you search.",
            opensAs: "Opens as", droplet: "Drop", openIsland: "Open island",
            preview: "Companion preview", previewHint: "Click to see it react.",
            side: "Side of the camera", left: "Left", right: "Right",
            frequency: "How often", rare: "Rarely", normal: "Sometimes", frequent: "Often",
            sky: "Sky",
            hubDescription: "A little friend in the Dynamic Island who says hello now and then and reacts to what happens on your Mac.",
            appearance: "Appearance", behavior: "Behavior",
            reactions: "React to what happens",
            reactionsHint: "It comes out to react to music, timers, downloads, screenshots, the microphone, Keep awake and more.",
            hidesWhenIdle: "Hide when idle",
            hidesWhenIdleHint: "After half a minute with nothing going on, it hops into the island and the island goes back to its usual size. Visits and reactions still bring it out.",
            sayHi: "Say Hi", sayHiHint: "Plays a visit in the Dynamic Island now.",
            momentsTitle: "See how it reacts",
            visitMoment: "A visit", timerStarted: "Timer started", downloadFailed: "Download failed", unlocked: "Mac unlocked",
            petTip: "Rest the pointer on it to pet it. Left alone, it dozes off until you come back.",
            livesInIsland: "The companion lives in the Dynamic Island.",
            keywords: "mascot pet buddy character")
        default: return NotchMascotStrings(
            title: "Compagnon",
            hint: "Un petit ami qui vit dans le Dynamic Island. Il s’y repose quand rien d’autre n’est affiché, et sort par-dessus la musique et les activités pour dire bonjour et réagir à ce qui se passe.",
            visits: "Passer de temps en temps",
            visitsHint: "Toutes les quelques minutes, il traverse l’île avec une courte animation.",
            style: "Style", minimal: "Minimaliste", robot: "Robot",
            shape: "Forme", ball: "Boule", egg: "Œuf", squircle: "Carré arrondi", pill: "Pilule",
            color: "Couleur", pearl: "Perle", mint: "Menthe", peach: "Pêche", lilac: "Lilas", lemon: "Citron", rose: "Rose",
            commandBar: "Barre de commande dans l’île",
            commandBarHint: "Avec le raccourci, la Barre de commande sort de l’île avec le compagnon comme visage. Il réagit pendant que vous cherchez.",
            opensAs: "S’ouvre en", droplet: "Goutte", openIsland: "Île ouverte",
            preview: "Aperçu du compagnon", previewHint: "Cliquez pour le voir réagir.",
            side: "Côté de la caméra", left: "Gauche", right: "Droite",
            frequency: "Fréquence", rare: "Rare", normal: "Normale", frequent: "Fréquente",
            sky: "Ciel",
            hubDescription: "Un petit ami dans le Dynamic Island qui dit bonjour de temps en temps et réagit à ce qui se passe sur votre Mac.",
            appearance: "Apparence", behavior: "Comportement",
            reactions: "Réagir à ce qui se passe",
            reactionsHint: "Il sort pour réagir à la musique, aux minuteurs, aux téléchargements, aux captures d’écran, au micro, à Garder éveillé et plus encore.",
            hidesWhenIdle: "Se cacher en cas d’inactivité",
            hidesWhenIdleHint: "Après une demi-minute sans activité, il saute dans l’île, qui reprend sa taille habituelle. Il en ressort toujours pour ses visites et ses réactions.",
            sayHi: "Dire bonjour", sayHiHint: "Joue une visite dans le Dynamic Island maintenant.",
            momentsTitle: "Voyez comment il réagit",
            visitMoment: "Une visite", timerStarted: "Minuteur lancé", downloadFailed: "Échec du téléchargement", unlocked: "Mac déverrouillé",
            petTip: "Laissez le pointeur posé sur lui pour le caresser. Seul, il s’assoupit jusqu’à votre retour.",
            livesInIsland: "Le compagnon vit dans le Dynamic Island.",
            keywords: "mascotte animal copain personnage")
        }
    }
}
