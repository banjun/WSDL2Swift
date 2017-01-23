import UIKit

class ViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "WSDL2Swift Example"
        view.backgroundColor = .white

        // codes depend on exampleWSDLs you place
        // this example use tempconvert.asmx.xml on http://www.w3schools.com/xml/tempconvert.asmx

        let service = Wsiv(endpoint: "http://www.ratp.fr/")
        service.request(Wsiv_getVersion()).onComplete { r in
            NSLog("%@", "Wsiv_getVersionRequest() = \(r)")
        }
        service.request(Wsiv_getStations(station: Wsiv_Station(direction: nil, geoPointA: nil, geoPointR: nil, id: "1975", idsNextA: [], idsNextR: [], line: nil, name: nil, stationArea: nil), gp: nil, distances: [], limit: 1, sortAlpha: nil)).onComplete { r in
            NSLog("%@", "Wsiv_getStations(...) = \(r)")
        }
    }
}
