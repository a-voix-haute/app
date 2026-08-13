// Journalisation centralisée.
//
// Les messages sont visibles dans Console.app en filtrant sur le sous-système,
// ou en ligne de commande :
//
//     log stream --predicate 'subsystem == "fr.dimitri.AVoixHaute"' --level debug

import Foundation
import os

enum Journal {
    private static let sousSysteme = "fr.dimitri.AVoixHaute"

    static let app = Logger(subsystem: sousSysteme, category: "app")
    static let synthese = Logger(subsystem: sousSysteme, category: "synthese")
    static let lecture = Logger(subsystem: sousSysteme, category: "lecture")
    static let entree = Logger(subsystem: sousSysteme, category: "entree")
    static let fichiers = Logger(subsystem: sousSysteme, category: "fichiers")

    // MARK: - Journal de fichier
    //
    // `os.Logger` écrit dans un stockage dont la rétention dépend du niveau et
    // de la configuration du système : les messages de niveau debug et info y
    // sont souvent absents à la relecture. Ce doublon dans un fichier garantit
    // qu'une trace reste consultable pendant le développement.
    //
    //     tail -f ~/Library/Logs/AVoixHaute.log

    /// Emplacement du journal de fichier.
    static let cheminFichier: String = {
        let dossier = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        return dossier.appendingPathComponent("AVoixHaute.log").path
    }()

    private static let fileEcriture = DispatchQueue(label: "fr.dimitri.AVoixHaute.journal")

    private static let horodateur: DateFormatter = {
        let formateur = DateFormatter()
        formateur.dateFormat = "HH:mm:ss.SSS"
        return formateur
    }()

    /// Écrit une ligne dans le journal de fichier.
    static func fichier(_ categorie: String, _ message: String) {
        let ligne = "\(horodateur.string(from: Date())) [\(categorie)] \(message)\n"
        fileEcriture.async {
            guard let donnees = ligne.data(using: .utf8) else { return }
            if let poignee = FileHandle(forWritingAtPath: cheminFichier) {
                defer { try? poignee.close() }
                poignee.seekToEndOfFile()
                poignee.write(donnees)
            } else {
                try? donnees.write(to: URL(fileURLWithPath: cheminFichier))
            }
        }
    }

    /// Repart d'un journal vide au démarrage, pour que chaque session soit
    /// lisible sans remonter l'historique.
    static func reinitialiserFichier() {
        try? FileManager.default.removeItem(atPath: cheminFichier)
        fichier("app", "— nouvelle session —")
    }
}
