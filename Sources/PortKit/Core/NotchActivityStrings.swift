// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct NotchActivityStrings {
    let timer: String
    let timerDescription: String
    let pomodoro: String
    let stopwatch: String
    let focus: String
    let shortBreak: String
    let longBreak: String
    let pomodoroHint: String
    let totalSessions: String
    let longBreakInterval: String
    let sessionProgress: String
    let pomodoroFinished: String
    let minutes: String
    let start: String
    let resume: String
    let finished: String
    let soundEnabled: String
    let hideTimerCountdown: String
    let camera: String
    let cameraUnavailable: String
    let cameraHint: String
    let startCamera: String
    let stopCamera: String
    let accessories: String
    let accessoryDescription: String
    let connected: String
    let lowBattery: String
    let keepAwakeActivity: String
    let keepAwakeActivityHint: String

    func phase(_ phase: NotchTimerPhase) -> String {
        switch phase {
        case .timer: return timer
        case .stopwatch: return stopwatch
        case .focus: return focus
        case .shortBreak: return shortBreak
        case .longBreak: return longBreak
        }
    }
}

extension FeatureStrings {
    static func notchActivities(_ language: AppLanguage) -> NotchActivityStrings {
        switch language {
        case .enUS: return NotchActivityStrings(
            timer: "Timer",
            timerDescription: "Timers, a stopwatch and focused work sessions in the Dynamic Island.",
            pomodoro: "Pomodoro",
            stopwatch: "Stopwatch",
            focus: "Focus",
            shortBreak: "Short break",
            longBreak: "Long break",
            pomodoroHint: "Start each phase when you are ready. The cycle ends after the last focus session.",
            totalSessions: "Total sessions",
            longBreakInterval: "Sessions between long breaks",
            sessionProgress: "Session %d of %d",
            pomodoroFinished: "Pomodoro complete",
            minutes: "Minutes",
            start: "Start",
            resume: "Resume",
            finished: "Time is up",
            soundEnabled: "Play sound when time is up",
            hideTimerCountdown: "Hide timer countdown",
            camera: "Camera mirror",
            cameraUnavailable: "The camera could not start. Try opening it again.",
            cameraHint: "Open a live mirror here. The camera stops when you leave this view.",
            startCamera: "Open camera",
            stopCamera: "Stop camera",
            accessories: "Accessory alerts",
            accessoryDescription: "Show connected accessories and warn once when their battery falls to 20%.",
            connected: "Connected",
            lowBattery: "Low battery",
            keepAwakeActivity: "Show “Keep awake” in the closed island",
            keepAwakeActivityHint: "A running session appears beside the camera with the time it has left, or ∞ when it has no end.")
        default: return NotchActivityStrings(
            timer: "Minuteur",
            timerDescription: "Des minuteurs, un chronomètre et des séances de concentration dans le Dynamic Island.",
            pomodoro: "Pomodoro",
            stopwatch: "Chronomètre",
            focus: "Concentration",
            shortBreak: "Pause courte",
            longBreak: "Pause longue",
            pomodoroHint: "Commencez chaque étape à votre rythme. Le cycle se termine après la dernière séance de concentration.",
            totalSessions: "Nombre de séances",
            longBreakInterval: "Séances entre les pauses longues",
            sessionProgress: "Séance %d sur %d",
            pomodoroFinished: "Pomodoro terminé",
            minutes: "Minutes",
            start: "Démarrer",
            resume: "Reprendre",
            finished: "Temps écoulé",
            soundEnabled: "Jouer un son à la fin",
            hideTimerCountdown: "Masquer le compte à rebours",
            camera: "Miroir de la caméra",
            cameraUnavailable: "La caméra n’a pas pu démarrer. Essayez de l’ouvrir à nouveau.",
            cameraHint: "Ouvrez un miroir en direct ici. La caméra s’arrête lorsque vous quittez cette vue.",
            startCamera: "Ouvrir la caméra",
            stopCamera: "Arrêter la caméra",
            accessories: "Alertes des accessoires",
            accessoryDescription: "Affiche les accessoires connectés et avertit une fois quand leur batterie atteint 20 %.",
            connected: "Connecté",
            lowBattery: "Batterie faible",
            keepAwakeActivity: "Afficher «\u{00A0}Garder éveillé\u{00A0}» dans l’île fermée",
            keepAwakeActivityHint: "Une session en cours apparaît à côté de la caméra avec le temps restant, ou ∞ si elle n’a pas de fin.")
        }
    }
}
