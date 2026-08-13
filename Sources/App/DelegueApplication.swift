// Délégué d'application : cycle de vie et enregistrement des canaux d'entrée.

import AppKit

@MainActor
final class DelegueApplication: NSObject, NSApplicationDelegate {

    private var elementBarreMenus: NSStatusItem?
    private let serveurSocket = ServeurSocket()

    /// Évite de redemander l'autorisation à chaque raccourci.
    private var autorisationDejaProposee = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Deux instances se disputeraient le socket et le raccourci global. La
        // seconde cède la place, après avoir mis la première au premier plan.
        //
        // Exception sous test : le harnais XCTest héberge ses tests dans une
        // instance de l'application, qui doit vivre même si une autre tourne.
        if !Self.sousTest, let existante = autreInstance() {
            existante.activate()
            Journal.fichier("app", "instance déjà active — sortie")
            NSApp.terminate(nil)
            return
        }

        Journal.reinitialiserFichier()
        Journal.app.info("Démarrage d’À Voix Haute")

        // À ce stade aucune lecture n'est en cours : tout fichier restant
        // provient d'une exécution précédente interrompue.
        GestionnaireFichiersTemp.nettoyerOrphelins()

        installerElementBarreMenus()
        installerServeurSocket()

        // Ni service ni raccourci sous test : ils sont enregistrés à l'échelle
        // du système et entreraient en conflit avec l'instance installée.
        guard !Self.sousTest else { return }
        FournisseurService.installer()
        installerRaccourciGlobal()

        // L'application n'ayant pas de fenêtre principale, rien n'indiquerait
        // au nouvel utilisateur ce qu'elle sait faire ni comment l'invoquer.
        FenetreBienvenue.partage.afficherSiPremierLancement()

        // Une vérification maintenant, puis chaque jour : l'application reste
        // lancée des semaines, une seule au démarrage laisserait passer les
        // versions.
        VerificateurMiseAJour.partage.demarrerSurveillance()
    }

    /// L'application est-elle hébergée par le harnais de tests ?
    private static var sousTest: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Cherche une autre instance de l'application déjà lancée.
    private func autreInstance() -> NSRunningApplication? {
        let miennes = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "fr.dimitri.AVoixHaute"
        )
        return miennes.first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }

    /// Branche le raccourci clavier global sur la capture de sélection.
    private func installerRaccourciGlobal() {
        RaccourciGlobal.partage.surDeclenchement = { [weak self] in
            self?.lireSelectionCourante()
        }
        RaccourciGlobal.partage.activer()
    }

    /// Lit ce qui est sélectionné dans l'application au premier plan.
    private func lireSelectionCourante() {
        let resultat = CaptureSelection.capturer(
            restaurer: Reglages.partage.restaurerPressePapiers
        )

        switch resultat {
        case .selection(let texte):
            Journal.fichier("raccourci", "sélection capturée : \(texte.count) caractères")
            lire(texte: texte, source: .raccourci)

        case .pressePapiers(let texte):
            // Sans autorisation, ou sélection vide : le presse-papiers reste
            // une source utilisable.
            Journal.fichier("raccourci", "repli sur le presse-papiers : \(texte.count) caractères")

            // Le repli passe souvent inaperçu — l'utilisateur entend un texte
            // sans comprendre pourquoi ce n'est pas sa sélection. On explique
            // la première fois, puis on se tait.
            if !CaptureSelection.estAutorisee && !autorisationDejaProposee {
                autorisationDejaProposee = true
                proposerAutorisationAccessibilite()
                return
            }

            lire(texte: texte, source: .pressePapiers)

        case .nonAutorisee:
            proposerAutorisationAccessibilite()

        case .rien:
            Journal.fichier("raccourci", "aucun texte à lire")
            NSSound.beep()
        }
    }

    /// Explique pourquoi l'autorisation est nécessaire et conduit au réglage.
    private func proposerAutorisationAccessibilite() {
        let alerte = NSAlert()
        alerte.messageText = tr("raccourci.alerteTitre")
        alerte.informativeText = tr("raccourci.alerteMessage")
        alerte.alertStyle = .informational
        alerte.addButton(withTitle: tr("raccourci.alerteOuvrir"))
        alerte.addButton(withTitle: tr("raccourci.alertePlusTard"))

        NSApp.activate(ignoringOtherApps: true)
        if alerte.runModal() == .alertFirstButtonReturn {
            // Cet appel inscrit l'application dans la liste des Réglages, où
            // elle n'apparaît pas tant qu'elle n'a rien demandé.
            CaptureSelection.demanderAutorisation()
            CaptureSelection.ouvrirReglagesAccessibilite()
        }
    }

    /// Ouvre le canal d'entrée principal, celui du helper `lire`.
    ///
    /// Rien n'est ouvert sous test : le socket est unique par utilisateur, et
    /// l'instance de test le déroberait à celle qui tourne réellement.
    private func installerServeurSocket() {
        guard !Self.sousTest else { return }
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
        Journal.app.info("Arrêt d’À Voix Haute")
        serveurSocket.arreter()
        GestionnaireFichiersTemp.nettoyerOrphelins()
    }

    /// L'application n'a pas d'icône dans le Dock : la barre de menus est le
    /// seul point d'accès permanent aux réglages et à l'arrêt.
    private func installerElementBarreMenus() {
        let element = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        element.button?.image = NSImage(
            systemSymbolName: "waveform",
            accessibilityDescription: "À Voix Haute"
        )

        let menu = NSMenu()
        menu.addItem(
            withTitle: tr("menu.lirePressePapiers"),
            action: #selector(lirePressePapiers),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: tr("menu.toutArreter"),
            action: #selector(toutArreter),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: tr("menu.rechercherMaj"),
            action: #selector(rechercherMiseAJour),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: tr("menu.guide"),
            action: #selector(ouvrirAssistant),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: tr("menu.reglages"),
            action: #selector(ouvrirReglages),
            keyEquivalent: ","
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: tr("menu.quitter"),
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

    @objc private func rechercherMiseAJour() {
        Task { await VerificateurMiseAJour.partage.verifier(silencieux: false) }
    }

    @objc private func ouvrirAssistant() {
        FenetreBienvenue.partage.afficher()
    }

    @objc private func ouvrirReglages() {
        FenetreReglages.partage.afficher()
    }
}
