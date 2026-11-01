// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

/// Localized strings for the screen recorder.
struct RecorderFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let panelCaption: String
    let startButton: String
    let stopButton: String
    let fileNamePrefix: String
    let selectionPurpose: String
    let indicatorTooltip: String
    let countdownLabel: String
    let countdownOff: String
    let countdownSecondsFormat: String
    let qualityLabel: String
    let qualitySmall: String
    let qualityBalanced: String
    let qualityHigh: String
    let qualityCaption: String
    let frameRateLabel: String
    let frameRateFormat: String
    let systemAudioToggle: String
    let systemAudioCaption: String
    let folderLabel: String
    let folderChoose: String
    let moreOptions: String
    let copyButton: String
    let copyGIFButton: String
    let saveButton: String
    let discardButton: String
    let copiedHUD: String
    let savedHUDFormat: String
    let recordFailed: String
    let noSpaceTitle: String
    let noSpaceMessage: String
    let stoppedNoSpaceHUD: String
    let shortcutLabel: String
    let editorTitle: String
    let saveVideoButton: String
    let saveGIFButton: String
    let exportingLabel: String
    let cancelButton: String
    let exportFailed: String
    let gifTooLongFormat: String
    let gifSizeLabel: String
    let gifSizeSmall: String
    let gifSizeMedium: String
    let gifSizeLarge: String
    let gifFrameRateLabel: String
    let discardTitle: String
    let discardMessage: String
    let openEditorToggle: String
    let openEditorCaption: String
    let lookLabel: String
    let lookRaw: String
    let lookClean: String
    let lookStudio: String
    let lookCaption: String
    let pointerSectionLabel: String
    let pointerShowToggle: String
    let pointerSmoothingLabel: String
    let pointerSmoothingOff: String
    let pointerSmoothingLight: String
    let pointerSmoothingSmooth: String
    let pointerSmoothingCinematic: String
    let pointerSizeLabel: String
    let clickRingToggle: String
    let zoomSectionLabel: String
    let zoomToggle: String
    let zoomAmountLabel: String
    let backgroundSectionLabel: String
    let shapeLabel: String
    let shapeOriginal: String
    let shapeWide: String
    let shapeSquare: String
    let shapeVertical: String
    let noPointerNote: String
    let zoomLaneEmptyHint: String
    let addZoomButton: String
    let removeZoom: String
    let thisZoomLabel: String
    let zoomWhereLabel: String
    let zoomFollowsPointer: String
    let zoomPickSpot: String
    let zoomPickSpotHint: String
    let regenerateZooms: String
    let backToOptions: String
    let cutOutButton: String
    let cutHint: String
    let addTextButton: String
    let textLaneEmptyHint: String
    let thisTextLabel: String
    let textPlaceholder: String
    let textContentLabel: String
    let textSizeLabel: String
    let textPositionLabel: String
    let textColorLabel: String
    let removeText: String
    let copyAndDeleteButton: String
    let saveAsButton: String
    let discardSavedMessage: String
    let presetsButton: String
    let savePreset: String
    let presetNamePlaceholder: String
    let removePreset: String
    let zoomEmptyTitle: String
    let zoomEmptyCaption: String
    let createAutomaticZooms: String
    let typingZoomToggle: String
    let typingZoomCaption: String
    let microphoneToggle: String
    let microphoneCaption: String
    let systemAudioTrackLabel: String
    let microphoneTrackLabel: String
    let audioVolumeLabel: String
    let removeAudio: String
    let restoreAudio: String
    let microphoneUnavailableHUD: String
    let microphonePermissionName: String
    let microphonePermissionExplain: String
    let automaticZoomToggle: String
    let automaticZoomCaption: String
    let pauseButton: String
    let resumeButton: String
    let blurLaneLabel: String
    let addBlurButton: String
    let blurLaneEmptyHint: String
    let thisBlurLabel: String
    let blurPickArea: String
    let blurPickAreaHint: String
    let blurCaption: String
    let addImageButton: String
    let imageLaneLabel: String
    let imageLaneEmptyHint: String
    let thisImageLabel: String
    let imageSizeLabel: String
    let imageOpacityLabel: String
    let imagePositionLabel: String
    let imageImportFailed: String
}

extension FeatureStrings {
    static func recorder(_ language: AppLanguage) -> RecorderFeatureStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension RecorderFeatureStrings {
    static let enUS = RecorderFeatureStrings(
        pageTitle: "Screen recording",
        hubDescription: "Records an area, window or screen and edits it afterwards",
        panelCaption: "Record an area, window or the whole screen",
        startButton: "Record now",
        stopButton: "Stop recording",
        fileNamePrefix: "Recording",
        selectionPurpose: "Choose what to record",
        indicatorTooltip: "Recording controls",
        countdownLabel: "Countdown",
        countdownOff: "Off",
        countdownSecondsFormat: "%d s",
        qualityLabel: "Quality",
        qualitySmall: "Small file",
        qualityBalanced: "Balanced",
        qualityHigh: "High",
        qualityCaption: "Balanced fits most uses. High keeps every detail and makes bigger files.",
        frameRateLabel: "Frames per second",
        frameRateFormat: "%d fps",
        systemAudioToggle: "Record the sound of the Mac",
        systemAudioCaption: "Everything you hear goes into the recording, on its own track, so you can silence it later.",
        folderLabel: "Save to",
        folderChoose: "Choose…",
        moreOptions: "More options",
        copyButton: "Copy",
        copyGIFButton: "Copy as GIF",
        saveButton: "Save",
        discardButton: "Delete",
        copiedHUD: "Recording copied",
        savedHUDFormat: "Saved to %@",
        recordFailed: "The screen could not be recorded",
        noSpaceTitle: "Not enough space to record",
        noSpaceMessage: "Free up some space on the disk and try again.",
        stoppedNoSpaceHUD: "Recording stopped, the disk is almost full",
        shortcutLabel: "Shortcut",
        editorTitle: "Recording",
        saveVideoButton: "Save",
        saveGIFButton: "Save as GIF",
        exportingLabel: "Saving…",
        cancelButton: "Cancel",
        exportFailed: "The recording could not be saved",
        gifTooLongFormat: "A GIF can be up to %d seconds long",
        gifSizeLabel: "GIF size",
        gifSizeSmall: "Small",
        gifSizeMedium: "Medium",
        gifSizeLarge: "Large",
        gifFrameRateLabel: "GIF smoothness",
        discardTitle: "Delete this recording?",
        discardMessage: "It has not been saved anywhere yet.",
        openEditorToggle: "Open the editor after recording",
        openEditorCaption: "The recording opens ready to trim, mute and save. Turn this off to get the file straight away.",
        lookLabel: "Look",
        lookRaw: "Original",
        lookClean: "Smooth",
        lookStudio: "Studio",
        lookCaption: "A starting point. Change anything below and it stays changed.",
        pointerSectionLabel: "Pointer",
        pointerShowToggle: "Draw the pointer",
        pointerSmoothingLabel: "Smoothing",
        pointerSmoothingOff: "None",
        pointerSmoothingLight: "Light",
        pointerSmoothingSmooth: "Smooth",
        pointerSmoothingCinematic: "Cinematic",
        pointerSizeLabel: "Size",
        clickRingToggle: "Mark where you click",
        zoomSectionLabel: "Zoom",
        zoomToggle: "Zoom in on every click",
        zoomAmountLabel: "How close",
        backgroundSectionLabel: "Background",
        shapeLabel: "Shape",
        shapeOriginal: "Original",
        shapeWide: "Wide",
        shapeSquare: "Square",
        shapeVertical: "Tall",
        noPointerNote: "This recording has no pointer track, so there is nothing to smooth. Zooms placed by hand still work.",
        zoomLaneEmptyHint: "Click here to add a zoom",
        addZoomButton: "Add a zoom",
        removeZoom: "Remove",
        thisZoomLabel: "This zoom",
        zoomWhereLabel: "Where it looks",
        zoomFollowsPointer: "Follows the pointer",
        zoomPickSpot: "Pick a spot",
        zoomPickSpotHint: "Click the picture to aim it",
        regenerateZooms: "Back to one per click",
        backToOptions: "All options",
        cutOutButton: "Cut out",
        cutHint: "Drag across the film to pick a part to remove",
        addTextButton: "Add text",
        textLaneEmptyHint: "Click here to add text",
        thisTextLabel: "This text",
        textPlaceholder: "Your text here",
        textContentLabel: "Text",
        textSizeLabel: "Size",
        textPositionLabel: "Position",
        textColorLabel: "Colour",
        removeText: "Remove",
        copyAndDeleteButton: "Copy and delete",
        saveAsButton: "Save as…",
        discardSavedMessage: "Saved and copied files will stay where they are.",
        presetsButton: "Presets",
        savePreset: "Save current preset…",
        presetNamePlaceholder: "Preset name",
        removePreset: "Remove preset",
        zoomEmptyTitle: "No zooms yet",
        zoomEmptyCaption: "Create them from your clicks or add one on the timeline.",
        createAutomaticZooms: "Create automatic zooms",
        typingZoomToggle: "Keep zoomed in while typing",
        typingZoomCaption: "After a click, typing keeps the automatic zoom on that spot.",
        microphoneToggle: "Record the microphone",
        microphoneCaption: "Your voice goes into its own track and stays adjustable in the editor.",
        systemAudioTrackLabel: "Mac sound",
        microphoneTrackLabel: "Microphone",
        audioVolumeLabel: "Volume",
        removeAudio: "Remove",
        restoreAudio: "Restore",
        microphoneUnavailableHUD: "Microphone unavailable",
        microphonePermissionName: "Microphone",
        microphonePermissionExplain: "Lets screen recordings include your voice when you turn it on.",
        automaticZoomToggle: "Add zooms automatically",
        automaticZoomCaption: "Turn this off to start new recordings without zooms. You can still add them in the editor.",
        pauseButton: "Pause recording",
        resumeButton: "Resume recording",
        blurLaneLabel: "Blur",
        addBlurButton: "Blur an area",
        blurLaneEmptyHint: "Click here to add a blur",
        thisBlurLabel: "This blur",
        blurPickArea: "Choose the area",
        blurPickAreaHint: "Drag over what should stay hidden",
        blurCaption: "Hidden for as long as its block lasts on the timeline.",
        addImageButton: "Add image",
        imageLaneLabel: "Image",
        imageLaneEmptyHint: "Click here to add an image",
        thisImageLabel: "This image",
        imageSizeLabel: "Size",
        imageOpacityLabel: "Opacity",
        imagePositionLabel: "Position",
        imageImportFailed: "Couldn’t add this image."
    )

    static let fr = RecorderFeatureStrings(
        pageTitle: "Enregistrement de l’écran",
        hubDescription: "Enregistre une zone, une fenêtre ou l’écran, puis permet de retoucher la vidéo",
        panelCaption: "Enregistrez une zone, une fenêtre ou tout l’écran",
        startButton: "Lancer l’enregistrement",
        stopButton: "Arrêter l’enregistrement",
        fileNamePrefix: "Enregistrement",
        selectionPurpose: "Choisissez ce que vous voulez enregistrer",
        indicatorTooltip: "Commandes d’enregistrement",
        countdownLabel: "Compte à rebours",
        countdownOff: "Aucun",
        countdownSecondsFormat: "%d s",
        qualityLabel: "Qualité",
        qualitySmall: "Fichier léger",
        qualityBalanced: "Équilibrée",
        qualityHigh: "Élevée",
        qualityCaption: "Équilibrée convient à la plupart des usages. Élevée garde tous les détails et donne des fichiers plus lourds.",
        frameRateLabel: "Images par seconde",
        frameRateFormat: "%d i/s",
        systemAudioToggle: "Enregistrer le son du Mac",
        systemAudioCaption: "Tout ce que vous entendez est enregistré sur une piste à part, pour pouvoir le couper plus tard.",
        folderLabel: "Enregistrer dans",
        folderChoose: "Choisir…",
        moreOptions: "Plus d’options",
        copyButton: "Copier",
        copyGIFButton: "Copier en GIF",
        saveButton: "Enregistrer",
        discardButton: "Supprimer",
        copiedHUD: "Enregistrement copié",
        savedHUDFormat: "Enregistré dans %@",
        recordFailed: "L’écran n’a pas pu être enregistré",
        noSpaceTitle: "Espace insuffisant pour enregistrer",
        noSpaceMessage: "Libérez de l’espace sur le disque et réessayez.",
        stoppedNoSpaceHUD: "Enregistrement arrêté, le disque est presque plein",
        shortcutLabel: "Raccourci",
        editorTitle: "Enregistrement",
        saveVideoButton: "Enregistrer",
        saveGIFButton: "Enregistrer en GIF",
        exportingLabel: "Enregistrement en cours…",
        cancelButton: "Annuler",
        exportFailed: "Impossible d’enregistrer la vidéo",
        gifTooLongFormat: "Un GIF peut durer jusqu’à %d secondes",
        gifSizeLabel: "Taille du GIF",
        gifSizeSmall: "Petite",
        gifSizeMedium: "Moyenne",
        gifSizeLarge: "Grande",
        gifFrameRateLabel: "Fluidité du GIF",
        discardTitle: "Supprimer cet enregistrement\u{00A0}?",
        discardMessage: "Il n’a encore été enregistré nulle part.",
        openEditorToggle: "Ouvrir l’éditeur après l’enregistrement",
        openEditorCaption: "La vidéo s’ouvre pour que vous puissiez la rogner, couper le son et l’enregistrer. Désactivez cette option pour obtenir le fichier tout de suite.",
        lookLabel: "Style",
        lookRaw: "Original",
        lookClean: "Fluide",
        lookStudio: "Studio",
        lookCaption: "Un point de départ. Ce que vous modifiez ci-dessous est conservé.",
        pointerSectionLabel: "Pointeur",
        pointerShowToggle: "Afficher le pointeur",
        pointerSmoothingLabel: "Lissage",
        pointerSmoothingOff: "Aucun",
        pointerSmoothingLight: "Léger",
        pointerSmoothingSmooth: "Fluide",
        pointerSmoothingCinematic: "Cinématique",
        pointerSizeLabel: "Taille",
        clickRingToggle: "Marquer les clics",
        zoomSectionLabel: "Zoom",
        zoomToggle: "Zoomer à chaque clic",
        zoomAmountLabel: "Intensité",
        backgroundSectionLabel: "Arrière-plan",
        shapeLabel: "Forme",
        shapeOriginal: "Original",
        shapeWide: "Large",
        shapeSquare: "Carré",
        shapeVertical: "Vertical",
        noPointerNote: "Cet enregistrement a été réalisé sans suivi du pointeur. Il n’y a donc rien à lisser ni à agrandir.",
        zoomLaneEmptyHint: "Cliquez ici pour ajouter un zoom",
        addZoomButton: "Ajouter un zoom",
        removeZoom: "Supprimer",
        thisZoomLabel: "Ce zoom",
        zoomWhereLabel: "Ce qu’il vise",
        zoomFollowsPointer: "Suit le pointeur",
        zoomPickSpot: "Choisir un point",
        zoomPickSpotHint: "Cliquez dans l’image pour placer le point",
        regenerateZooms: "Revenir à un zoom par clic",
        backToOptions: "Toutes les options",
        cutOutButton: "Couper",
        cutHint: "Faites glisser sur la pellicule pour choisir le passage à retirer",
        addTextButton: "Ajouter du texte",
        textLaneEmptyHint: "Cliquez ici pour ajouter du texte",
        thisTextLabel: "Ce texte",
        textPlaceholder: "Votre texte ici",
        textContentLabel: "Texte",
        textSizeLabel: "Taille",
        textPositionLabel: "Position",
        textColorLabel: "Couleur",
        removeText: "Supprimer",
        copyAndDeleteButton: "Copier et supprimer",
        saveAsButton: "Enregistrer sous…",
        discardSavedMessage: "Les fichiers enregistrés et copiés resteront à leur emplacement.",
        presetsButton: "Préréglages",
        savePreset: "Enregistrer le préréglage actuel…",
        presetNamePlaceholder: "Nom du préréglage",
        removePreset: "Supprimer le préréglage",
        zoomEmptyTitle: "Aucun zoom pour le moment",
        zoomEmptyCaption: "Créez-les à partir de vos clics ou ajoutez-en un à la chronologie.",
        createAutomaticZooms: "Créer des zooms automatiques",
        typingZoomToggle: "Garder le zoom pendant la saisie",
        typingZoomCaption: "Après un clic, la saisie maintient le zoom automatique sur cet endroit.",
        microphoneToggle: "Enregistrer le micro",
        microphoneCaption: "Votre voix va sur une piste séparée et reste réglable dans l’éditeur.",
        systemAudioTrackLabel: "Son du Mac",
        microphoneTrackLabel: "Micro",
        audioVolumeLabel: "Volume",
        removeAudio: "Retirer",
        restoreAudio: "Restaurer",
        microphoneUnavailableHUD: "Microphone indisponible",
        microphonePermissionName: "Microphone",
        microphonePermissionExplain: "Permet d’ajouter votre voix aux enregistrements d’écran si vous l’activez.",
        automaticZoomToggle: "Ajouter les zooms automatiquement",
        automaticZoomCaption: "Désactivez cette option pour commencer sans zoom. Vous pourrez toujours en ajouter dans l’éditeur.",
        pauseButton: "Mettre l’enregistrement en pause",
        resumeButton: "Reprendre l’enregistrement",
        blurLaneLabel: "Flou",
        addBlurButton: "Flouter une zone",
        blurLaneEmptyHint: "Cliquez ici pour ajouter un flou",
        thisBlurLabel: "Ce flou",
        blurPickArea: "Choisir la zone",
        blurPickAreaHint: "Faites glisser sur ce qui doit rester caché",
        blurCaption: "Reste caché tant que son bloc dure dans la chronologie.",
        addImageButton: "Ajouter une image",
        imageLaneLabel: "Image",
        imageLaneEmptyHint: "Cliquez ici pour ajouter une image",
        thisImageLabel: "Cette image",
        imageSizeLabel: "Taille",
        imageOpacityLabel: "Opacité",
        imagePositionLabel: "Position",
        imageImportFailed: "Impossible d’ajouter cette image."
    )

}
