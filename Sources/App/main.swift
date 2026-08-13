// Point d'entrée de Lecteur.
//
// L'application est de type .accessory : aucune icône dans le Dock, aucune
// entrée dans Cmd+Tab. Elle ne se manifeste que par ses fenêtres flottantes et
// son élément de barre de menus.

import AppKit

let application = NSApplication.shared
application.setActivationPolicy(.accessory)

let delegue = DelegueApplication()
application.delegate = delegue

application.run()
