// Délégué d'application : cycle de vie et enregistrement des canaux d'entrée.

import AppKit

final class DelegueApplication: NSObject, NSApplicationDelegate {

    private var elementBarreMenus: NSStatusItem?

    /// Lecteurs ouverts. Repris par GestionnaireLecteurs à l'étape 6.
    private var controleurs: [ControleurFenetreLecteur] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        Journal.app.info("Démarrage de Lecteur")

        // À ce stade aucune lecture n'est en cours : tout fichier restant
        // provient d'une exécution précédente interrompue.
        GestionnaireFichiersTemp.nettoyerOrphelins()

        installerElementBarreMenus()
    }

    /// Canal d'entrée URL : `lire://presse-papiers` ou `lire://texte?t=…`
    ///
    /// Ce canal convient aux textes courts ; au-delà, les limites de longueur
    /// d'URL s'appliquent, d'où le socket Unix comme canal principal.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "lire" {
            switch url.host {
            case "presse-papiers", "clipboard", nil:
                lirePressePapiers()
            case "texte":
                let composants = URLComponents(url: url, resolvingAgainstBaseURL: false)
                if let texte = composants?.queryItems?.first(where: { $0.name == "t" })?.value {
                    lire(texte: texte, titre: "Lecture")
                }
            default:
                Journal.entree.notice("URL non reconnue : \(url.absoluteString, privacy: .public)")
            }
        }
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
        lire(texte: texte, titre: "Presse-papiers")
    }

    /// Chaîne complète : nettoyage, synthèse, ouverture du lecteur.
    ///
    /// Remplacé par GestionnaireLecteurs à l'étape 6, qui y ajoutera les règles
    /// de coexistence entre lecteurs.
    private func lire(texte: String, titre: String) {
        let propre = NettoyeurMarkdown.nettoyer(texte)
        guard !propre.isEmpty else {
            Journal.entree.notice("Texte vide après nettoyage")
            return
        }

        let moteur = MoteurSay()
        guard let voix = moteur.voixDisponibles().first(where: { $0.nom == "Thomas" })
                ?? moteur.voixDisponibles().first(where: { $0.codeLangue == "fr" }) else {
            Journal.synthese.error("Aucune voix française disponible")
            return
        }

        Task { @MainActor in
            do {
                let audio = try await moteur.synthetiser(
                    texte: propre,
                    voix: voix,
                    vitesseBase: 1.0
                ) { _ in }

                let lecteur = Lecteur(fichier: audio)
                let controleur = ControleurFenetreLecteur(
                    lecteur: lecteur,
                    titre: titre,
                    rang: self.controleurs.count
                )
                controleur.surFermeture = { [weak self] ferme in
                    self?.controleurs.removeAll { $0 === ferme }
                }
                self.controleurs.append(controleur)
                controleur.afficher()
                lecteur.lire()
            } catch {
                Journal.synthese.error("Synthèse échouée : \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    @objc private func ouvrirReglages() {
        // Fenêtre de réglages ajoutée à l'étape 9.
        Journal.app.debug("Ouverture des réglages demandée")
    }
}
