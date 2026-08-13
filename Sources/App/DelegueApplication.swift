// Délégué d'application : cycle de vie et enregistrement des canaux d'entrée.

import AppKit

final class DelegueApplication: NSObject, NSApplicationDelegate {

    private var elementBarreMenus: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Journal.app.info("Démarrage de Lecteur")

        // À ce stade aucune lecture n'est en cours : tout fichier restant
        // provient d'une exécution précédente interrompue.
        GestionnaireFichiersTemp.nettoyerOrphelins()

        installerElementBarreMenus()
    }

    func applicationWillTerminate(_ notification: Notification) {
        Journal.app.info("Arrêt de Lecteur")
        GestionnaireFichiersTemp.nettoyerOrphelins()
    }

    /// L'application n'a pas d'icône dans le Dock : la barre de menus est le
    /// seul point d'accès permanent aux réglages et à l'arrêt.
    private func installerElementBarreMenus() {
        let element = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        element.button?.image = NSImage(
            systemSymbolName: "waveform",
            accessibilityDescription: "Lecteur"
        )

        let menu = NSMenu()
        menu.addItem(
            withTitle: "Lire le presse-papiers",
            action: #selector(lirePressePapiers),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Réglages…",
            action: #selector(ouvrirReglages),
            keyEquivalent: ","
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: "Quitter Lecteur",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        element.menu = menu
        elementBarreMenus = element
    }

    @objc private func lirePressePapiers() {
        guard let texte = NSPasteboard.general.string(forType: .string), !texte.isEmpty else {
            Journal.entree.notice("Presse-papiers vide ou sans texte")
            return
        }
        Journal.entree.info("Lecture depuis le presse-papiers : \(texte.count) caractères")
        // Raccordé au GestionnaireLecteurs à l'étape 6.
    }

    @objc private func ouvrirReglages() {
        // Fenêtre de réglages ajoutée à l'étape 9.
        Journal.app.debug("Ouverture des réglages demandée")
    }
}
