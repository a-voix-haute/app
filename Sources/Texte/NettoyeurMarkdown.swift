// Conversion de Markdown en texte destiné à la synthèse vocale.
//
// L'objectif n'est pas de produire du texte brut fidèle, mais du texte qui
// s'écoute bien : le balisage disparaît, la ponctuation qui structure la lecture
// est conservée ou ajoutée.
//
// Trois principes guident les choix ci-dessous :
//
//  - un titre devient une phrase terminée par un point, pour que la voix marque
//    la pause qu'un lecteur humain ferait ;
//  - un bloc de code est annoncé mais non lu — énoncer du code caractère par
//    caractère est inaudible ;
//  - un lien conserve son libellé et perd son URL, qui ne s'écoute pas.

import Foundation

struct NettoyeurMarkdown {

    /// Transforme du Markdown en texte prêt pour la synthèse.
    static func nettoyer(_ source: String) -> String {
        var texte = source

        texte = normaliserRetoursLigne(texte)
        texte = retirerEnteteYAML(texte)
        texte = remplacerBlocsCode(texte)
        texte = retirerImages(texte)
        texte = aplatirLiens(texte)
        texte = simplifierTableaux(texte)
        texte = traiterLignes(texte)
        texte = retirerEmphase(texte)
        texte = retirerHTML(texte)
        texte = normaliserEspaces(texte)

        return texte.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Étapes

    private static func normaliserRetoursLigne(_ texte: String) -> String {
        texte.replacingOccurrences(of: "\r\n", with: "\n")
             .replacingOccurrences(of: "\r", with: "\n")
    }

    /// Retire l'en-tête YAML des fichiers Markdown qui en portent un.
    private static func retirerEnteteYAML(_ texte: String) -> String {
        guard texte.hasPrefix("---\n") else { return texte }
        let suite = texte.dropFirst(4)
        guard let fin = suite.range(of: "\n---\n") ?? suite.range(of: "\n---") else { return texte }
        return String(suite[fin.upperBound...])
    }

    /// Remplace chaque bloc de code par une annonce.
    ///
    /// Le contenu est écarté : lu à voix haute, il produit une bouillie de
    /// symboles. Le langage, quand il est indiqué, sert à formuler l'annonce.
    private static func remplacerBlocsCode(_ texte: String) -> String {
        let motif = try! NSRegularExpression(
            pattern: "^[ \\t]*```[ \\t]*([\\w+#-]*)[^\\n]*\\n(?:.*?\\n)??[ \\t]*```[ \\t]*$",
            options: [.dotMatchesLineSeparators, .anchorsMatchLines]
        )

        let resultat = NSMutableString(string: texte)
        let correspondances = motif.matches(
            in: texte,
            range: NSRange(texte.startIndex..., in: texte)
        ).reversed()

        for correspondance in correspondances {
            var annonce = "(bloc de code)"
            if correspondance.numberOfRanges > 1,
               let plage = Range(correspondance.range(at: 1), in: texte) {
                let langage = String(texte[plage])
                if !langage.isEmpty {
                    annonce = "(bloc de code \(nomLangage(langage)))"
                }
            }
            resultat.replaceCharacters(in: correspondance.range, with: annonce)
        }

        return resultat as String
    }

    /// Traduit les identifiants de langage courants en un nom prononçable.
    private static func nomLangage(_ identifiant: String) -> String {
        switch identifiant.lowercased() {
        case "js", "javascript":   return "JavaScript"
        case "ts", "typescript":   return "TypeScript"
        case "py", "python":       return "Python"
        case "rb", "ruby":         return "Ruby"
        case "sh", "bash", "zsh":  return "shell"
        case "php":                return "PHP"
        case "html":               return "HTML"
        case "css":                return "CSS"
        case "sql":                return "SQL"
        case "json":               return "JSON"
        case "yaml", "yml":        return "YAML"
        case "swift":              return "Swift"
        case "c", "cpp", "c++":    return "C"
        case "java":               return "Java"
        case "go":                 return "Go"
        case "rust", "rs":         return "Rust"
        default:                   return identifiant
        }
    }

    /// Retire les images en conservant le texte alternatif s'il est présent.
    private static func retirerImages(_ texte: String) -> String {
        remplacer(texte, motif: "!\\[([^\\]]*)\\]\\([^)]*\\)") { groupes in
            groupes.first?.isEmpty == false ? "(image : \(groupes[0]))" : "(image)"
        }
    }

    /// Conserve le libellé d'un lien, écarte l'URL.
    private static func aplatirLiens(_ texte: String) -> String {
        var resultat = remplacer(texte, motif: "\\[([^\\]]+)\\]\\([^)]*\\)") { $0[0] }
        // Liens de référence : [libellé][clé] et définitions [clé]: url
        resultat = remplacer(resultat, motif: "\\[([^\\]]+)\\]\\[[^\\]]*\\]") { $0[0] }
        resultat = remplacer(resultat, motif: "(?m)^\\[[^\\]]+\\]:[ \\t]*\\S+.*$") { _ in "" }
        // Liens automatiques <https://…> : une URL ne s'écoute pas.
        resultat = remplacer(resultat, motif: "<https?://[^>]+>") { _ in "(lien)" }
        return resultat
    }

    /// Réduit un tableau à ses cellules, séparées par des virgules.
    ///
    /// La ligne de séparation (|---|---|) est supprimée ; les autres lignes
    /// deviennent des énumérations, ce qui reste compréhensible à l'oreille.
    private static func simplifierTableaux(_ texte: String) -> String {
        texte.split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { ligne -> String? in
                let nettoyee = ligne.trimmingCharacters(in: .whitespaces)
                guard nettoyee.hasPrefix("|") else { return String(ligne) }

                // Ligne de séparation : uniquement -, :, | et espaces.
                let sansStructure = nettoyee.replacingOccurrences(
                    of: "[|:\\-\\s]", with: "", options: .regularExpression
                )
                if sansStructure.isEmpty { return nil }

                let cellules = nettoyee
                    .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    .split(separator: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }

                return cellules.isEmpty ? nil : cellules.joined(separator: ", ") + "."
            }
            .joined(separator: "\n")
    }

    /// Traite le balisage qui se situe en début de ligne.
    private static func traiterLignes(_ texte: String) -> String {
        var lignes: [String] = []

        for ligne in texte.split(separator: "\n", omittingEmptySubsequences: false) {
            var courante = String(ligne)
            let sansIndentation = courante.trimmingCharacters(in: .whitespaces)

            // Ligne horizontale : --- ou *** ou ___
            if sansIndentation.range(of: "^([-*_])\\1{2,}$", options: .regularExpression) != nil {
                lignes.append("")
                continue
            }

            // Titre ATX : # Titre → « Titre. »
            if let plage = sansIndentation.range(of: "^#{1,6}[ \\t]+", options: .regularExpression) {
                var contenu = String(sansIndentation[plage.upperBound...])
                contenu = contenu.replacingOccurrences(
                    of: "[ \\t]*#+[ \\t]*$", with: "", options: .regularExpression
                )
                lignes.append(ponctuer(contenu))
                continue
            }

            // Citation : > texte
            if let plage = sansIndentation.range(of: "^>[ \\t]?", options: .regularExpression) {
                courante = String(sansIndentation[plage.upperBound...])
                lignes.append(courante)
                continue
            }

            // Puce : -, *, + suivi d'un espace
            if let plage = sansIndentation.range(of: "^[-*+][ \\t]+", options: .regularExpression) {
                var contenu = String(sansIndentation[plage.upperBound...])
                // Case à cocher : - [ ] ou - [x]
                if let coche = contenu.range(of: "^\\[([ xX])\\][ \\t]*", options: .regularExpression) {
                    let cochee = contenu[coche].lowercased().contains("x")
                    contenu = String(contenu[coche.upperBound...])
                    lignes.append(ponctuer((cochee ? "fait : " : "à faire : ") + contenu))
                } else {
                    lignes.append(ponctuer(contenu))
                }
                continue
            }

            // Liste numérotée : 1. texte — le numéro est conservé, il porte du sens.
            if let plage = sansIndentation.range(of: "^(\\d+)[.)][ \\t]+", options: .regularExpression) {
                let numero = sansIndentation[plage].trimmingCharacters(
                    in: CharacterSet(charactersIn: " \t.)")
                )
                let contenu = String(sansIndentation[plage.upperBound...])
                lignes.append(ponctuer("\(numero). \(contenu)"))
                continue
            }

            lignes.append(courante)
        }

        return lignes.joined(separator: "\n")
    }

    /// Ajoute un point final si la ligne n'a pas déjà une ponctuation forte.
    ///
    /// C'est ce qui fait qu'un titre ou une puce s'entend comme une unité, avec
    /// une pause à la fin, plutôt que collé à la phrase suivante.
    private static func ponctuer(_ texte: String) -> String {
        let nettoye = texte.trimmingCharacters(in: .whitespaces)
        guard let dernier = nettoye.last else { return nettoye }
        return ".!?:;,".contains(dernier) ? nettoye : nettoye + "."
    }

    /// Retire l'emphase et le code en ligne, en conservant le contenu.
    private static func retirerEmphase(_ texte: String) -> String {
        var resultat = texte

        // Code en ligne : `code` — le contenu est conservé, il porte du sens
        // (nom de fonction, de fichier), contrairement à un bloc entier.
        resultat = remplacer(resultat, motif: "`{1,3}([^`\\n]+)`{1,3}") { $0[0] }

        // Gras et italique, du plus long au plus court pour éviter les résidus.
        for motif in ["\\*\\*\\*([^*\\n]+)\\*\\*\\*",
                      "___([^_\\n]+)___",
                      "\\*\\*([^*\\n]+)\\*\\*",
                      "__([^_\\n]+)__",
                      "\\*([^*\\n]+)\\*",
                      "(?<![\\w_])_([^_\\n]+)_(?![\\w_])"] {
            resultat = remplacer(resultat, motif: motif) { $0[0] }
        }

        // Barré : ~~texte~~
        resultat = remplacer(resultat, motif: "~~([^~\\n]+)~~") { $0[0] }

        return resultat
    }

    /// Retire les balises HTML éventuellement présentes dans le Markdown.
    private static func retirerHTML(_ texte: String) -> String {
        var resultat = remplacer(texte, motif: "<!--(?:.|\\n)*?-->") { _ in "" }
        resultat = remplacer(resultat, motif: "</?[a-zA-Z][^>]*>") { _ in "" }
        return resultat
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "et")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    /// Réduit les espaces multiples et limite les lignes vides consécutives.
    private static func normaliserEspaces(_ texte: String) -> String {
        var resultat = texte.replacingOccurrences(
            of: "[ \\t]+", with: " ", options: .regularExpression
        )
        resultat = resultat.replacingOccurrences(
            of: " *\\n *", with: "\n", options: .regularExpression
        )
        // Au-delà de deux sauts de ligne, la pause n'augmente plus.
        resultat = resultat.replacingOccurrences(
            of: "\\n{3,}", with: "\n\n", options: .regularExpression
        )
        return resultat
    }

    // MARK: - Utilitaire

    /// Applique une expression régulière en confiant le remplacement à une
    /// closure qui reçoit les groupes capturés.
    private static func remplacer(
        _ texte: String,
        motif: String,
        transformation: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: motif,
            options: [.dotMatchesLineSeparators]
        ) else { return texte }

        let resultat = NSMutableString(string: texte)
        let correspondances = regex.matches(
            in: texte,
            range: NSRange(texte.startIndex..., in: texte)
        ).reversed()

        for correspondance in correspondances {
            var groupes: [String] = []
            for index in 1..<correspondance.numberOfRanges {
                if let plage = Range(correspondance.range(at: index), in: texte) {
                    groupes.append(String(texte[plage]))
                } else {
                    groupes.append("")
                }
            }
            resultat.replaceCharacters(
                in: correspondance.range,
                with: transformation(groupes)
            )
        }

        return resultat as String
    }
}
