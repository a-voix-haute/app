// Gestion des fichiers audio temporaires.
//
// Chaque lecture produit un fichier .m4a dans un dossier dédié. Ces fichiers
// sont supprimés à la fermeture du lecteur correspondant ; ceux qu'un arrêt
// brutal aurait laissés derrière sont balayés au démarrage de l'application.

import Foundation

enum GestionnaireFichiersTemp {

    /// Dossier de travail, sous le dossier temporaire de l'utilisateur.
    static let dossier: URL = {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fr.dimitri.AVoixHaute", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

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
    static func nettoyerOrphelins() {
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
}
