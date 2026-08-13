// Moteur de synthèse fondé sur la commande `say`.
//
// Deux choix méritent explication :
//
//  - le texte est écrit dans un fichier et passé par `-f`, jamais en argument.
//    Cela supprime d'un coup la question de l'échappement et la limite ARG_MAX,
//    qu'un document un peu long dépasserait ;
//
//  - `--data-format=aac` produit directement le .m4a. Passer par un AIFF
//    intermédiaire coûterait environ 140 Mo pour un texte de 60 Ko, pour un
//    résultat identique après conversion.

import Foundation

final class MoteurSay: MoteurSynthese {

    let type: TypeMoteur = .say

    private static let cheminSay = "/usr/bin/say"

    // MARK: - Catalogue

    /// Interroge `say -v '?'` pour connaître les voix installées.
    ///
    /// Chaque ligne a la forme :
    ///
    ///     Thomas              fr_FR    # Bonjour, je m'appelle Thomas.
    func voixDisponibles() -> [VoixDisponible] {
        guard let sortie = executerSay(arguments: ["-v", "?"]) else { return [] }

        var voix: [VoixDisponible] = []
        for ligne in sortie.split(separator: "\n") {
            guard let separateur = ligne.range(of: "#") else { continue }
            let avant = ligne[..<separateur.lowerBound]
                .trimmingCharacters(in: .whitespaces)

            // Le code langue est le dernier champ avant le commentaire.
            let champs = avant.split(separator: " ", omittingEmptySubsequences: true)
            guard champs.count >= 2, let langueBrute = champs.last else { continue }

            let langue = String(langueBrute).replacingOccurrences(of: "_", with: "-")
            // Le nom peut contenir des espaces : « Grandma (Français (France)) ».
            let nom = champs.dropLast()
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            guard !nom.isEmpty else { continue }

            voix.append(VoixDisponible(
                id: nom,
                nom: nom,
                langue: langue,
                // `say` n'expose aucune information de qualité, et n'accède
                // qu'aux voix compactes.
                qualite: .compacte,
                moteur: .say
            ))
        }

        return voix.sorted { ($0.langue, $0.nom) < ($1.langue, $1.nom) }
    }

    // MARK: - Synthèse

    func synthetiser(
        texte: String,
        voix: VoixDisponible,
        vitesseBase: Float,
        progression: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {

        let contenu = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !contenu.isEmpty else { throw ErreurSynthese.texteVide }

        let fichierTexte = GestionnaireFichiersTemp.nouveauFichierTexte()
        let fichierAudio = GestionnaireFichiersTemp.nouveauFichierAudio()

        do {
            try contenu.write(to: fichierTexte, atomically: true, encoding: .utf8)
        } catch {
            throw ErreurSynthese.echecEcriture(error.localizedDescription)
        }
        defer { GestionnaireFichiersTemp.supprimer(fichierTexte) }

        progression(0)

        var arguments = [
            "-v", voix.nom,
            "-f", fichierTexte.path,
            "--data-format=aac",
            "-o", fichierAudio.path
        ]

        // `say -r` s'exprime en mots par minute ; la vitesse de base est un
        // multiplicateur autour de 175, débit par défaut du système.
        if vitesseBase != 1.0 {
            let motsParMinute = Int((175.0 * Double(vitesseBase)).rounded())
            arguments.insert(contentsOf: ["-r", String(motsParMinute)], at: 0)
        }

        Journal.synthese.info("say : \(contenu.count) caractères, voix \(voix.nom, privacy: .public)")

        do {
            try await executerProcessus(arguments: arguments)
        } catch {
            GestionnaireFichiersTemp.supprimer(fichierAudio)
            throw error
        }

        guard FileManager.default.fileExists(atPath: fichierAudio.path) else {
            throw ErreurSynthese.echecEcriture("aucun fichier produit")
        }

        progression(1)
        return fichierAudio
    }

    // MARK: - Exécution

    /// Lance `say` et attend sa fin, en respectant l'annulation.
    private func executerProcessus(arguments: [String]) async throws {
        let processus = Process()
        processus.executableURL = URL(fileURLWithPath: Self.cheminSay)
        processus.arguments = arguments

        let sortieErreur = Pipe()
        processus.standardError = sortieErreur
        processus.standardOutput = Pipe()

        // withTaskCancellationHandler permet de tuer le processus si la tâche
        // appelante est annulée — fermeture du lecteur, nouvelle lecture…
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (suite: CheckedContinuation<Void, Error>) in
                processus.terminationHandler = { processusTermine in
                    if processusTermine.terminationStatus == 0 {
                        suite.resume()
                    } else if processusTermine.terminationReason == .uncaughtSignal {
                        suite.resume(throwing: ErreurSynthese.annulee)
                    } else {
                        let donnees = sortieErreur.fileHandleForReading.readDataToEndOfFile()
                        let message = String(data: donnees, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        suite.resume(throwing: ErreurSynthese.processusEchoue(
                            code: processusTermine.terminationStatus,
                            message: message
                        ))
                    }
                }

                do {
                    try processus.run()
                } catch {
                    suite.resume(throwing: ErreurSynthese.processusEchoue(
                        code: -1,
                        message: error.localizedDescription
                    ))
                }
            }
        } onCancel: {
            if processus.isRunning { processus.terminate() }
        }
    }

    /// Exécution synchrone brève, réservée à l'interrogation du catalogue.
    private func executerSay(arguments: [String]) -> String? {
        let processus = Process()
        processus.executableURL = URL(fileURLWithPath: Self.cheminSay)
        processus.arguments = arguments

        let tube = Pipe()
        processus.standardOutput = tube
        processus.standardError = Pipe()

        do {
            try processus.run()
        } catch {
            Journal.synthese.error("say injoignable : \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let donnees = tube.fileHandleForReading.readDataToEndOfFile()
        processus.waitUntilExit()
        return String(data: donnees, encoding: .utf8)
    }
}
