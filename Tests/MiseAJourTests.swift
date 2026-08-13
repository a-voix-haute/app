import XCTest
@testable import AVoixHaute

/// La comparaison de versions décide si une mise à jour est proposée : une
/// erreur ici ferait soit manquer une version, soit en proposer une plus
/// ancienne.
final class ComparaisonVersionsTests: XCTestCase {

    private func plusRecente(_ a: String, _ b: String) -> Bool {
        VerificateurMiseAJour.estPlusRecente(a, que: b)
    }

    func testVersionSuperieure() {
        XCTAssertTrue(plusRecente("1.1.0", "1.0.0"))
        XCTAssertTrue(plusRecente("2.0.0", "1.9.9"))
        XCTAssertTrue(plusRecente("1.0.1", "1.0.0"))
    }

    func testVersionInferieure() {
        XCTAssertFalse(plusRecente("1.0.0", "1.1.0"))
        XCTAssertFalse(plusRecente("1.9.9", "2.0.0"))
    }

    func testVersionIdentique() {
        XCTAssertFalse(plusRecente("1.0.0", "1.0.0"))
        XCTAssertFalse(plusRecente("2.5.3", "2.5.3"))
    }

    /// Le piège d'une comparaison de chaînes : « 1.10.0 » y serait inférieur à
    /// « 1.9.0 », puisque « 1 » précède « 9 ».
    func testDeuxChiffresApresLePoint() {
        XCTAssertTrue(plusRecente("1.10.0", "1.9.0"))
        XCTAssertTrue(plusRecente("1.0.10", "1.0.9"))
        XCTAssertTrue(plusRecente("10.0.0", "9.0.0"))
        XCTAssertFalse(plusRecente("1.9.0", "1.10.0"))
    }

    func testNombreDeSegmentsDifferent() {
        XCTAssertTrue(plusRecente("1.1", "1.0.9"))
        XCTAssertFalse(plusRecente("1.0", "1.0.0"))
        XCTAssertTrue(plusRecente("2", "1.9.9"))
    }

    /// Les tags portent un « v » que le module retire avant de comparer ; on
    /// vérifie qu'un résidu ne fausserait pas le résultat.
    func testSuffixesNonNumeriques() {
        XCTAssertTrue(plusRecente("1.1.0-beta", "1.0.0"))
        XCTAssertFalse(plusRecente("1.0.0-beta", "1.0.0"))
    }

    func testVersionInstalleeEstLisible() {
        let version = VerificateurMiseAJour.versionInstallee
        XCTAssertFalse(version.isEmpty)
        // Au moins un chiffre : « 0.0.0 » est le repli, pas une chaîne vide.
        XCTAssertTrue(version.contains(where: \.isNumber))
    }
}
