// Raccourci clavier global.
//
// `RegisterEventHotKey` appartient à Carbon, réputé obsolète, mais c'est la
// seule interface qui capte une combinaison de touches sans exiger
// l'autorisation Accessibilité — et qui consomme l'événement, là où
// `NSEvent.addGlobalMonitorForEvents` le laisse aussi filer vers l'application
// active. Vérifié sur le SDK macOS 26 : compile sans avertissement de
// dépréciation et renvoie `noErr`.
//
// L'autorisation reste nécessaire pour la capture de la sélection, mais elle
// n'est demandée qu'au premier usage, pas au simple enregistrement.

import AppKit
import Carbon.HIToolbox

@MainActor
final class RaccourciGlobal {

    static let partage = RaccourciGlobal()

    /// Appelé quand la combinaison est enfoncée.
    var surDeclenchement: (() -> Void)?

    private var reference: EventHotKeyRef?
    private var gestionnaire: EventHandlerRef?
    private var installe = false

    /// Signature identifiant nos raccourcis auprès du système : « LECT ».
    private static let signature = OSType(0x4C454354)

    private init() {}

    // MARK: - Cycle de vie

    /// Enregistre la combinaison définie dans les réglages.
    ///
    /// - Returns: `true` si l'enregistrement a réussi. Un échec signifie le plus
    ///   souvent qu'une autre application occupe déjà cette combinaison.
    @discardableResult
    func activer() -> Bool {
        desactiver()

        let reglages = Reglages.partage
        guard reglages.raccourciGlobalActif else { return false }

        installerGestionnaire()

        var identifiant = EventHotKeyID(signature: Self.signature, id: 1)
        var nouvelle: EventHotKeyRef?

        let statut = RegisterEventHotKey(
            UInt32(reglages.raccourciCodeTouche),
            UInt32(reglages.raccourciModificateurs),
            identifiant,
            GetApplicationEventTarget(),
            0,
            &nouvelle
        )

        guard statut == noErr, let enregistree = nouvelle else {
            Journal.fichier("raccourci", "enregistrement refusé (statut \(statut)) — combinaison déjà prise ?")
            return false
        }

        reference = enregistree
        let combinaison = Self.description(
            codeTouche: reglages.raccourciCodeTouche,
            modificateurs: reglages.raccourciModificateurs
        )
        Journal.fichier("raccourci", "raccourci global actif : \(combinaison)")
        return true
    }

    func desactiver() {
        if let reference {
            UnregisterEventHotKey(reference)
            self.reference = nil
        }
    }

    /// Installe le gestionnaire d'événements, une seule fois par processus.
    private func installerGestionnaire() {
        guard !installe else { return }

        var specification = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let rappel: EventHandlerUPP = { _, evenement, _ in
            var identifiant = EventHotKeyID()
            let statut = GetEventParameter(
                evenement,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &identifiant
            )

            guard statut == noErr, identifiant.signature == RaccourciGlobal.signature else {
                return OSStatus(eventNotHandledErr)
            }

            // Le rappel Carbon n'est pas isolé : on repasse par la file
            // principale avant de toucher au modèle.
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    RaccourciGlobal.partage.surDeclenchement?()
                }
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            rappel,
            1,
            &specification,
            nil,
            &gestionnaire
        )

        installe = true
    }

    // MARK: - Affichage

    /// Traduit une combinaison en symboles, façon « ⌃⌥L ».
    nonisolated static func description(codeTouche: Int, modificateurs: Int) -> String {
        var texte = ""
        if modificateurs & controlKey != 0 { texte += "⌃" }
        if modificateurs & optionKey != 0 { texte += "⌥" }
        if modificateurs & shiftKey != 0 { texte += "⇧" }
        if modificateurs & cmdKey != 0 { texte += "⌘" }
        texte += nomTouche(codeTouche)
        return texte
    }

    /// Nom lisible d'un code de touche virtuel.
    nonisolated static func nomTouche(_ code: Int) -> String {
        switch code {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_V: return "V"
        case kVK_Space:  return "Espace"
        case kVK_Escape: return "Échap"
        case kVK_F1:     return "F1"
        case kVK_F2:     return "F2"
        case kVK_F5:     return "F5"
        case kVK_F6:     return "F6"
        default:         return "touche \(code)"
        }
    }

    /// Combinaisons proposées dans les réglages.
    ///
    /// Toutes reposent sur Contrôle + Option, peu utilisé par les applications
    /// courantes, ce qui limite les conflits.
    nonisolated static var combinaisonsProposees: [(libelle: String, code: Int, modificateurs: Int)] {
        [
            ("⌃⌥L", kVK_ANSI_L, controlKey | optionKey),
            ("⌃⌥P", kVK_ANSI_P, controlKey | optionKey),
            ("⌃⌥S", kVK_ANSI_S, controlKey | optionKey),
            ("⌃⌥Espace", kVK_Space, controlKey | optionKey),
            ("⌃⌥⇧L", kVK_ANSI_L, controlKey | optionKey | shiftKey)
        ]
    }
}
