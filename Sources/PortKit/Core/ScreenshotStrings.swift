// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

/// Localized strings for the screenshot tool.
struct ScreenshotFeatureStrings {
    let pageTitle: String
    let hubDescription: String
    let captureButton: String
    let panelCaption: String
    let fileNamePrefix: String
    let hintDrag: String
    let hintClick: String
    let hintFullScreen: String
    let hintCancel: String
    let hintRepeat: String
    let freezeToggle: String
    let freezeCaption: String
    let folderLabel: String
    let folderChoose: String
    let subfolderLabel: String
    let subfolderCaption: String
    let fileNamePatternLabel: String
    let fileNamePatternCaption: String
    let fileNumberStartLabel: String
    let fileNumberResetButton: String
    let fileNumberNextFormat: String
    let delayLabel: String
    let delayOff: String
    let delaySecondsFormat: String
    let pointerToggle: String
    let downscaleToggle: String
    let downscaleCaption: String
    let editorTitle: String
    let toolShortcutsTitle: String
    let toolShortcutsToggle: String
    let toolShortcutsCaption: String
    let toolShortcutReserved: String
    let toolSelect: String
    let toolArrow: String
    let arrowStyleLabel: String
    let arrowStyleFilled: String
    let arrowStyleOutline: String
    let arrowStyleOpen: String
    let arrowStyleDoubleEnded: String
    let arrowStyleScribbly: String
    let toolLine: String
    let toolRect: String
    let toolEllipse: String
    let toolFreehand: String
    let toolHighlight: String
    let toolSpotlight: String
    let toolText: String
    let toolSticker: String
    let toolCounter: String
    let toolPixelate: String
    let toolRedact: String
    let toolCrop: String
    let toolExpandCanvas: String
    let moreTools: String
    let pastedImage: String
    let canvasFillWhite: String
    let canvasFillTransparent: String
    let canvasFillCustom: String
    let textPlaceholder: String
    let cropApply: String
    let cancel: String
    let colorLabel: String
    let strokeLabel: String
    let fontSizeLabel: String
    let blurStrengthLabel: String
    let spotlightDimStrengthLabel: String
    let toolBlur: String
    let blurStyleLabel: String
    let blurStyleErase: String
    let blurTextOnly: String
    let shadowLabel: String
    let backdropLabel: String
    let backdropNone: String
    let editButton: String
    let copyButton: String
    let saveButton: String
    let saveAsButton: String
    let pinButton: String
    let copyTextButton: String
    let discardTitle: String
    let discardMessage: String
    let discardConfirm: String
    let copiedHUD: String
    let savedHUDFormat: String
    let savedAndCopiedHUDFormat: String
    let defaultActionLabel: String
    let defaultActionCaption: String
    let confirmationPreviewToggle: String
    let confirmationPreviewDurationLabel: String
    let confirmationPreviewUntilDismissed: String
    let confirmationPreviewCaption: String
    let defaultActionNone: String
    let defaultActionSaveAndCopy: String
    let captureFailed: String
    let pinOpacity: String
    let pinClickThrough: String
    let pinCloseAll: String
    let backdropPaddingLabel: String
    let backdropWallpaperLabel: String
    let backdropImageButton: String
    let backdropSolidLabel: String
    let backdropGradientLabel: String
    let backdropCornersLabel: String
    let backdropSavePreset: String
    let backdropDeletePreset: String
    let backdropCustomLabel: String
    let openEditorToggle: String
    let openEditorCaption: String
    let autoCopyToggle: String
    let autoCopyCaption: String
    let addToShelfToggle: String
    let addToShelfCaption: String
    let addToShelfButton: String
    let hintLoupe: String
    let lastRegionToggle: String
    let highlightWindowsToggle: String
    let highlightWindowsCaption: String
    let backdropBlurLabel: String
    let scrollingCaptureButton: String
    let scrollingCaptureTitle: String
    let scrollingCaptureProgressHUD: String
    let scrollingCaptureHintOff: String
    let scrollingCaptureHintOn: String
    let scrollingCaptureTooLongHUD: String
    let uploadLastCapture: String
    let uploadExpiry: String
    let editLastCapture: String
    let lastCaptureMissing: String
    let fullScreenCaptureButton: String
    let fullScreenShortcutTitle: String
    let bringForward: String
    let sendBackward: String
    let shareSectionTitle: String
    let shareCaption: String
    let shareButton: String
    let shareOneHour: String
    let shareSixHours: String
    let shareTwentyFourHours: String
    let sharingHUD: String
    let sharedHUD: String
    let shareFailedHUD: String
    let linkCopyFailedHUD: String
    let sharedLinksTitle: String
    let sharedLinksEmpty: String
    let expiresLabel: String
    let deleteLink: String
    let linkDeletedHUD: String
    let deleteFailedHUD: String
    let openLink: String
    let copyLink: String
    let done: String
    let sharePrivacyButton: String
    let sharePrivacyTitle: String
    let sharePrivacyData: String
    let sharePrivacyStorage: String
    let sharePrivacyAccess: String
    let scrollingCaptureCaption: String
    let scrollingCaptureSelectionHint: String
    let scrollingCapturePartialHUD: String
    let previewPositionLabel: String
    let previewPositionAutomatic: String
    let previewPositionTopLeft: String
    let previewPositionTopRight: String
    let previewPositionBottomLeft: String
    let previewPositionBottomRight: String
    let previewFocusToggle: String
    let previewFocusCaption: String
    let hideVorssaintWindowsToggle: String
    let shareEnabledToggle: String
    let editClipboardImage: String
    let clipboardImageMissing: String
    let showCaptureMenuOnShortcut: String
    let screenCaptureTitle: String
    let dragOutHandleLabel: String
    let loupeStartsOnToggle: String
    let loupeRememberZoomToggle: String
    let loupeDefaultZoomLabel: String
    let loupeWheelZoomLabel: String
    let loupeZoomFast: String
    let loupeZoomStepped: String
    let loupeZoomOptionCaption: String
    let watermarkLabel: String
    let watermarkImageLabel: String
    let watermarkTextPlaceholder: String
    let watermarkPositionLabel: String
    let watermarkSizeLabel: String
    let watermarkOpacityLabel: String
    let watermarkRotationLabel: String
    let watermarkSavePreset: String
    let watermarkColorRed: String
    let watermarkColorOrange: String
    let watermarkColorYellow: String
    let watermarkColorGreen: String
    let watermarkColorBlue: String
    let watermarkColorPurple: String
    let watermarkColorBlack: String
    let watermarkColorWhite: String
    let watermarkPositionTopLeading: String
    let watermarkPositionTop: String
    let watermarkPositionTopTrailing: String
    let watermarkPositionLeading: String
    let watermarkPositionCenter: String
    let watermarkPositionTrailing: String
    let watermarkPositionBottomLeading: String
    let watermarkPositionBottom: String
    let watermarkPositionBottomTrailing: String

    func watermarkColorName(_ color: ScreenshotSupport.ColorID) -> String {
        switch color {
        case .red: return watermarkColorRed
        case .orange: return watermarkColorOrange
        case .yellow: return watermarkColorYellow
        case .green: return watermarkColorGreen
        case .blue: return watermarkColorBlue
        case .purple: return watermarkColorPurple
        case .black: return watermarkColorBlack
        case .white: return watermarkColorWhite
        }
    }

    func watermarkPositionName(_ anchor: ScreenshotSupport.WatermarkStyle.Anchor) -> String {
        switch anchor {
        case .topLeading: return watermarkPositionTopLeading
        case .top: return watermarkPositionTop
        case .topTrailing: return watermarkPositionTopTrailing
        case .leading: return watermarkPositionLeading
        case .center: return watermarkPositionCenter
        case .trailing: return watermarkPositionTrailing
        case .bottomLeading: return watermarkPositionBottomLeading
        case .bottom: return watermarkPositionBottom
        case .bottomTrailing: return watermarkPositionBottomTrailing
        }
    }
}

extension FeatureStrings {
    static func screenshot(_ language: AppLanguage) -> ScreenshotFeatureStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension ScreenshotFeatureStrings {
    static let enUS = ScreenshotFeatureStrings(
        pageTitle: "Screenshot",
        hubDescription: "Captures an area, window or screen and annotates it",
        captureButton: "Capture now",
        panelCaption: "Capture an area, window or the whole screen",
        fileNamePrefix: "Screenshot",
        hintDrag: "Drag to select an area",
        hintClick: "Click a window to capture it",
        hintFullScreen: "Return captures the whole screen",
        hintCancel: "Esc cancels",
        hintRepeat: "R repeats the last area",
        freezeToggle: "Freeze the screen while selecting",
        freezeCaption: "The picture stops while you choose the area, so nothing moves away or changes during the selection.",
        folderLabel: "Save to",
        folderChoose: "Choose…",
        subfolderLabel: "Subfolder pattern",
        subfolderCaption: "Optional. Creates dated subfolders inside the folder above using %y, %year, %mo, %month, %d, %h, %mi and %s, for example %y-%mo for 24-03.",
        fileNamePatternLabel: "File name",
        fileNamePatternCaption: "Optional. Overrides the default name using the same %y, %year, %mo, %month, %d, %h, %mi and %s tokens, plus %# for an auto-incrementing number (%## pads to 2 digits, %### to 3, and so on).",
        fileNumberStartLabel: "Starts at",
        fileNumberResetButton: "Reset",
        fileNumberNextFormat: "Next: %d",
        delayLabel: "Delay",
        delayOff: "Off",
        delaySecondsFormat: "%d s",
        pointerToggle: "Include the pointer",
        downscaleToggle: "Save at 1x size",
        downscaleCaption: "Retina captures are saved at half their pixel size, which makes smaller files.",
        editorTitle: "Screenshot",
        toolShortcutsTitle: "Editor tools",
        toolShortcutsToggle: "Use tool shortcuts",
        toolShortcutsCaption: "Click a shortcut to record a key. Digits 1–9 move the tool. Delete clears its shortcut.",
        toolShortcutReserved: "This key belongs to the editor.",
        toolSelect: "Select",
        toolArrow: "Arrow",
        arrowStyleLabel: "Arrow style",
        arrowStyleFilled: "Solid",
        arrowStyleOutline: "Outline",
        arrowStyleOpen: "Open",
        arrowStyleDoubleEnded: "Double-ended",
        arrowStyleScribbly: "Scribbly",
        toolLine: "Line",
        toolRect: "Rectangle",
        toolEllipse: "Ellipse",
        toolFreehand: "Pen",
        toolHighlight: "Highlighter",
        toolSpotlight: "Spotlight",
        toolText: "Text",
        toolSticker: "Sticker",
        toolCounter: "Number",
        toolPixelate: "Pixelate",
        toolRedact: "Solid block",
        toolCrop: "Crop",
        toolExpandCanvas: "Expand canvas",
        moreTools: "More tools",
        pastedImage: "Image",
        canvasFillWhite: "White",
        canvasFillTransparent: "Transparent",
        canvasFillCustom: "Custom color",
        textPlaceholder: "Text",
        cropApply: "Crop",
        cancel: "Cancel",
        colorLabel: "Color",
        strokeLabel: "Thickness",
        fontSizeLabel: "Font size",
        blurStrengthLabel: "Blur strength",
        spotlightDimStrengthLabel: "Dim outside",
        toolBlur: "Blur",
        blurStyleLabel: "Blur style",
        blurStyleErase: "Erase",
        blurTextOnly: "Text only",
        shadowLabel: "Shadows",
        backdropLabel: "Background",
        backdropNone: "None",
        editButton: "Edit",
        copyButton: "Copy",
        saveButton: "Save",
        saveAsButton: "Save As…",
        pinButton: "Pin to screen",
        copyTextButton: "Copy text",
        discardTitle: "Discard this screenshot?",
        discardMessage: "It was not copied or saved yet.",
        discardConfirm: "Discard",
        copiedHUD: "Screenshot copied",
        savedHUDFormat: "Saved to %@",
        savedAndCopiedHUDFormat: "Saved to %@ and copied",
        defaultActionLabel: "Default action",
        defaultActionCaption: "Runs automatically right after capture.",
        confirmationPreviewToggle: "Show confirmation preview",
        confirmationPreviewDurationLabel: "Confirmation duration",
        confirmationPreviewUntilDismissed: "Until dismissed",
        confirmationPreviewCaption: "After a successful automatic action, keep the preview available for editing or discarding.",
        defaultActionNone: "Ask each time",
        defaultActionSaveAndCopy: "Save & Copy",
        captureFailed: "The screen could not be captured",
        pinOpacity: "Opacity",
        pinClickThrough: "Ignore clicks",
        pinCloseAll: "Close all pins",
        backdropPaddingLabel: "Margin",
        backdropWallpaperLabel: "Wallpaper",
        backdropImageButton: "Image…",
        backdropSolidLabel: "Solid",
        backdropGradientLabel: "Gradient",
        backdropCornersLabel: "Corners",
        backdropSavePreset: "Save background",
        backdropDeletePreset: "Remove",
        backdropCustomLabel: "Custom",
        openEditorToggle: "Open the editor right after capturing",
        openEditorCaption: "The capture skips the floating preview and opens ready to annotate.",
        autoCopyToggle: "Copy to the clipboard automatically",
        autoCopyCaption: "Every capture goes to the clipboard as soon as it is taken, ready to paste. Saving a file stays a separate choice.",
        addToShelfToggle: "Add to the shelf automatically",
        addToShelfCaption: "Every capture also goes to the shelf, ready to drag into any app. One that opens in the editor goes there with Add to Shelf. Works while the shelf is on.",
        addToShelfButton: "Add to Shelf",
        hintLoupe: "Z toggles the loupe",
        lastRegionToggle: "Show the last capture outline",
        highlightWindowsToggle: "Highlight the window under the pointer",
        highlightWindowsCaption: "Turn off the blue window highlight while choosing an area. You can still click to capture a window.",
        backdropBlurLabel: "Blur",
        scrollingCaptureButton: "Scrolling capture",
        scrollingCaptureTitle: "Scrolling screenshot",
        scrollingCaptureProgressHUD: "Scroll with your mouse or trackpad. Press Enter or choose Done.",
        scrollingCaptureHintOff: "S toggles scrolling",
        scrollingCaptureHintOn: "Scrolling on",
        scrollingCaptureTooLongHUD: "Capture stopped at the safe limit",
        uploadLastCapture: "Upload latest screenshot",
        uploadExpiry: "Default link expiry",
        editLastCapture: "Edit latest screenshot",
        lastCaptureMissing: "Take a screenshot first",
        fullScreenCaptureButton: "Full screen",
        fullScreenShortcutTitle: "Capture the whole screen",
        bringForward: "Bring forward",
        sendBackward: "Send backward",
        shareSectionTitle: "Temporary links",
        shareCaption: "Choose 1, 6 or 24 hours when sharing. The image is deleted automatically.",
        shareButton: "Share",
        shareOneHour: "For 1 hour",
        shareSixHours: "For 6 hours",
        shareTwentyFourHours: "For 24 hours",
        sharingHUD: "Creating link…",
        sharedHUD: "Link copied",
        shareFailedHUD: "The link could not be created",
        linkCopyFailedHUD: "Link created, but copying failed. Copy it from Temporary links in Settings.",
        sharedLinksTitle: "Shared links",
        sharedLinksEmpty: "No active links",
        expiresLabel: "Expires",
        deleteLink: "Delete now",
        linkDeletedHUD: "Link deleted",
        deleteFailedHUD: "The link could not be deleted",
        openLink: "Open",
        copyLink: "Copy link",
        done: "Done",
        sharePrivacyButton: "Privacy",
        sharePrivacyTitle: "Privacy for temporary links",
        sharePrivacyData: "Mac Island sends only the rendered image and the expiration you choose. It does not send your name, account, device identifier or MAC address. On this Mac, it keeps only the link, expiration and private deletion token while the link is active.",
        sharePrivacyStorage: "Network providers and the service temporarily process your public IP to prevent abuse. The image and its link metadata are permanently deleted when you delete the link or its time ends. The service does not create screenshot backups.",
        sharePrivacyAccess: "Anyone with the link can view, download, save or redistribute the image. Active links are available to the service operator for abuse moderation. Share only with people you trust.",
        scrollingCaptureCaption: "Choose an area, scroll with your mouse or trackpad, then press Enter or Done to join it.",
        scrollingCaptureSelectionHint: "Drag only the part of the page that moves.",
        scrollingCapturePartialHUD: "The page changed. The completed part was kept.",
        previewPositionLabel: "Preview position",
        previewPositionAutomatic: "Automatic",
        previewPositionTopLeft: "Top left",
        previewPositionTopRight: "Top right",
        previewPositionBottomLeft: "Bottom left",
        previewPositionBottomRight: "Bottom right",
        previewFocusToggle: "Focus the preview automatically",
        previewFocusCaption: "Shortcuts work the moment the preview appears, but the keyboard leaves the app you were using until it closes.",
        hideVorssaintWindowsToggle: "Hide Mac Island windows",
        shareEnabledToggle: "Allow temporary links",
        editClipboardImage: "Edit clipboard image",
        clipboardImageMissing: "Copy an image first",
        showCaptureMenuOnShortcut: "Show capture menu when using keyboard shortcut",
        screenCaptureTitle: "Screen capture",
        dragOutHandleLabel: "Drag and drop",
        loupeStartsOnToggle: "Start selection with the magnifier on",
        loupeRememberZoomToggle: "Remember the magnifier’s last zoom",
        loupeDefaultZoomLabel: "Default magnifier zoom",
        loupeWheelZoomLabel: "Wheel zoom",
        loupeZoomFast: "Fast",
        loupeZoomStepped: "Step by step",
        loupeZoomOptionCaption: "Hold ⌥ to temporarily use the other mode.",
        watermarkLabel: "Watermark",
        watermarkImageLabel: "Image",
        watermarkTextPlaceholder: "Watermark text",
        watermarkPositionLabel: "Position",
        watermarkSizeLabel: "Size",
        watermarkOpacityLabel: "Opacity",
        watermarkRotationLabel: "Rotation",
        watermarkSavePreset: "Save watermark",
        watermarkColorRed: "Red",
        watermarkColorOrange: "Orange",
        watermarkColorYellow: "Yellow",
        watermarkColorGreen: "Green",
        watermarkColorBlue: "Blue",
        watermarkColorPurple: "Purple",
        watermarkColorBlack: "Black",
        watermarkColorWhite: "White",
        watermarkPositionTopLeading: "Top left",
        watermarkPositionTop: "Top center",
        watermarkPositionTopTrailing: "Top right",
        watermarkPositionLeading: "Center left",
        watermarkPositionCenter: "Center",
        watermarkPositionTrailing: "Center right",
        watermarkPositionBottomLeading: "Bottom left",
        watermarkPositionBottom: "Bottom center",
        watermarkPositionBottomTrailing: "Bottom right"
    )

    static let fr = ScreenshotFeatureStrings(
        pageTitle: "Capture d’écran",
        hubDescription: "Capture une zone, une fenêtre ou l’écran et permet de l’annoter",
        captureButton: "Capturer maintenant",
        panelCaption: "Capturez une zone, une fenêtre ou tout l’écran",
        fileNamePrefix: "Capture d’écran",
        hintDrag: "Faites glisser pour sélectionner une zone",
        hintClick: "Cliquez sur une fenêtre pour la capturer",
        hintFullScreen: "Return capture tout l’écran",
        hintCancel: "Esc annule",
        hintRepeat: "R répète la dernière zone",
        freezeToggle: "Figer l’écran pendant la sélection",
        freezeCaption: "L’image s’arrête pendant que vous choisissez la zone, donc rien ne bouge ni ne change pendant la sélection.",
        folderLabel: "Enregistrer dans",
        folderChoose: "Choisir…",
        subfolderLabel: "Motif de sous-dossier",
        subfolderCaption: "Facultatif. Crée des sous-dossiers datés dans le dossier ci-dessus avec %y, %year, %mo, %month, %d, %h, %mi et %s, par exemple %y-%mo pour 24-03.",
        fileNamePatternLabel: "Nom du fichier",
        fileNamePatternCaption: "Facultatif. Remplace le nom par défaut avec les mêmes jetons %y, %year, %mo, %month, %d, %h, %mi et %s, plus %# pour un numéro qui s’incrémente automatiquement (%## le remplit sur 2 chiffres, %### sur 3, etc.).",
        fileNumberStartLabel: "Commence à",
        fileNumberResetButton: "Réinitialiser",
        fileNumberNextFormat: "Suivant\u{00A0}: %d",
        delayLabel: "Délai",
        delayOff: "Désactivé",
        delaySecondsFormat: "%d s",
        pointerToggle: "Inclure le pointeur",
        downscaleToggle: "Enregistrer en taille 1x",
        downscaleCaption: "Les captures Retina sont enregistrées avec moitié moins de pixels, ce qui donne des fichiers plus petits.",
        editorTitle: "Capture d’écran",
        toolShortcutsTitle: "Outils de l’éditeur",
        toolShortcutsToggle: "Utiliser les raccourcis des outils",
        toolShortcutsCaption: "Cliquez sur un raccourci pour enregistrer une touche. Les chiffres 1 à 9 déplacent l’outil. Delete efface le raccourci.",
        toolShortcutReserved: "Cette touche est réservée à l’éditeur.",
        toolSelect: "Sélectionner",
        toolArrow: "Flèche",
        arrowStyleLabel: "Style de flèche",
        arrowStyleFilled: "Pleine",
        arrowStyleOutline: "Contour",
        arrowStyleOpen: "Ouverte",
        arrowStyleDoubleEnded: "À deux pointes",
        arrowStyleScribbly: "Gribouillée",
        toolLine: "Ligne",
        toolRect: "Rectangle",
        toolEllipse: "Ellipse",
        toolFreehand: "Crayon",
        toolHighlight: "Surligneur",
        toolSpotlight: "Projecteur",
        toolText: "Texte",
        toolSticker: "Autocollant",
        toolCounter: "Numéro",
        toolPixelate: "Pixelliser",
        toolRedact: "Bloc plein",
        toolCrop: "Rogner",
        toolExpandCanvas: "Agrandir le canevas",
        moreTools: "Autres outils",
        pastedImage: "Image",
        canvasFillWhite: "Blanc",
        canvasFillTransparent: "Transparent",
        canvasFillCustom: "Couleur personnalisée",
        textPlaceholder: "Texte",
        cropApply: "Rogner",
        cancel: "Annuler",
        colorLabel: "Couleur",
        strokeLabel: "Épaisseur",
        fontSizeLabel: "Taille de police",
        blurStrengthLabel: "Intensité du flou",
        spotlightDimStrengthLabel: "Assombrir l’extérieur",
        toolBlur: "Flouter",
        blurStyleLabel: "Style du flou",
        blurStyleErase: "Effacer",
        blurTextOnly: "Texte seul",
        shadowLabel: "Ombres",
        backdropLabel: "Arrière-plan",
        backdropNone: "Aucun",
        editButton: "Modifier",
        copyButton: "Copier",
        saveButton: "Enregistrer",
        saveAsButton: "Enregistrer sous…",
        pinButton: "Épingler à l’écran",
        copyTextButton: "Copier le texte",
        discardTitle: "Abandonner cette capture\u{00A0}?",
        discardMessage: "Elle n’a pas encore été copiée ni enregistrée.",
        discardConfirm: "Abandonner",
        copiedHUD: "Capture copiée",
        savedHUDFormat: "Enregistrée dans %@",
        savedAndCopiedHUDFormat: "Enregistrée dans %@ et copiée",
        defaultActionLabel: "Action par défaut",
        defaultActionCaption: "S’exécute automatiquement juste après la capture.",
        confirmationPreviewToggle: "Afficher l’aperçu de confirmation",
        confirmationPreviewDurationLabel: "Durée de confirmation",
        confirmationPreviewUntilDismissed: "Jusqu’à la fermeture",
        confirmationPreviewCaption: "Après une action automatique réussie, garde l’aperçu disponible pour le modifier ou le supprimer.",
        defaultActionNone: "Demander à chaque fois",
        defaultActionSaveAndCopy: "Enregistrer et copier",
        captureFailed: "Impossible de capturer l’écran",
        pinOpacity: "Opacité",
        pinClickThrough: "Ignorer les clics",
        pinCloseAll: "Fermer toutes les épingles",
        backdropPaddingLabel: "Marge",
        backdropWallpaperLabel: "Fond d’écran",
        backdropImageButton: "Image…",
        backdropSolidLabel: "Unie",
        backdropGradientLabel: "Dégradé",
        backdropCornersLabel: "Coins",
        backdropSavePreset: "Enregistrer le fond",
        backdropDeletePreset: "Supprimer",
        backdropCustomLabel: "Personnalisé",
        openEditorToggle: "Ouvrir l’éditeur juste après la capture",
        openEditorCaption: "La capture ignore l’aperçu flottant et s’ouvre prête à être annotée.",
        autoCopyToggle: "Copier automatiquement dans le presse-papiers",
        autoCopyCaption: "Chaque capture va dans le presse-papiers dès qu’elle est prise, prête à être collée. Enregistrer un fichier reste un choix distinct.",
        addToShelfToggle: "Ajouter automatiquement à l’étagère",
        addToShelfCaption: "Chaque capture va aussi sur l’étagère, prête à être glissée dans n’importe quelle app. Celle qui s’ouvre dans l’éditeur y va avec Ajouter à l’étagère. Fonctionne tant que l’étagère est activée.",
        addToShelfButton: "Ajouter à l’étagère",
        hintLoupe: "Z active la loupe",
        lastRegionToggle: "Afficher le contour de la dernière capture",
        highlightWindowsToggle: "Surligner la fenêtre sous le pointeur",
        highlightWindowsCaption: "Désactivez le surlignage bleu de la fenêtre lors du choix d’une zone. Vous pouvez toujours cliquer pour capturer une fenêtre.",
        backdropBlurLabel: "Flou",
        scrollingCaptureButton: "Capture avec défilement",
        scrollingCaptureTitle: "Capture avec défilement",
        scrollingCaptureProgressHUD: "Faites défiler avec la souris ou le trackpad. Appuyez sur Entrée ou choisissez Terminé.",
        scrollingCaptureHintOff: "S active le défilement",
        scrollingCaptureHintOn: "Défilement activé",
        scrollingCaptureTooLongHUD: "La capture s’est arrêtée à la limite sûre",
        uploadLastCapture: "Envoyer la dernière capture",
        uploadExpiry: "Expiration du lien par défaut",
        editLastCapture: "Modifier la dernière capture",
        lastCaptureMissing: "Prenez d’abord une capture d’écran",
        fullScreenCaptureButton: "Écran entier",
        fullScreenShortcutTitle: "Capturer tout l’écran",
        bringForward: "Avancer",
        sendBackward: "Reculer",
        shareSectionTitle: "Liens temporaires",
        shareCaption: "Choisissez 1, 6 ou 24 heures lors du partage. L’image est supprimée automatiquement.",
        shareButton: "Partager",
        shareOneHour: "Pendant 1 heure",
        shareSixHours: "Pendant 6 heures",
        shareTwentyFourHours: "Pendant 24 heures",
        sharingHUD: "Création du lien…",
        sharedHUD: "Lien copié",
        shareFailedHUD: "Impossible de créer le lien",
        linkCopyFailedHUD: "Lien créé, mais la copie a échoué. Copiez-le depuis Liens temporaires dans les réglages.",
        sharedLinksTitle: "Liens partagés",
        sharedLinksEmpty: "Aucun lien actif",
        expiresLabel: "Expire",
        deleteLink: "Supprimer maintenant",
        linkDeletedHUD: "Lien supprimé",
        deleteFailedHUD: "Impossible de supprimer le lien",
        openLink: "Ouvrir",
        copyLink: "Copier le lien",
        done: "Terminé",
        sharePrivacyButton: "Confidentialité",
        sharePrivacyTitle: "Confidentialité des liens temporaires",
        sharePrivacyData: "Mac Island envoie uniquement l’image finale et la durée choisie. Il n’envoie ni votre nom, ni votre compte, ni l’identifiant de l’appareil, ni l’adresse MAC. Sur ce Mac, seuls le lien, son expiration et le jeton privé de suppression sont conservés tant que le lien est actif.",
        sharePrivacyStorage: "Les fournisseurs réseau et le service traitent temporairement votre adresse IP publique pour empêcher les abus. L’image et les métadonnées du lien sont définitivement supprimées lorsque vous supprimez le lien ou qu’il expire. Le service ne crée aucune sauvegarde des captures.",
        sharePrivacyAccess: "Toute personne disposant du lien peut afficher, télécharger, enregistrer ou redistribuer l’image. Les liens actifs sont accessibles à l’opérateur du service pour modérer les abus. Partagez-les uniquement avec des personnes de confiance.",
        scrollingCaptureCaption: "Choisissez une zone, faites-la défiler avec la souris ou le trackpad, puis appuyez sur Entrée ou Terminé pour l’assembler.",
        scrollingCaptureSelectionHint: "Sélectionnez uniquement la partie de la page qui défile.",
        scrollingCapturePartialHUD: "La page a changé. La partie terminée a été conservée.",
        previewPositionLabel: "Position de l’aperçu",
        previewPositionAutomatic: "Automatique",
        previewPositionTopLeft: "En haut à gauche",
        previewPositionTopRight: "En haut à droite",
        previewPositionBottomLeft: "En bas à gauche",
        previewPositionBottomRight: "En bas à droite",
        previewFocusToggle: "Donner le focus à l’aperçu automatiquement",
        previewFocusCaption: "Les raccourcis fonctionnent dès que l’aperçu apparaît, mais le clavier quitte l’app que vous utilisiez jusqu’à sa fermeture.",
        hideVorssaintWindowsToggle: "Masquer les fenêtres Mac Island",
        shareEnabledToggle: "Autoriser les liens temporaires",
        editClipboardImage: "Modifier l’image copiée",
        clipboardImageMissing: "Copiez d’abord une image",
        showCaptureMenuOnShortcut: "Afficher le menu de capture avec le raccourci clavier",
        screenCaptureTitle: "Outils de capture",
        dragOutHandleLabel: "Glisser-déposer",
        loupeStartsOnToggle: "Démarrer la sélection avec la loupe activée",
        loupeRememberZoomToggle: "Mémoriser le dernier zoom de la loupe",
        loupeDefaultZoomLabel: "Zoom par défaut de la loupe",
        loupeWheelZoomLabel: "Zoom à la molette",
        loupeZoomFast: "Rapide",
        loupeZoomStepped: "Pas à pas",
        loupeZoomOptionCaption: "Maintenez ⌥ pour utiliser temporairement l’autre mode.",
        watermarkLabel: "Filigrane",
        watermarkImageLabel: "Image",
        watermarkTextPlaceholder: "Texte du filigrane",
        watermarkPositionLabel: "Position",
        watermarkSizeLabel: "Taille",
        watermarkOpacityLabel: "Opacité",
        watermarkRotationLabel: "Rotation",
        watermarkSavePreset: "Enregistrer le filigrane",
        watermarkColorRed: "Rouge",
        watermarkColorOrange: "Orange",
        watermarkColorYellow: "Jaune",
        watermarkColorGreen: "Vert",
        watermarkColorBlue: "Bleu",
        watermarkColorPurple: "Violet",
        watermarkColorBlack: "Noir",
        watermarkColorWhite: "Blanc",
        watermarkPositionTopLeading: "En haut à gauche",
        watermarkPositionTop: "En haut au centre",
        watermarkPositionTopTrailing: "En haut à droite",
        watermarkPositionLeading: "Au centre à gauche",
        watermarkPositionCenter: "Centre",
        watermarkPositionTrailing: "Au centre à droite",
        watermarkPositionBottomLeading: "En bas à gauche",
        watermarkPositionBottom: "En bas au centre",
        watermarkPositionBottomTrailing: "En bas à droite"
    )

}

extension ScreenshotFeatureStrings {
    func blurStyleTitle(_ style: ScreenshotSupport.BlurStyleID) -> String {
        switch style {
        case .pixelate: return toolPixelate
        case .blur: return toolBlur
        case .erase: return blurStyleErase
        }
    }

    func arrowStyleTitle(_ style: ScreenshotSupport.ArrowStyleID) -> String {
        switch style {
        case .filled: return arrowStyleFilled
        case .outline: return arrowStyleOutline
        case .open: return arrowStyleOpen
        case .doubleEnded: return arrowStyleDoubleEnded
        case .scribbly: return arrowStyleScribbly
        }
    }
}
