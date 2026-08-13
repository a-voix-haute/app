// Point d'entrée de Lecteur.
//
// L'application est de type .accessory : aucune icône dans le Dock, aucune
// entrée dans Cmd+Tab. Elle ne se manifeste que par ses fenêtres flottantes et
// son élément de barre de menus.

import AppKit

// Le code de premier niveau d'un main.swift ne s'exécute pas sur le MainActor
// aux yeux du compilateur ; l'assertion le lui indique, ce qui est exact ici
// puisque ce fichier constitue le point d'entrée du processus.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)

    let delegue = DelegueApplication()
    application.delegate = delegue

    // Conservé en vie pour toute la durée du processus : NSApplication ne
    // retient pas son délégué.
    objc_setAssociatedObject(application, "delegueLecteur", delegue, .OBJC_ASSOCIATION_RETAIN)

    application.run()
}
