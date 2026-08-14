// Assemble une fenêtre flottante, sa vue et son lecteur.

import AppKit
import SwiftUI

@MainActor
final class ControleurFenetreLecteur: NSObject, NSWindowDelegate {

    let lecteur: Lecteur
    private let fenetre: FenetreFlottante
    private var surveillantClavier: Any?

    /// Minuteur de fermeture automatique, armé quand la lecture se termine.
    private var minuteurFermeture: Timer?

    /// Le curseur survole-t-il la fenêtre ?
    ///
    /// Le décompte est suspendu tant que c'est le cas, et reprend au départ
    /// quand le curseur ressort : quelqu'un dont la main passe sur le lecteur
    /// s'apprête peut-être à cliquer « rejouer ».
    private var curseurSurLaFenetre = false

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
        // La vue SwiftUI ne peint aucun fond : le matériau vient de la couche
        // Glass en dessous, qui doit rester visible au travers.
        hebergeur.wantsLayer = true
        hebergeur.layer?.backgroundColor = .clear

        let survol = VueSurvol(frame: NSRect(origin: .zero, size: FenetreFlottante.taille))
        survol.autoresizingMask = [.width, .height]
        survol.surEntree = { [weak self] in self?.curseurEstEntre() }
        survol.surSortie = { [weak self] in self?.curseurEstSorti() }
        hebergeur.addSubview(survol)

        fenetre.contentView = Self.envelopperDansGlass(hebergeur)
        fenetre.delegate = self
        fenetre.positionner(rang: rang)

        installerRaccourcisClavier()

        lecteur.surChangementEtat = { [weak self] etat in
            self?.reagirAuChangementEtat(etat)
        }
    }

    // MARK: - Habillage

    /// Enveloppe la vue dans le matériau Liquid Glass.
    ///
    /// C'est la couche de fond qui porte le rayon des coins : le lui confier
    /// évite le liseré que produit un second arrondi appliqué par-dessus, et
    /// laisse le système gérer le rendu du matériau, les reflets et l'adaptation
    /// au contenu situé derrière la fenêtre.
    private static func envelopperDansGlass(_ contenu: NSView) -> NSView {
        let cadre = NSRect(origin: .zero, size: FenetreFlottante.taille)
        contenu.autoresizingMask = [.width, .height]

        if #available(macOS 26.0, *) {
            let verre = NSGlassEffectView()
            verre.frame = cadre
            verre.cornerRadius = FenetreFlottante.rayonCoins
            verre.style = .regular
            verre.autoresizingMask = [.width, .height]
            verre.contentView = contenu
            return verre
        }

        // Repli avant macOS 26 : matériau HUD et arrondi porté par la couche,
        // ce qui reste un seul arrondi.
        let flou = NSVisualEffectView(frame: cadre)
        flou.material = .hudWindow
        flou.blendingMode = .behindWindow
        flou.state = .active
        flou.wantsLayer = true
        flou.layer?.cornerRadius = FenetreFlottante.rayonCoins
        flou.layer?.masksToBounds = true
        flou.autoresizingMask = [.width, .height]
        contenu.frame = cadre
        flou.addSubview(contenu)
        return flou
    }

    // MARK: - Affichage

    /// Affiche la fenêtre sans activer l'application ni voler le focus :
    /// la lecture est le plus souvent déclenchée depuis une autre application.
    func afficher() {
        fenetre.afficherAuPremierPlan()
    }

    func fermer() {
        annulerMinuteurFermeture()
        retirerRaccourcisClavier()
        lecteur.fermer()
        fenetre.delegate = nil
        fenetre.orderOut(nil)
        surFermeture?(self)
    }

    /// Ferme sans déclencher `surFermeture`.
    ///
    /// Utilisé par le gestionnaire quand il retire lui-même la session de sa
    /// liste : le rappel modifierait la collection pendant son parcours.
    func fermerSansNotifier() {
        surFermeture = nil
        annulerMinuteurFermeture()
        retirerRaccourcisClavier()
        lecteur.fermer()
        fenetre.delegate = nil
        fenetre.orderOut(nil)
    }

    // MARK: - Fermeture automatique

    /// Arme ou désarme le minuteur selon le nouvel état de la lecture.
    ///
    /// Toute reprise annule un décompte en cours : relancer la lecture d'un
    /// texte terminé est précisément le geste que l'option ne doit pas
    /// contrarier.
    private func reagirAuChangementEtat(_ etat: Lecteur.Etat) {
        if etat == .termine {
            armerMinuteurFermeture()
        } else {
            annulerMinuteurFermeture()
        }
    }

    private func armerMinuteurFermeture() {
        annulerMinuteurFermeture()

        let reglages = Reglages.partage
        guard reglages.fermetureAutomatique else { return }
        // Le curseur sur la fenêtre suspend le décompte ; `curseurEstSorti`
        // le relancera depuis le début.
        guard !curseurSurLaFenetre else { return }

        let delai = TimeInterval(reglages.delaiFermetureAutomatique)
        minuteurFermeture = Timer.scheduledTimer(withTimeInterval: delai, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // L'état est revérifié : une lecture relancée juste avant le
                // tir aurait déjà annulé le minuteur, mais la garde ne coûte
                // rien et couvre un changement d'état sans passage par le
                // rappel.
                guard self.lecteur.etat == .termine, !self.curseurSurLaFenetre else { return }
                self.fermer()
            }
        }
    }

    private func annulerMinuteurFermeture() {
        minuteurFermeture?.invalidate()
        minuteurFermeture = nil
    }

    private func curseurEstEntre() {
        curseurSurLaFenetre = true
        annulerMinuteurFermeture()
    }

    private func curseurEstSorti() {
        curseurSurLaFenetre = false
        // Le décompte repart entier : la fenêtre ne disparaît pas dans la
        // seconde qui suit le retrait de la souris.
        if lecteur.etat == .termine {
            armerMinuteurFermeture()
        }
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
        annulerMinuteurFermeture()
        retirerRaccourcisClavier()
        lecteur.fermer()
        surFermeture?(self)
    }
}

// MARK: - Détection du survol

/// Vue invisible qui signale l'entrée et la sortie du curseur.
///
/// Une `NSTrackingArea` plutôt qu'un moniteur d'événements `.mouseMoved` :
/// ce dernier ne reçoit rien tant que l'application n'est pas active, or le
/// lecteur est justement conçu pour vivre au-dessus d'une autre application.
/// `.activeAlways` couvre ce cas.
private final class VueSurvol: NSView {

    var surEntree: (() -> Void)?
    var surSortie: (() -> Void)?

    /// La vue ne sert qu'à observer : elle laisse passer tous les clics vers
    /// les commandes SwiftUI situées en dessous.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Les zones de suivi ne suivent pas le redimensionnement de la vue :
    /// AppKit appelle cette méthode pour qu'on les reconstruise.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        for zone in trackingAreas {
            removeTrackingArea(zone)
        }

        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { surEntree?() }
    override func mouseExited(with event: NSEvent) { surSortie?() }
}
