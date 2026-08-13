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

    /// Processus `say` en cours, protégé par un verrou.
    ///
    /// L'annulation coopérative de Swift ne suffit pas ici : le lien
    /// d'annulation ne traverse pas la frontière d'acteur entre le gestionnaire
    /// et ce moteur, et `onCancel` n'est alors jamais exécuté. Garder une prise
    /// directe sur le processus permet de le tuer sans dépendre de ce
    /// mécanisme.
    private let verrou = NSLock()
    private var processusEnCours: [Int32: Process] = [:]

    /// Tue tous les processus de synthèse en cours.
    ///
    /// - Returns: le nombre de processus effectivement arrêtés.
    @discardableResult
    func interrompreTout() -> Int {
        verrou.lock()
        let processus = Array(processusEnCours.values)
        processusEnCours.removeAll()
        verrou.unlock()

        var arretes = 0
        for unProcessus in processus where unProcessus.isRunning {
            let pid = unProcessus.processIdentifier
            unProcessus.terminate()

            // `say` en train d'encoder son fichier de sortie ne traite pas le
            // SIGTERM avant d'avoir fini : sans SIGKILL, il produirait un
            // fichier audio complet dont plus personne ne veut.
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
            }
            arretes += 1
        }

        if arretes > 0 {
            Journal.fichier("synthese", "\(arretes) processus say interrompu(s)")
        }
        return arretes
    }

    private func enregistrer(_ processus: Process) {
        verrou.lock()
        processusEnCours[processus.processIdentifier] = processus
        verrou.unlock()
    }

    private func oublier(_ processus: Process) {
        verrou.lock()
        processusEnCours[processus.processIdentifier] = nil
        verrou.unlock()
    }

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
                qualite: Self.qualiteDapresLeNom(nom),
                moteur: .say
            ))
        }

        return voix.sorted { ($0.langue, $0.nom) < ($1.langue, $1.nom) }
    }

    /// Déduit la qualité d'une voix de son nom.
    ///
    /// `say` n'expose aucun champ de qualité, mais nomme les variantes
    /// téléchargées « Thomas (Enhanced) » ou « Audrey (Premium) ». C'est la
    /// seule information disponible, et elle suffit à trier le catalogue.
    private static func qualiteDapresLeNom(_ nom: String) -> QualiteVoix {
        let minuscule = nom.lowercased()
        if minuscule.contains("(premium)") { return .premium }
        if minuscule.contains("(enhanced)") || minuscule.contains("(améliorée)") { return .amelioree }
        return .compacte
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
            // Interrompu, `say` laisse un fichier tronqué : il part avec lui.
            GestionnaireFichiersTemp.supprimer(fichierAudio)
            throw error
        }

        // L'annulation peut survenir entre la fin du processus et le retour.
        if Task.isCancelled {
            GestionnaireFichiersTemp.supprimer(fichierAudio)
            throw ErreurSynthese.annulee
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

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (suite: CheckedContinuation<Void, Error>) in
                processus.terminationHandler = { [weak self] processusTermine in
                    self?.oublier(processusTermine)

                    if processusTermine.terminationStatus == 0 {
                        suite.resume()
                    } else if processusTermine.terminationReason == .uncaughtSignal {
                        // Terminé par un signal : c'est une interruption
                        // volontaire, pas une erreur de synthèse.
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
                    enregistrer(processus)
                } catch {
                    suite.resume(throwing: ErreurSynthese.processusEchoue(
                        code: -1,
                        message: error.localizedDescription
                    ))
                }
            }
        } onCancel: {
            // Chemin secondaire : n'agit que si l'annulation traverse
            // effectivement jusqu'ici. `interrompreTout()` reste le moyen sûr.
            guard processus.isRunning else { return }
            let pid = processus.processIdentifier
            processus.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
            }
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
