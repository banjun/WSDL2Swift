import UIKit
import BrightFutures

class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "WSDL2Swift Example"
        view.backgroundColor = .white

        // codes depend on exampleWSDLs you place
        // this example use tempconvert.asmx.xml on http://www.w3schools.com/xml/tempconvert.asmx

        let service = TempConvert(endpoint: "http://www.w3schools.com")
        service.request(TempConvert_CelsiusToFahrenheit(Celsius: "23.4")).onComplete { r in
            NSLog("%@", "TempConvert_CelsiusToFahrenheit(Celsius: \"23.4\") = \(r)")
        }
}
