// Lecture d'un fichier audio, avec vitesse ajustable en cours d'écoute.
//
// C'est le cœur du projet, et la raison pour laquelle AVPlayer est employé
// plutôt qu'AVAudioPlayer : seul AVPlayerItem expose `audioTimePitchAlgorithm`,
// qui préserve la hauteur de voix quand on accélère. Sans lui, une lecture à
// 2,5× donne une voix de dessin animé — exactement le défaut du raccourci
// « Énoncer la sélection » que cette application remplace.

import AVFoundation
import Foundation
import Observation

@Observable
@MainActor
final class Lecteur {

    /// Vitesses proposées par l'interface.
    static let vitessesDisponibles: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    enum Etat {
        case enLecture
        case enPause
        case termine
    }

    // MARK: - État observable

    private(set) var etat: Etat = .enPause {
        didSet {
            guard etat != oldValue else { return }
            surChangementEtat?(etat)
        }
    }
    private(set) var position: TimeInterval = 0
    private(set) var duree: TimeInterval = 0

    /// Appelé à chaque changement d'état.
    ///
    /// Un rappel explicite plutôt qu'un `withObservationTracking` côté
    /// contrôleur : ce dernier ne notifie qu'une fois et demanderait d'être
    /// réarmé à chaque passage, ce qui se prête mal à un état qui va et vient
    /// entre lecture, pause et fin.
    var surChangementEtat: ((Etat) -> Void)?

    /// Vitesse voulue par l'utilisateur.
    ///
    /// Elle est distincte de `AVPlayer.rate` : sur AVPlayer, `rate == 0`
    /// *signifie* « en pause ». Lire `rate` pour connaître la vitesse donnerait
    /// donc 0 dès la première pause, puis une reprise à vitesse nulle.
    private(set) var vitesse: Float = 1.0

    // MARK: - Éléments privés

    private let joueur: AVPlayer
    private let element: AVPlayerItem
    private let fichier: URL
    private var observateurTemps: Any?
    private var observateurFin: NSObjectProtocol?

    // MARK: - Cycle de vie

    init(fichier: URL, vitesseInitiale: Float = 1.0) {
        self.fichier = fichier

        element = AVPlayerItem(url: fichier)
        // Le point décisif : « Modest quality, less expensive. Suitable for
        // voice » d'après la documentation d'Apple.
        element.audioTimePitchAlgorithm = .timeDomain

        joueur = AVPlayer(playerItem: element)
        joueur.actionAtItemEnd = .pause

        vitesse = vitesseInitiale
        // defaultRate fixe la vitesse qu'utilisera `play()`, sans démarrer la
        // lecture — contrairement à `rate`, qui la déclenche immédiatement.
        joueur.defaultRate = vitesseInitiale

        observerTemps()
        observerFin()
        chargerDuree()
    }

    // Pas de `deinit` : il n'est pas isolé au MainActor et ne peut donc pas
    // toucher aux propriétés de cette classe. Le retrait des observateurs et la
    // suppression du fichier sont faits par `fermer()`, que le contrôleur de
    // fenêtre appelle systématiquement.

    /// Arrête la lecture et libère le fichier temporaire.
    func fermer() {
        joueur.pause()
        if let observateur = observateurTemps {
            joueur.removeTimeObserver(observateur)
            observateurTemps = nil
        }
        if let observateur = observateurFin {
            NotificationCenter.default.removeObserver(observateur)
            observateurFin = nil
        }
        GestionnaireFichiersTemp.supprimer(fichier)
    }

    // MARK: - Commandes

    func lire() {
        guard etat != .enLecture else { return }

        // Relancer depuis la fin recommencerait au même point : on repart du
        // début, comportement attendu d'un bouton « lecture » après la fin.
        if etat == .termine {
            chercher(vers: 0)
        }

        joueur.defaultRate = vitesse
        joueur.play()
        etat = .enLecture
    }

    func pause() {
        guard etat == .enLecture else { return }
        joueur.pause()
        etat = .enPause
    }

    func basculerLecture() {
        etat == .enLecture ? pause() : lire()
    }

    /// Change la vitesse, y compris pendant la lecture.
    func definirVitesse(_ nouvelle: Float) {
        let bornee = min(max(nouvelle, 0.25), 4.0)
        vitesse = bornee
        joueur.defaultRate = bornee
        // `rate` n'est modifié qu'en lecture : l'assigner en pause relancerait
        // la lecture.
        if etat == .enLecture {
            joueur.rate = bornee
        }
    }

    /// Passe à la vitesse suivante de la liste, en bouclant.
    func vitesseSuivante() {
        let index = Self.vitessesDisponibles.firstIndex(of: vitesse) ?? 2
        definirVitesse(Self.vitessesDisponibles[(index + 1) % Self.vitessesDisponibles.count])
    }

    /// Passe à la vitesse précédente de la liste, en bouclant.
    func vitessePrecedente() {
        let index = Self.vitessesDisponibles.firstIndex(of: vitesse) ?? 2
        let nombre = Self.vitessesDisponibles.count
        definirVitesse(Self.vitessesDisponibles[(index - 1 + nombre) % nombre])
    }

    /// Déplace la tête de lecture, sans tolérance pour un positionnement exact.
    ///
    /// Le déplacement est asynchrone : `position` est mise à jour tout de suite
    /// pour que la barre suive le doigt, puis corrigée à la complétion. Sans
    /// cela, l'observateur périodique renverrait brièvement l'ancienne valeur
    /// et la barre reculerait d'un cran après le clic.
    func chercher(vers secondes: TimeInterval) {
        let cible = min(max(0, secondes), max(duree, 0))
        position = cible

        if etat == .termine && cible < duree {
            etat = .enPause
        }

        let temps = CMTime(seconds: cible, preferredTimescale: 600)
        joueur.seek(to: temps, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] termine in
            guard termine else { return }
            MainActor.assumeIsolated {
                self?.position = temps.seconds
            }
        }
    }

    func decaler(de secondes: TimeInterval) {
        chercher(vers: position + secondes)
    }

    // MARK: - Observation

    private func observerTemps() {
        // Dix rafraîchissements par seconde : assez fluide pour la barre de
        // progression, sans solliciter le processeur inutilement.
        let intervalle = CMTime(seconds: 0.1, preferredTimescale: 600)
        observateurTemps = joueur.addPeriodicTimeObserver(
            forInterval: intervalle,
            queue: .main
        ) { [weak self] temps in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.position = temps.seconds
                if self.duree == 0 { self.chargerDuree() }
            }
        }
    }

    private func observerFin() {
        observateurFin = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: element,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.etat = .termine
                self.position = self.duree
            }
        }
    }

    /// Récupère la durée dès qu'elle est connue.
    ///
    /// Elle ne l'est pas à l'instant de la création : AVPlayerItem doit d'abord
    /// analyser le fichier.
    private func chargerDuree() {
        let brute = element.duration
        if brute.isNumeric && brute.seconds.isFinite && brute.seconds > 0 {
            duree = brute.seconds
            return
        }

        Task { [weak self] in
            guard let self else { return }
            if let chargee = try? await self.element.asset.load(.duration),
               chargee.seconds.isFinite, chargee.seconds > 0 {
                self.duree = chargee.seconds
            }
        }
    }

    // MARK: - Affichage

    /// Formate une durée en `m:ss` ou `h:mm:ss`.
    ///
    /// `nonisolated` : fonction pure, utilisable depuis n'importe quel contexte.
    nonisolated static func formaterDuree(_ secondes: TimeInterval) -> String {
        guard secondes.isFinite, secondes >= 0 else { return "0:00" }
        let total = Int(secondes.rounded())
        let heures = total / 3600
        let minutes = (total % 3600) / 60
        let restantes = total % 60
        return heures > 0
            ? String(format: "%d:%02d:%02d", heures, minutes, restantes)
            : String(format: "%d:%02d", minutes, restantes)
    }

    /// Vitesse formatée pour l'affichage : « 1× », « 1,5× ».
    nonisolated static func formaterVitesse(_ vitesse: Float) -> String {
        if vitesse == vitesse.rounded() {
            return String(format: "%.0f×", vitesse)
        }
        let texte = String(format: "%.2f", vitesse)
            .replacingOccurrences(of: "0$", with: "", options: .regularExpression)
            .replacingOccurrences(of: ".", with: ",")
        return texte + "×"
    }
}
