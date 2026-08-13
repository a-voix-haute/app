// Capture du texte sélectionné dans l'application au premier plan.
//
// Aucune interface publique ne permet de lire la sélection d'une autre
// application sans passer par l'Accessibilité. La méthode retenue simule ⌘C,
// puis restaure le presse-papiers pour ne pas écraser ce que l'utilisateur y
// avait mis — un presse-papiers silencieusement remplacé est une nuisance
// difficile à diagnostiquer.

import AppKit
import Foundation

enum CaptureSelection {

    /// Intervalle entre deux vérifications du presse-papiers.
    private static let pasSondage: TimeInterval = 0.02

    /// Au-delà, on considère que la copie n'a rien produit.
    private static let delaiMaximal: TimeInterval = 0.5

    /// Délai avant restauration : l'application de destination peut encore lire
    /// le presse-papiers juste après la copie.
    private static let delaiRestauration: TimeInterval = 0.3

    // MARK: - Autorisation

    /// L'application est-elle autorisée à envoyer des événements clavier ?
    static var estAutorisee: Bool {
        AXIsProcessTrusted()
    }

    /// Demande l'autorisation, en affichant la fenêtre système si nécessaire.
    ///
    /// - Returns: `true` si l'autorisation est déjà accordée. Sinon macOS
    ///   affiche sa propre demande et l'utilisateur devra relancer l'action.
    @discardableResult
    static func demanderAutorisation() -> Bool {
        let cle = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [cle: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Ouvre directement le volet d'autorisation dans les Réglages Système.
    static func ouvrirReglagesAccessibilite() {
        let adresse = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: adresse) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Capture

    enum Resultat {
        case selection(String)
        case pressePapiers(String)
        case rien
        case nonAutorisee
    }

    /// Récupère le texte sélectionné dans l'application au premier plan.
    ///
    /// - Parameter restaurer: remet le presse-papiers dans son état initial une
    ///   fois la copie effectuée.
    static func capturer(restaurer: Bool = true) -> Resultat {
        guard estAutorisee else {
            // Sans autorisation, il reste le contenu courant du presse-papiers :
            // moins direct, mais l'utilisateur n'est pas bloqué.
            if let texte = NSPasteboard.general.string(forType: .string),
               !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .pressePapiers(texte)
            }
            return .nonAutorisee
        }

        let pressePapiers = NSPasteboard.general
        let compteurInitial = pressePapiers.changeCount
        let sauvegarde = restaurer ? preserverContenu(pressePapiers) : nil

        simulerCopie()

        // Attendre que le presse-papiers change : la copie est asynchrone, et
        // sa durée dépend de l'application source.
        var attendu: TimeInterval = 0
        while pressePapiers.changeCount == compteurInitial && attendu < delaiMaximal {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(pasSondage))
            attendu += pasSondage
        }

        let texte = pressePapiers.string(forType: .string)

        if let sauvegarde {
            DispatchQueue.main.asyncAfter(deadline: .now() + delaiRestauration) {
                restaurerContenu(sauvegarde, dans: pressePapiers)
            }
        }

        guard pressePapiers.changeCount != compteurInitial,
              let texte,
              !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Rien n'a été copié : soit aucune sélection, soit l'application ne
            // répond pas à ⌘C. On se rabat sur le presse-papiers existant.
            if let ancien = sauvegarde?.texte,
               !ancien.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .pressePapiers(ancien)
            }
            return .rien
        }

        return .selection(texte)
    }

    // MARK: - Simulation clavier

    /// Envoie ⌘C au processus au premier plan.
    private static func simulerCopie() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        // Empêche l'état des modificateurs réellement enfoncés d'interférer
        // avec les événements synthétiques.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let toucheC: CGKeyCode = 0x08

        let appui = CGEvent(keyboardEventSource: source, virtualKey: toucheC, keyDown: true)
        appui?.flags = .maskCommand
        let relachement = CGEvent(keyboardEventSource: source, virtualKey: toucheC, keyDown: false)
        relachement?.flags = .maskCommand

        appui?.post(tap: .cghidEventTap)
        relachement?.post(tap: .cghidEventTap)
    }

    // MARK: - Sauvegarde du presse-papiers

    /// Contenu mémorisé du presse-papiers.
    ///
    /// Tous les types présents sont conservés, pas seulement le texte : un
    /// presse-papiers contenant une image ou du texte enrichi doit revenir
    /// intact.
    private struct Contenu {
        let elements: [[NSPasteboard.PasteboardType: Data]]
        let texte: String?
    }

    private static func preserverContenu(_ pressePapiers: NSPasteboard) -> Contenu {
        var elements: [[NSPasteboard.PasteboardType: Data]] = []

        for element in pressePapiers.pasteboardItems ?? [] {
            var types: [NSPasteboard.PasteboardType: Data] = [:]
            for type in element.types {
                if let donnees = element.data(forType: type) {
                    types[type] = donnees
                }
            }
            if !types.isEmpty { elements.append(types) }
        }

        return Contenu(
            elements: elements,
            texte: pressePapiers.string(forType: .string)
        )
    }

    private static func restaurerContenu(_ contenu: Contenu, dans pressePapiers: NSPasteboard) {
        pressePapiers.clearContents()

        guard !contenu.elements.isEmpty else { return }

        let elements: [NSPasteboardItem] = contenu.elements.map { types in
            let element = NSPasteboardItem()
            for (type, donnees) in types {
                element.setData(donnees, forType: type)
            }
            return element
        }

        pressePapiers.writeObjects(elements)
    }
}
