// Synthèse par l'API OpenAI.
//
// Seul moteur à faire sortir le texte de la machine. Il est donc désactivé
// tant que l'utilisateur n'a pas enregistré de clé, et l'interface dit
// clairement ce qui part.
//
// Son intérêt tient à une chose que les voix du système ne savent pas faire :
// ses voix sont multilingues. Un texte franglais — « on a retiré
// get-task-allow du build » — est prononcé avec l'accent qui convient à chaque
// passage, là où `say` lit tout en français.

import Foundation

/// Isolé au MainActor : le moteur lit les réglages et les clés, tous deux
/// isolés. L'appel réseau, lui, est `async` et ne bloque pas l'interface.
@MainActor
final class MoteurOpenAI: MoteurSynthese {

    let type: TypeMoteur = .openAI

    /// Modèles proposés. `tts-1` suffit à l'écoute courante ; `tts-1-hd` rend
    /// un son plus riche pour deux fois le prix.
    enum Modele: String, CaseIterable, Codable {
        case standard = "tts-1"
        case hauteDefinition = "tts-1-hd"

        var libelle: String {
            switch self {
            case .standard:        return "tts-1"
            case .hauteDefinition: return "tts-1-hd"
            }
        }
    }

    /// Voix du service, identiques quelle que soit la langue du texte.
    ///
    /// `langue` vaut « mul » — multilingue : le reste de l'application range
    /// les voix par langue, et prétendre que celles-ci sont françaises les
    /// exclurait d'un texte anglais.
    nonisolated static let voix: [(identifiant: String, nom: String)] = [
        ("alloy", "Alloy"), ("echo", "Echo"), ("fable", "Fable"),
        ("onyx", "Onyx"), ("nova", "Nova"), ("shimmer", "Shimmer")
    ]

    private static let urlAPI = URL(string: "https://api.openai.com/v1/audio/speech")!

    /// Limite imposée par l'API : au-delà, la requête est refusée.
    ///
    /// `nonisolated` : constante et découpage sont purs, utilisables depuis
    /// n'importe quel contexte — et testables sans passer par le MainActor.
    nonisolated static let limiteCaracteres = 4096

    func voixDisponibles() -> [VoixDisponible] {
        Self.voix.map {
            VoixDisponible(
                id: $0.identifiant,
                nom: $0.nom,
                langue: "mul",
                qualite: .premium,
                moteur: .openAI
            )
        }
    }

    // MARK: - Synthèse

    func synthetiser(
        texte: String,
        voix: VoixDisponible,
        vitesseBase: Float,
        progression: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard let cle = ClesAPI.active(), let secret = ClesAPI.secret(de: cle) else {
            throw ErreurSynthese.echecEcriture(tr("openai.erreur.cleAbsente"))
        }

        progression(0)
        let debut = Date()

        // L'API plafonne à 4096 caractères par requête : les textes plus longs
        // sont découpés, puis les fragments audio concaténés.
        let fragments = Self.decouper(texte)
        var fichiers: [URL] = []

        do {
            for (index, fragment) in fragments.enumerated() {
                try Task.checkCancellation()
                let fichier = try await appeler(
                    fragment: fragment,
                    voix: voix.id,
                    secret: secret,
                    vitesse: vitesseBase
                )
                fichiers.append(fichier)
                progression(Double(index + 1) / Double(fragments.count))
            }
        } catch {
            fichiers.forEach { GestionnaireFichiersTemp.supprimer($0) }
            JournalAppelsAPI.enregistrer(AppelAPI(
                date: debut, fournisseur: "openai", nomCle: cle.nom,
                modele: Reglages.partage.modeleOpenAI.rawValue, voix: voix.nom,
                caracteres: texte.count, dureeSecondes: Date().timeIntervalSince(debut),
                succes: false, erreur: error.localizedDescription
            ))
            throw error
        }

        JournalAppelsAPI.enregistrer(AppelAPI(
            date: debut, fournisseur: "openai", nomCle: cle.nom,
            modele: Reglages.partage.modeleOpenAI.rawValue, voix: voix.nom,
            caracteres: texte.count, dureeSecondes: Date().timeIntervalSince(debut),
            succes: true, erreur: nil
        ))

        progression(1)
        return fichiers.count == 1 ? fichiers[0] : try Self.concatener(fichiers)
    }

    // MARK: - Appel

    private func appeler(fragment: String, voix: String,
                         secret: String, vitesse: Float) async throws -> URL {
        var requete = URLRequest(url: Self.urlAPI)
        requete.httpMethod = "POST"
        requete.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        requete.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Une synthèse longue dépasse volontiers le délai par défaut.
        requete.timeoutInterval = 120

        let corps: [String: Any] = [
            "model": Reglages.partage.modeleOpenAI.rawValue,
            "input": fragment,
            "voice": voix,
            // `mp3` plutôt que `aac` : en AAC, l'API renvoie un flux ADTS
            // brut, que `AVPlayer` refuse de lire sous une extension .m4a —
            // celle-ci annonce un conteneur MPEG-4. Le lecteur s'ouvrait
            // alors sans un son et sans erreur. Le MP3 porte son propre
            // format, extension et contenu concordent.
            "response_format": "mp3",
            // L'API accepte de 0,25 à 4 ; au-delà la requête est refusée.
            "speed": Double(min(max(vitesse, 0.25), 4.0))
        ]
        requete.httpBody = try JSONSerialization.data(withJSONObject: corps)

        let (donnees, reponse) = try await URLSession.shared.data(for: requete)
        try Task.checkCancellation()

        guard let http = reponse as? HTTPURLResponse else {
            throw ErreurSynthese.processusEchoue(code: -1, message: tr("openai.erreur.reponseInvalide"))
        }
        guard http.statusCode == 200 else {
            throw ErreurSynthese.processusEchoue(
                code: Int32(http.statusCode),
                message: Self.messageErreur(donnees, code: http.statusCode)
            )
        }

        let fichier = GestionnaireFichiersTemp.nouveauFichierAudio(extension: "mp3")
        try donnees.write(to: fichier)
        GestionnaireFichiersTemp.restreindre(fichier)
        return fichier
    }

    /// Extrait le message d'erreur du corps JSON renvoyé par l'API.
    private static func messageErreur(_ donnees: Data, code: Int) -> String {
        if let objet = try? JSONSerialization.jsonObject(with: donnees) as? [String: Any],
           let erreur = objet["error"] as? [String: Any],
           let message = erreur["message"] as? String {
            return message
        }
        switch code {
        case 401: return tr("openai.erreur.cleRefusee")
        case 429: return tr("openai.erreur.quota")
        default:  return tr("openai.erreur.http", code)
        }
    }

    // MARK: - Découpage et assemblage

    /// Découpe en fragments d'au plus 4096 caractères, aux frontières de
    /// phrase quand c'est possible : couper au milieu d'un mot s'entend.
    nonisolated static func decouper(_ texte: String, limite: Int = limiteCaracteres) -> [String] {
        guard texte.count > limite else { return [texte] }

        var fragments: [String] = []
        var courant = ""

        for phrase in texte.split(separator: "\n", omittingEmptySubsequences: false)
                           .flatMap({ Self.phrases(String($0)) }) {
            if courant.count + phrase.count > limite, !courant.isEmpty {
                fragments.append(courant)
                courant = ""
            }
            // Une phrase à elle seule plus longue que la limite : elle est
            // coupée net, faute de meilleure frontière.
            if phrase.count > limite {
                var reste = Substring(phrase)
                while !reste.isEmpty {
                    let bout = reste.prefix(limite)
                    fragments.append(String(bout))
                    reste = reste.dropFirst(bout.count)
                }
            } else {
                courant += phrase
            }
        }

        if !courant.isEmpty { fragments.append(courant) }
        return fragments.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    nonisolated private static func phrases(_ texte: String) -> [String] {
        var resultat: [String] = []
        var courante = ""
        for caractere in texte {
            courante.append(caractere)
            if ".!?".contains(caractere) {
                resultat.append(courante)
                courante = ""
            }
        }
        if !courante.isEmpty { resultat.append(courante) }
        return resultat
    }

    /// Assemble les fragments en un seul fichier.
    ///
    /// Concaténation brute des flux MP3 : chaque trame porte son propre
    /// en-tête, les fragments viennent du même encodeur avec les mêmes
    /// paramètres, et AVPlayer les lit à la suite.
    private static func concatener(_ fichiers: [URL]) throws -> URL {
        let destination = GestionnaireFichiersTemp.nouveauFichierAudio(extension: "mp3")
        var assemble = Data()
        for fichier in fichiers {
            assemble.append(try Data(contentsOf: fichier))
            GestionnaireFichiersTemp.supprimer(fichier)
        }
        try assemble.write(to: destination)
        GestionnaireFichiersTemp.restreindre(destination)
        return destination
    }
}
