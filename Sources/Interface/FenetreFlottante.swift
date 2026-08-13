// Fenêtre du lecteur : sans bordure, translucide, au-dessus de tout.
//
// Trois réglages font le comportement recherché :
//
//  - `level = .statusBar` place la fenêtre au-dessus des fenêtres ordinaires ;
//  - `fullScreenAuxiliary` l'autorise à s'afficher par-dessus une application
//    en plein écran, ce qu'un niveau élevé seul ne suffit pas à obtenir ;
//  - `canJoinAllSpaces` la fait suivre l'utilisateur d'un bureau à l'autre.
//
// `becomesKeyOnlyIfNeeded` est tout aussi important : sans lui, un clic sur le
// lecteur retirerait le focus à l'application en cours d'utilisation.

import AppKit

final class FenetreFlottante: NSPanel {

    static let taille = NSSize(width: 360, height: 104)

    /// Rayon des coins, appliqué par la couche Liquid Glass et par elle seule.
    ///
    /// 22 points suivent la courbure des fenêtres système de macOS 26.
    static let rayonCoins: CGFloat = 22

    /// Décalage appliqué entre deux fenêtres pour éviter le recouvrement.
    static let decalageCascade: CGFloat = 24

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.taille),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true

        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        isFloatingPanel = true
        // Ne prend le focus que si un champ le réclame : les clics sur les
        // boutons n'interrompent pas le travail en cours dans une autre app.
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow

        // Sans cela, la fenêtre disparaîtrait au changement d'application.
        isReleasedWhenClosed = false
    }

    // Une fenêtre sans bordure refuse par défaut de devenir principale ou clé ;
    // il faut l'autoriser pour que les raccourcis clavier fonctionnent.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Affiche la fenêtre sans activer l'application.
    ///
    /// Le niveau est réappliqué ici : construire un NSPanel avec
    /// `.nonactivatingPanel` le ramène à un niveau plus bas que celui demandé
    /// dans l'initialiseur (mesuré : 3 au lieu de 25), ce qui ne suffit pas à
    /// passer au-dessus d'une application en plein écran.
    func afficherAuPremierPlan() {
        orderFrontRegardless()
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    /// Place la fenêtre en haut à droite de l'écran actif, décalée selon le
    /// rang qu'elle occupe parmi les lecteurs ouverts.
    func positionner(rang: Int) {
        guard let ecran = NSScreen.main else { return }
        let zone = ecran.visibleFrame
        let decalage = CGFloat(rang) * Self.decalageCascade

        var origine = NSPoint(
            x: zone.maxX - Self.taille.width - 20 - decalage,
            y: zone.maxY - Self.taille.height - 20 - decalage
        )

        // Au-delà d'un certain nombre de fenêtres, la cascade sortirait de
        // l'écran : on repart du haut.
        if origine.y < zone.minY + 20 || origine.x < zone.minX + 20 {
            let rangRamene = rang % 5
            origine = NSPoint(
                x: zone.maxX - Self.taille.width - 20 - CGFloat(rangRamene) * Self.decalageCascade,
                y: zone.maxY - Self.taille.height - 20 - CGFloat(rangRamene) * Self.decalageCascade
            )
        }

        setFrameOrigin(origine)
    }
}
