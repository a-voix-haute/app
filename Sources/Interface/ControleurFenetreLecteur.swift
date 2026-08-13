// Assemble une fenêtre flottante, sa vue et son lecteur.

import AppKit
import SwiftUI

@MainActor
final class ControleurFenetreLecteur: NSObject, NSWindowDelegate {

    let lecteur: Lecteur
    private let fenetre: FenetreFlottante
    private var surveillantClavier: Any?

    /// Appelé quand la fenêtre se ferme, quelle qu'en soit la cause.
    var surFermeture: ((ControleurFenetreLecteur) -> Void)?

    init(lecteur: Lecteur, titre: String, rang: Int) {
        self.lecteur = lecteur
        self.fenetre = FenetreFlottante()
        super.init()

        let vue = VueLecteur(lecteur: lecteur, titre: titre) { [weak self] in
            self?.fermer()
        }

        let hebergeur = NSHostingView(rootView: vue)
        hebergeur.frame = NSRect(origin: .zero, size: FenetreFlottante.taille)
        fenetre.contentView = hebergeur
        fenetre.delegate = self
        fenetre.positionner(rang: rang)

        installerRaccourcisClavier()
    }

    // MARK: - Affichage

    /// Affiche la fenêtre sans activer l'application ni voler le focus :
    /// la lecture est le plus souvent déclenchée depuis une autre application.
    func afficher() {
        fenetre.afficherAuPremierPlan()
    }

    func fermer() {
        retirerRaccourcisClavier()
        lecteur.fermer()
        fenetre.delegate = nil
        fenetre.orderOut(nil)
        surFermeture?(self)
    }

    // MARK: - Clavier

    /// Les raccourcis n'agissent que lorsque cette fenêtre est au premier plan,
    /// ce qui évite d'intercepter les frappes destinées à une autre application.
    private func installerRaccourcisClavier() {
        surveillantClavier = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] evenement in
            guard let self, evenement.window === self.fenetre else { return evenement }

            // Une combinaison avec Commande appartient au système ou à
            // l'application : on ne la capture pas.
            if evenement.modifierFlags.contains(.command) { return evenement }

            switch evenement.keyCode {
            case 49: // Espace
                self.lecteur.basculerLecture()
                return nil
            case 124: // Flèche droite
                self.lecteur.decaler(de: 15)
                return nil
            case 123: // Flèche gauche
                self.lecteur.decaler(de: -15)
                return nil
            case 126: // Flèche haut
                self.lecteur.vitesseSuivante()
                return nil
            case 125: // Flèche bas
                self.lecteur.vitessePrecedente()
                return nil
            case 53: // Échap
                self.fermer()
                return nil
            default:
                return evenement
            }
        }
    }

    private func retirerRaccourcisClavier() {
        if let surveillant = surveillantClavier {
            NSEvent.removeMonitor(surveillant)
            surveillantClavier = nil
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        retirerRaccourcisClavier()
        lecteur.fermer()
        surFermeture?(self)
    }
}
