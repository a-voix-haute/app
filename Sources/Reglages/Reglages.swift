// Réglages de l'application, adossés à UserDefaults.
//
// Le volume est minuscule et les types sont simples : un fichier de
// configuration n'apporterait rien, tandis que `defaults read fr.dimitri.AVoixHaute`
// permet de tout inspecter depuis le terminal.

import Foundation
import Observation

/// Ce que devient une lecture en cours quand une nouvelle est demandée.
enum ComportementNouvelleLecture: String, CaseIterable, Codable {
    /// La lecture en cours continue ; la nouvelle attend en pause.
    case continuer
    /// La lecture en cours se met en pause et la nouvelle prend la main.
    case mettreEnPause

    var libelle: String {
        switch self {
        case .continuer:     return tr("lecture.continuer")
        case .mettreEnPause: return tr("lecture.mettreEnPause")
        }
    }
}

@Observable
final class Reglages {

    @MainActor static let partage = Reglages()

    private let stockage: UserDefaults

    private init(stockage: UserDefaults = .standard) {
        self.stockage = stockage
        stockage.register(defaults: Self.valeursParDefaut)
    }

    /// Valeurs appliquées tant que l'utilisateur n'a rien choisi.
    private static let valeursParDefaut: [String: Any] = [
        Cle.demarrageAutomatique: true,
        Cle.comportementNouvelleLecture: ComportementNouvelleLecture.continuer.rawValue,
        Cle.limiteLecteurs: 5,
        Cle.vitesseParDefaut: 1.0,
        Cle.pasDecalage: 15,
        Cle.moteurActif: TypeMoteur.say.rawValue,
        Cle.vitesseSyntheseBase: 1.0,
        Cle.detectionLangueAuto: true,
        Cle.langueParDefaut: "fr-FR",
        Cle.nettoyageMarkdown: true,
        Cle.restaurerPressePapiers: true,
        Cle.raccourciGlobalActif: false
    ]

    private enum Cle {
        static let demarrageAutomatique = "demarrageAutomatique"
        static let comportementNouvelleLecture = "comportementNouvelleLecture"
        static let limiteLecteurs = "limiteLecteurs"
        static let vitesseParDefaut = "vitesseParDefaut"
        static let pasDecalage = "pasDecalage"
        static let moteurActif = "moteurActif"
        static let voixSay = "voixSay"
        static let voixAVSpeech = "voixAVSpeech"
        static let vitesseSyntheseBase = "vitesseSyntheseBase"
        static let detectionLangueAuto = "detectionLangueAuto"
        static let langueParDefaut = "langueParDefaut"
        static let nettoyageMarkdown = "nettoyageMarkdown"
        static let restaurerPressePapiers = "restaurerPressePapiers"
        static let raccourciGlobalActif = "raccourciGlobalActif"
        static let raccourciCodeTouche = "raccourciCodeTouche"
        static let raccourciModificateurs = "raccourciModificateurs"
        static let assistantVu = "assistantVu"
    }

    // MARK: - Lecture

    /// Démarrer automatiquement quand aucune autre lecture n'est en cours.
    var demarrageAutomatique: Bool {
        get { stockage.bool(forKey: Cle.demarrageAutomatique) }
        set { stockage.set(newValue, forKey: Cle.demarrageAutomatique) }
    }

    var comportementNouvelleLecture: ComportementNouvelleLecture {
        get {
            let brut = stockage.string(forKey: Cle.comportementNouvelleLecture) ?? ""
            return ComportementNouvelleLecture(rawValue: brut) ?? .continuer
        }
        set { stockage.set(newValue.rawValue, forKey: Cle.comportementNouvelleLecture) }
    }

    /// Nombre maximal de lecteurs ouverts simultanément, entre 1 et 10.
    var limiteLecteurs: Int {
        get { min(max(stockage.integer(forKey: Cle.limiteLecteurs), 1), 10) }
        set { stockage.set(min(max(newValue, 1), 10), forKey: Cle.limiteLecteurs) }
    }

    var vitesseParDefaut: Float {
        get { stockage.float(forKey: Cle.vitesseParDefaut) }
        set { stockage.set(newValue, forKey: Cle.vitesseParDefaut) }
    }

    /// Amplitude des boutons d'avance et de recul, en secondes.
    var pasDecalage: Int {
        get { max(stockage.integer(forKey: Cle.pasDecalage), 1) }
        set { stockage.set(max(newValue, 1), forKey: Cle.pasDecalage) }
    }

    // MARK: - Synthèse

    var moteurActif: TypeMoteur {
        get {
            let brut = stockage.string(forKey: Cle.moteurActif) ?? ""
            return TypeMoteur(rawValue: brut) ?? .say
        }
        set { stockage.set(newValue.rawValue, forKey: Cle.moteurActif) }
    }

    /// Identifiant de la voix retenue pour un moteur donné.
    ///
    /// Les catalogues sont séparés : `say` n'accède pas aux voix Premium, une
    /// voix choisie pour l'un n'a pas de sens pour l'autre.
    func voix(pour moteur: TypeMoteur) -> String? {
        stockage.string(forKey: moteur == .say ? Cle.voixSay : Cle.voixAVSpeech)
    }

    func definirVoix(_ identifiant: String?, pour moteur: TypeMoteur) {
        stockage.set(identifiant, forKey: moteur == .say ? Cle.voixSay : Cle.voixAVSpeech)
    }

    /// Débit de la synthèse, distinct de la vitesse de lecture.
    var vitesseSyntheseBase: Float {
        get { stockage.float(forKey: Cle.vitesseSyntheseBase) }
        set { stockage.set(newValue, forKey: Cle.vitesseSyntheseBase) }
    }

    var detectionLangueAuto: Bool {
        get { stockage.bool(forKey: Cle.detectionLangueAuto) }
        set { stockage.set(newValue, forKey: Cle.detectionLangueAuto) }
    }

    var langueParDefaut: String {
        get { stockage.string(forKey: Cle.langueParDefaut) ?? "fr-FR" }
        set { stockage.set(newValue, forKey: Cle.langueParDefaut) }
    }

    // MARK: - Texte

    var nettoyageMarkdown: Bool {
        get { stockage.bool(forKey: Cle.nettoyageMarkdown) }
        set { stockage.set(newValue, forKey: Cle.nettoyageMarkdown) }
    }

    // MARK: - Entrées

    var restaurerPressePapiers: Bool {
        get { stockage.bool(forKey: Cle.restaurerPressePapiers) }
        set { stockage.set(newValue, forKey: Cle.restaurerPressePapiers) }
    }

    var raccourciGlobalActif: Bool {
        get { stockage.bool(forKey: Cle.raccourciGlobalActif) }
        set { stockage.set(newValue, forKey: Cle.raccourciGlobalActif) }
    }

    // MARK: - Premier lancement

    /// L'assistant de configuration a-t-il déjà été parcouru ?
    var assistantVu: Bool {
        get { stockage.bool(forKey: Cle.assistantVu) }
        set { stockage.set(newValue, forKey: Cle.assistantVu) }
    }

    /// Code de touche du raccourci global. 37 correspond à « L ».
    var raccourciCodeTouche: Int {
        get {
            let valeur = stockage.integer(forKey: Cle.raccourciCodeTouche)
            return valeur == 0 ? 37 : valeur
        }
        set { stockage.set(newValue, forKey: Cle.raccourciCodeTouche) }
    }

    /// Modificateurs du raccourci global, au format Carbon.
    var raccourciModificateurs: Int {
        get {
            let valeur = stockage.integer(forKey: Cle.raccourciModificateurs)
            // Par défaut Contrôle + Option, peu susceptible d'entrer en conflit.
            return valeur == 0 ? 0x1000 | 0x0800 : valeur
        }
        set { stockage.set(newValue, forKey: Cle.raccourciModificateurs) }
    }
}
