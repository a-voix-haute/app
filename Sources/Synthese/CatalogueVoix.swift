// Catalogue des voix disponibles, pour l'interface de réglages.
//
// Les catalogues sont distincts par moteur : `say` n'accède qu'aux voix
// compactes, tandis qu'AVSpeechSynthesizer voit aussi les voix Améliorées et
// Premium téléchargées. Une voix choisie pour l'un n'a donc pas de sens pour
// l'autre.

import AppKit
import AVFoundation
import Foundation

@MainActor
enum CatalogueVoix {

    /// Phrase d'essai lue lors d'un aperçu.
    ///
    /// Elle mêle nasales, liaisons et une question, de quoi juger une voix
    /// française sur autre chose qu'un mot isolé.
    static let phraseApercu = "Bonjour, voici un aperçu de ma voix. Est-ce qu'elle vous convient ?"

    /// Voix regroupées par langue, triées par qualité décroissante puis par nom.
    static func parLangue(_ moteur: MoteurSynthese) -> [(langue: String, voix: [VoixDisponible])] {
        let toutes = moteur.voixDisponibles()
        let groupes = Dictionary(grouping: toutes, by: \.langue)

        return groupes
            .map { langue, voix in
                let triees = voix.sorted { gauche, droite in
                    gauche.qualite == droite.qualite
                        ? gauche.nom < droite.nom
                        : gauche.qualite > droite.qualite
                }
                return (langue: langue, voix: triees)
            }
            .sorted { gauche, droite in
                // La langue de l'interface d'abord, le reste par ordre alphabétique.
                let prefereeGauche = gauche.langue.hasPrefix(languePreferee)
                let prefereeDroite = droite.langue.hasPrefix(languePreferee)
                if prefereeGauche != prefereeDroite { return prefereeGauche }
                return nomLangue(gauche.langue) < nomLangue(droite.langue)
            }
    }

    private static var languePreferee: String {
        String((Locale.preferredLanguages.first ?? "fr").prefix(2))
    }

    /// Nom lisible d'un code langue : « fr-FR » devient « Français (France) ».
    static func nomLangue(_ code: String) -> String {
        let locale = Locale(identifier: Locale.preferredLanguages.first ?? "fr_FR")
        let identifiant = code.replacingOccurrences(of: "-", with: "_")
        return locale.localizedString(forIdentifier: identifiant)?.capitalized
            ?? locale.localizedString(forLanguageCode: String(code.prefix(2)))?.capitalized
            ?? code
    }

    // MARK: - Aperçu

    private static var lecteurApercu: AVAudioPlayer?
    private static var processusApercu: Process?

    /// Fait entendre un court extrait avec la voix indiquée.
    ///
    /// L'aperçu court-circuite volontairement la chaîne complète : il n'ouvre
    /// pas de fenêtre de lecteur et ne passe pas par le gestionnaire, sans quoi
    /// essayer trois voix laisserait trois fenêtres ouvertes.
    static func ecouterApercu(_ voix: VoixDisponible) {
        arreterApercu()

        let processus = Process()
        processus.executableURL = URL(fileURLWithPath: "/usr/bin/say")
        processus.arguments = ["-v", voix.nom, phraseApercu]
        processus.standardOutput = Pipe()
        processus.standardError = Pipe()

        do {
            try processus.run()
            processusApercu = processus
        } catch {
            Journal.synthese.error("Aperçu impossible : \(error.localizedDescription, privacy: .public)")
        }
    }

    static func arreterApercu() {
        if let processus = processusApercu, processus.isRunning {
            processus.terminate()
        }
        processusApercu = nil
        lecteurApercu?.stop()
        lecteurApercu = nil
    }

    // MARK: - Téléchargement

    /// Ouvre le panneau système où se téléchargent les voix.
    ///
    /// Les voix Améliorées et Premium ne sont pas installées par défaut ; une
    /// fois téléchargées, elles deviennent visibles pour l'application. Les voix
    /// Siri, elles, restent réservées au système, quelle qu'en soit la
    /// signature.
    static func ouvrirTelechargementVoix() {
        let adresses = [
            "x-apple.systempreferences:com.apple.preference.universalaccess?spokenContent",
            "x-apple.systempreferences:com.apple.Accessibility-Settings.extension?Speech",
            "x-apple.systempreferences:com.apple.preference.universalaccess"
        ]

        for adresse in adresses {
            if let url = URL(string: adresse), NSWorkspace.shared.open(url) {
                return
            }
        }
        Journal.app.notice("Panneau des voix introuvable")
    }
}
