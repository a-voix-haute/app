// Service macOS : « Lire à voix haute » dans le menu Services.
//
// C'est le canal qui remplace le raccourci système « Énoncer la sélection » :
// on sélectionne du texte dans n'importe quelle application, clic droit, et la
// lecture démarre — mais dans un lecteur dont la vitesse reste ajustable.
//
// La signature de la méthode est imposée par AppKit et doit être exposée à
// l'Objective-C ; son nom correspond à la clé NSMessage de l'Info.plist.

import AppKit

final class FournisseurService: NSObject {

    /// Point d'entrée déclaré par `NSMessage` dans l'Info.plist.
    ///
    /// - Parameters:
    ///   - pboard: presse-papiers privé contenant la sélection de l'utilisateur.
    ///   - userData: valeur de `NSUserData`, inutilisée ici.
    ///   - error: message rapporté à l'utilisateur si la lecture est impossible.
    @objc func lireSelection(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString>?
    ) {
        guard let texte = pboard.string(forType: .string),
              !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error?.pointee = "Aucun texte sélectionné." as NSString
            return
        }

        Journal.fichier("service", "sélection reçue : \(texte.count) caractères")

        Task { @MainActor in
            GestionnaireLecteurs.partage.demanderLecture(
                texte: texte,
                source: .service
            )
        }
    }

    // MARK: - Enregistrement

    /// Déclare le fournisseur auprès du système.
    ///
    /// `NSUpdateDynamicServices` demande à macOS de relire les services
    /// déclarés. En développement, l'application changeant d'emplacement à
    /// chaque compilation, il faut en plus la réenregistrer auprès de
    /// LaunchServices — ce que fait `Scripts/enregistrer_service.sh`.
    @MainActor
    static func installer() {
        let fournisseur = FournisseurService()
        NSApp.servicesProvider = fournisseur

        // Retenu par l'application : NSApp ne conserve pas son fournisseur.
        stockage = fournisseur

        NSUpdateDynamicServices()
        Journal.fichier("service", "fournisseur de services enregistré")
    }

    @MainActor private static var stockage: FournisseurService?
}
