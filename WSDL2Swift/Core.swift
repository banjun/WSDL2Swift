import Foundation
import AEXML
import Stencil


private func template(named name: String) -> Template {
    return try! Template(URL: Bundle.main.url(forResource: name, withExtension: "stencil", subdirectory: "Stencils")!)
}


private let typeMap: [String: String] = [
    "xs:string": "\(String.self)",
    "xs:boolean": "\(Bool.self)",
    "xs:int": "\(Int32.self)",
    "xs:long": "\(Int64.self)",
    "xs:dateTime": "\(Date.self)",
    "xs:base64Binary": "\(Data.self)",
]

private let swiftKeywords: [String] = [
    "operator",
    "return",
]
private func swiftKeywordsAvoidedName(_ name: String) -> String {
    return swiftKeywords.contains(name) ? name + "_" : name
}


private func replaceTargetNameSpace(_ name: String, prefix: String) -> String {
    return name.replacingOccurrences(of: "tns:", with: prefix)
}


struct Core {
    static func main(out: URL, in files: [(wsdlPath: String, xsdPath: String)]) throws {
        let preamble = try template(named: "Preamble").render()

        let wsdls = files.map {WSDL(path: $0.wsdlPath)!}
        let xsds = zip(files, wsdls).map {try! parseXSD($0.0.xsdPath, prefix: $0.1.prefix)}

        let types = xsds.joined()
        try (preamble
            + types.map {compact($0.type.swift(types.map {$0.type}, prefix: $0.prefix))}.joined(separator: "\n\n")
            + "\n\n"
            + wsdls.map {$0.swift()}.joined())
            .write(to: out, atomically: true, encoding: .utf8)
    }

    fileprivate static func parseXSD(_ path: String, prefix: String) throws -> [(prefix: String, type: XSDType)] {
        let xsd = try AEXMLDocument(xml: Data(contentsOf: URL(fileURLWithPath: path)))
        let types = (xsd.root["xs:complexType"].all ?? [])
            .flatMap {XSDType.deserialize($0, prefix: prefix)}
            .map {(prefix, $0)}
        return types
    }

    // Workaround until Stencil fixes https://github.com/kylef/Stencil/issues/22
    fileprivate static func compact(_ s: String) -> String {
        return s.replacingOccurrences(of: "\n\n", with: "\n")
    }
}


struct WSDL {
    var targetNamespace: String
    var messages: [WSDLMessage]
    var portType: WSDLPortType
    var binding: WSDLBinding
    var service: WSDLService
    var prefix: String { return service.name + "_" }

    init?(path: String) {
        guard let wsdl = try? AEXMLDocument(xml: Data(contentsOf: URL(fileURLWithPath: path))) else { return nil }
        targetNamespace = wsdl.root.attributes["targetNamespace"]!
        messages = (wsdl.root["message"].all ?? []).flatMap(WSDLMessage.deserialize)
        portType = (wsdl.root["portType"].all ?? []).flatMap(WSDLPortType.deserialize).first!
        binding = (wsdl.root["binding"].all ?? []).flatMap(WSDLBinding.deserialize).first!
        service = (wsdl.root["service"].all ?? []).flatMap(WSDLService.deserialize).first!
    }

    func swift() -> String {
        return try! template(named: "WSDLService").render(Context(dictionary: [
            "targetNamespace": targetNamespace,
            "name": service.name,
            "path": URL(string: service.port.location)?.path ?? (service.port.location as NSString).lastPathComponent,
            "operations": portType.operations.map { op in
                return [
                    "name": swiftKeywordsAvoidedName(op.name),
                    "inParam": replaceTargetNameSpace(op.inputMessage, prefix: prefix),
                    "outParam": replaceTargetNameSpace(op.outputMessage, prefix: prefix),
                ]}]))
    }
}


struct WSDLMessage {
    var name: String
    // var part

    static func deserialize(_ node: AEXMLElement) -> WSDLMessage? {
        guard let name = node.attributes["name"] else {
            NSLog("%@", "cannot deserialize \(self) from node \(node.xmlCompact)")
            return nil
        }
        return self.init(name: name)
    }
}

struct WSDLPortType {
    var name: String
    var operations: [WSDLOperation]

    static func deserialize(_ node: AEXMLElement) -> WSDLPortType? {
        guard let name = node.attributes["name"],
            let operations = node["operation"].all?.flatMap({WSDLOperation.deserialize($0)}) else {
            NSLog("%@", "cannot deserialize \(self) from node \(node.xmlCompact)")
            return nil
        }
        return self.init(name: name, operations: operations)
    }
}

struct WSDLOperation {
    var name: String
    var inputMessage: String
    var outputMessage: String

    static func deserialize(_ node: AEXMLElement) -> WSDLOperation? {
        guard let name = node.attributes["name"],
            let inputMessage = node["input"].first?.attributes["message"],
            let outputMessage = node["output"].first?.attributes["message"] else {
                NSLog("%@", "cannot deserialize \(self) from node \(node.xmlCompact)")
                return nil
        }
        return self.init(name: name, inputMessage: inputMessage, outputMessage: outputMessage)
    }
}

struct WSDLBinding {
    var name: String
    // omit check for: <soap:binding transport="http://schemas.xmlsoap.org/soap/http" style="document" />
    // omit check for <operations> other than WSDLOperation, without any informative parts

    static func deserialize(_ node: AEXMLElement) -> WSDLBinding? {
        guard let name = node.attributes["name"] else {
            NSLog("%@", "cannot deserialize \(self) from node \(node.xmlCompact)")
            return nil
        }
        return self.init(name: name)
    }
}

struct WSDLService {
    var name: String
    var port: WSDLServicePort

    static func deserialize(_ node: AEXMLElement) -> WSDLService? {
        guard let name = node.attributes["name"],
            let port = node["port"].first.flatMap({WSDLServicePort.deserialize($0)}) else {
            NSLog("%@", "cannot deserialize \(self) from node \(node.xmlCompact)")
            return nil
        }
        return self.init(name: name, port: port)
    }
}

struct WSDLServicePort {
    var name: String
    var binding: String
    var location: String // <soap:address location="*" />

    static func deserialize(_ node: AEXMLElement) -> WSDLServicePort? {
        guard let name = node.attributes["name"],
            let binding = node.attributes["binding"],
            let location = node["soap:address"].first?.attributes["location"] else {
            NSLog("%@", "cannot deserialize \(self) from node \(node.xmlCompact)")
            return nil
        }
        return self.init(name: name, binding: binding, location: location)
    }
}


struct XSDType {
    var prefix: String
    var bareName: String
    var name: String {return prefix + bareName}
    var elements: [XSDElement]
    var base: String?

    static func deserialize(_ node: AEXMLElement, prefix: String = "") -> XSDType? {
        guard let name = node.attributes["name"] else {
            NSLog("%@", "cannot deserialize \(self) from node \(node.xmlCompact)")
            return nil
        }

        guard let n = node.children.first else {
            NSLog("%@", "Warning: unsupported multiple children in type.*: \(node.xmlCompact)")
            return nil
        }


        var elements: [XSDElement] = []
        let base: String?

        func parseChildElements(_ sequence: AEXMLElement) {
            for sn in sequence.children {
                switch sn.name {
                case "xs:element":
                    if let e = XSDElement.deserialize(sn, prefix: prefix) {
                        elements.append(e)
                    }
                default:
                    NSLog("%@", "Warning: unsupported node as type.sequence.*: \(n.xmlCompact)")
                }
            }
        }

        switch n.name {
        case "xs:sequence":
            base = nil
            parseChildElements(n)
        case "xs:complexContent":
            guard n["xs:extension"].count == 1,
                let ext = n["xs:extension"].first,
                let b = ext.attributes["base"] else {
                    NSLog("%@", "Warning: extension missing for complexContent: \(n.xmlCompact)")
                    return nil
            }
            parseChildElements(ext["xs:sequence"])
            base = b.hasPrefix("tns:") ? b.substring(from: b.characters.index(b.characters.startIndex, offsetBy: "tns:".characters.count)) : b
        default:
            NSLog("%@", "Warning: unsupported node as type.*: \(n.xmlCompact)")
            base = nil
        }
        return self.init(prefix: prefix, bareName: name, elements: elements, base: base.map {prefix + $0})
    }

    func dictionary(_ env: [XSDType], prefix: String, indentLevel: Int = 0) -> [String: Any] {
        let baseType: XSDType?
        if let base = self.base {
            guard let bt = env.filter({$0.name == base}).first else {
                NSLog("%@", "Cannot resolve base type for \(name): \(base)")
                return [:]
            }
            baseType = bt
        } else {
            baseType = nil
        }

        let elements = self.elements.map {$0.dictionary(prefix)}
        let bases = baseType.map {$0.dictionary(env, prefix: prefix)}

        return [
            "name": name,
            "bareName": bareName,
            "elements": elements,
            "base": bases,
            "xmlParams": (self.elements + (baseType?.elements ?? [])).map {["name": $0.name, "swiftName": $0.swiftName]},
            "conformances": "XSDType",
            "innerTypes": self.elements.flatMap { e -> String? in
                if case let .inner(t) = e.type { return t.swift(env, prefix: prefix, indentLevel: indentLevel + 1) } else { return nil }
            },
        ]
    }

    func swift(_ env: [XSDType], prefix: String, indentLevel: Int = 0) -> String {
        return try! template(named: "XSDType").render(Context(dictionary: dictionary(env, prefix: prefix)))
            .replacingOccurrences(of: "\n\n", with: "\n")
            .components(separatedBy: "\n")
            .joined(separator: "\n" + [String](repeating: "    ", count: indentLevel).joined(separator: ""))
            .replacingOccurrences(of: "\n\n", with: "\n")
    }
}

struct XSDElement {
    let name: String
    let type: Type
    let minOccurs: UInt
    let maxOccurs: UInt

    enum `Type` {
        case atomic(String)
        case inner(XSDType)

        var string: String {
            switch self {
            case let .atomic(s): return s
            case let .inner(t): return t.name
            }
        }
    }

    static func deserialize(_ node: AEXMLElement, prefix: String = "") -> XSDElement? {
        guard let name = node.attributes["name"] else {
            NSLog("%@", "cannot deserialize \(self) from node \(node.xmlCompact)")
            return nil
        }

        let type: Type
        if let t = node.attributes["type"] {
            // element外部の型
            type = .atomic(t)
        } else {
            // element内部で定義される型
            let complexType = node["xs:complexType"]
            complexType.attributes["name"] = name
            guard let t = XSDType.deserialize(complexType, prefix: prefix) else {
                return nil
            }
            type = .inner(t)
        }

        let minOccurs = node.attributes["minOccurs"]
        let maxOCcurs = node.attributes["maxOccurs"]

        return self.init(
            name: name,
            type: type,
            minOccurs: minOccurs.flatMap {UInt($0)} ?? 1, // XSD default = 1
            maxOccurs: maxOCcurs.flatMap {$0 == "unbounded" ? UInt.max : UInt($0)} ?? 1) // XSD default = 1
    }

    func dictionary(_ prefix: String) -> [String: Any] {
        let safeType = typeMap[type.string] ?? type.string
        let swiftType: String
        switch (minOccurs, maxOccurs) {
        case (0, 1): swiftType = safeType + "?"
        case (0, UInt.max): swiftType = "[\(safeType)]"
        case (1, 1): swiftType = safeType
        default:
            NSLog("%@", "cannot handle \(self)")
            swiftType = "\(safeType) // FIXME: unknown occurances [\(minOccurs), \(maxOccurs)]"
        }

        return [
            "name": swiftName,
            "type": swiftType.replacingOccurrences(of: "tns:", with: prefix),
        ]
    }

    var swiftName: String { return swiftKeywordsAvoidedName(name) }
}
