import Foundation
import AEXML
import Result
import BrightFutures
import ISO8601

// accessible from @testable
public protocol SOAPParamConvertible {
    func xmlElements(name: String) -> [AEXMLElement]
}

// accessible from @testable, adopted by _XSDType
public protocol XSDType: SOAPParamConvertible {}


public protocol WSDLService {
    var endpoint: String { get set }
    var path: String { get }
    var targetNamespace: String { get }
    var interceptURLRequest: ((URLRequest) -> URLRequest)? { get set }
    var interceptResponse: ((Data?, URLResponse?, Error?) -> (Data?, URLResponse?, Error?))? { get set }
    init(endpoint: String)
}

public enum WSDLOperationError: Error {
    case unknown
    case urlSession(Error)
    case invalidXML
    case invalidXMLContent
    case soapFault(SOAPMessage.Fault)
}


public struct SOAPMessage {
    public var header: Header?
    public var body: Body

    private let soapNameSpace: String
    private let targetNamespace: String

    public init?(xml: AEXMLDocument, targetNamespace: String) {
        guard let soapNameSpace = (xml.root.attributes.first {$0.key.hasPrefix("xmlns:") && $0.value == "http://schemas.xmlsoap.org/soap/envelope/"}?.key.components(separatedBy: ":").last),
            let body = Body(xml: xml[soapNameSpace + ":Envelope"][soapNameSpace + ":Body"], soapNameSpace: soapNameSpace, targetNamespace: targetNamespace) else {
                return nil // invalid soap message
        }
        self.targetNamespace = targetNamespace
        self.soapNameSpace = soapNameSpace
        self.body = body
    }

    public struct Header {
        // TODO
    }

    public struct Body {
        public var output: AEXMLElement? // first <(ns2):(name) xmlns:(ns2)="(targetNamespace)">...</...>
        public var fault: Fault?

        public var xml: AEXMLElement // for now, raw XML

        public init?(xml: AEXMLElement, soapNameSpace: String, targetNamespace: String) {
            var options = AEXMLOptions()
            options.parserSettings.shouldProcessNamespaces = true
            options.parserSettings.shouldReportNamespacePrefixes = false
            guard let namespaceRemovedXML = try? AEXMLDocument(xml: xml.xml, encoding: .utf8, options: options) else { return nil }
            self.xml = namespaceRemovedXML
            self.output = namespaceRemovedXML.root.children.first
            self.fault = Fault(xml: xml[soapNameSpace + ":Fault"])
        }
    }

    public struct Fault {
        // supports soap 1.1 (S:Fault xmlns:S="http://schemas.xmlsoap.org/soap/envelope/")
        var faultCode: String
        var faultString: String
        var faultActor: String?
        var detail: String?

        public init?(xml: AEXMLElement) {
            guard let faultCode = xml["faultcode"].value else { return nil } // faultcode MUST be present in a SOAP Fault element
            guard let faultString = xml["faultstring"].value else { return nil } // faultString MUST be present in a SOAP Fault element
            self.faultCode = faultCode
            self.faultString = faultString
            self.faultActor = xml["faultactor"].value
            self.detail = xml["detail"].value
        }
    }
}
