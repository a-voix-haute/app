// lire — helper en ligne de commande pour À Voix Haute
//
//     lire fichier.md          lit un fichier
//     pbpaste | lire           lit l'entrée standard
//     echo "texte" | lire      idem
//     lire --stop              arrête toutes les lectures en cours
//
// Le texte transite par un socket de domaine Unix, sans limite de taille.
// L'application est lancée automatiquement si elle ne tourne pas encore.
//
// La commande est installée sous six noms — lire, read-aloud, leer, vorlesen,
// leggi, ler — qui pointent tous sur ce binaire, et ses messages suivent la
// langue du système. Les noms et les options, eux, restent identiques partout :
// ce sont des identifiants à taper, pas du texte à lire.

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
            .appendingPathComponent("AVoixHaute", isDirectory: true)
            .appendingPathComponent("avoixhaute.sock")
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
        var interrompues: Int?
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
        processus.arguments = ["-b", "app.avoixhaute.player"]
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
                erreur(Messages.lancementImpossible)
                return nil
            }
            descripteur = connecter()
        }

        guard let actif = descripteur else {
            erreur(Messages.connexionImpossible)
            return nil
        }
        defer { close(actif) }

        guard let charge = try? JSONEncoder().encode(requete) else { return nil }
        guard Protocole.ecrireTout(actif, Protocole.encadrer(charge)) else {
            erreur(Messages.envoiInterrompu)
            return nil
        }

        guard let reponseBrute = Protocole.lireTrame(actif) else { return nil }
        return try? JSONDecoder().decode(Protocole.Reponse.self, from: reponseBrute)
    }
}

// MARK: - Sortie

/// Nom sous lequel la commande a été appelée.
///
/// La commande est installée sous six noms — `lire`, `read-aloud`, `leer`,
/// `vorlesen`, `leggi`, `ler` — qui pointent tous sur ce binaire. Reprendre
/// celui qu'a tapé l'utilisateur évite une aide qui parlerait d'une autre
/// commande que la sienne.
let nomCommande = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "lire"

/// Langue retenue pour les messages, parmi les six que couvre l'application.
///
/// Le helper est une cible distincte du bundle : il n'a accès ni à
/// `Localizable.strings` ni à `tr()`, d'où ces textes intégrés. Le repli est le
/// français, langue de développement du projet.
let langue: String = {
    let preferee = Locale.preferredLanguages.first ?? "fr"
    let code = String(preferee.prefix(2))
    return ["fr", "en", "es", "de", "it", "pt"].contains(code) ? code : "fr"
}()

func erreur(_ message: String) {
    FileHandle.standardError.write("\(nomCommande) : \(message)\n".data(using: .utf8)!)
}

/// Messages d'erreur, dans la langue du système.
enum Messages {
    static var fichierIllisible: String {
        switch langue {
        case "en": return "unreadable file"
        case "es": return "archivo ilegible"
        case "de": return "Datei nicht lesbar"
        case "it": return "file illeggibile"
        case "pt": return "ficheiro ilegível"
        default:   return "fichier illisible"
        }
    }

    static var lecturesArretees: String {
        switch langue {
        case "en": return "playback stopped"
        case "es": return "lecturas detenidas"
        case "de": return "Wiedergabe gestoppt"
        case "it": return "letture interrotte"
        case "pt": return "leituras paradas"
        default:   return "lectures arrêtées"
        }
    }

    static var aucuneLecture: String {
        switch langue {
        case "en": return "no playback in progress"
        case "es": return "ninguna lectura en curso"
        case "de": return "keine Wiedergabe aktiv"
        case "it": return "nessuna lettura in corso"
        case "pt": return "nenhuma leitura em curso"
        default:   return "aucune lecture en cours"
        }
    }

    static var lancementImpossible: String {
        switch langue {
        case "en": return "could not launch À Voix Haute"
        case "es": return "imposible iniciar À Voix Haute"
        case "de": return "À Voix Haute konnte nicht gestartet werden"
        case "it": return "impossibile avviare À Voix Haute"
        case "pt": return "impossível iniciar À Voix Haute"
        default:   return "impossible de lancer À Voix Haute"
        }
    }

    static var connexionImpossible: String {
        switch langue {
        case "en": return "could not connect to the socket"
        case "es": return "conexión al socket imposible"
        case "de": return "Verbindung zum Socket nicht möglich"
        case "it": return "connessione al socket impossibile"
        case "pt": return "ligação ao socket impossível"
        default:   return "connexion au socket impossible"
        }
    }

    static var envoiInterrompu: String {
        switch langue {
        case "en": return "transfer interrupted"
        case "es": return "envío interrumpido"
        case "de": return "Übertragung abgebrochen"
        case "it": return "invio interrotto"
        case "pt": return "envio interrompido"
        default:   return "envoi interrompu"
        }
    }

    static var echec: String {
        switch langue {
        case "en": return "failed"
        case "es": return "fallo"
        case "de": return "fehlgeschlagen"
        case "it": return "errore"
        case "pt": return "falha"
        default:   return "échec"
        }
    }
}

func afficherAide() {
    let n = nomCommande

    let corps: String
    switch langue {
    case "en":
        corps = """
        \(n) — read text aloud with À Voix Haute

        Usage:
          \(n) <file>          read a file's contents
          \(n) --stop          stop all playback in progress
          \(n) --help          show this help

          … | \(n)             read standard input

        Examples:
          pbpaste | \(n)
          \(n) ~/notes.md
          echo "Hello" | \(n)
        """
    case "es":
        corps = """
        \(n) — lectura en voz alta con À Voix Haute

        Uso:
          \(n) <archivo>       lee el contenido de un archivo
          \(n) --stop          detiene todas las lecturas en curso
          \(n) --help          muestra esta ayuda

          … | \(n)             lee la entrada estándar

        Ejemplos:
          pbpaste | \(n)
          \(n) ~/notas.md
          echo "Hola" | \(n)
        """
    case "de":
        corps = """
        \(n) — Text vorlesen mit À Voix Haute

        Verwendung:
          \(n) <Datei>         liest den Inhalt einer Datei
          \(n) --stop          bricht alle laufenden Wiedergaben ab
          \(n) --help          zeigt diese Hilfe

          … | \(n)             liest die Standardeingabe

        Beispiele:
          pbpaste | \(n)
          \(n) ~/notizen.md
          echo "Hallo" | \(n)
        """
    case "it":
        corps = """
        \(n) — lettura ad alta voce con À Voix Haute

        Uso:
          \(n) <file>          legge il contenuto di un file
          \(n) --stop          interrompe tutte le letture in corso
          \(n) --help          mostra questo aiuto

          … | \(n)             legge lo standard input

        Esempi:
          pbpaste | \(n)
          \(n) ~/note.md
          echo "Ciao" | \(n)
        """
    case "pt":
        corps = """
        \(n) — leitura em voz alta com À Voix Haute

        Utilização:
          \(n) <ficheiro>      lê o conteúdo de um ficheiro
          \(n) --stop          para todas as leituras em curso
          \(n) --help          mostra esta ajuda

          … | \(n)             lê a entrada padrão

        Exemplos:
          pbpaste | \(n)
          \(n) ~/notas.md
          echo "Olá" | \(n)
        """
    default:
        corps = """
        \(n) — lecture audio de texte par À Voix Haute

        Usage :
          \(n) <fichier>       lit le contenu d'un fichier
          \(n) --stop          arrête toutes les lectures en cours
          \(n) --help          affiche cette aide

          … | \(n)             lit l'entrée standard

        Exemples :
          pbpaste | \(n)
          \(n) ~/notes.md
          echo "Bonjour" | \(n)
        """
    }

    // Les alias sont listés tels quels : ce sont des identifiants à taper,
    // identiques sur toutes les machines.
    print("""
    \(corps)

      lire · read-aloud · leer · vorlesen · leggi · ler
      --stop · --arreter · --parar · --stopp · --ferma
    """)
}

// MARK: - Point d'entrée

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case "--help", "-h", "--aide", "--ayuda", "--hilfe", "--aiuto", "--ajuda":
    afficherAide()

case "--stop", "-s", "--arreter", "--arrêter", "--parar", "--stopp", "--ferma":
    // Inutile de lancer l'application pour lui demander de se taire.
    if let descripteur = Client.connecter() {
        defer { close(descripteur) }
        let requete = Protocole.Requete(commande: "arreter")

        // Le message vient de la réponse et non du seul fait que
        // l'application ait répondu : elle tourne souvent sans rien lire, et
        // annoncer un arrêt dans ce cas serait faux.
        var interrompu = false
        if let charge = try? JSONEncoder().encode(requete) {
            Protocole.ecrireTout(descripteur, Protocole.encadrer(charge))
            if let brute = Protocole.lireTrame(descripteur),
               let reponse = try? JSONDecoder().decode(Protocole.Reponse.self, from: brute) {
                // Le champ prime ; le repli sur le message couvre une
                // application antérieure qui ne l'enverrait pas.
                interrompu = reponse.interrompues.map { $0 > 0 }
                    ?? (reponse.message == "lectures arrêtées")
            }
        }
        print(interrompu ? Messages.lecturesArretees : Messages.aucuneLecture)
    } else {
        print(Messages.aucuneLecture)
    }

default:
    var texte: String?
    var titre: String?

    if let chemin = arguments.first, !chemin.hasPrefix("-") {
        let url = URL(fileURLWithPath: (chemin as NSString).expandingTildeInPath)
        guard let contenu = try? String(contentsOf: url, encoding: .utf8) else {
            erreur("\(Messages.fichierIllisible) — \(chemin)")
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
        erreur(reponse.message ?? Messages.echec)
        exit(1)
    }
}
