import Foundation
import AEXML
import Stencil


private func template(named name: String) -> Template {
    return try! Template(URL: Bundle.main.url(forResource: name, withExtension: "stencil", subdirectory: "Stencils")!)
}


private let typeMap: [String: String] = [
    "string": "\(String.self)", // xs:string
    "boolean": "\(Bool.self)", // xs:boolean
    "int": "\(Int32.self)",
    "long": "\(Int64.self)",
    "dateTime": "\(Date.self)",
    "base64Binary": "\(Data.self)",
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
    static func main(out: URL, in files: [String], publicMemberwiseInit: Bool) throws {
        let preamble = try template(named: "Preamble").render()
        var wsdls: [WSDL] = []
        var types: [(prefix: String, type: XSDType)] = []

        // each file can be either WSDL or XSD file
        for f in files {
            if let wsdl = WSDL(path: f) {
                wsdls.append(wsdl)

                (wsdl.types?["schema"].all ?? []).forEach { s in
                    var options = AEXMLOptions()
                    options.parserSettings.shouldProcessNamespaces = true // ignore namespace
                    options.parserSettings.shouldReportNamespacePrefixes = false // ignore namespace
                    let xml = AEXMLDocument(root: s, options: options)
                    if let xsd = parseXSD(xml, prefix: wsdl.prefix) {
                        types.append(contentsOf: xsd)
                    }
                }

                continue
            }

            guard let wsdl = wsdls.last else {
                print("error: files.first should be WSDL xml file: \(f)")
                return
            }

            guard let xsd = parseXSD(f, prefix: wsdl.prefix) else {
                print("error: file is not WSDL nor XSD: \(f)")
                return
            }
            types.append(contentsOf: xsd)
        }

        guard !wsdls.isEmpty else {
            print("error: no WSDLs found in: \(files)")
            return
        }

        let extensions = types.map {$0.type.dictionariesForExpressibleByXMLProtocol(types.map {$0.type}, typeQualifier: [])}.joined()
        let expressibleByXMLExtensions: [String] = extensions.map {try! compact(template(named: "ExpressibleByXML").render(Context(dictionary: $0)))}
        
        try (wsdls.map {$0.swift()}.joined()
            + types.map {compact($0.type.swift(types.map {$0.type}, prefix: $0.prefix, publicMemberwiseInit: publicMemberwiseInit))}.joined(separator: "\n")
            + "\n\n"
            + preamble
            + expressibleByXMLExtensions.joined())
            .write(to: out, atomically: true, encoding: .utf8)
    }

    fileprivate static func parseXSD(_ path: String, prefix: String) -> [(prefix: String, type: XSDType)]? {
        var options = AEXMLOptions()
        options.parserSettings.shouldProcessNamespaces = true // ignore namespace
        options.parserSettings.shouldReportNamespacePrefixes = false // ignore namespace
        guard let xsd = try? AEXMLDocument(xml: Data(contentsOf: URL(fileURLWithPath: path)), options: options) else { return nil }
        return parseXSD(xsd, prefix: prefix)
    }

    fileprivate static func parseXSD(_ xsd: AEXMLDocument, prefix: String) -> [(prefix: String, type: XSDType)]? {
        // * top-level <complexType name="...">... use the name as type name
        // * child of element <complexType>... use the enclosing element name as type name
        guard xsd.root.name == "schema" else { return nil }
        let complexTypes: [AEXMLElement] = (xsd.root["complexType"].all ?? [])
            + ((xsd.root["element"].all ?? []).flatMap {$0["complexType"].all}.joined())
        let types = complexTypes
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
    var types: AEXMLElement?
    var messages: [WSDLMessage]
    var portType: WSDLPortType
    var binding: WSDLBinding
    var service: WSDLService
    var prefix: String { return service.name + "_" }

    init?(path: String) {
        var options = AEXMLOptions()
        options.parserSettings.shouldProcessNamespaces = true // ignore namespace
        options.parserSettings.shouldReportNamespacePrefixes = false // ignore namespace
        guard let wsdl = try? AEXMLDocument(xml: Data(contentsOf: URL(fileURLWithPath: path)), options: options) else { return nil }

        guard wsdl.root.name == "definitions" else { return nil }
        targetNamespace = wsdl.root.attributes["targetNamespace"]!
        types = (wsdl.root["types"])
        messages = (wsdl.root["message"].all ?? []).flatMap(WSDLMessage.deserialize)
        portType = (wsdl.root["portType"].all ?? []).flatMap(WSDLPortType.deserialize).first!
        binding = (wsdl.root["binding"].all ?? []).flatMap(WSDLBinding.deserialize).first!
        service = (wsdl.root["service"].all ?? []).flatMap(WSDLService.deserialize).first!
    }

    func swift() -> String {
        return try! template(named: "WSDLService").render(Context(dictionary: [
            "targetNamespace": targetNamespace,
            "name": service.name,
            "path":  {
                let p = URL(string: service.port.location)?.path ?? (service.port.location as NSString).lastPathComponent
                return String(p.characters.dropFirst(p.characters.first == "/" ? 1 : 0))
            }(),
            "operations": portType.operations.map { op -> [String: String] in
                let inputMessage = messages.first {$0.name == replaceTargetNameSpace(op.inputMessage, prefix: "")}!
                let outputMessage = messages.first {$0.name == replaceTargetNameSpace(op.outputMessage, prefix: "")}!
                return [
                    "name": swiftKeywordsAvoidedName(op.name),
                    "inParam": replaceTargetNameSpace(inputMessage.parameterName, prefix: prefix),
                    "outParam": replaceTargetNameSpace(outputMessage.parameterName, prefix: prefix),
                ]}]))
    }
}


struct WSDLMessage {
    var name: String
    var part: AEXMLElement
    var parameterName: String {return part.attributes["element"]!}

    static func deserialize(_ node: AEXMLElement) -> WSDLMessage? {
        guard let name = node.attributes["name"] else {
            NSLog("%@", "cannot deserialize \(self) from node \(node.xmlCompact)")
            return nil
        }
        return self.init(name: name, part: node["part"].first!)
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
            let location = node["address"].first?.attributes["location"] else {
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
        func resolveName() -> String? {
            if let name = node.attributes["name"] { return name }
            if let name = node.parent?.attributes["name"], node.parent?.name == "element" { return name }
            return nil
        }
        guard let name = resolveName() else {
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
            func definedByRootElement(_ parent: AEXMLElement?) -> Bool {
                guard let parent = parent else { return false }
                if parent.parent?.name == "schema" && parent.name == "element" { // root is <schema>
                    return true
                }
                return definedByRootElement(parent.parent)
            }
            let byRoot = definedByRootElement(sequence.parent)

            for sn in sequence.children {
                switch sn.name {
                case "element":
                    if let e = XSDElement.deserialize(sn, prefix: prefix, definedByRootElement: byRoot) {
                        elements.append(e)
                    }
                default:
                    NSLog("%@", "Warning: unsupported node as type.sequence.*: \(n.xmlCompact)")
                }
            }
        }

        switch n.name {
        case "sequence":
            base = nil
            parseChildElements(n)
        case "complexContent":
            guard n["extension"].count == 1,
                let ext = n["extension"].first,
                let b = ext.attributes["base"] else {
                    NSLog("%@", "Warning: extension missing for complexContent: \(n.xmlCompact)")
                    return nil
            }
            parseChildElements(ext["sequence"])
            base = b.hasPrefix("tns:") ? b.substring(from: b.characters.index(b.characters.startIndex, offsetBy: "tns:".characters.count)) : b
        default:
            NSLog("%@", "Warning: unsupported node as type.*: \(n.xmlCompact)")
            base = nil
        }
        return self.init(prefix: prefix, bareName: name, elements: elements, base: base.map {prefix + $0})
    }

    func baseType(_ env: [XSDType]) -> XSDType? {
        if let base = self.base {
            guard let bt = env.filter({$0.name == base}).first else {
                NSLog("%@", "error: Cannot resolve base type for \(name): \(base)")
                return nil
            }
            return bt
        } else {
            return nil
        }
    }

    func dictionary(_ env: [XSDType], prefix: String, publicMemberwiseInit: Bool, typeQualifier: [String] = []) -> [String: Any] {
        let baseType = self.baseType(env)
        let elements = self.elements.map {$0.dictionary(prefix)}
        let bases = baseType.map {$0.dictionary(env, prefix: prefix, publicMemberwiseInit: publicMemberwiseInit)}

        return [
            "name": name,
            "bareName": bareName,
            "elements": elements,
            "base": bases ?? [:],
            "publicMemberwiseInit": publicMemberwiseInit,
            "xmlParams": (self.elements + (baseType?.elements ?? [])).map {["name": $0.name, "swiftName": $0.swiftName, "xmlns": $0.xmlns]},
            "innerTypes": self.elements.flatMap { e -> String? in
                if case let .inner(t) = e.type { return t.swift(env, prefix: prefix, publicMemberwiseInit: publicMemberwiseInit, typeQualifier: typeQualifier + [name]) } else { return nil }
            },
        ]
    }

    func dictionariesForExpressibleByXMLProtocol(_ env: [XSDType], typeQualifier: [String] = []) -> [[String: Any]] {
        var ds: [[String: Any]] = []
        let fqn = typeQualifier + [name]
        ds.append(["fqn": fqn.joined(separator: "."),
                   "xmlParams": (self.elements + (baseType(env)?.elements ?? [])).map {["name": $0.name, "swiftName": $0.swiftName, "xmlns": $0.xmlns]},
                   ])
        for case let .inner(t) in (elements.map {$0.type}) {
            ds.append(contentsOf: t.dictionariesForExpressibleByXMLProtocol(env, typeQualifier: fqn))
        }
        return ds
    }

    func swift(_ env: [XSDType], prefix: String, publicMemberwiseInit: Bool, typeQualifier: [String] = []) -> String {
        let d = dictionary(env, prefix: prefix, publicMemberwiseInit: publicMemberwiseInit)
        let indentLevel = typeQualifier.count
        return try! template(named: "XSDType").render(Context(dictionary: d))
//            + template(named: "ExpressibleByXML").render(Context(dictionary: [
//                "fqn": (typeQualifier + [name]).joined(separator: "."),
//                "xmlParams": d["xmlParams"] ?? [:],
//                ]))
            .replacingOccurrences(of: "\n\n", with: "\n")
            .components(separatedBy: "\n")
            .joined(separator: "\n" + [String](repeating: "    ", count: indentLevel).joined(separator: ""))
            .replacingOccurrences(of: "\\s*\n\\s*\n", with: "\n", options: [.regularExpression])
    }
}

struct XSDElement {
    let name: String
    let type: Type
    let minOccurs: UInt
    let maxOccurs: UInt
    let xmlns: String

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

    static func deserialize(_ node: AEXMLElement, prefix: String = "", definedByRootElement: Bool) -> XSDElement? {
        guard let name = node.attributes["name"] else {
            NSLog("%@", "cannot deserialize \(self) from node \(node.xmlCompact)")
            return nil
        }

        let type: Type
        if let t = node.attributes["type"] {
            // types external to element
            type = .atomic(replaceTargetNameSpace(t, prefix: prefix).components(separatedBy: ":").last ?? t) // ignore namespace
        } else {
            // types internal to element
            let complexType = node["complexType"]
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
            maxOccurs: maxOCcurs.flatMap {$0 == "unbounded" ? UInt.max : UInt($0)} ?? 1, // XSD default = 1
            xmlns: definedByRootElement ? "tns" : "")
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
