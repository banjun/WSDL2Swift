import XCTest
import WSDL2Swift
import JetToTheFuture
import Mockingjay
import OHHTTPStubs
import AEXML

@testable import iOSWSDL2Swift

extension XCTest {
    @discardableResult
    public func stub<S: WSDLService, T: XSDType, R: XSDType>(_ service: S, _ type: T.Type, _ response: R) -> Stub {
        return stub(
            service.stubMatcher(type),
            service.stubBuilder(response))
    }
}

private let optionsForNamespaceRemoving: AEXMLOptions = {
    var options = AEXMLOptions()
    options.parserSettings.shouldProcessNamespaces = true
    options.parserSettings.shouldReportNamespacePrefixes = false
    return options
}()

extension WSDLService {
    func stubMatcher<T: XSDType>(_ type: T.Type, dataModifier: @escaping (Data) -> Data = {$0}) -> Matcher {
        return { request in
            let body = (request as NSURLRequest).ohhttpStubs_HTTPBody()
            guard let data = body.map(dataModifier),
                let xml = try? AEXMLDocument(xml: data, options: optionsForNamespaceRemoving) else { return false }

            let typeName = String(describing: type)
            let typeSuffix = typeName.components(separatedBy: "_").last ?? typeName

            return (uri(self.endpoint + self.path)(request) &&
                xml["Envelope"]["Body"][typeSuffix].first != nil)
        }
    }

    func stubBuilder<R: XSDType>(_ response: R, dataModifier: @escaping (Data) -> Data = {$0}) -> Builder {
        let targetNamespace = self.targetNamespace
        return { request in
            let soapResponse = response.soapRequest(targetNamespace)
            guard let data = soapResponse.xml.data(using: .utf8) else {
                return .failure(NSError(domain: "", code: 0, userInfo: nil))
            }
            return http(200, headers: [:], download: .content(dataModifier(data)))(request)
        }
    }
}

class iOSWSDL2SwiftTests: XCTestCase {
    let service = TempConvert(endpoint: "/")

    func testTempConvert_CelsiusToFahrenheit() {
        stub(service,
             TempConvert_CelsiusToFahrenheit.self,
             TempConvert_CelsiusToFahrenheitResponse(CelsiusToFahrenheitResult: "999"))

        let r = forcedFuture {self.service.request(TempConvert_CelsiusToFahrenheit(Celsius: "30"))}
        XCTAssertNotNil(r.value)
        XCTAssertEqual(r.value?.CelsiusToFahrenheitResult, "999")
    }
}
