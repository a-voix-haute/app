// Réglages de l'application, adossés à UserDefaults.
//
// Le volume est minuscule et les types sont simples : un fichier de
// configuration n'apporterait rien, tandis que `defaults read app.avoixhaute.player`
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

    /// Compteur incrémenté à chaque écriture, seul point observable de la
    /// classe.
    ///
    /// `@Observable` réécrit les propriétés **stockées** pour y insérer ses
    /// appels à `access` et `withMutation`. Les réglages, eux, sont des
    /// propriétés calculées adossées à `UserDefaults` : le macro n'a rien à
    /// instrumenter, et SwiftUI n'est jamais prévenu d'un changement. Une vue
    /// dépourvue d'autre état ne se redessine donc pas — c'est ce qui laissait
    /// la case du raccourci vide dans l'assistant de bienvenue, alors que le
    /// réglage était bien écrit.
    ///
    /// Chaque accesseur lit ce compteur et chaque mutateur l'incrémente, ce qui
    /// rétablit la chaîne d'observation sans changer le stockage.
    private var revision = 0

    /// À appeler au début de chaque `get`.
    private func signalerLecture() {
        _ = revision
    }

    /// À appeler à la fin de chaque `set`.
    private func signalerEcriture() {
        revision &+= 1
    }

    private init(stockage: UserDefaults = .standard) {
        self.stockage = stockage
        // La reprise précède l'enregistrement des valeurs par défaut : après
        // `register(defaults:)`, `object(forKey:)` répond pour toute clé
        // pourvue d'un défaut, et l'on ne saurait plus distinguer un réglage
        // choisi par l'utilisateur d'une valeur d'usine.
        reprendreAncienDomaine()
        stockage.register(defaults: Self.valeursParDefaut)
    }

    /// Identifiant employé jusqu'à la version 1.1.2.
    private static let domaineHerite = "fr.dimitri.AVoixHaute"

    /// Reprend les réglages de l'identifiant précédent, une seule fois.
    ///
    /// `UserDefaults` est indexé sur l'identifiant du bundle : en changer rend
    /// l'ancien domaine invisible sans pour autant le supprimer. Il reste donc
    /// lisible nommément, le temps de cette reprise — sans quoi l'utilisateur
    /// retrouverait une application aux réglages d'usine.
    ///
    /// L'ancien domaine n'est pas effacé ensuite : un retour à une version
    /// antérieure doit y retrouver ses réglages. La désinstallation, elle,
    /// purge les deux.
    private func reprendreAncienDomaine() {
        guard !stockage.bool(forKey: Cle.repriseAncienDomaine) else { return }
        defer { stockage.set(true, forKey: Cle.repriseAncienDomaine) }

        guard let ancien = UserDefaults(suiteName: Self.domaineHerite) else { return }

        // `object(forKey:)` et non les accesseurs typés : seules les clés
        // réellement écrites par l'utilisateur sont reprises. Les valeurs par
        // défaut, elles, viennent d'être enregistrées et ne doivent pas être
        // confondues avec un choix.
        for (cle, valeur) in ancien.dictionaryRepresentation() where Self.clesConnues.contains(cle) {
            guard stockage.object(forKey: cle) == nil else { continue }
            stockage.set(valeur, forKey: cle)
        }
    }

    /// Clés susceptibles d'être reprises de l'ancien domaine.
    ///
    /// `dictionaryRepresentation()` renvoie aussi les réglages globaux de
    /// macOS — langues, formats, accessibilité. Les recopier polluerait le
    /// domaine de l'application ; la liste blanche l'évite.
    private static let clesConnues: Set<String> = [
        Cle.demarrageAutomatique, Cle.comportementNouvelleLecture,
        Cle.limiteLecteurs, Cle.vitesseParDefaut, Cle.pasDecalage,
        Cle.fermetureAutomatique, Cle.delaiFermetureAutomatique,
        Cle.moteurActif, Cle.voixSay, Cle.voixAVSpeech,
        Cle.vitesseSyntheseBase, Cle.detectionLangueAuto, Cle.langueParDefaut,
        Cle.nettoyageMarkdown, Cle.restaurerPressePapiers,
        Cle.raccourciGlobalActif, Cle.raccourciCodeTouche,
        Cle.raccourciModificateurs, Cle.assistantVu, Cle.miseAJourAutomatique
    ]

    /// Valeurs appliquées tant que l'utilisateur n'a rien choisi.
    private static let valeursParDefaut: [String: Any] = [
        Cle.demarrageAutomatique: true,
        Cle.comportementNouvelleLecture: ComportementNouvelleLecture.continuer.rawValue,
        Cle.limiteLecteurs: 5,
        Cle.vitesseParDefaut: 1.0,
        Cle.pasDecalage: 15,
        Cle.fermetureAutomatique: false,
        Cle.delaiFermetureAutomatique: 30,
        Cle.moteurActif: TypeMoteur.say.rawValue,
        Cle.vitesseSyntheseBase: 1.0,
        Cle.detectionLangueAuto: true,
        Cle.langueParDefaut: "fr-FR",
        Cle.nettoyageMarkdown: true,
        Cle.restaurerPressePapiers: true,
        Cle.raccourciGlobalActif: false,
        Cle.miseAJourAutomatique: true
    ]

    private enum Cle {
        static let demarrageAutomatique = "demarrageAutomatique"
        static let comportementNouvelleLecture = "comportementNouvelleLecture"
        static let limiteLecteurs = "limiteLecteurs"
        static let vitesseParDefaut = "vitesseParDefaut"
        static let pasDecalage = "pasDecalage"
        static let fermetureAutomatique = "fermetureAutomatique"
        static let delaiFermetureAutomatique = "delaiFermetureAutomatique"
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
        static let miseAJourAutomatique = "miseAJourAutomatique"
        static let repriseAncienDomaine = "repriseAncienDomaineFaite"
    }

    // MARK: - Lecture

    /// Démarrer automatiquement quand aucune autre lecture n'est en cours.
    var demarrageAutomatique: Bool {
        get { signalerLecture(); return stockage.bool(forKey: Cle.demarrageAutomatique) }
        set { stockage.set(newValue, forKey: Cle.demarrageAutomatique); signalerEcriture() }
    }

    var comportementNouvelleLecture: ComportementNouvelleLecture {
        get {
            signalerLecture()
            let brut = stockage.string(forKey: Cle.comportementNouvelleLecture) ?? ""
            return ComportementNouvelleLecture(rawValue: brut) ?? .continuer
        }
        set { stockage.set(newValue.rawValue, forKey: Cle.comportementNouvelleLecture); signalerEcriture() }
    }

    /// Nombre maximal de lecteurs ouverts simultanément, entre 1 et 10.
    var limiteLecteurs: Int {
        get { signalerLecture(); return min(max(stockage.integer(forKey: Cle.limiteLecteurs), 1), 10) }
        set { stockage.set(min(max(newValue, 1), 10), forKey: Cle.limiteLecteurs); signalerEcriture() }
    }

    var vitesseParDefaut: Float {
        get { signalerLecture(); return stockage.float(forKey: Cle.vitesseParDefaut) }
        set { stockage.set(newValue, forKey: Cle.vitesseParDefaut); signalerEcriture() }
    }

    /// Amplitude des boutons d'avance et de recul, en secondes.
    var pasDecalage: Int {
        get { signalerLecture(); return max(stockage.integer(forKey: Cle.pasDecalage), 1) }
        set { stockage.set(max(newValue, 1), forKey: Cle.pasDecalage); signalerEcriture() }
    }

    /// Fermer le lecteur seul, une fois sa lecture terminée.
    ///
    /// Désactivé par défaut : une fenêtre qui disparaît sans qu'on l'ait
    /// demandé se remarque, et les installations déjà en place ne doivent pas
    /// changer de comportement à la mise à jour.
    var fermetureAutomatique: Bool {
        get { signalerLecture(); return stockage.bool(forKey: Cle.fermetureAutomatique) }
        set { stockage.set(newValue, forKey: Cle.fermetureAutomatique); signalerEcriture() }
    }

    /// Délais proposés par l'interface, en secondes.
    static let delaisFermetureDisponibles = [10, 30, 60, 120, 300]

    /// Attente entre la fin de la lecture et la fermeture, en secondes.
    var delaiFermetureAutomatique: Int {
        get { signalerLecture(); return max(stockage.integer(forKey: Cle.delaiFermetureAutomatique), 1) }
        set { stockage.set(max(newValue, 1), forKey: Cle.delaiFermetureAutomatique); signalerEcriture() }
    }

    // MARK: - Synthèse

    var moteurActif: TypeMoteur {
        get {
            signalerLecture()
            let brut = stockage.string(forKey: Cle.moteurActif) ?? ""
            return TypeMoteur(rawValue: brut) ?? .say
        }
        set { stockage.set(newValue.rawValue, forKey: Cle.moteurActif); signalerEcriture() }
    }

    /// Identifiant de la voix retenue pour un moteur donné.
    ///
    /// Les catalogues sont séparés : `say` n'accède pas aux voix Premium, une
    /// voix choisie pour l'un n'a pas de sens pour l'autre.
    func voix(pour moteur: TypeMoteur) -> String? {
        signalerLecture()
        return stockage.string(forKey: moteur == .say ? Cle.voixSay : Cle.voixAVSpeech)
    }

    func definirVoix(_ identifiant: String?, pour moteur: TypeMoteur) {
        stockage.set(identifiant, forKey: moteur == .say ? Cle.voixSay : Cle.voixAVSpeech)
        signalerEcriture()
    }

    /// Débit de la synthèse, distinct de la vitesse de lecture.
    var vitesseSyntheseBase: Float {
        get { signalerLecture(); return stockage.float(forKey: Cle.vitesseSyntheseBase) }
        set { stockage.set(newValue, forKey: Cle.vitesseSyntheseBase); signalerEcriture() }
    }

    var detectionLangueAuto: Bool {
        get { signalerLecture(); return stockage.bool(forKey: Cle.detectionLangueAuto) }
        set { stockage.set(newValue, forKey: Cle.detectionLangueAuto); signalerEcriture() }
    }

    var langueParDefaut: String {
        get { signalerLecture(); return stockage.string(forKey: Cle.langueParDefaut) ?? "fr-FR" }
        set { stockage.set(newValue, forKey: Cle.langueParDefaut); signalerEcriture() }
    }

    // MARK: - Texte

    var nettoyageMarkdown: Bool {
        get { signalerLecture(); return stockage.bool(forKey: Cle.nettoyageMarkdown) }
        set { stockage.set(newValue, forKey: Cle.nettoyageMarkdown); signalerEcriture() }
    }

    // MARK: - Entrées

    var restaurerPressePapiers: Bool {
        get { signalerLecture(); return stockage.bool(forKey: Cle.restaurerPressePapiers) }
        set { stockage.set(newValue, forKey: Cle.restaurerPressePapiers); signalerEcriture() }
    }

    var raccourciGlobalActif: Bool {
        get { signalerLecture(); return stockage.bool(forKey: Cle.raccourciGlobalActif) }
        set { stockage.set(newValue, forKey: Cle.raccourciGlobalActif); signalerEcriture() }
    }

    // MARK: - Premier lancement

    /// L'assistant de configuration a-t-il déjà été parcouru ?
    var assistantVu: Bool {
        get { signalerLecture(); return stockage.bool(forKey: Cle.assistantVu) }
        set { stockage.set(newValue, forKey: Cle.assistantVu); signalerEcriture() }
    }

    // MARK: - Mise à jour

    /// Rechercher les mises à jour au démarrage puis chaque jour.
    var miseAJourAutomatique: Bool {
        get { signalerLecture(); return stockage.bool(forKey: Cle.miseAJourAutomatique) }
        set { stockage.set(newValue, forKey: Cle.miseAJourAutomatique); signalerEcriture() }
    }

    /// Code de touche du raccourci global. 37 correspond à « L ».
    var raccourciCodeTouche: Int {
        get {
            signalerLecture()
            let valeur = stockage.integer(forKey: Cle.raccourciCodeTouche)
            return valeur == 0 ? 37 : valeur
        }
        set { stockage.set(newValue, forKey: Cle.raccourciCodeTouche); signalerEcriture() }
    }

    /// Modificateurs du raccourci global, au format Carbon.
    var raccourciModificateurs: Int {
        get {
            signalerLecture()
            let valeur = stockage.integer(forKey: Cle.raccourciModificateurs)
            // Par défaut Contrôle + Option, peu susceptible d'entrer en conflit.
            return valeur == 0 ? 0x1000 | 0x0800 : valeur
        }
        set { stockage.set(newValue, forKey: Cle.raccourciModificateurs); signalerEcriture() }
    }
}
