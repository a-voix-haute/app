import XCTest
@testable import Lecteur

final class NettoyeurMarkdownTests: XCTestCase {

    // MARK: - Titres

    func testTitreDevientPhrase() {
        XCTAssertEqual(NettoyeurMarkdown.nettoyer("# Introduction"), "Introduction.")
        XCTAssertEqual(NettoyeurMarkdown.nettoyer("### Sous-partie"), "Sous-partie.")
    }

    func testTitreConserveSaPonctuation() {
        XCTAssertEqual(NettoyeurMarkdown.nettoyer("## Pourquoi ?"), "Pourquoi ?")
    }

    func testTitreFerme() {
        XCTAssertEqual(NettoyeurMarkdown.nettoyer("## Titre ##"), "Titre.")
    }

    func testDiereseSansEspaceNestPasUnTitre() {
        // #tag n'est pas un titre Markdown : le croisillon doit être conservé.
        XCTAssertEqual(NettoyeurMarkdown.nettoyer("#motclé"), "#motclé")
    }

    // MARK: - Emphase

    func testGrasEtItalique() {
        XCTAssertEqual(NettoyeurMarkdown.nettoyer("Texte **important** ici"),
                       "Texte important ici")
        XCTAssertEqual(NettoyeurMarkdown.nettoyer("Texte *accentué* ici"),
                       "Texte accentué ici")
        XCTAssertEqual(NettoyeurMarkdown.nettoyer("Du ***gras italique*** ici"),
                       "Du gras italique ici")
    }

    func testSoulignementDansUnIdentifiantEstPreserve() {
        // nom_de_variable ne doit pas être interprété comme de l'italique.
        XCTAssertEqual(NettoyeurMarkdown.nettoyer("La variable nom_de_variable existe"),
                       "La variable nom_de_variable existe")
    }

    func testBarre() {
        XCTAssertEqual(NettoyeurMarkdown.nettoyer("~~annulé~~ valide"), "annulé valide")
    }

    // MARK: - Code

    func testCodeEnLigneConserveSonContenu() {
        XCTAssertEqual(NettoyeurMarkdown.nettoyer("Appelle `maFonction()` pour cela"),
                       "Appelle maFonction() pour cela")
    }

    func testBlocDeCodeEstAnnonceEtNonLu() {
        let source = """
        Avant

        ```swift
        let x = 42
        print(x)
        ```

        Après
        """
        let resultat = NettoyeurMarkdown.nettoyer(source)
        XCTAssertTrue(resultat.contains("(bloc de code Swift)"), resultat)
        XCTAssertFalse(resultat.contains("let x = 42"), resultat)
        XCTAssertTrue(resultat.contains("Avant"))
        XCTAssertTrue(resultat.contains("Après"))
    }

    func testBlocDeCodeSansLangage() {
        let source = """
        ```
        du contenu
        ```
        """
        XCTAssertEqual(NettoyeurMarkdown.nettoyer(source), "(bloc de code)")
    }

    // MARK: - Liens et images

    func testLienConserveSonLibelle() {
        XCTAssertEqual(
            NettoyeurMarkdown.nettoyer("Voir [la documentation](https://exemple.fr/doc)"),
            "Voir la documentation"
        )
    }

    func testImageAvecTexteAlternatif() {
        XCTAssertEqual(
            NettoyeurMarkdown.nettoyer("![Schéma du flux](img/flux.png)"),
            "(image : Schéma du flux)"
        )
    }

    func testLienAutomatique() {
        XCTAssertEqual(NettoyeurMarkdown.nettoyer("Site <https://exemple.fr> ouvert"),
                       "Site (lien) ouvert")
    }

    // MARK: - Listes

    func testPuces() {
        let source = """
        - premier
        - deuxième
        """
        XCTAssertEqual(NettoyeurMarkdown.nettoyer(source), "premier.\ndeuxième.")
    }

    func testListeNumeroteeConserveLesNumeros() {
        let source = """
        1. étape une
        2. étape deux
        """
        XCTAssertEqual(NettoyeurMarkdown.nettoyer(source), "1. étape une.\n2. étape deux.")
    }

    func testCasesACocher() {
        let source = """
        - [x] terminé
        - [ ] restant
        """
        let resultat = NettoyeurMarkdown.nettoyer(source)
        XCTAssertTrue(resultat.contains("fait : terminé."), resultat)
        XCTAssertTrue(resultat.contains("à faire : restant."), resultat)
    }

    // MARK: - Structure

    func testCitation() {
        XCTAssertEqual(NettoyeurMarkdown.nettoyer("> une citation"), "une citation")
    }

    func testLigneHorizontaleDisparait() {
        let source = """
        Avant

        ---

        Après
        """
        let resultat = NettoyeurMarkdown.nettoyer(source)
        XCTAssertFalse(resultat.contains("---"), resultat)
        XCTAssertTrue(resultat.contains("Avant"))
        XCTAssertTrue(resultat.contains("Après"))
    }

    func testTableauDevientEnumeration() {
        let source = """
        | Nom | Rôle |
        |-----|------|
        | Marie | Cheffe |
        """
        let resultat = NettoyeurMarkdown.nettoyer(source)
        XCTAssertTrue(resultat.contains("Nom, Rôle."), resultat)
        XCTAssertTrue(resultat.contains("Marie, Cheffe."), resultat)
        XCTAssertFalse(resultat.contains("|"), resultat)
        XCTAssertFalse(resultat.contains("---"), resultat)
    }

    func testEnteteYAMLRetire() {
        let source = """
        ---
        title: Mon document
        auteur: Dimitri
        ---

        Le contenu réel.
        """
        let resultat = NettoyeurMarkdown.nettoyer(source)
        XCTAssertEqual(resultat, "Le contenu réel.")
    }

    // MARK: - HTML

    func testBalisesHTMLRetirees() {
        XCTAssertEqual(NettoyeurMarkdown.nettoyer("Un <strong>mot</strong> ici"),
                       "Un mot ici")
    }

    func testCommentaireHTMLRetire() {
        XCTAssertEqual(NettoyeurMarkdown.nettoyer("Visible <!-- caché --> aussi"),
                       "Visible aussi")
    }

    func testEntitesHTML() {
        XCTAssertEqual(NettoyeurMarkdown.nettoyer("Riz &amp; haricots"),
                       "Riz et haricots")
    }

    // MARK: - Espaces

    func testEspacesMultiplesReduits() {
        XCTAssertEqual(NettoyeurMarkdown.nettoyer("trop     d'espaces"),
                       "trop d'espaces")
    }

    func testLignesVidesLimitees() {
        let source = "Un\n\n\n\n\nDeux"
        XCTAssertEqual(NettoyeurMarkdown.nettoyer(source), "Un\n\nDeux")
    }

    // MARK: - Cas limites

    func testTexteVide() {
        XCTAssertEqual(NettoyeurMarkdown.nettoyer(""), "")
        XCTAssertEqual(NettoyeurMarkdown.nettoyer("   \n\n  "), "")
    }

    func testTexteSansMarkdownEstIntact() {
        let source = "Une phrase simple, sans aucun balisage."
        XCTAssertEqual(NettoyeurMarkdown.nettoyer(source), source)
    }

    func testAccentsPreserves() {
        let source = "**Où** sont les *élèves* ?"
        XCTAssertEqual(NettoyeurMarkdown.nettoyer(source), "Où sont les élèves ?")
    }

    // MARK: - Document complet

    func testDocumentRealiste() {
        let source = """
        # Guide d'installation

        Ce guide décrit l'installation de **Lecteur** sur macOS.

        ## Prérequis

        - macOS 14 ou supérieur
        - [Xcode](https://developer.apple.com/xcode/) installé

        ## Étapes

        1. Cloner le dépôt
        2. Lancer `make install`

        ```bash
        git clone https://exemple.fr/lecteur.git
        cd lecteur && make install
        ```

        > Note : l'autorisation Accessibilité est requise.
        """

        let resultat = NettoyeurMarkdown.nettoyer(source)

        // Aucun symbole de balisage ne subsiste.
        XCTAssertFalse(resultat.contains("#"), resultat)
        XCTAssertFalse(resultat.contains("**"), resultat)
        XCTAssertFalse(resultat.contains("```"), resultat)
        XCTAssertFalse(resultat.contains("]("), resultat)
        XCTAssertFalse(resultat.contains(">"), resultat)

        // Le contenu utile est préservé.
        XCTAssertTrue(resultat.contains("Guide d'installation."), resultat)
        XCTAssertTrue(resultat.contains("Lecteur"), resultat)
        XCTAssertTrue(resultat.contains("Xcode"), resultat)
        XCTAssertTrue(resultat.contains("(bloc de code shell)"), resultat)
        XCTAssertFalse(resultat.contains("git clone"), resultat)
    }
}
