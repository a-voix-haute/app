// Recherche et installation des mises à jour.
//
// Les versions publiées sont lues depuis l'API publique de GitHub. Le dépôt est
// public, aucune authentification n'est donc nécessaire — et il ne faut surtout
// pas en embarquer : un jeton inclus dans une application distribuée est lisible
// par quiconque en ouvre le binaire.
//
// La mise à jour n'est jamais installée sans accord : l'utilisateur voit ce qui
// change avant de décider.

import AppKit
import Foundation

/// Une version disponible au téléchargement.
struct VersionDisponible {
    let version: String
    let notes: String
    let adresseTelechargement: URL
    let taille: Int
    let datePublication: Date
}

@MainActor
@Observable
final class VerificateurMiseAJour {

    static let partage = VerificateurMiseAJour()

    /// Dépôt public consulté. Il n'expose que des releases, aucune donnée
    /// personnelle ne transite.
    private static let depot = "a-voix-haute/app"

    private static let adresseAPI = URL(
        string: "https://api.github.com/repos/\(depot)/releases/latest"
    )!

    enum Etat: Equatable {
        case inactif
        case verification
        case aJour
        case disponible(String)
        case telechargement(Double)
        case pretAInstaller
        case echec(String)
    }

    private(set) var etat: Etat = .inactif
    private(set) var versionDisponible: VersionDisponible?

    private var minuteur: Timer?
    private var fichierTelecharge: URL?

    private init() {}

    // MARK: - Version installée

    /// Version de l'application en cours d'exécution.
    ///
    /// `nonisolated` : simple lecture de l'Info.plist, sans état partagé.
    nonisolated static var versionInstallee: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    // MARK: - Vérification périodique

    /// Démarre la surveillance : une vérification maintenant, puis chaque jour.
    ///
    /// L'application restant lancée des semaines durant, une vérification au
    /// seul démarrage laisserait passer les versions.
    func demarrerSurveillance() {
        guard Reglages.partage.miseAJourAutomatique else { return }

        Task { await verifier(silencieux: true) }

        minuteur?.invalidate()
        minuteur = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { _ in
            Task { @MainActor in
                await VerificateurMiseAJour.partage.verifier(silencieux: true)
            }
        }
    }

    func arreterSurveillance() {
        minuteur?.invalidate()
        minuteur = nil
    }

    // MARK: - Vérification

    /// Interroge GitHub et compare à la version installée.
    ///
    /// - Parameter silencieux: en mode silencieux, aucune fenêtre n'apparaît si
    ///   l'application est à jour ou si le réseau est indisponible. Une
    ///   vérification déclenchée par l'utilisateur, elle, doit toujours répondre.
    func verifier(silencieux: Bool) async {
        etat = .verification

        do {
            let version = try await interrogerDerniereVersion()

            guard Self.estPlusRecente(version.version, que: Self.versionInstallee) else {
                etat = .aJour
                Journal.fichier("maj", "à jour : \(Self.versionInstallee)")
                if !silencieux { afficherDejaAJour() }
                return
            }

            versionDisponible = version
            etat = .disponible(version.version)
            Journal.fichier("maj", "version \(version.version) disponible")

            FenetreMiseAJour.partage.afficher(version: version)

        } catch {
            etat = .echec(error.localizedDescription)
            Journal.fichier("maj", "vérification impossible : \(error.localizedDescription)")
            if !silencieux { afficherEchec(error) }
        }
    }

    private func interrogerDerniereVersion() async throws -> VersionDisponible {
        var requete = URLRequest(url: Self.adresseAPI)
        requete.timeoutInterval = 15
        // En-tête recommandé par GitHub : sans lui, l'API peut renvoyer une
        // représentation différente selon les évolutions futures.
        requete.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        requete.setValue("AVoixHaute/\(Self.versionInstallee)", forHTTPHeaderField: "User-Agent")

        let (donnees, reponse) = try await URLSession.shared.data(for: requete)

        guard let http = reponse as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (reponse as? HTTPURLResponse)?.statusCode ?? 0
            throw ErreurMiseAJour.reponseInattendue(code)
        }

        guard let objet = try JSONSerialization.jsonObject(with: donnees) as? [String: Any],
              let tag = objet["tag_name"] as? String,
              let actifs = objet["assets"] as? [[String: Any]] else {
            throw ErreurMiseAJour.reponseIllisible
        }

        // Le disque d'installation est le seul actif qui nous intéresse.
        guard let disque = actifs.first(where: {
            ($0["name"] as? String)?.hasSuffix(".dmg") == true
        }),
        let adresse = disque["browser_download_url"] as? String,
        let url = URL(string: adresse) else {
            throw ErreurMiseAJour.aucunDisque
        }

        let formateur = ISO8601DateFormatter()
        let date = (objet["published_at"] as? String).flatMap(formateur.date(from:)) ?? Date()

        return VersionDisponible(
            version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
            notes: (objet["body"] as? String) ?? "",
            adresseTelechargement: url,
            taille: (disque["size"] as? Int) ?? 0,
            datePublication: date
        )
    }

    // MARK: - Comparaison de versions

    /// Compare deux versions sémantiques, segment par segment.
    ///
    /// Une comparaison de chaînes donnerait « 1.10.0 » < « 1.9.0 », d'où ce
    /// découpage numérique.
    nonisolated static func estPlusRecente(_ candidate: String, que reference: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        let b = reference.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }

        for index in 0..<max(a.count, b.count) {
            let gauche = index < a.count ? a[index] : 0
            let droite = index < b.count ? b[index] : 0
            if gauche != droite { return gauche > droite }
        }
        return false
    }

    // MARK: - Téléchargement et installation

    /// Télécharge le disque, vérifie sa signature, puis remplace l'application.
    func installer(_ version: VersionDisponible) async {
        do {
            etat = .telechargement(0)
            let disque = try await telecharger(version)
            fichierTelecharge = disque

            etat = .pretAInstaller
            try verifierSignature(disque)
            try await remplacerApplication(depuis: disque)

            // Le remplacement a réussi : l'application redémarre sur la
            // nouvelle version.
            redemarrer()

        } catch {
            etat = .echec(error.localizedDescription)
            Journal.fichier("maj", "installation échouée : \(error.localizedDescription)")
            afficherEchec(error)
        }
    }

    private func telecharger(_ version: VersionDisponible) async throws -> URL {
        let (fichier, reponse) = try await URLSession.shared.download(
            from: version.adresseTelechargement
        )

        guard let http = reponse as? HTTPURLResponse, http.statusCode == 200 else {
            throw ErreurMiseAJour.telechargementEchoue
        }

        // Le fichier temporaire d'URLSession disparaît au retour : on le déplace
        // dans notre propre dossier de travail.
        let destination = GestionnaireFichiersTemp.dossier
            .appendingPathComponent("AVoixHaute-\(version.version).dmg")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: fichier, to: destination)

        Journal.fichier("maj", "disque téléchargé : \(destination.lastPathComponent)")
        return destination
    }

    /// Refuse tout disque qui ne serait pas signé par notre identité.
    ///
    /// Sans cette vérification, une réponse détournée pourrait faire installer
    /// n'importe quel binaire à la place de la mise à jour.
    private func verifierSignature(_ disque: URL) throws {
        let processus = Process()
        processus.executableURL = URL(fileURLWithPath: "/usr/sbin/spctl")
        processus.arguments = [
            "-a", "-t", "open",
            "--context", "context:primary-signature",
            disque.path
        ]
        let sortie = Pipe()
        processus.standardError = sortie
        processus.standardOutput = Pipe()

        try processus.run()
        let donnees = sortie.fileHandleForReading.readDataToEndOfFile()
        processus.waitUntilExit()

        let message = String(data: donnees, encoding: .utf8) ?? ""

        guard processus.terminationStatus == 0,
              message.contains("accepted"),
              message.contains("Notarized Developer ID") else {
            Journal.fichier("maj", "signature refusée : \(message)")
            throw ErreurMiseAJour.signatureInvalide
        }

        Journal.fichier("maj", "signature et notarisation vérifiées")
    }

    private func remplacerApplication(depuis disque: URL) async throws {
        let montage = try monter(disque)
        defer { demonter(montage) }

        let contenu = try FileManager.default.contentsOfDirectory(atPath: montage.path)
        guard let nomApp = contenu.first(where: { $0.hasSuffix(".app") }) else {
            throw ErreurMiseAJour.applicationIntrouvable
        }

        let source = montage.appendingPathComponent(nomApp)
        let destination = Bundle.main.bundleURL

        // L'application ne peut pas se remplacer elle-même pendant qu'elle
        // s'exécute : la copie passe par un emplacement voisin, et un script
        // détaché fait la permutation après notre sortie.
        let intermediaire = destination.deletingLastPathComponent()
            .appendingPathComponent(".AVoixHaute-nouvelle.app")

        try? FileManager.default.removeItem(at: intermediaire)
        try FileManager.default.copyItem(at: source, to: intermediaire)

        try lancerPermutation(nouvelle: intermediaire, ancienne: destination)
    }

    private func monter(_ disque: URL) throws -> URL {
        let processus = Process()
        processus.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        processus.arguments = ["attach", disque.path, "-nobrowse", "-readonly", "-plist"]

        let sortie = Pipe()
        processus.standardOutput = sortie
        processus.standardError = Pipe()

        try processus.run()
        let donnees = sortie.fileHandleForReading.readDataToEndOfFile()
        processus.waitUntilExit()

        guard processus.terminationStatus == 0,
              let plist = try? PropertyListSerialization.propertyList(
                  from: donnees, format: nil
              ) as? [String: Any],
              let entites = plist["system-entities"] as? [[String: Any]],
              let point = entites.compactMap({ $0["mount-point"] as? String }).first else {
            throw ErreurMiseAJour.montageEchoue
        }

        return URL(fileURLWithPath: point)
    }

    private func demonter(_ montage: URL) {
        let processus = Process()
        processus.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        processus.arguments = ["detach", montage.path, "-quiet"]
        processus.standardOutput = Pipe()
        processus.standardError = Pipe()
        try? processus.run()
        processus.waitUntilExit()
    }

    /// Prépare un script qui remplacera l'application après notre sortie.
    ///
    /// Le script attend la fin du processus courant, permute les dossiers, puis
    /// relance l'application et s'efface.
    private func lancerPermutation(nouvelle: URL, ancienne: URL) throws {
        let script = GestionnaireFichiersTemp.dossier
            .appendingPathComponent("permuter-\(UUID().uuidString).sh")

        let contenu = """
        #!/bin/bash
        # Remplace l'application après la sortie du processus qui l'a lancé.
        set -e

        PID=$1
        NOUVELLE="$2"
        ANCIENNE="$3"

        # Attendre que l'application se soit vraiment terminée.
        for _ in $(seq 1 100); do
            kill -0 "$PID" 2>/dev/null || break
            sleep 0.1
        done

        rm -rf "$ANCIENNE"
        mv "$NOUVELLE" "$ANCIENNE"

        # Réenregistrer : le service et l'URL scheme pointent vers le bundle.
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$ANCIENNE" 2>/dev/null || true
        /System/Library/CoreServices/pbs -flush 2>/dev/null || true

        open "$ANCIENNE"
        rm -f "$0"
        """

        try contenu.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: script.path
        )

        let processus = Process()
        processus.executableURL = URL(fileURLWithPath: "/bin/bash")
        processus.arguments = [
            script.path,
            String(ProcessInfo.processInfo.processIdentifier),
            nouvelle.path,
            ancienne.path
        ]
        try processus.run()

        Journal.fichier("maj", "permutation programmée")
    }

    private func redemarrer() {
        // Le script attend notre sortie : il suffit de quitter proprement.
        NSApp.terminate(nil)
    }

    // MARK: - Messages

    private func afficherDejaAJour() {
        let alerte = NSAlert()
        alerte.messageText = tr("maj.aJourTitre")
        alerte.informativeText = tr("maj.aJourMessage", Self.versionInstallee)
        alerte.alertStyle = .informational
        alerte.addButton(withTitle: tr("erreur.fermer"))
        NSApp.activate(ignoringOtherApps: true)
        alerte.runModal()
    }

    private func afficherEchec(_ erreur: Error) {
        let alerte = NSAlert()
        alerte.messageText = tr("maj.echecTitre")
        alerte.informativeText = erreur.localizedDescription
        alerte.alertStyle = .warning
        alerte.addButton(withTitle: tr("erreur.fermer"))
        NSApp.activate(ignoringOtherApps: true)
        alerte.runModal()
    }
}

// MARK: - Erreurs

enum ErreurMiseAJour: LocalizedError {
    case reponseInattendue(Int)
    case reponseIllisible
    case aucunDisque
    case telechargementEchoue
    case signatureInvalide
    case montageEchoue
    case applicationIntrouvable

    var errorDescription: String? {
        switch self {
        case .reponseInattendue(let code):
            return tr("maj.erreur.reponse", code)
        case .reponseIllisible:
            return tr("maj.erreur.illisible")
        case .aucunDisque:
            return tr("maj.erreur.aucunDisque")
        case .telechargementEchoue:
            return tr("maj.erreur.telechargement")
        case .signatureInvalide:
            return tr("maj.erreur.signature")
        case .montageEchoue:
            return tr("maj.erreur.montage")
        case .applicationIntrouvable:
            return tr("maj.erreur.applicationIntrouvable")
        }
    }
}
