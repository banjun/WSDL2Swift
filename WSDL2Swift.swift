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
public protocol XSDType: SOAPParamConvertible {
    // name, swiftName, xmlns
    var xmlParams: [(String, SOAPParamConvertible?, String)] { get }
}

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
        public var faultCode: String
        public var faultString: String
        public var faultActor: String?
        public var detail: String?

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

public protocol ExpressibleByXML {
    // returns:
    //  * Self: parse succeeded to an value
    //  * nil: parse succeeded to nil
    //  * SOAPParamError.unknown: parse failed
    init?(xml: AEXMLElement) throws // SOAPParamError
    init?(xmlValue: String) throws // SOAPParamError
}

extension ExpressibleByXML {
    // default implementation for primitive values
    // element nil check and text value empty check
    public init?(xml: AEXMLElement) throws {
        guard let value = xml.value else { return nil }
        guard !value.isEmpty else { return nil }
        try self.init(xmlValue: value)
    }
}

extension String: ExpressibleByXML, SOAPParamConvertible {
    public init?(xmlValue: String) {
        self.init(xmlValue)
    }

    public func xmlElements(name: String) -> [AEXMLElement] {
        return [AEXMLElement(name: name, value: self)]
    }
}
extension Bool: ExpressibleByXML, SOAPParamConvertible {
    public init?(xmlValue: String) throws {
        switch xmlValue.lowercased() {
        case "true": self = true
        case "false": self = false
        default: throw SOAPParamError.unknown
        }
    }
    public func xmlElements(name: String) -> [AEXMLElement] {
        return [AEXMLElement(name: name, value: self ? "true" : "false")]
    }
}
extension Int32: ExpressibleByXML, SOAPParamConvertible {
    public init?(xmlValue: String) throws {
        guard let v = Int32(xmlValue) else { throw SOAPParamError.unknown }
        self = v
    }
    public func xmlElements(name: String) -> [AEXMLElement] {
        return [AEXMLElement(name: name, value: String(self))]
    }
}
extension Int64: ExpressibleByXML, SOAPParamConvertible {
    public init?(xmlValue: String) throws {
        guard let v = Int64(xmlValue) else { throw SOAPParamError.unknown }
        self = v
    }
    public func xmlElements(name: String) -> [AEXMLElement] {
        return [AEXMLElement(name: name, value: String(self))]
    }
}
extension Date: ExpressibleByXML, SOAPParamConvertible {
    public init?(xmlValue: String) throws {
        guard let v = NSDate(iso8601String: xmlValue) as Date? else { throw SOAPParamError.unknown }
        self = v
    }
    public func xmlElements(name: String) -> [AEXMLElement] {
        return [AEXMLElement(name: name, value: (self as NSDate).iso8601String())]
    }
}
extension Data: ExpressibleByXML, SOAPParamConvertible {
    public init?(xmlValue: String) {
        self.init(base64Encoded: xmlValue)
    }
    public func xmlElements(name: String) -> [AEXMLElement] {
        return [AEXMLElement(name: name, value: base64EncodedString())]
    }
}
extension Array: SOAPParamConvertible { // Swift 3 does not yet support conditional protocol conformance (where Element: SOAPParamConvertible)
    public func xmlElements(name: String) -> [AEXMLElement] {
        var a: [AEXMLElement] = []
        forEach { e in
            guard let children = (e as? SOAPParamConvertible)?.xmlElements(name: name) else { return }
            a.append(contentsOf: children)
        }
        return a
    }
}


public enum SOAPParamError: Error { case unknown }

// ex. let x: Bool = parseXSDType(v), success only if T(v) is succeeded
public func parseXSDType<T: ExpressibleByXML>(_ element: AEXMLElement) throws -> T {
    guard let v = try T(xml: element) else { throw SOAPParamError.unknown }
    return v
}

// ex. let x: Bool? = parseXSDType(v), failure only if T(v) is failed
public func parseXSDType<T: ExpressibleByXML>(_ element: AEXMLElement) throws -> T? {
    return try T(xml: element)
}

// ex. let x: [String] = parseXSDType(v), failure only if any T(v.children) is failed
public func parseXSDType<T: ExpressibleByXML>(_ element: AEXMLElement) throws -> [T] {
    return try (element.all ?? []).map(parseXSDType)
}
