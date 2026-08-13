import XCTest
@testable import AVoixHaute

/// Les réglages sont testés sur un domaine dédié, pour ne pas écraser ceux de
/// l'utilisateur pendant l'exécution de la suite.
final class ReglagesTests: XCTestCase {

    private var domaine: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        domaine = "fr.dimitri.AVoixHaute.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: domaine)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: domaine)
        super.tearDown()
    }

    // MARK: - Bornes

    func testLimiteLecteursBorneeEntreUnEtDix() {
        defaults.set(0, forKey: "limiteLecteurs")
        XCTAssertEqual(min(max(defaults.integer(forKey: "limiteLecteurs"), 1), 10), 1)

        defaults.set(50, forKey: "limiteLecteurs")
        XCTAssertEqual(min(max(defaults.integer(forKey: "limiteLecteurs"), 1), 10), 10)

        defaults.set(5, forKey: "limiteLecteurs")
        XCTAssertEqual(min(max(defaults.integer(forKey: "limiteLecteurs"), 1), 10), 5)
    }

    // MARK: - Comportement

    func testComportementInvalideRetombeSurContinuer() {
        XCTAssertNil(ComportementNouvelleLecture(rawValue: "n'importe quoi"))
        XCTAssertEqual(ComportementNouvelleLecture(rawValue: "continuer"), .continuer)
        XCTAssertEqual(ComportementNouvelleLecture(rawValue: "mettreEnPause"), .mettreEnPause)
    }

    func testTousLesComportementsOntUnLibelle() {
        for cas in ComportementNouvelleLecture.allCases {
            XCTAssertFalse(cas.libelle.isEmpty)
        }
    }

    // MARK: - Moteurs

    func testMoteurInvalideRetombeSurSay() {
        XCTAssertNil(TypeMoteur(rawValue: "inconnu"))
        XCTAssertEqual(TypeMoteur(rawValue: "say"), .say)
        XCTAssertEqual(TypeMoteur(rawValue: "avSpeech"), .avSpeech)
    }

    func testQualiteVoixEstOrdonnee() {
        XCTAssertLessThan(QualiteVoix.compacte, QualiteVoix.amelioree)
        XCTAssertLessThan(QualiteVoix.amelioree, QualiteVoix.premium)
    }
}

final class VoixDisponibleTests: XCTestCase {

    func testCodeLangueExtraitLesDeuxPremieresLettres() {
        let voix = VoixDisponible(
            id: "Thomas", nom: "Thomas", langue: "fr-FR",
            qualite: .compacte, moteur: .say
        )
        XCTAssertEqual(voix.codeLangue, "fr")
    }

    func testDescriptionMasqueLaQualiteCompacte() {
        let compacte = VoixDisponible(
            id: "Thomas", nom: "Thomas", langue: "fr-FR",
            qualite: .compacte, moteur: .say
        )
        XCTAssertEqual(compacte.descriptionComplete, "Thomas")

        let premium = VoixDisponible(
            id: "Marie", nom: "Marie", langue: "fr-FR",
            qualite: .premium, moteur: .avSpeech
        )
        XCTAssertEqual(premium.descriptionComplete, "Marie (Premium)")
    }
}

final class DetecteurLangueTests: XCTestCase {

    func testDetecteLeFrancais() {
        let texte = "Voici un texte suffisamment long, écrit en français, "
                  + "afin que la détection automatique puisse se prononcer avec confiance."
        XCTAssertEqual(DetecteurLangue.detecter(texte, parDefaut: "en-US"), "fr-FR")
    }

    func testDetecteLAnglais() {
        let texte = "This is a reasonably long English sentence, written so that "
                  + "the language recognizer has enough material to be confident."
        XCTAssertEqual(DetecteurLangue.detecter(texte, parDefaut: "fr-FR"), "en-US")
    }

    func testTexteTropCourtGardeLaValeurParDefaut() {
        XCTAssertEqual(DetecteurLangue.detecter("Bonjour", parDefaut: "fr-FR"), "fr-FR")
        XCTAssertEqual(DetecteurLangue.detecter("", parDefaut: "de-DE"), "de-DE")
    }
}

final class FormatageLecteurTests: XCTestCase {

    func testFormatageDuree() {
        XCTAssertEqual(Lecteur.formaterDuree(0), "0:00")
        XCTAssertEqual(Lecteur.formaterDuree(9), "0:09")
        XCTAssertEqual(Lecteur.formaterDuree(75), "1:15")
        XCTAssertEqual(Lecteur.formaterDuree(3661), "1:01:01")
    }

    func testFormatageDureeInvalide() {
        XCTAssertEqual(Lecteur.formaterDuree(-5), "0:00")
        XCTAssertEqual(Lecteur.formaterDuree(.infinity), "0:00")
        XCTAssertEqual(Lecteur.formaterDuree(.nan), "0:00")
    }

    func testFormatageVitesseUtiliseLaVirguleFrancaise() {
        XCTAssertEqual(Lecteur.formaterVitesse(1.0), "1×")
        XCTAssertEqual(Lecteur.formaterVitesse(2.0), "2×")
        XCTAssertEqual(Lecteur.formaterVitesse(1.5), "1,5×")
        XCTAssertEqual(Lecteur.formaterVitesse(0.75), "0,75×")
    }

    func testLaListeDeVitessesEstCroissanteEtContientUn() {
        let vitesses = Lecteur.vitessesDisponibles
        XCTAssertEqual(vitesses, vitesses.sorted())
        XCTAssertTrue(vitesses.contains(1.0))
        XCTAssertEqual(vitesses.first, 0.5)
        XCTAssertEqual(vitesses.last, 3.0)
    }
}
