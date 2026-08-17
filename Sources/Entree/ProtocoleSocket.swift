// Protocole d'échange entre le helper `lire` et l'application.
//
// Un socket de domaine Unix a été retenu parce qu'il accepte des textes de
// taille arbitraire : NSDistributedNotificationCenter abandonne silencieusement
// les charges utiles volumineuses, et une URL corrompt ou tronque les longs
// textes. Mesuré ici : 110 Ko d'UTF-8 transmis sans altération.
//
// Trame : quatre octets de longueur en grand-boutiste, puis la charge JSON.
// Le préfixe de longueur est indispensable — un flux TCP ne préserve pas les
// frontières de messages, une lecture pouvant en livrer un fragment ou deux
// messages accolés.

import Foundation

enum ProtocoleSocket {

    /// Emplacement du socket.
    ///
    /// Sous « Application Support » plutôt que dans le dossier temporaire : le
    /// chemin doit rester stable entre les redémarrages pour que le helper le
    /// retrouve, et il doit être court, `sun_path` étant limité à 104 octets.
    static var cheminSocket: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("AVoixHaute", isDirectory: true)
            .appendingPathComponent("avoixhaute.sock")
            .path
    }

    /// Taille maximale acceptée pour un message, garde-fou contre un client
    /// défaillant qui annoncerait une longueur aberrante.
    static let tailleMaximale = 16 * 1024 * 1024

    // MARK: - Messages

    enum TypeCommande: String, Codable {
        case lire
        case arreter
        case ping
    }

    struct Requete: Codable {
        let commande: TypeCommande
        var texte: String?
        var titre: String?
        var source: String?
    }

    struct Reponse: Codable {
        let succes: Bool
        var message: String?
        /// Nombre de lectures et de synthèses interrompues par `arreter`.
        ///
        /// Optionnel : une version antérieure du helper ne l'envoie pas, et
        /// une réponse sans ce champ reste décodable.
        var interrompues: Int?
    }

    // MARK: - Encodage de trame

    /// Préfixe les données de leur longueur sur quatre octets grand-boutistes.
    static func encadrer(_ charge: Data) -> Data {
        var trame = Data(capacity: charge.count + 4)
        let longueur = UInt32(charge.count).bigEndian
        withUnsafeBytes(of: longueur) { trame.append(contentsOf: $0) }
        trame.append(charge)
        return trame
    }

    /// Lit exactement `nombre` octets, en bouclant tant que le compte n'y est
    /// pas : `read` peut en livrer moins que demandé.
    static func lireExactement(_ descripteur: Int32, nombre: Int) -> Data? {
        guard nombre > 0, nombre <= tailleMaximale else { return nil }
        var tampon = [UInt8](repeating: 0, count: nombre)
        var recu = 0

        while recu < nombre {
            let lus = tampon.withUnsafeMutableBytes { pointeur -> Int in
                guard let base = pointeur.baseAddress else { return -1 }
                return read(descripteur, base.advanced(by: recu), nombre - recu)
            }
            if lus > 0 {
                recu += lus
            } else if lus == 0 {
                return nil // connexion fermée par le pair
            } else if errno == EINTR {
                continue   // interruption par un signal : on réessaie
            } else {
                return nil
            }
        }

        return Data(tampon)
    }

    /// Lit une trame complète : longueur puis charge utile.
    static func lireTrame(_ descripteur: Int32) -> Data? {
        guard let entete = lireExactement(descripteur, nombre: 4) else { return nil }
        let longueur = entete.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        guard longueur > 0, Int(longueur) <= tailleMaximale else { return nil }
        return lireExactement(descripteur, nombre: Int(longueur))
    }

    /// Écrit l'intégralité des données, en bouclant sur les écritures partielles.
    @discardableResult
    static func ecrireTout(_ descripteur: Int32, _ donnees: Data) -> Bool {
        var envoye = 0
        let total = donnees.count

        return donnees.withUnsafeBytes { pointeur -> Bool in
            guard let base = pointeur.baseAddress else { return false }
            while envoye < total {
                let ecrits = write(descripteur, base.advanced(by: envoye), total - envoye)
                if ecrits > 0 {
                    envoye += ecrits
                } else if ecrits < 0 && errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
    }
}

/// Client minimal, employé quand une seconde instance doit passer la main.
///
/// Le helper en ligne de commande a son propre client, dans `SourcesCLI` : les
/// deux cibles ne partagent pas de module. Celui-ci reste volontairement
/// réduit — il envoie et n'attend rien, l'instance destinataire se charge de
/// la suite.
enum ClientSocket {

    /// Demande une lecture à l'instance déjà lancée.
    ///
    /// L'écriture est synchrone et brève : quelques centaines d'octets sur un
    /// socket local, juste avant que le processus ne se termine. La déléguer à
    /// une tâche risquerait de voir le processus disparaître avant l'envoi.
    @discardableResult
    static func envoyerLecture(_ texte: String, titre: String? = nil, source: String) -> Bool {
        let chemin = ProtocoleSocket.cheminSocket
        guard FileManager.default.fileExists(atPath: chemin) else { return false }

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
        guard connecte == 0 else { return false }

        let requete = ProtocoleSocket.Requete(
            commande: .lire,
            texte: texte,
            titre: titre,
            source: source
        )
        guard let charge = try? JSONEncoder().encode(requete) else { return false }
        guard ProtocoleSocket.ecrireTout(descripteur, ProtocoleSocket.encadrer(charge)) else {
            return false
        }

        // La réponse est attendue, et pas seulement l'écriture : `ecrireTout`
        // rend la main dès que les octets sont dans le tampon du noyau, bien
        // avant que le serveur ne les ait lus. L'appelant terminant le
        // processus juste après, sans cette attente la requête partirait avec
        // lui.
        //
        // L'attente n'est pas une condition de succès : le serveur répond
        // avant de lancer la lecture, et une réponse perdue ne signifie donc
        // pas que la requête l'a été. L'écriture ayant abouti, on rend `true`
        // quoi qu'il advienne ensuite — le seul rôle de cette lecture est de
        // retenir le processus le temps que le serveur consomme la trame.
        var delai = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(descripteur, SOL_SOCKET, SO_RCVTIMEO, &delai, socklen_t(MemoryLayout<timeval>.size))
        _ = ProtocoleSocket.lireTrame(descripteur)
        return true
    }
}
