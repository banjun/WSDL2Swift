import Foundation
import Commander

let main = command(
    Option<String>("out", "./WSDL.swift", description: "(overwrite) output swift file path for generated swift"),
    VaradicArgument<String>("files", description: "WSDL xmls and XSD xmls, ordered as: ws1.xml ws2.xml xsd-for-ws2.xml ws3.xml xsd-for-ws3-1.xml xsd-for-ws3-2.xml ...")
) { (out: String, filenames: [String]) in
    print("WSDL2Swift to \(out) from \(filenames)...")
    try Core.main(out: URL(fileURLWithPath: (out as NSString).expandingTildeInPath),
                  in: filenames.map {($0 as NSString).expandingTildeInPath})
}

main.run()
