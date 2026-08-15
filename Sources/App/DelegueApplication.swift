// Délégué d'application : cycle de vie et enregistrement des canaux d'entrée.

import AppKit

@MainActor
final class DelegueApplication: NSObject, NSApplicationDelegate {

    private var elementBarreMenus: NSStatusItem?
    private let serveurSocket = ServeurSocket()

    /// Évite de redemander l'autorisation à chaque raccourci.
    private var autorisationDejaProposee = false

    /// URL reçues avant que l'application ne soit prête.
    ///
    /// `application(_:open:)` précède `applicationDidFinishLaunching` : une URL
    /// arrive donc avant que l'on sache si cette instance vivra ou cédera la
    /// place à une autre. Les URL sont mises de côté ici, puis traitées — ou
    /// relayées — une fois cette question tranchée.
    private var urlsEnAttente: [URL] = []

    /// L'application est-elle prête à traiter une URL sans la différer ?
    private var demarrageTermine = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Deux instances se disputeraient le socket et le raccourci global. La
        // seconde cède la place, après avoir mis la première au premier plan.
        //
        // Exception sous test : le harnais XCTest héberge ses tests dans une
        // instance de l'application, qui doit vivre même si une autre tourne.
        if !Self.sousTest, let existante = autreInstance() {
            existante.activate()
            // Traité avant de céder la place : l'inscription concerne le
            // bundle, non le processus, et cette instance-ci est aussi
            // légitime que l'autre pour la demander.
            appliquerArgumentsOuvertureSession()
            // Sans ce relais, une URL ouverte alors que l'application tourne
            // déjà serait perdue : cette instance-ci s'arrête, et celle qui
            // vit n'a jamais rien reçu.
            relayerUrlsEnAttente()
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

        // Les canaux d'entrée sont en place : une URL peut désormais être
        // traitée directement. Avant ce point, `application(_:open:)` se
        // contente de mettre de côté.
        demarrageTermine = true
        traiterUrlsEnAttente()

        appliquerArgumentsOuvertureSession()

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

    /// Applique les arguments d'inscription à l'ouverture de session.
    ///
    /// `Scripts/installer.sh` les passe plutôt que de poser un agent launchd :
    /// les deux mécanismes ne se voient pas, et l'interrupteur des réglages
    /// interroge SMAppService.
    private func appliquerArgumentsOuvertureSession() {
        let arguments = CommandLine.arguments
        if arguments.contains("--inscrire-ouverture-session") {
            InstallationSysteme.definirLancementOuvertureSession(true)
        }
        if arguments.contains("--retirer-ouverture-session") {
            InstallationSysteme.definirLancementOuvertureSession(false)
        }
    }

    /// L'application est-elle hébergée par le harnais de tests ?
    private static var sousTest: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Cherche une autre instance de l'application déjà lancée.
    private func autreInstance() -> NSRunningApplication? {
        let miennes = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "app.avoixhaute.player"
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

    /// Schémas d'URL enregistrés, un par langue de l'application.
    ///
    /// Doit rester en accord avec `CFBundleURLSchemes` dans l'Info.plist :
    /// LaunchServices n'achemine vers l'application que les schémas qui y sont
    /// déclarés, ce test n'en est que la contrepartie côté code.
    private static let schemas: Set<String> = [
        "lire", "read-aloud", "leer", "vorlesen", "leggi", "ler"
    ]

    /// Hôtes désignant le presse-papiers, un par langue de l'application.
    ///
    /// Les six formes sont acceptées en permanence, sans regard pour la langue
    /// du système : une URL notée dans un script ou une documentation doit
    /// fonctionner sur toutes les machines, ce qu'un identifiant suivant la
    /// langue du poste ne permettrait pas.
    private static let hotesPressePapiers: Set<String> = [
        "presse-papiers", "clipboard", "portapapeles",
        "zwischenablage", "appunti", "area-de-transferencia"
    ]

    /// Hôtes désignant un texte passé en paramètre.
    private static let hotesTexte: Set<String> = [
        "texte", "text", "texto", "testo"
    ]

    /// Canal d'entrée URL : `lire://presse-papiers` ou `lire://texte?t=…`
    ///
    /// Ce canal convient aux textes courts ; au-delà, les limites de longueur
    /// d'URL s'appliquent, d'où le socket Unix comme canal principal.
    func application(_ application: NSApplication, open urls: [URL]) {
        // Ce message précède `applicationDidFinishLaunching` : au premier
        // lancement, ni le socket ni le gestionnaire de lecteurs n'existent
        // encore. Les URL attendent que le démarrage ait tranché.
        guard demarrageTermine else {
            urlsEnAttente.append(contentsOf: urls)
            return
        }
        traiter(urls)
    }

    /// Traite les URL mises de côté pendant le démarrage.
    private func traiterUrlsEnAttente() {
        let differees = urlsEnAttente
        urlsEnAttente.removeAll()
        guard !differees.isEmpty else { return }
        traiter(differees)
    }

    /// Transmet les URL à l'instance déjà lancée, par le socket.
    ///
    /// Le presse-papiers est lu ici plutôt que là-bas : l'instance active n'a
    /// pas besoin de connaître l'URL, seulement le texte à lire.
    private func relayerUrlsEnAttente() {
        for url in urlsEnAttente where Self.schemas.contains(url.scheme?.lowercased() ?? "") {
            let hote = url.host?.lowercased()

            var texte: String?
            if hote == nil || Self.hotesPressePapiers.contains(hote ?? "") {
                texte = NSPasteboard.general.string(forType: .string)
            } else if Self.hotesTexte.contains(hote ?? "") {
                let composants = URLComponents(url: url, resolvingAgainstBaseURL: false)
                texte = composants?.queryItems?.first(where: { $0.name == "t" })?.value
            }

            guard let contenu = texte,
                  !contenu.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

            ClientSocket.envoyerLecture(contenu, source: "url")
        }
        urlsEnAttente.removeAll()
    }

    private func traiter(_ urls: [URL]) {
        for url in urls where Self.schemas.contains(url.scheme?.lowercased() ?? "") {
            // L'hôte d'une URL est normalisé en minuscules par le système,
            // mais une saisie manuelle peut porter des majuscules.
            let hote = url.host?.lowercased()

            switch hote {
            case let hote? where Self.hotesPressePapiers.contains(hote):
                lirePressePapiers()
            case nil:
                lirePressePapiers()
            case let hote? where Self.hotesTexte.contains(hote):
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
