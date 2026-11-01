import IslandKit

/// The 12 existing modules (the Display one was retired into the ported auto-quit, W3D). W1 moves each descriptor into its own module; ids are stable and double as tab ids.
public enum ShellDescriptors {
    public static let all: [FeatureDescriptor] = [
        .init(id: "terminal", title: "Terminal", summary: "Terminal intégré dans l'île.",
              systemImage: "terminal", category: .daily, tabID: "terminal"),
        .init(id: "agents", title: "Agents", summary: "Sessions et consommation des agents de code.",
              systemImage: "sparkles", category: .claude, tabID: "agents"),
        .init(id: "clipboard", title: "Presse-papiers", summary: "Historique du presse-papiers et collage sans mise en forme.",
              systemImage: "doc.on.clipboard", category: .daily, tabID: "clipboard"),
        .init(id: "shelf", title: "Étagère", summary: "Dépose temporaire de fichiers et de blocs-notes.",
              systemImage: "tray.and.arrow.down", category: .daily, tabID: "shelf"),
        .init(id: "keepawake", title: "Éveil", summary: "Garde le Mac éveillé, avec durée facultative.",
              systemImage: "cup.and.saucer", category: .daily, tabID: "keepawake"),
        .init(id: "nowplaying", title: "Lecture", summary: "Lecture en cours et touches multimédia.",
              systemImage: "play.circle", category: .media, permissions: [.automation], tabID: "nowplaying"),
        .init(id: "audio", title: "Mixer", summary: "Volume par application et priorité des sorties.",
              systemImage: "slider.vertical.3", category: .sound, permissions: [.audioCapture],
              risk: .touchesSystem, tabID: "audio"),
        .init(id: "monitor", title: "Moniteur", summary: "Processeur, mémoire et alertes.",
              systemImage: "gauge.with.dots.needle.bottom.50percent", category: .monitor, tabID: "monitor"),
        .init(id: "fans", title: "Ventilos", summary: "Lecture des ventilateurs ; réglage manuel via l'assistant approuvé.",
              systemImage: "fan", category: .monitor, permissions: [.helperDaemon],
              risk: .privileged, tabID: "fans"),
        .init(id: "commandbar", title: "Commandes", summary: "Barre de commandes globale et calculatrice.",
              systemImage: "command", category: .tools, tabID: "commandbar"),
        .init(id: "finder", title: "Finder", summary: "Couper-coller de fichiers et raccourcis dans le Finder.",
              systemImage: "folder", category: .files, permissions: [.accessibility, .automation],
              risk: .touchesInput, tabID: "finder"),
        .init(id: "dock", title: "Dock", summary: "Aperçus de fenêtres et actions au clic sur le Dock.",
              systemImage: "dock.rectangle", category: .windows, permissions: [.accessibility, .screenRecording],
              risk: .touchesInput, tabID: "dock"),
    ]
}
