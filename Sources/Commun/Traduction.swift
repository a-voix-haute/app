// Accès aux chaînes traduites.
//
// L'application est traduite en six langues : français — langue de
// développement —, anglais, espagnol, allemand, italien et portugais. macOS
// choisit le catalogue d'après les préférences de langue du système, et retombe
// sur le français si aucune ne correspond.
//
// L'abréviation `tr` évite d'alourdir les vues : `tr("menu.reglages")` se lit
// mieux qu'un appel complet répété deux cents fois.

import Foundation
import SwiftUI

/// Chaîne traduite, désignée par sa clé.
func tr(_ cle: String) -> String {
    Bundle.main.localizedString(forKey: cle, value: nil, table: nil)
}

/// Chaîne traduite comportant des paramètres.
///
/// Les positions `%@` et `%d` sont conservées telles quelles dans chaque
/// catalogue ; une traduction peut en changer l'ordre en les numérotant
/// (`%1$@`, `%2$d`).
func tr(_ cle: String, _ arguments: CVarArg...) -> String {
    let modele = Bundle.main.localizedString(forKey: cle, value: nil, table: nil)
    return String(format: modele, locale: .current, arguments: arguments)
}

extension Text {
    /// Texte SwiftUI construit depuis une clé de traduction.
    init(cle: String) {
        self.init(verbatim: tr(cle))
    }
}
