// Détection de la langue d'un texte, pour choisir une voix adaptée.
//
// L'usage principal est francophone, mais les documents techniques mêlent
// souvent de l'anglais. Faire lire un paragraphe anglais par une voix française
// donne un résultat incompréhensible, d'où cette détection — que l'utilisateur
// peut désactiver s'il préfère une voix fixe.

import Foundation
import NaturalLanguage

enum DetecteurLangue {

    /// En deçà de ce niveau de confiance, la détection n'est pas suivie.
    private static let confianceMinimale = 0.7

    /// Les textes très courts ne donnent pas assez de matière pour décider.
    private static let longueurMinimale = 20

    /// Analyser le début du texte suffit et garde l'opération instantanée.
    private static let longueurAnalysee = 1000

    /// Détecte la langue dominante, ou renvoie `parDefaut` en cas de doute.
    ///
    /// - Returns: un code de type « fr-FR », prêt à être comparé aux voix.
    static func detecter(_ texte: String, parDefaut: String) -> String {
        let echantillon = String(texte.prefix(longueurAnalysee))
        guard echantillon.count >= longueurMinimale else { return parDefaut }

        let reconnaisseur = NLLanguageRecognizer()
        reconnaisseur.processString(echantillon)

        guard let langue = reconnaisseur.dominantLanguage else { return parDefaut }

        let hypotheses = reconnaisseur.languageHypotheses(withMaximum: 1)
        let confiance = hypotheses[langue] ?? 0
        guard confiance >= confianceMinimale else {
            Journal.synthese.debug("Langue incertaine (\(confiance, format: .fixed(precision: 2))), repli sur \(parDefaut, privacy: .public)")
            return parDefaut
        }

        return codeComplet(pour: langue, parDefaut: parDefaut)
    }

    /// Associe une langue à une variante régionale plausible.
    ///
    /// NLLanguage ne fournit qu'un code à deux lettres ; les voix système sont
    /// désignées par un code complet.
    private static func codeComplet(pour langue: NLLanguage, parDefaut: String) -> String {
        switch langue {
        case .french:     return "fr-FR"
        case .english:    return "en-US"
        case .spanish:    return "es-ES"
        case .german:     return "de-DE"
        case .italian:    return "it-IT"
        case .portuguese: return "pt-PT"
        case .dutch:      return "nl-NL"
        case .russian:    return "ru-RU"
        case .japanese:   return "ja-JP"
        case .simplifiedChinese, .traditionalChinese: return "zh-CN"
        case .korean:     return "ko-KR"
        case .arabic:     return "ar-SA"
        default:
            // Langue reconnue mais sans variante connue : on garde le code brut
            // s'il ressemble à un code langue, sinon le réglage par défaut.
            let brut = langue.rawValue
            return brut.count == 2 ? brut : parDefaut
        }
    }
}
