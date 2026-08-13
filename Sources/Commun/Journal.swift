// Journalisation centralisée.
//
// Les messages sont visibles dans Console.app en filtrant sur le sous-système,
// ou en ligne de commande :
//
//     log stream --predicate 'subsystem == "fr.dimitri.Lecteur"' --level debug

import Foundation
import os

enum Journal {
    private static let sousSysteme = "fr.dimitri.Lecteur"

    static let app = Logger(subsystem: sousSysteme, category: "app")
    static let synthese = Logger(subsystem: sousSysteme, category: "synthese")
    static let lecture = Logger(subsystem: sousSysteme, category: "lecture")
    static let entree = Logger(subsystem: sousSysteme, category: "entree")
    static let fichiers = Logger(subsystem: sousSysteme, category: "fichiers")
}
