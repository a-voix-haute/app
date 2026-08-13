// Intégration de la commande de lecture aux assistants en ligne de commande.
//
// Claude Code, Codex et Cursor partagent le même format : un dossier par
// compétence, contenant un fichier SKILL.md dont l'en-tête déclare un nom et
// une description. Une seule définition suffit donc pour les trois.
//
// Claude Code accepte en outre les commandes simples — un fichier Markdown dans
// ~/.claude/commands — invocables par /lire. Les deux formes coexistent sans se
// gêner ; la commande est conservée car elle est plus directe à l'usage.

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
    /// Ce que l'utilisateur tapera une fois l'installation faite.
    let invocation: String

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
            invocation: "« lis ceci à voix haute »"
        ),
        AssistantIA(
            id: "cursor",
            nom: "Cursor",
            dossierConfiguration: ".cursor",
            dossierCible: ".cursor/skills",
            format: .skill,
            invocation: "« lis ceci à voix haute »"
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
            invocation: "« lis ceci à voix haute »"
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
            invocation: "« lis ceci à voix haute »"
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

    /// Texte de la commande, adapté au format de l'assistant.
    static func contenu(pour assistant: AssistantIA) -> String {
        switch assistant.format {
        case .commande: return commandeMarkdown
        case .skill:    return competenceMarkdown
        }
    }

    /// Format « commande » : invoquée explicitement par l'utilisateur.
    private static let commandeMarkdown = """
    Lit un texte à voix haute dans le lecteur flottant d'À Voix Haute.

    Le Markdown est nettoyé avant la synthèse : ni croisillons, ni astérisques,
    ni URL prononcées. Le lecteur reste au-dessus des autres fenêtres, même en
    plein écran, et sa vitesse s'ajuste en cours d'écoute sans que la voix monte
    dans les aigus.

    ## Comportement

    Choisis la source selon ce que contient `$ARGUMENTS` :

    **Sans argument** — lis ta dernière réponse, dans son intégralité et telle
    que tu l'as écrite en Markdown :

    ```bash
    cat <<'TEXTE' | lire
    <ta dernière réponse>
    TEXTE
    ```

    **Un chemin de fichier** :

    ```bash
    lire "$ARGUMENTS"
    ```

    **`presse-papiers`** :

    ```bash
    pbpaste | lire
    ```

    **`stop`** :

    ```bash
    lire --stop
    ```

    **Tout autre texte** — lis-le directement :

    ```bash
    cat <<'TEXTE' | lire
    $ARGUMENTS
    TEXTE
    ```

    ## Règles

    - N'annonce pas ce que tu vas faire : lance la commande, puis confirme en
      une ligne.
    - Pour ta dernière réponse, transmets le texte complet, sans le résumer.
      Le nettoyage du balisage est fait par l'application.
    - Si `lire` est introuvable, indique que l'application À Voix Haute doit
      être installée, et sa commande activée dans ses réglages.

    ## Exemples

    - `/lire` — écoute la dernière réponse
    - `/lire README.md` — écoute un fichier
    - `/lire presse-papiers` — écoute le presse-papiers
    - `/lire stop` — arrête toutes les lectures
    """

    /// Format « compétence » : l'assistant décide lui-même quand s'en servir,
    /// d'où une description centrée sur les situations d'usage.
    private static let competenceMarkdown = """
    ---
    name: lire
    description: Lit un texte à voix haute sur macOS, dans un lecteur audio flottant. À utiliser lorsque l'utilisateur demande d'écouter quelque chose, de lire à voix haute, de vocaliser un texte, ou dit qu'il préfère écouter plutôt que lire. Fonctionne avec la dernière réponse, un fichier, le presse-papiers ou un texte fourni.
    ---

    # Lire à voix haute

    La commande `lire` transmet du texte à l'application À Voix Haute, qui le
    synthétise et l'ouvre dans un lecteur flottant. Le balisage Markdown est
    retiré avant la lecture : ni croisillons, ni astérisques, ni URL prononcées.

    ## Utilisation

    Lire la dernière réponse — transmettre le texte complet, sans le résumer :

    ```bash
    cat <<'TEXTE' | lire
    <le texte à lire>
    TEXTE
    ```

    Lire un fichier :

    ```bash
    lire chemin/vers/document.md
    ```

    Lire le presse-papiers :

    ```bash
    pbpaste | lire
    ```

    Arrêter toutes les lectures :

    ```bash
    lire --stop
    ```

    ## À savoir

    - L'application se lance d'elle-même si elle ne tourne pas.
    - Le nettoyage du Markdown est fait par l'application : transmettre le texte
      brut, sans le préparer.
    - Ne pas annoncer l'action avant de la faire ; confirmer en une ligne après.
    - Si `lire` est introuvable, l'application À Voix Haute n'est pas installée,
      ou sa commande n'a pas été activée dans ses réglages.
    """
}
