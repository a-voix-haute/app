// Point d'entrée unique de toute demande de lecture.
//
// Quel que soit le canal — helper CLI, service macOS, raccourci global, URL,
// barre de menus — la demande passe par ici, ce qui garantit que les règles de
// coexistence entre lecteurs s'appliquent partout de la même façon.

import AppKit
import Foundation
import Observation

/// Provenance d'une demande, à des fins de journalisation et de titre.
enum SourceLecture: String {
    case pressePapiers
    case fichier
    case service
    case raccourci
    case url
    case cli

    var titreParDefaut: String {
        switch self {
        case .pressePapiers: return "Presse-papiers"
        case .fichier:       return "Document"
        case .service:       return "Sélection"
        case .raccourci:     return "Sélection"
        case .url:           return "Lecture"
        case .cli:           return "Lecture"
        }
    }
}

@Observable
@MainActor
final class GestionnaireLecteurs {

    static let partage = GestionnaireLecteurs()

    /// Lecteurs ouverts, du plus ancien au plus récent.
    private(set) var sessions: [SessionLecture] = []

    /// Nombre de synthèses en cours, pour l'affichage d'une progression.
    private(set) var syntheseEnCours = 0

    private var moteurSay = MoteurSay()

    private init() {}

    // MARK: - Demande de lecture

    /// Traite une demande de lecture de bout en bout.
    ///
    /// Le texte est nettoyé, synthétisé, puis confié à un nouveau lecteur dont
    /// le démarrage dépend de l'état des lecteurs déjà ouverts.
    func demanderLecture(texte: String, source: SourceLecture, titre: String? = nil) {
        let reglages = Reglages.partage

        let prepare = reglages.nettoyageMarkdown
            ? NettoyeurMarkdown.nettoyer(texte)
            : texte.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !prepare.isEmpty else {
            Journal.lecture.notice("Demande ignorée : texte vide après nettoyage")
            return
        }

        let moteur = moteurCourant()
        guard let voix = choisirVoix(pour: moteur, texte: prepare) else {
            Journal.synthese.error("Aucune voix disponible pour le moteur \(moteur.type.rawValue, privacy: .public)")
            return
        }

        Journal.lecture.info("""
            Demande de lecture : \(prepare.count) caractères, \
            source \(source.rawValue, privacy: .public), voix \(voix.nom, privacy: .public)
            """)

        syntheseEnCours += 1

        Task { [weak self] in
            defer { Task { @MainActor in self?.syntheseEnCours -= 1 } }
            do {
                let audio = try await moteur.synthetiser(
                    texte: prepare,
                    voix: voix,
                    vitesseBase: reglages.vitesseSyntheseBase
                ) { _ in }

                await MainActor.run {
                    self?.ouvrirLecteur(
                        fichier: audio,
                        titre: titre ?? source.titreParDefaut
                    )
                }
            } catch is CancellationError {
                Journal.synthese.info("Synthèse annulée")
            } catch {
                Journal.synthese.error("Synthèse échouée : \(error.localizedDescription, privacy: .public)")
                await MainActor.run { self?.signalerEchec(error) }
            }
        }
    }

    /// Arrête et ferme tous les lecteurs.
    func toutArreter() {
        for session in sessions {
            session.controleur.fermerSansNotifier()
        }
        sessions.removeAll()
        Journal.lecture.info("Toutes les lectures ont été arrêtées")
    }

    // MARK: - Ouverture

    private func ouvrirLecteur(fichier: URL, titre: String) {
        let reglages = Reglages.partage

        // Décidé avant d'ajouter la nouvelle session, sinon elle se compterait
        // elle-même.
        let uneLectureEnCours = sessions.contains { $0.lecteur.etat == .enLecture }

        libererPlace()

        let lecteur = Lecteur(fichier: fichier, vitesseInitiale: reglages.vitesseParDefaut)
        let controleur = ControleurFenetreLecteur(
            lecteur: lecteur,
            titre: titre,
            rang: sessions.count
        )

        let session = SessionLecture(lecteur: lecteur, controleur: controleur)
        controleur.surFermeture = { [weak self] ferme in
            self?.sessions.removeAll { $0.controleur === ferme }
        }

        sessions.append(session)
        controleur.afficher()

        appliquerReglesDemarrage(
            nouvelle: session,
            uneLectureEnCours: uneLectureEnCours,
            reglages: reglages
        )
    }

    /// Décide si la nouvelle lecture démarre, et ce que deviennent les autres.
    private func appliquerReglesDemarrage(
        nouvelle: SessionLecture,
        uneLectureEnCours: Bool,
        reglages: Reglages
    ) {
        guard reglages.demarrageAutomatique else {
            Journal.lecture.debug("Démarrage automatique désactivé : la fenêtre attend")
            return
        }

        guard uneLectureEnCours else {
            // Rien ne joue : on démarre sans hésiter.
            nouvelle.lecteur.lire()
            return
        }

        switch reglages.comportementNouvelleLecture {
        case .continuer:
            // L'écoute en cours n'est pas interrompue ; la nouvelle attend un
            // appui sur lecture.
            Journal.lecture.debug("Lecture en cours : la nouvelle fenêtre attend")

        case .mettreEnPause:
            for session in sessions where session !== nouvelle {
                if session.lecteur.etat == .enLecture {
                    session.lecteur.pause()
                }
            }
            nouvelle.lecteur.lire()
        }
    }

    // MARK: - Éviction

    /// Ferme les lecteurs excédentaires avant d'en ouvrir un nouveau.
    ///
    /// Les candidats sont retenus dans l'ordre où ils gênent le moins :
    /// d'abord ceux dont la lecture est terminée, puis ceux en pause, et en
    /// dernier recours une lecture en cours. À état égal, le plus ancien part.
    private func libererPlace() {
        let limite = Reglages.partage.limiteLecteurs
        guard sessions.count >= limite else { return }

        let aFermer = sessions.count - limite + 1
        let candidats = sessions
            .enumerated()
            .sorted { gauche, droite in
                let priorite = Self.prioriteEviction(gauche.element.lecteur.etat)
                let autre = Self.prioriteEviction(droite.element.lecteur.etat)
                return priorite == autre ? gauche.offset < droite.offset : priorite < autre
            }
            .prefix(aFermer)
            .map(\.element)

        for session in candidats {
            Journal.lecture.debug("Éviction d'un lecteur (limite de \(limite) atteinte)")
            session.controleur.fermerSansNotifier()
            sessions.removeAll { $0 === session }
        }
    }

    /// Ordre de sacrifice : plus la valeur est basse, plus le lecteur part tôt.
    private static func prioriteEviction(_ etat: Lecteur.Etat) -> Int {
        switch etat {
        case .termine:   return 0
        case .enPause:   return 1
        case .enLecture: return 2
        }
    }

    // MARK: - Moteur et voix

    private func moteurCourant() -> MoteurSynthese {
        // MoteurAVSpeech arrive à l'étape 8 ; d'ici là, `say` assure les deux.
        moteurSay
    }

    /// Choisit la voix réglée, ou la meilleure disponible dans la langue voulue.
    ///
    /// Le repli est silencieux : une voix désinstallée ne doit pas empêcher la
    /// lecture, seulement la rendre moins agréable.
    private func choisirVoix(pour moteur: MoteurSynthese, texte: String) -> VoixDisponible? {
        let reglages = Reglages.partage
        let disponibles = moteur.voixDisponibles()
        guard !disponibles.isEmpty else { return nil }

        if let identifiant = reglages.voix(pour: moteur.type),
           let choisie = disponibles.first(where: { $0.id == identifiant }) {
            return choisie
        }

        let langue = reglages.detectionLangueAuto
            ? DetecteurLangue.detecter(texte, parDefaut: reglages.langueParDefaut)
            : reglages.langueParDefaut

        let code = String(langue.prefix(2)).lowercased()
        let memeLangue = disponibles.filter { $0.codeLangue == code }

        if let meilleure = memeLangue.max(by: { $0.qualite < $1.qualite }) {
            return meilleure
        }

        Journal.synthese.notice("Aucune voix pour \(langue, privacy: .public), repli sur la première disponible")
        return disponibles.first
    }

    // MARK: - Erreurs

    private func signalerEchec(_ erreur: Error) {
        let alerte = NSAlert()
        alerte.messageText = "Lecture impossible"
        alerte.informativeText = erreur.localizedDescription
        alerte.alertStyle = .warning
        alerte.addButton(withTitle: "Fermer")
        alerte.runModal()
    }
}

/// Un lecteur ouvert et sa fenêtre.
@MainActor
final class SessionLecture {
    let lecteur: Lecteur
    let controleur: ControleurFenetreLecteur
    let dateCreation = Date()

    init(lecteur: Lecteur, controleur: ControleurFenetreLecteur) {
        self.lecteur = lecteur
        self.controleur = controleur
    }
}
