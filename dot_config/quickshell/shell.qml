import Quickshell
import "components"
import "services"

Scope {
    StatusService {
        id: statusService
    }

    Variants {
        model: Quickshell.screens

        TopBar {
            service: statusService
        }

    }

}
