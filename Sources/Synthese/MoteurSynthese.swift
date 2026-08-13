// Abstraction des moteurs de synthèse vocale.
//
// Deux implémentations coexistent :
//
//  - MoteurSay        : la commande `say`, simple et rapide, limitée aux voix
//                       compactes du système ;
//  - MoteurAVSpeech   : AVSpeechSynthesizer, seul à donner accès aux voix
//                       Premium une fois celles-ci téléchargées.
//
// Le reste de l'application ignore lequel est actif : elle demande un fichier
// audio et reçoit son URL.

import Foundation

/// Qualité d'une voix, par ordre croissant.
///
/// Les voix Siri (`com.apple.siri.*`) sont volontairement absentes : macOS les
/// réserve à ses propres services et les rend inaccessibles aux applications
/// tierces, quelle que soit leur signature.
enum QualiteVoix: Int, Comparable, Codable {
    case compacte = 0
    case amelioree = 1
    case premium = 2

    static func < (gauche: QualiteVoix, droite: QualiteVoix) -> Bool {
        gauche.rawValue < droite.rawValue
    }

    var libelle: String {
        switch self {
        case .compacte:  return tr("voix.qualite.compacte")
        case .amelioree: return tr("voix.qualite.amelioree")
        case .premium:   return tr("voix.qualite.premium")
        }
    }
}

enum TypeMoteur: String, Codable, CaseIterable {
    case say
    case avSpeech

    var libelle: String {
        switch self {
        case .say:      return "Système (say)"
        case .avSpeech: return "AVSpeech (voix Premium)"
        }
    }
}

/// Une voix utilisable par un moteur donné.
///
/// Les catalogues sont distincts par moteur : `say` désigne ses voix par un nom
/// (« Thomas »), AVSpeechSynthesizer par un identifiant inversé.
struct VoixDisponible: Identifiable, Hashable, Codable {
    let id: String
    let nom: String
    let langue: String
    let qualite: QualiteVoix
    let moteur: TypeMoteur

    /// Code langue seul, par exemple « fr » pour « fr-FR ».
    var codeLangue: String {
        String(langue.prefix(2)).lowercased()
    }

    /// Nom débarrassé des mentions techniques.
    ///
    /// `say` nomme ses variantes « Thomas (Enhanced) » ou « Grandma (Français
    /// (France)) » ; seule la première partie intéresse l'utilisateur, la
    /// qualité et la langue étant affichées séparément.
    var nomAffiche: String {
        guard let parenthese = nom.firstIndex(of: "(") else { return nom }
        let court = nom[..<parenthese].trimmingCharacters(in: .whitespaces)
        return court.isEmpty ? nom : court
    }

    var descriptionComplete: String {
        qualite == .compacte ? nomAffiche : "\(nomAffiche) (\(qualite.libelle))"
    }
}

enum ErreurSynthese: LocalizedError {
    case texteVide
    case voixIntrouvable(String)
    case echecEcriture(String)
    case processusEchoue(code: Int32, message: String)
    case annulee

    var errorDescription: String? {
        switch self {
        case .texteVide:
            return tr("erreur.texteVide")
        case .voixIntrouvable(let id):
            return tr("erreur.voixIntrouvable", id)
        case .echecEcriture(let détail):
            return tr("erreur.echecEcriture", détail)
        case .processusEchoue(let code, let message):
            return message.isEmpty
                ? "La synthèse a échoué (code \(code))."
                : "La synthèse a échoué : \(message)"
        case .annulee:
            return tr("erreur.annulee")
        }
    }
}

/// Contrat commun aux moteurs de synthèse.
protocol MoteurSynthese: AnyObject {
    var type: TypeMoteur { get }

    /// Voix utilisables par ce moteur, telles qu'installées sur la machine.
    func voixDisponibles() -> [VoixDisponible]

    /// Synthétise `texte` vers un fichier audio et renvoie son URL.
    ///
    /// L'implémentation doit respecter l'annulation coopérative : la tâche
    /// appelante peut être annulée à tout moment, et le fichier partiel doit
    /// alors être supprimé.
    ///
    /// - Parameter progression: appelée avec une valeur de 0 à 1. Les moteurs
    ///   incapables d'estimer leur avancement ne rapportent que 0 puis 1.
    func synthetiser(
        texte: String,
        voix: VoixDisponible,
        vitesseBase: Float,
        progression: @escaping @Sendable (Double) -> Void
    ) async throws -> URL
}
