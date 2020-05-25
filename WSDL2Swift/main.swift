import Foundation
import Commander

let main = command(
    Option<String>("out", default: "./WSDL.swift", description: "(overwrite) output swift file path for generated swift"),
    Flag("public-memberwise-init", description: "synthesize public memberwise init instead of default internal one"),
    VariadicArgument<String>("files", description: "WSDL xmls and XSD xmls, ordered as: ws1.xml ws2.xml xsd-for-ws2.xml ws3.xml xsd-for-ws3-1.xml xsd-for-ws3-2.xml ...")
) { (out: String, publicMemberwiseInit: Bool, filenames: [String]) in
    print("WSDL2Swift to \(out) from \(filenames)...")
    try Core.main(out: URL(fileURLWithPath: (out as NSString).expandingTildeInPath),
                  in: filenames.map {($0 as NSString).expandingTildeInPath},
                  publicMemberwiseInit: publicMemberwiseInit)
}

main.run()
