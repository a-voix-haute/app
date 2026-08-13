// Intégration de la commande de lecture aux assistants en ligne de commande.
//
// Deux conventions coexistent, et elles ne s'utilisent pas de la même façon :
//
//  - une commande est un fichier Markdown que l'utilisateur appelle lui-même,
//    en tapant /lire ;
//  - une compétence est un dossier contenant un SKILL.md, que l'assistant
//    charge de sa propre initiative lorsque la demande s'y prête. Codex et
//    Cursor n'ont pas de /lire : on leur demande de lire à voix haute, et ils
//    trouvent la compétence.
//
// Le corps du fichier diffère en conséquence : la commande décrit une marche à
// suivre, la compétence décrit surtout les situations qui la justifient.

import Foundation

/// Un assistant en ligne de commande susceptible d'accueillir la commande.
struct AssistantIA: Identifiable, Hashable {

    enum Format {
        /// Dossier par compétence, contenant un SKILL.md.
        case skill
        /// Fichier Markdown unique, invocable par une barre oblique.
        case commande
    }

    let id: String
    let nom: String
    /// Dossier de configuration dont la présence atteste l'installation.
    let dossierConfiguration: String
    /// Dossier où déposer la commande, relatif au dossier personnel.
    let dossierCible: String
    let format: Format
    /// Ce que l'utilisateur tapera une fois l'installation faite, pour une
    /// commande. Vide pour une compétence, qui se déclenche d'elle-même.
    let invocation: String

    /// Comment se sert-on de la commande, une fois installée ?
    ///
    /// Une commande s'appelle explicitement ; une compétence est proposée par
    /// l'assistant lorsqu'il juge qu'elle répond à la demande. La distinction
    /// mérite d'être affichée : chercher un `/lire` inexistant est déroutant.
    var modeEmploi: String {
        switch format {
        case .commande:
            return tr("terminal.tapez", invocation)
        case .skill:
            return tr("terminal.automatique")
        }
    }

    var cheminConfiguration: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(dossierConfiguration)
    }

    var cheminCible: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(dossierCible)
    }

    /// Emplacement final du fichier installé.
    var cheminFichier: URL {
        switch format {
        case .skill:    return cheminCible.appendingPathComponent("lire/SKILL.md")
        case .commande: return cheminCible.appendingPathComponent("lire.md")
        }
    }

    /// L'assistant est-il installé sur cette machine ?
    var estPresent: Bool {
        FileManager.default.fileExists(atPath: cheminConfiguration.path)
    }

    /// La commande y est-elle installée ?
    var commandeInstallee: Bool {
        FileManager.default.fileExists(atPath: cheminFichier.path)
    }
}

@MainActor
enum IntegrationIA {

    /// Assistants pris en charge.
    ///
    /// Deux conventions coexistent. Les assistants qui reconnaissent les
    /// commandes par barre oblique reçoivent un simple fichier Markdown ; ceux
    /// qui gèrent des compétences reçoivent un dossier contenant un SKILL.md,
    /// dont l'en-tête leur indique quand s'en servir d'eux-mêmes.
    ///
    /// La liste est volontairement large : un assistant absent n'apparaît que
    /// dans la rubrique « non détectés », sans nuisance.
    static let assistants: [AssistantIA] = [
        AssistantIA(
            id: "claude",
            nom: "Claude Code",
            dossierConfiguration: ".claude",
            dossierCible: ".claude/commands",
            format: .commande,
            invocation: "/lire"
        ),
        AssistantIA(
            id: "codex",
            nom: "Codex",
            dossierConfiguration: ".codex",
            dossierCible: ".codex/skills",
            format: .skill,
            invocation: ""
        ),
        AssistantIA(
            id: "cursor",
            nom: "Cursor",
            dossierConfiguration: ".cursor",
            dossierCible: ".cursor/skills",
            format: .skill,
            invocation: ""
        ),
        AssistantIA(
            id: "gemini",
            nom: "Gemini CLI",
            dossierConfiguration: ".gemini",
            dossierCible: ".gemini/commands",
            format: .commande,
            invocation: "/lire"
        ),
        AssistantIA(
            id: "grok",
            nom: "Grok CLI",
            dossierConfiguration: ".grok",
            dossierCible: ".grok/commands",
            format: .commande,
            invocation: "/lire"
        ),
        AssistantIA(
            id: "opencode",
            nom: "OpenCode",
            dossierConfiguration: ".config/opencode",
            dossierCible: ".config/opencode/command",
            format: .commande,
            invocation: "/lire"
        ),
        AssistantIA(
            id: "goose",
            nom: "Goose",
            dossierConfiguration: ".config/goose",
            dossierCible: ".config/goose/skills",
            format: .skill,
            invocation: ""
        ),
        AssistantIA(
            id: "crush",
            nom: "Crush",
            dossierConfiguration: ".config/crush",
            dossierCible: ".config/crush/commands",
            format: .commande,
            invocation: "/lire"
        ),
        AssistantIA(
            id: "amp",
            nom: "Amp",
            dossierConfiguration: ".config/amp",
            dossierCible: ".config/amp/skills",
            format: .skill,
            invocation: ""
        ),
        AssistantIA(
            id: "copilot",
            nom: "GitHub Copilot CLI",
            dossierConfiguration: ".config/github-copilot",
            dossierCible: ".config/github-copilot/prompts",
            format: .commande,
            invocation: "/lire"
        ),
        AssistantIA(
            id: "aider",
            nom: "Aider",
            dossierConfiguration: ".aider",
            dossierCible: ".aider/commands",
            format: .commande,
            invocation: "/lire"
        ),
        AssistantIA(
            id: "q",
            nom: "Amazon Q",
            dossierConfiguration: ".aws/amazonq",
            dossierCible: ".aws/amazonq/prompts",
            format: .commande,
            invocation: "@lire"
        )
    ]

    /// Assistants effectivement installés sur cette machine.
    static var assistantsPresents: [AssistantIA] {
        assistants.filter(\.estPresent)
    }

    // MARK: - Installation

    enum ResultatInstallation {
        case installee
        case echec(String)
    }

    @discardableResult
    static func installer(dans assistant: AssistantIA) -> ResultatInstallation {
        let fichier = assistant.cheminFichier

        do {
            try FileManager.default.createDirectory(
                at: fichier.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contenu(pour: assistant).write(to: fichier, atomically: true, encoding: .utf8)
            Journal.fichier("integration", "commande installée pour \(assistant.nom)")
            return .installee
        } catch {
            Journal.fichier("integration", "échec pour \(assistant.nom) : \(error.localizedDescription)")
            return .echec(error.localizedDescription)
        }
    }

    @discardableResult
    static func desinstaller(de assistant: AssistantIA) -> Bool {
        let fichier = assistant.cheminFichier
        guard FileManager.default.fileExists(atPath: fichier.path) else { return true }

        do {
            try FileManager.default.removeItem(at: fichier)
            // Pour une compétence, le dossier qui la contenait n'a plus d'objet.
            if assistant.format == .skill {
                let dossier = fichier.deletingLastPathComponent()
                if let restants = try? FileManager.default.contentsOfDirectory(atPath: dossier.path),
                   restants.isEmpty {
                    try? FileManager.default.removeItem(at: dossier)
                }
            }
            Journal.fichier("integration", "commande retirée de \(assistant.nom)")
            return true
        } catch {
            Journal.fichier("integration", "retrait impossible : \(error.localizedDescription)")
            return false
        }
    }

    /// Installe la commande dans tous les assistants détectés.
    @discardableResult
    static func installerPartout() -> Int {
        var nombre = 0
        for assistant in assistantsPresents where installerEstUnSucces(assistant) {
            nombre += 1
        }
        return nombre
    }

    private static func installerEstUnSucces(_ assistant: AssistantIA) -> Bool {
        if case .installee = installer(dans: assistant) { return true }
        return false
    }

    // MARK: - Contenu

    /// Texte de la commande, adapté au format de l'assistant et à la langue.
    ///
    /// Les textes vivent dans des fichiers Markdown localisés plutôt que dans le
    /// code : ils font une soixantaine de lignes chacun, et un littéral Swift
    /// multiligne les rendrait illisibles. macOS choisit le fichier selon la
    /// langue du système, exactement comme pour le reste de l'interface.
    static func contenu(pour assistant: AssistantIA) -> String {
        let nom = assistant.format == .commande ? "commande-lire" : "competence-lire"

        guard let chemin = Bundle.main.path(forResource: nom, ofType: "md"),
              let texte = try? String(contentsOfFile: chemin, encoding: .utf8) else {
            Journal.fichier("integration", "texte \(nom) introuvable dans le bundle")
            return ""
        }
        return texte
    }
}
