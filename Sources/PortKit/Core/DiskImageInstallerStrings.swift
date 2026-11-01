// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Derived from Vorssaint (c) 2026 Vorssaint, GPL-3.0-or-later. Modified for Mac Island.

import Foundation

struct DiskImageInstallerStrings {
    let title: String
    let hubDescription: String
    let useUserApplications: String
    let applicationsFolder: String
    let userApplicationsFolder: String
    let promptTitle: String
    let promptBodyFormat: String
    let installButton: String
    let installedTitle: String
    let installedBodyFormat: String
    let installedKeepingMountBodyFormat: String
    let installedKeepingDownloadBodyFormat: String
    let failedTitle: String
    let failedBody: String
    let verificationFailedBody: String
    let alreadyInstalledBodyFormat: String
    let trashDownloadOption: String
    let revealAppOption: String
    let installedKeptDownloadBodyFormat: String
    let installingFormat: String
}

extension FeatureStrings {
    static func diskImageInstaller(_ language: AppLanguage) -> DiskImageInstallerStrings {
        switch language {
        case .enUS: return .enUS
        default: return .fr
        }
    }
}

extension DiskImageInstallerStrings {
    static let enUS = DiskImageInstallerStrings(
        title: "Disk image installer",
        hubDescription: "Install the single app inside a disk image and clean up the download",
        useUserApplications: "Install in the Applications folder inside your home folder",
        applicationsFolder: "the Applications folder",
        userApplicationsFolder: "the Applications folder inside your home folder",
        promptTitle: "Install this app?",
        promptBodyFormat: "%@ will be copied to %@ and the disk image ejected.",
        installButton: "Install",
        installedTitle: "App installed",
        installedBodyFormat: "%@ is ready in %@. The disk image was ejected and its download moved to Trash.",
        installedKeepingMountBodyFormat: "%@ is installed in %@, but the disk image could not be ejected. Its download was kept.",
        installedKeepingDownloadBodyFormat: "%@ is installed in %@ and the disk image was ejected, but its download could not be moved to Trash.",
        failedTitle: "Could not install",
        failedBody: "Nothing was changed. You can still drag the app to Applications.",
        verificationFailedBody: "This Mac could not verify the app, so nothing was installed.",
        alreadyInstalledBodyFormat: "%@ is already in Applications.",
        trashDownloadOption: "Move the download to Trash",
        revealAppOption: "Show the installed app in Finder",
        installedKeptDownloadBodyFormat: "%@ is ready in %@. The disk image was ejected and its download kept.",
        installingFormat: "Installing %@…"
    )

    static let fr = DiskImageInstallerStrings(
        title: "Installation depuis une image disque",
        hubDescription: "Installez l’unique app d’une image disque et nettoyez le téléchargement",
        useUserApplications: "Installer dans le dossier Applications de votre dossier personnel",
        applicationsFolder: "le dossier Applications",
        userApplicationsFolder: "le dossier Applications de votre dossier personnel",
        promptTitle: "Installer cette app\u{00A0}?",
        promptBodyFormat: "%@ sera copiée dans %@ et l’image disque éjectée.",
        installButton: "Installer",
        installedTitle: "App installée",
        installedBodyFormat: "%@ est prête dans %@. L’image disque a été éjectée et le téléchargement placé dans la Corbeille.",
        installedKeepingMountBodyFormat: "%@ est installée dans %@, mais l’image disque n’a pas pu être éjectée. Le téléchargement a été conservé.",
        installedKeepingDownloadBodyFormat: "%@ est installée dans %@ et l’image disque a été éjectée, mais le téléchargement n’a pas pu être placé dans la Corbeille.",
        failedTitle: "Installation impossible",
        failedBody: "Rien n’a été modifié. Vous pouvez toujours faire glisser l’app vers Applications.",
        verificationFailedBody: "Ce Mac n’a pas pu vérifier l’app, donc rien n’a été installé.",
        alreadyInstalledBodyFormat: "%@ se trouve déjà dans Applications.",
        trashDownloadOption: "Placer le téléchargement dans la Corbeille",
        revealAppOption: "Afficher l’app installée dans le Finder",
        installedKeptDownloadBodyFormat: "%@ est prête dans %@. L’image disque a été éjectée et le téléchargement conservé.",
        installingFormat: "Installation de %@…"
    )

}
