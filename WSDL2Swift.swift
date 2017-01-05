import Foundation
import AEXML
import Result
import BrightFutures
import ISO8601

public protocol SOAPParamConvertible {
    func xmlElements(name: String) -> [AEXMLElement]
}

public protocol XSDType: SOAPParamConvertible {
    // name, swiftName, xmlns
    var xmlParams: [(String, SOAPParamConvertible?, String)] { get }
}

public extension XSDType {
    func soapRequest(_ tns: String) -> AEXMLDocument {
        let action = "\(String(describing: type(of: self)))".components(separatedBy: "_").last!
        let soapRequest = AEXMLDocument()
        let envelope = soapRequest.addChild(name: "S:Envelope", attributes: [
            "xmlns:S": "http://schemas.xmlsoap.org/soap/envelope/",
            "xmlns:tns": tns,
            ])
        let _ = envelope.addChild(name: "S:Header")
        let body = envelope.addChild(name: "S:Body")
        xmlElements(name: "tns:" + action).forEach {body.addChild($0)} // assumes "tns:" prefixed for all actions. JAX-WS requires prefixed or xmlns specification on this node.
        return soapRequest
    }

    func xmlElements(name: String) -> [AEXMLElement] {
        let typeElement = AEXMLElement(name: name)
        for case let (k, v?, ns) in xmlParams {
            let name = ns.isEmpty ? k : (ns + ":" + k)
            let children = v.xmlElements(name: name)
            children.forEach {typeElement.addChild($0)}
        }
        return [typeElement]
    }
}

public protocol WSDLService {
    var endpoint: String { get set }
    var path: String { get }
    var targetNamespace: String { get }
    var interceptURLRequest: ((URLRequest) -> URLRequest)? { get set }
    var interceptResponse: ((Data?, URLResponse?, Error?) -> (Data?, URLResponse?, Error?))? { get set }
    init(endpoint: String)
}

public extension WSDLService {
    init(endpoint: String, interceptURLRequest: ((URLRequest) -> URLRequest)? = nil, interceptResponse: ((Data?, URLResponse?, Error?) -> (Data?, URLResponse?, Error?))? = nil) {
        self.init(endpoint: endpoint)
        self.interceptURLRequest = interceptURLRequest
        self.interceptResponse = interceptResponse
    }

    func requestGeneric<I: XSDType, O: XSDType & ExpressibleByXML>(_ parameters: I) -> Future<O, WSDLOperationError> {
        let promise = Promise<O, WSDLOperationError>()

        let soapRequest = parameters.soapRequest(targetNamespace)
        //        print("request to \(endpoint + path) using: \(soapRequest.xml)")

        var request = URLRequest(url: URL(string: endpoint)!.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.addValue("text/xml", forHTTPHeaderField: "Content-Type")
        request.addValue("WSDL2Swift", forHTTPHeaderField: "User-Agent")
        if let data = soapRequest.xml.data(using: .utf8) {
            //            request.addValue(String(data.length), forHTTPHeaderField: "Content-Length")
            request.httpBody = data
        }
        //        NSLog("%@", "headers: \(request.allHTTPHeaderFields)")
        request = interceptURLRequest?(request) ?? request
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            let (data, _, error) = self.interceptResponse?(data, response, error) ?? (data, response, error)
            //            NSLog("%@", "\((response, error))")

            if let error = error {
                promise.failure(.urlSession(error))
                return
            }

            guard let d = data, let xml = try? AEXMLDocument(xml: d) else {
                promise.failure(.invalidXML)
                return
            }

            guard let soapMessage = SOAPMessage(xml: xml, targetNamespace: self.targetNamespace) else {
                promise.failure(.invalidXMLContent)
                return
            }

            guard let out = O(soapMessage: soapMessage) else {
                if let fault = soapMessage.body.fault {
                    promise.failure(.soapFault(fault))
                } else {
                    promise.failure(.invalidXMLContent)
                }
                return
            }

            promise.success(out)
        }
        task.resume()
        return promise.future
    }
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
            self.fault = Fault(xml: xml[soapNameSpace + ":Fault"])
            self.output = self.fault == nil ? namespaceRemovedXML.root.children.first : nil
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

public extension ExpressibleByXML {
    // default implementation for primitive values
    // element nil check and text value empty check
    init?(xml: AEXMLElement) throws {
        guard let value = xml.value else { return nil }
        guard !value.isEmpty else { return nil }
        try self.init(xmlValue: value)
    }

    init?(xmlValue: String) throws {
        // compound type cannot be initialized with a text element
        throw SOAPParamError.unknown
    }
    
    init?(soapMessage message: SOAPMessage) {
        guard let xml = message.body.output else { return nil }
        try? self.init(xml: xml)
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
