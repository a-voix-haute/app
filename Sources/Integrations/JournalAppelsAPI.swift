// Journal des appels aux moteurs distants.
//
// L'application ne calcule aucun coût : les tarifs changent, et un montant
// faux inspire moins confiance qu'un montant absent. Elle enregistre ce
// qu'elle sait exactement — combien de caractères sont partis, quand, avec
// quelle clé — et laisse la facturation à la console du fournisseur.
//
// La clé est nommée dans chaque ligne : c'est ce qui permet de rapprocher une
// consommation observée là-bas d'un usage précis ici.
//
// Le texte envoyé n'est jamais écrit. Un journal qui conserverait les
// sélections de l'utilisateur annulerait la protection des fichiers
// temporaires.

import AppKit
import Foundation

struct AppelAPI: Codable {
    let date: Date
    let fournisseur: String
    let nomCle: String
    let modele: String
    let voix: String
    let caracteres: Int
    let dureeSecondes: Double
    let succes: Bool
    let erreur: String?
}

enum JournalAppelsAPI {

    /// Fichier distinct du journal principal : il se consulte pour une autre
    /// raison, et se conserve plus longtemps.
    static var chemin: String {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library")
        return base
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("AVoixHaute-api.log")
            .path
    }

    private static let file = DispatchQueue(label: "app.avoixhaute.player.journal-api")

    private static let horodatage: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func enregistrer(_ appel: AppelAPI) {
        let ligne = [
            horodatage.string(from: appel.date),
            appel.fournisseur,
            appel.nomCle,
            appel.modele,
            appel.voix,
            "\(appel.caracteres) car.",
            String(format: "%.1f s", appel.dureeSecondes),
            appel.succes ? "ok" : "échec : \(appel.erreur ?? "inconnu")"
        ].joined(separator: " | ") + "\n"

        file.async {
            guard let donnees = ligne.data(using: .utf8) else { return }
            let url = URL(fileURLWithPath: chemin)

            if let poignee = try? FileHandle(forWritingTo: url) {
                defer { try? poignee.close() }
                _ = try? poignee.seekToEnd()
                try? poignee.write(contentsOf: donnees)
            } else {
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? donnees.write(to: url)
                // Le journal nomme les clés employées : il se restreint à son
                // propriétaire, comme les fichiers temporaires.
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: url.path
                )
            }
        }
    }

    // MARK: - Lecture

    /// Nombre d'appels et de caractères depuis une date, par clé.
    ///
    /// Relit le fichier à chaque consultation plutôt que de tenir un compteur :
    /// le volume est dérisoire, et un compteur séparé finirait par diverger du
    /// journal qu'il prétend résumer.
    static func resume(depuis debut: Date) -> [(cle: String, appels: Int, caracteres: Int)] {
        guard let contenu = try? String(contentsOfFile: chemin, encoding: .utf8) else { return [] }

        var parCle: [String: (appels: Int, caracteres: Int)] = [:]
        for ligne in contenu.split(separator: "\n") {
            let champs = ligne.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard champs.count >= 6,
                  let date = horodatage.date(from: champs[0]), date >= debut,
                  champs.last?.hasPrefix("ok") == true
            else { continue }

            let nombre = Int(champs[5].replacingOccurrences(of: " car.", with: "")) ?? 0
            let nom = champs[2]
            let courant = parCle[nom] ?? (0, 0)
            parCle[nom] = (courant.appels + 1, courant.caracteres + nombre)
        }

        return parCle
            .map { (cle: $0.key, appels: $0.value.appels, caracteres: $0.value.caracteres) }
            .sorted { $0.caracteres > $1.caracteres }
    }

    /// Début du mois courant, pour le résumé affiché dans les réglages.
    static var debutDuMois: Date {
        let calendrier = Calendar.current
        let composants = calendrier.dateComponents([.year, .month], from: Date())
        return calendrier.date(from: composants) ?? Date.distantPast
    }

    static func ouvrirDansFinder() {
        NSWorkspace.shared.selectFile(chemin, inFileViewerRootedAtPath: "")
    }
}