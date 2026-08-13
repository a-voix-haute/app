// lire — helper en ligne de commande pour Lecteur.app
//
//     lire fichier.md          lit un fichier
//     pbpaste | lire           lit l'entrée standard
//     echo "texte" | lire      idem
//     lire --stop              arrête toutes les lectures en cours
//
// Le texte transite par un socket de domaine Unix, sans limite de taille.
// L'application est lancée automatiquement si elle ne tourne pas encore.

import Foundation

// MARK: - Protocole
//
// Dupliqué depuis Sources/Entree/ProtocoleSocket.swift : les deux cibles ne
// partagent pas de module, et introduire une bibliothèque pour une trame de
// quatre octets coûterait plus qu'il ne rapporte. Toute modification doit être
// répercutée des deux côtés.

enum Protocole {
    static var cheminSocket: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Lecteur", isDirectory: true)
            .appendingPathComponent("lecteur.sock")
            .path
    }

    struct Requete: Codable {
        let commande: String
        var texte: String?
        var titre: String?
        var source: String?
    }

    struct Reponse: Codable {
        let succes: Bool
        var message: String?
    }

    static func encadrer(_ charge: Data) -> Data {
        var trame = Data(capacity: charge.count + 4)
        let longueur = UInt32(charge.count).bigEndian
        withUnsafeBytes(of: longueur) { trame.append(contentsOf: $0) }
        trame.append(charge)
        return trame
    }

    static func lireExactement(_ descripteur: Int32, nombre: Int) -> Data? {
        guard nombre > 0, nombre <= 16 * 1024 * 1024 else { return nil }
        var tampon = [UInt8](repeating: 0, count: nombre)
        var recu = 0
        while recu < nombre {
            let lus = tampon.withUnsafeMutableBytes { pointeur -> Int in
                guard let base = pointeur.baseAddress else { return -1 }
                return read(descripteur, base.advanced(by: recu), nombre - recu)
            }
            if lus > 0 { recu += lus }
            else if lus == 0 { return nil }
            else if errno == EINTR { continue }
            else { return nil }
        }
        return Data(tampon)
    }

    static func lireTrame(_ descripteur: Int32) -> Data? {
        guard let entete = lireExactement(descripteur, nombre: 4) else { return nil }
        let longueur = entete.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        return lireExactement(descripteur, nombre: Int(longueur))
    }

    @discardableResult
    static func ecrireTout(_ descripteur: Int32, _ donnees: Data) -> Bool {
        var envoye = 0
        let total = donnees.count
        return donnees.withUnsafeBytes { pointeur -> Bool in
            guard let base = pointeur.baseAddress else { return false }
            while envoye < total {
                let ecrits = write(descripteur, base.advanced(by: envoye), total - envoye)
                if ecrits > 0 { envoye += ecrits }
                else if ecrits < 0 && errno == EINTR { continue }
                else { return false }
            }
            return true
        }
    }
}

// MARK: - Client

enum Client {

    /// Ouvre une connexion au socket, ou renvoie nil si l'application n'écoute
    /// pas encore.
    static func connecter() -> Int32? {
        let chemin = Protocole.cheminSocket
        guard FileManager.default.fileExists(atPath: chemin) else { return nil }

        let descripteur = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descripteur >= 0 else { return nil }

        var adresse = sockaddr_un()
        adresse.sun_family = sa_family_t(AF_UNIX)

        let octets = Array(chemin.utf8)
        let capacite = MemoryLayout.size(ofValue: adresse.sun_path) - 1
        guard octets.count <= capacite else { close(descripteur); return nil }
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

        guard connecte == 0 else { close(descripteur); return nil }
        return descripteur
    }

    /// Lance l'application et attend que son socket réponde.
    ///
    /// L'attente est progressive : la plupart des lancements aboutissent en
    /// moins d'une seconde, mais un démarrage à froid demande davantage.
    static func lancerApplication() -> Bool {
        let processus = Process()
        processus.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        processus.arguments = ["-b", "fr.dimitri.Lecteur"]
        processus.standardOutput = Pipe()
        processus.standardError = Pipe()

        do {
            try processus.run()
            processus.waitUntilExit()
        } catch {
            return false
        }
        guard processus.terminationStatus == 0 else { return false }

        var attente: useconds_t = 100_000 // 0,1 s
        var cumul: Double = 0
        while cumul < 5.0 {
            usleep(attente)
            cumul += Double(attente) / 1_000_000
            if let descripteur = connecter() {
                close(descripteur)
                return true
            }
            attente = min(attente * 2, 500_000)
        }
        return false
    }

    /// Envoie une requête et renvoie la réponse de l'application.
    static func envoyer(_ requete: Protocole.Requete) -> Protocole.Reponse? {
        var descripteur = connecter()

        if descripteur == nil {
            guard lancerApplication() else {
                erreur("impossible de lancer Lecteur.app")
                return nil
            }
            descripteur = connecter()
        }

        guard let actif = descripteur else {
            erreur("connexion au socket impossible")
            return nil
        }
        defer { close(actif) }

        guard let charge = try? JSONEncoder().encode(requete) else { return nil }
        guard Protocole.ecrireTout(actif, Protocole.encadrer(charge)) else {
            erreur("envoi interrompu")
            return nil
        }

        guard let reponseBrute = Protocole.lireTrame(actif) else { return nil }
        return try? JSONDecoder().decode(Protocole.Reponse.self, from: reponseBrute)
    }
}

// MARK: - Sortie

func erreur(_ message: String) {
    FileHandle.standardError.write("lire : \(message)\n".data(using: .utf8)!)
}

func afficherAide() {
    print("""
    lire — lecture audio de texte par Lecteur.app

    Usage :
      lire <fichier>       lit le contenu d'un fichier
      lire --stop          arrête toutes les lectures en cours
      lire --help          affiche cette aide

      … | lire             lit l'entrée standard

    Exemples :
      pbpaste | lire
      lire ~/notes.md
      echo "Bonjour" | lire
      curl -s https://exemple.fr/article.md | lire
    """)
}

// MARK: - Point d'entrée

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case "--help", "-h":
    afficherAide()

case "--stop", "-s":
    // Inutile de lancer l'application pour lui demander de se taire.
    if let descripteur = Client.connecter() {
        defer { close(descripteur) }
        let requete = Protocole.Requete(commande: "arreter")
        if let charge = try? JSONEncoder().encode(requete) {
            Protocole.ecrireTout(descripteur, Protocole.encadrer(charge))
            _ = Protocole.lireTrame(descripteur)
        }
        print("lectures arrêtées")
    } else {
        print("aucune lecture en cours")
    }

default:
    var texte: String?
    var titre: String?

    if let chemin = arguments.first, !chemin.hasPrefix("-") {
        let url = URL(fileURLWithPath: (chemin as NSString).expandingTildeInPath)
        guard let contenu = try? String(contentsOf: url, encoding: .utf8) else {
            erreur("fichier illisible — \(chemin)")
            exit(1)
        }
        texte = contenu
        titre = url.lastPathComponent
    } else if isatty(FileHandle.standardInput.fileDescriptor) == 0 {
        let donnees = FileHandle.standardInput.readDataToEndOfFile()
        texte = String(data: donnees, encoding: .utf8)
    }

    guard let contenu = texte,
          !contenu.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        afficherAide()
        exit(arguments.isEmpty ? 0 : 1)
    }

    let requete = Protocole.Requete(
        commande: "lire",
        texte: contenu,
        titre: titre,
        source: "cli"
    )

    guard let reponse = Client.envoyer(requete) else { exit(1) }
    if !reponse.succes {
        erreur(reponse.message ?? "échec")
        exit(1)
    }
}
