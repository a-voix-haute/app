// lire — helper en ligne de commande pour Lecteur.app
//
//     lire fichier.md          lit un fichier
//     pbpaste | lire           lit l'entrée standard
//     echo "texte" | lire      idem
//     lire --stop              arrête toutes les lectures en cours
//
// Le texte est transmis à l'application par socket de domaine Unix ; celle-ci
// est lancée automatiquement si elle ne tourne pas encore.
//
// L'implémentation du protocole arrive à l'étape 7 ; pour l'instant ce binaire
// se contente de valider ses arguments et de lire le texte en entrée.

import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())

func afficherAide() {
    print("""
    lire — lecture audio de texte

    Usage :
      lire <fichier>       lit le contenu d'un fichier
      lire --stop          arrête toutes les lectures
      lire --help          affiche cette aide

      … | lire             lit l'entrée standard

    Exemples :
      pbpaste | lire
      lire ~/notes.md
      echo "Bonjour" | lire
    """)
}

// Récupère le texte à lire : argument fichier, ou entrée standard.
func recupererTexte() -> String? {
    if let chemin = arguments.first, !chemin.hasPrefix("-") {
        let url = URL(fileURLWithPath: (chemin as NSString).expandingTildeInPath)
        guard let contenu = try? String(contentsOf: url, encoding: .utf8) else {
            FileHandle.standardError.write("lire : fichier illisible — \(chemin)\n".data(using: .utf8)!)
            exit(1)
        }
        return contenu
    }

    // Pas d'argument : lire stdin, sauf si le terminal est interactif.
    guard isatty(FileHandle.standardInput.fileDescriptor) == 0 else { return nil }
    let donnees = FileHandle.standardInput.readDataToEndOfFile()
    return String(data: donnees, encoding: .utf8)
}

switch arguments.first {
case "--help", "-h":
    afficherAide()

case "--stop":
    // Raccordé au socket à l'étape 7.
    print("lire : arrêt demandé")

default:
    guard let texte = recupererTexte(), !texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        afficherAide()
        exit(arguments.isEmpty ? 0 : 1)
    }
    // Envoi par socket à l'étape 7.
    print("lire : \(texte.count) caractères prêts à être transmis")
}
