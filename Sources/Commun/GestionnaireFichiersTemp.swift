// Gestion des fichiers audio temporaires.
//
// Chaque lecture produit un fichier .m4a dans un dossier dédié. Ces fichiers
// sont supprimés à la fermeture du lecteur correspondant ; ceux qu'un arrêt
// brutal aurait laissés derrière sont balayés au démarrage de l'application.
//
// Ils portent le texte de l'utilisateur — une sélection prise dans n'importe
// quelle application, parfois un mot de passe ou un message privé. Dossier et
// fichiers sont donc restreints au propriétaire : le dossier temporaire de
// macOS l'est déjà, mais un réglage qui ne dépend que du système est un
// réglage qu'on ne contrôle pas.

import Foundation

enum GestionnaireFichiersTemp {

    /// Dossier de travail, sous le dossier temporaire de l'utilisateur.
    static let dossier: URL = {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("app.avoixhaute.player", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        // Le dossier peut préexister à cette exécution : les attributs ne sont
        // appliqués qu'à la création.
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: url.path
        )
        return url
    }()

    /// Restreint un fichier à son propriétaire.
    ///
    /// `write(to:)` et `say` créent leurs fichiers en 644, lisibles par tout
    /// processus de la machine. Appelé après chaque création.
    static func restreindre(_ fichier: URL) {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fichier.path
        )
    }

    /// Fabrique une URL de fichier audio unique.
    static func nouveauFichierAudio(extension ext: String = "m4a") -> URL {
        dossier.appendingPathComponent("lecture-\(UUID().uuidString).\(ext)")
    }

    /// Fabrique une URL de fichier texte unique.
    ///
    /// Le texte à synthétiser est écrit sur disque puis passé à `say -f`, ce qui
    /// évite à la fois l'échappement shell et la limite `ARG_MAX`.
    static func nouveauFichierTexte() -> URL {
        dossier.appendingPathComponent("texte-\(UUID().uuidString).txt")
    }

    /// Supprime un fichier, à condition qu'il se trouve dans le dossier de
    /// travail. Cette vérification empêche qu'un chemin inattendu conduise à
    /// supprimer un fichier arbitraire.
    @discardableResult
    static func supprimer(_ url: URL) -> Bool {
        let chemin = url.standardizedFileURL.path
        let attendu = dossier.standardizedFileURL.path
        guard chemin.hasPrefix(attendu + "/") else {
            Journal.fichiers.warning("Suppression refusée hors du dossier de travail : \(chemin, privacy: .public)")
            return false
        }
        do {
            try FileManager.default.removeItem(atPath: chemin)
            return true
        } catch CocoaError.fileNoSuchFile {
            return true // déjà absent : le résultat voulu est atteint
        } catch {
            Journal.fichiers.error("Échec de suppression : \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Supprime les fichiers laissés par une exécution précédente.
    ///
    /// Appelé au démarrage : à cet instant, aucune lecture n'est en cours, donc
    /// tout fichier présent est nécessairement orphelin.
    /// Supprime le dossier de travail de l'identifiant précédent.
    ///
    /// Les fichiers audio y sont éphémères : rien n'est à reprendre, seulement
    /// à balayer. Sans cela, le renommage laisserait un dossier que plus rien
    /// ne viendrait vider — c'est ce qu'avait fait le passage de « Lecteur » à
    /// « À Voix Haute ».
    private static func retirerAncienDossier() {
        let ancien = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fr.dimitri.AVoixHaute", isDirectory: true)
        guard FileManager.default.fileExists(atPath: ancien.path) else { return }
        try? FileManager.default.removeItem(at: ancien)
    }

    static func nettoyerOrphelins() {
        retirerAncienDossier()

        let gestionnaire = FileManager.default
        guard let contenu = try? gestionnaire.contentsOfDirectory(
            at: dossier,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var nombre = 0
        var octets = 0
        for url in contenu {
            let taille = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if (try? gestionnaire.removeItem(at: url)) != nil {
                nombre += 1
                octets += taille
            }
        }

        if nombre > 0 {
            Journal.fichiers.info("\(nombre) fichier(s) orphelin(s) supprimé(s), \(octets / 1024) Ko libérés")
        }
    }

    // MARK: - Occupation

    /// Nombre de fichiers présents et octets occupés.
    ///
    /// Le dossier n'est vidé qu'au démarrage : une application qui reste
    /// lancée des semaines peut accumuler les résidus d'une synthèse
    /// interrompue sans jamais les balayer. Les réglages exposent donc la
    /// mesure et le nettoyage.
    static func occupation() -> (fichiers: Int, octets: Int) {
        guard let contenu = try? FileManager.default.contentsOfDirectory(
            at: dossier,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return (0, 0) }

        let octets = contenu.reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return (contenu.count, octets)
    }

    /// Vide le dossier, en épargnant les fichiers passés en paramètre.
    ///
    /// - Parameter enUsage: fichiers d'une lecture en cours, à ne pas
    ///   supprimer sous peine d'interrompre l'écoute.
    /// - Returns: nombre de fichiers supprimés et octets libérés.
    @discardableResult
    static func vider(sauf enUsage: Set<String> = []) -> (fichiers: Int, octets: Int) {
        let gestionnaire = FileManager.default
        guard let contenu = try? gestionnaire.contentsOfDirectory(
            at: dossier,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return (0, 0) }

        var nombre = 0
        var octets = 0
        for url in contenu {
            guard !enUsage.contains(url.standardizedFileURL.path) else { continue }
            let taille = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

            if (try? gestionnaire.removeItem(at: url)) == nil {
                // Un fichier verrouillé par un processus qui n'a pas rendu la
                // main : les permissions sont rétablies avant un second essai.
                try? gestionnaire.setAttributes(
                    [.posixPermissions: 0o600, .immutable: false],
                    ofItemAtPath: url.path
                )
                guard (try? gestionnaire.removeItem(at: url)) != nil else {
                    Journal.fichier("fichiers", "suppression impossible : \(url.lastPathComponent)")
                    continue
                }
            }
            nombre += 1
            octets += taille
        }

        if nombre > 0 {
            Journal.fichier("fichiers", "nettoyage manuel : \(nombre) fichier(s), \(octets / 1024) Ko")
        }
        return (nombre, octets)
    }
}
