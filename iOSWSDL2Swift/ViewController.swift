import UIKit

class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "WSDL2Swift Example"
        view.backgroundColor = .white

        // codes depend on exampleWSDLs you place
        let auth = AuthenticationServiceService(endpoint: "https://examle.com")
        let login = auth.request(AuthenticationServiceService_login(arg0: "alice@example.com", arg1: "password"))
        login.onComplete { r in
            NSLog("%@", "result = \(r)")
        }
    }
}
