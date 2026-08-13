// Délégué d'application : cycle de vie et enregistrement des canaux d'entrée.

import AppKit

@MainActor
final class DelegueApplication: NSObject, NSApplicationDelegate {

    private var elementBarreMenus: NSStatusItem?
    private let serveurSocket = ServeurSocket()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Journal.reinitialiserFichier()
        Journal.app.info("Démarrage de Lecteur")

        // À ce stade aucune lecture n'est en cours : tout fichier restant
        // provient d'une exécution précédente interrompue.
        GestionnaireFichiersTemp.nettoyerOrphelins()

        installerElementBarreMenus()
        installerServeurSocket()
    }

    /// Ouvre le canal d'entrée principal, celui du helper `lire`.
    private func installerServeurSocket() {
        serveurSocket.surDemandeLecture = { texte, titre, source in
            let origine = source.flatMap(SourceLecture.init(rawValue:)) ?? .cli
            GestionnaireLecteurs.partage.demanderLecture(
                texte: texte,
                source: origine,
                titre: titre
            )
        }
        serveurSocket.surDemandeArret = {
            GestionnaireLecteurs.partage.toutArreter()
        }
        serveurSocket.demarrer()
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
                    lire(texte: texte, source: .url)
                }
            default:
                Journal.entree.notice("URL non reconnue : \(url.absoluteString, privacy: .public)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Journal.app.info("Arrêt de Lecteur")
        serveurSocket.arreter()
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
        menu.addItem(
            withTitle: "Arrêter toutes les lectures",
            action: #selector(toutArreter),
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
        lire(texte: texte, source: .pressePapiers)
    }

    private func lire(texte: String, source: SourceLecture, titre: String? = nil) {
        GestionnaireLecteurs.partage.demanderLecture(
            texte: texte,
            source: source,
            titre: titre
        )
    }

    @objc private func toutArreter() {
        GestionnaireLecteurs.partage.toutArreter()
    }

    @objc private func ouvrirReglages() {
        // Fenêtre de réglages ajoutée à l'étape 9.
        Journal.app.debug("Ouverture des réglages demandée")
    }
}
