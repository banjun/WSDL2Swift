import Foundation
import Commander

let main = command(Option<String>("out", "."), VaradicArgument<String>("file")) { (out: String, filenames: [String]) in
    print("WSDL2Swift to \(out) from \(filenames)...")

    var filePairs: [(wsdlPath: String, xsdPath: String)] = []
    for i in 0..<filenames.count - 1 {
        guard i % 2 == 0 else { continue }
        filePairs.append((wsdlPath: filenames[i], xsdPath: filenames[i + 1]))
    }
    try Core.main(out: URL(fileURLWithPath: out), in: filePairs)
}

main.run()
