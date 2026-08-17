// Serveur de socket : reçoit les demandes du helper `lire`.
//
// L'écoute repose sur un DispatchSource, ce qui évite d'immobiliser un thread
// en attente d'une connexion — le noyau réveille le processus quand un client
// se présente.

import Foundation

final class ServeurSocket {

    /// Appelé pour chaque demande de lecture reçue, sur la file principale.
    var surDemandeLecture: (@MainActor (String, String?, String?) -> Void)?

    /// Appelé pour chaque demande d'arrêt, sur la file principale.
    var surDemandeArret: (@MainActor () -> Int)?

    private var descripteurEcoute: Int32 = -1
    private var sourceEcoute: DispatchSourceRead?
    private let file = DispatchQueue(label: "app.avoixhaute.player.socket", qos: .userInitiated)

    // MARK: - Démarrage

    func demarrer() {
        let chemin = ProtocoleSocket.cheminSocket

        do {
            try FileManager.default.createDirectory(
                at: URL(fileURLWithPath: chemin).deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            Journal.entree.error("Dossier du socket impossible à créer : \(error.localizedDescription, privacy: .public)")
            return
        }

        // Un socket laissé par un arrêt brutal empêcherait bind() de réussir.
        // Mais avant de le supprimer, vérifier qu'aucune autre instance n'écoute
        // dessus : sans cette précaution, une seconde instance déroberait le
        // socket à la première, qui deviendrait injoignable.
        if FileManager.default.fileExists(atPath: chemin), Self.instanceActive(sur: chemin) {
            Journal.fichier("socket", "une autre instance écoute déjà — serveur non démarré")
            return
        }
        unlink(chemin)

        descripteurEcoute = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descripteurEcoute >= 0 else {
            Journal.entree.error("Création du socket impossible (errno \(errno))")
            return
        }

        var adresse = sockaddr_un()
        adresse.sun_family = sa_family_t(AF_UNIX)

        // sun_path est un tableau C de 104 octets : on le remplit octet par
        // octet, en réservant la place du terminateur.
        let octets = Array(chemin.utf8)
        let capacite = MemoryLayout.size(ofValue: adresse.sun_path) - 1
        guard octets.count <= capacite else {
            Journal.entree.error("Chemin du socket trop long (\(octets.count) > \(capacite))")
            fermer()
            return
        }
        withUnsafeMutablePointer(to: &adresse.sun_path) { pointeur in
            pointeur.withMemoryRebound(to: CChar.self, capacity: capacite + 1) { destination in
                for (index, octet) in octets.enumerated() {
                    destination[index] = CChar(bitPattern: octet)
                }
                destination[octets.count] = 0
            }
        }

        let taille = socklen_t(MemoryLayout<sockaddr_un>.size)
        let lie = withUnsafePointer(to: &adresse) { pointeur in
            pointeur.withMemoryRebound(to: sockaddr.self, capacity: 1) { adresseGenerique in
                bind(descripteurEcoute, adresseGenerique, taille)
            }
        }

        guard lie == 0 else {
            Journal.entree.error("bind() a échoué (errno \(errno))")
            fermer()
            return
        }

        // Le socket n'est accessible qu'à son propriétaire.
        chmod(chemin, 0o600)

        guard listen(descripteurEcoute, 8) == 0 else {
            Journal.entree.error("listen() a échoué (errno \(errno))")
            fermer()
            return
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: descripteurEcoute, queue: file)
        source.setEventHandler { [weak self] in self?.accepterConnexion() }
        source.setCancelHandler { [weak self] in
            guard let self, self.descripteurEcoute >= 0 else { return }
            close(self.descripteurEcoute)
            self.descripteurEcoute = -1
        }
        source.resume()
        sourceEcoute = source

        Journal.entree.info("Socket à l'écoute : \(chemin, privacy: .public)")
    }

    func arreter() {
        sourceEcoute?.cancel()
        sourceEcoute = nil
        unlink(ProtocoleSocket.cheminSocket)
    }

    private func fermer() {
        if descripteurEcoute >= 0 {
            close(descripteurEcoute)
            descripteurEcoute = -1
        }
    }

    /// Teste si une instance écoute déjà sur ce socket.
    ///
    /// Une simple connexion suffit : elle réussit tant qu'un serveur accepte,
    /// et échoue avec ECONNREFUSED sur un fichier de socket orphelin.
    private static func instanceActive(sur chemin: String) -> Bool {
        let descripteur = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descripteur >= 0 else { return false }
        defer { close(descripteur) }

        var adresse = sockaddr_un()
        adresse.sun_family = sa_family_t(AF_UNIX)

        let octets = Array(chemin.utf8)
        let capacite = MemoryLayout.size(ofValue: adresse.sun_path) - 1
        guard octets.count <= capacite else { return false }
        withUnsafeMutablePointer(to: &adresse.sun_path) { pointeur in
            pointeur.withMemoryRebound(to: CChar.self, capacity: capacite + 1) { destination in
                for (index, octet) in octets.enumerated() {
                    destination[index] = CChar(bitPattern: octet)
                }
                destination[octets.count] = 0
            }
        }

        let taille = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connecte = withUnsafePointer(to: &adresse) { pointeur in
            pointeur.withMemoryRebound(to: sockaddr.self, capacity: 1) { generique in
                connect(descripteur, generique, taille)
            }
        }

        return connecte == 0
    }

    // MARK: - Traitement

    private func accepterConnexion() {
        let client = accept(descripteurEcoute, nil, nil)
        guard client >= 0 else { return }

        // Chaque client est traité sur la file du serveur ; les échanges sont
        // brefs et séquentiels, un client ne peut donc pas bloquer les autres
        // durablement.
        file.async { [weak self] in
            defer { close(client) }
            self?.traiter(client: client)
        }
    }

    private func traiter(client: Int32) {
        guard let charge = ProtocoleSocket.lireTrame(client) else {
            Journal.entree.notice("Trame illisible ou connexion interrompue")
            return
        }

        let decodeur = JSONDecoder()
        guard let requete = try? decodeur.decode(ProtocoleSocket.Requete.self, from: charge) else {
            repondre(client, succes: false, message: "Requête illisible.")
            return
        }

        switch requete.commande {
        case .ping:
            repondre(client, succes: true, message: "prêt")

        case .arreter:
            // La réponse attend le compte : le helper distingue ainsi « rien
            // ne tournait » d'un arrêt réel. L'attente est brève — quelques
            // invalidations sur le MainActor — et le client, lui, attend déjà.
            let rappel = surDemandeArret
            let attente = DispatchSemaphore(value: 0)
            var interrompues = 0
            Task { @MainActor in
                interrompues = rappel?() ?? 0
                attente.signal()
            }
            // Le délai borne le cas où le MainActor serait bloqué : mieux vaut
            // une réponse imprécise qu'un client suspendu.
            _ = attente.wait(timeout: .now() + 5)
            repondre(
                client,
                succes: true,
                message: interrompues > 0 ? "lectures arrêtées" : "aucune lecture en cours",
                interrompues: interrompues
            )

        case .lire:
            guard let texte = requete.texte, !texte.isEmpty else {
                repondre(client, succes: false, message: "Aucun texte fourni.")
                return
            }
            Task { @MainActor in
                self.surDemandeLecture?(texte, requete.titre, requete.source)
            }
            repondre(client, succes: true, message: "\(texte.count) caractères reçus")
        }
    }

    private func repondre(
        _ client: Int32,
        succes: Bool,
        message: String?,
        interrompues: Int? = nil
    ) {
        let reponse = ProtocoleSocket.Reponse(
            succes: succes,
            message: message,
            interrompues: interrompues
        )
        guard let charge = try? JSONEncoder().encode(reponse) else { return }
        ProtocoleSocket.ecrireTout(client, ProtocoleSocket.encadrer(charge))
    }
}
