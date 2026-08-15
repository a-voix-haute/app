// Ce que `Scripts/installer.sh` pose autour du bundle, fait par l'application
// elle-même.
//
// Une installation par glisser-déposer depuis le disque `.dmg` ne copie que le
// bundle. Le service du clic droit, le raccourci global et les schémas d'URL
// s'en accommodent — ils sont déclarés dans l'Info.plist ou enregistrés au
// lancement. Deux choses manquaient : la commande en ligne de commande et le
// lancement à l'ouverture de session, toutes deux réservées jusqu'ici à ceux
// qui compilent depuis les sources.

import AppKit
import ServiceManagement

@MainActor
enum InstallationSysteme {

    // MARK: - Lancement à l'ouverture de session

    /// L'application est-elle inscrite pour démarrer à l'ouverture de session ?
    static var lancementOuvertureSession: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// L'inscription a-t-elle été refusée par l'utilisateur dans les Réglages
    /// Système ?
    ///
    /// `SMAppService` n'échoue pas dans ce cas : il accepte la demande et
    /// laisse le statut à `requiresApproval`. Sans cette distinction,
    /// l'interrupteur paraîtrait actif alors que rien ne démarrerait.
    static var approbationRequise: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Inscrit ou retire l'application de l'ouverture de session.
    ///
    /// `SMAppService` plutôt qu'un agent `launchd` écrit à la main : macOS 13
    /// l'expose à toute application signée, et l'inscription apparaît dans
    /// Réglages Système → Général → Ouverture, où l'utilisateur peut la
    /// retirer. Un agent posé dans `~/Library/LaunchAgents` y figure aussi,
    /// mais l'application ne saurait pas qu'il a été désactivé.
    @discardableResult
    static func definirLancementOuvertureSession(_ actif: Bool) -> Bool {
        do {
            if actif {
                // `register()` lève si le service est déjà inscrit : le cas
                // n'est pas une erreur.
                guard SMAppService.mainApp.status != .enabled else { return true }
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Journal.fichier("installation", "ouverture de session : \(actif)")
            return true
        } catch {
            Journal.fichier(
                "installation",
                "ouverture de session refusée : \(error.localizedDescription)"
            )
            return false
        }
    }

    // MARK: - Commande en ligne de commande

    /// Dossier des commandes de l'utilisateur.
    ///
    /// `~/.local/bin` suit la convention XDG et figure dans le `PATH` de la
    /// plupart des configurations. `/usr/local/bin` demanderait les droits
    /// d'administrateur.
    static let dossierCommandes = URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent(".local/bin", isDirectory: true)

    /// Noms sous lesquels la commande répond, un par langue de l'application.
    ///
    /// Doit rester en accord avec `NOMS_HELPER` dans `Scripts/installer.sh`.
    /// « read-aloud » et non « read » : `read` est une primitive de bash et de
    /// zsh, et une primitive l'emporte toujours sur un fichier du `PATH`.
    static let nomsCommande = ["lire", "read-aloud", "leer", "vorlesen", "leggi", "ler"]

    /// Emplacement du binaire dans le bundle.
    private static var binaire: URL? {
        Bundle.main.url(forResource: "lire", withExtension: nil)
    }

    /// Les commandes sont-elles installées et à jour ?
    ///
    /// Un lien qui pointe ailleurs — vers une copie déplacée, ou vers une
    /// installation précédente — compte pour absent : il ne mènerait pas à ce
    /// bundle-ci.
    static var commandeInstallee: Bool {
        guard let binaire else { return false }
        return nomsCommande.allSatisfy { nom in
            let lien = dossierCommandes.appendingPathComponent(nom)
            guard let cible = try? FileManager.default.destinationOfSymbolicLink(atPath: lien.path)
            else { return false }
            return cible == binaire.path
        }
    }

    /// `~/.local/bin` figure-t-il dans le `PATH` de l'utilisateur ?
    ///
    /// L'information ne conditionne pas l'installation : elle sert à prévenir
    /// que la commande existe sans être trouvable, ce qui serait autrement
    /// incompréhensible.
    static var dossierDansPath: Bool {
        guard let chemin = ProcessInfo.processInfo.environment["PATH"] else { return false }
        let attendu = dossierCommandes.path
        return chemin.split(separator: ":").contains { element in
            // Le `PATH` peut contenir la forme littérale « ~/.local/bin ».
            let normalise = element.replacingOccurrences(
                of: "~",
                with: NSHomeDirectory()
            )
            return normalise == attendu
        }
    }

    /// Crée un lien par nom de commande. Renvoie le nombre de liens posés.
    @discardableResult
    static func installerCommande() -> Int {
        guard let binaire else {
            Journal.fichier("installation", "binaire « lire » introuvable dans le bundle")
            return 0
        }

        let gestionnaire = FileManager.default
        try? gestionnaire.createDirectory(at: dossierCommandes, withIntermediateDirectories: true)

        var poses = 0
        for nom in nomsCommande {
            let lien = dossierCommandes.appendingPathComponent(nom)

            // Un lien existant est remplacé, un fichier ordinaire ne l'est
            // jamais : il appartient à quelqu'un d'autre.
            if let type = try? gestionnaire.attributesOfItem(atPath: lien.path)[.type] as? FileAttributeType {
                guard type == .typeSymbolicLink else {
                    Journal.fichier("installation", "\(nom) existe et n'est pas un lien — ignoré")
                    continue
                }
                try? gestionnaire.removeItem(at: lien)
            }

            do {
                try gestionnaire.createSymbolicLink(at: lien, withDestinationURL: binaire)
                poses += 1
            } catch {
                Journal.fichier("installation", "\(nom) : \(error.localizedDescription)")
            }
        }

        Journal.fichier("installation", "commande installée : \(poses) lien(s)")
        return poses
    }

    /// Retire les liens qui pointent vers ce bundle, et eux seuls.
    @discardableResult
    static func desinstallerCommande() -> Int {
        guard let binaire else { return 0 }
        let gestionnaire = FileManager.default

        var retires = 0
        for nom in nomsCommande {
            let lien = dossierCommandes.appendingPathComponent(nom)
            guard let cible = try? gestionnaire.destinationOfSymbolicLink(atPath: lien.path),
                  cible == binaire.path else { continue }
            if (try? gestionnaire.removeItem(at: lien)) != nil { retires += 1 }
        }

        Journal.fichier("installation", "commande retirée : \(retires) lien(s)")
        return retires
    }
}
