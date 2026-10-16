// Clés d'API des moteurs distants, conservées dans le trousseau.
//
// Le trousseau plutôt que `UserDefaults` : une clé d'API ouvre un compte
// facturé, elle n'a pas sa place dans un fichier de préférences lisible par
// n'importe quel processus de la session. macOS la chiffre et la protège
// derrière l'authentification de l'utilisateur.
//
// Plusieurs clés coexistent, chacune nommée — « Perso », « Pro ». Le journal
// des appels retient laquelle a servi, ce qui permet de retrouver sur la
// console du fournisseur à quoi correspond une consommation.

import Foundation
import Security

/// Une clé enregistrée, désignée par un nom choisi par l'utilisateur.
struct CleAPI: Identifiable, Hashable, Codable {
    /// Identifiant stable, indépendant du nom : renommer ne perd pas la clé.
    let id: UUID
    var nom: String
    let fournisseur: String

    init(id: UUID = UUID(), nom: String, fournisseur: String = ClesAPI.fournisseurOpenAI) {
        self.id = id
        self.nom = nom
        self.fournisseur = fournisseur
    }
}

enum ClesAPI {

    static let fournisseurOpenAI = "openai"

    /// Service sous lequel les clés sont rangées dans le trousseau.
    private static let service = "app.avoixhaute.player.cles"

    // MARK: - Index des clés

    /// L'index — identifiants et noms — vit dans les préférences ; les secrets
    /// restent dans le trousseau. Rien d'exploitable ne fuit si le fichier de
    /// préférences est lu : il ne contient que des noms et des UUID.
    private static let cleIndex = "clesAPI"

    static func toutes(pour fournisseur: String = fournisseurOpenAI) -> [CleAPI] {
        guard let donnees = UserDefaults.standard.data(forKey: cleIndex),
              let index = try? JSONDecoder().decode([CleAPI].self, from: donnees)
        else { return [] }
        return index.filter { $0.fournisseur == fournisseur }
    }

    private static func enregistrerIndex(_ index: [CleAPI]) {
        guard let donnees = try? JSONEncoder().encode(index) else { return }
        UserDefaults.standard.set(donnees, forKey: cleIndex)
    }

    // MARK: - Clé active

    private static let cleActive = "cleAPIActive"

    /// Clé employée pour les appels, ou la première disponible à défaut.
    static func active(pour fournisseur: String = fournisseurOpenAI) -> CleAPI? {
        let disponibles = toutes(pour: fournisseur)
        guard let brut = UserDefaults.standard.string(forKey: cleActive),
              let identifiant = UUID(uuidString: brut),
              let trouvee = disponibles.first(where: { $0.id == identifiant })
        else { return disponibles.first }
        return trouvee
    }

    static func definirActive(_ cle: CleAPI?) {
        UserDefaults.standard.set(cle?.id.uuidString, forKey: cleActive)
    }

    // MARK: - Enregistrement

    /// Ajoute une clé, ou remplace le secret d'une clé existante.
    @discardableResult
    static func enregistrer(nom: String, secret: String,
                            fournisseur: String = fournisseurOpenAI) -> CleAPI? {
        let nettoye = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nettoye.isEmpty else { return nil }

        let cle = CleAPI(nom: nom, fournisseur: fournisseur)
        guard ecrireSecret(nettoye, pour: cle.id) else { return nil }

        var index = chargerIndexComplet()
        index.append(cle)
        enregistrerIndex(index)

        if active(pour: fournisseur) == nil { definirActive(cle) }
        Journal.fichier("cles", "clé ajoutée : \(nom)")
        return cle
    }

    static func renommer(_ cle: CleAPI, en nouveau: String) {
        var index = chargerIndexComplet()
        guard let position = index.firstIndex(where: { $0.id == cle.id }) else { return }
        index[position].nom = nouveau
        enregistrerIndex(index)
    }

    static func supprimer(_ cle: CleAPI) {
        effacerSecret(pour: cle.id)
        var index = chargerIndexComplet()
        index.removeAll { $0.id == cle.id }
        enregistrerIndex(index)

        // La clé active vient peut-être de disparaître : une autre prend sa
        // place, sans quoi les appels échoueraient sans raison visible.
        if active(pour: cle.fournisseur) == nil {
            definirActive(toutes(pour: cle.fournisseur).first)
        }
        Journal.fichier("cles", "clé supprimée : \(cle.nom)")
    }

    /// Secret associé à une clé, lu depuis le trousseau.
    static func secret(de cle: CleAPI) -> String? {
        lireSecret(pour: cle.id)
    }

    private static func chargerIndexComplet() -> [CleAPI] {
        guard let donnees = UserDefaults.standard.data(forKey: cleIndex),
              let index = try? JSONDecoder().decode([CleAPI].self, from: donnees)
        else { return [] }
        return index
    }

    // MARK: - Trousseau

    private static func requete(pour identifiant: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: identifiant.uuidString
        ]
    }

    private static func ecrireSecret(_ secret: String, pour identifiant: UUID) -> Bool {
        guard let donnees = secret.data(using: .utf8) else { return false }
        var ajout = requete(pour: identifiant)
        ajout[kSecValueData as String] = donnees
        // Accessible seulement quand la session est déverrouillée, et jamais
        // transférée vers un autre Mac par une sauvegarde.
        ajout[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        SecItemDelete(requete(pour: identifiant) as CFDictionary)
        return SecItemAdd(ajout as CFDictionary, nil) == errSecSuccess
    }

    private static func lireSecret(pour identifiant: UUID) -> String? {
        var recherche = requete(pour: identifiant)
        recherche[kSecReturnData as String] = true
        recherche[kSecMatchLimit as String] = kSecMatchLimitOne

        var resultat: CFTypeRef?
        guard SecItemCopyMatching(recherche as CFDictionary, &resultat) == errSecSuccess,
              let donnees = resultat as? Data
        else { return nil }
        return String(data: donnees, encoding: .utf8)
    }

    private static func effacerSecret(pour identifiant: UUID) {
        SecItemDelete(requete(pour: identifiant) as CFDictionary)
    }
}
