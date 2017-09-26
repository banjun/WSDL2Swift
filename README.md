WSDL2Swift
==========

Swift alternative to WSDL2ObjC making a SOAP request & parsing its response as defined in WSDL.
Objective-C free.

## Input & Output

Input

* WSDL 1.1 xmls
* XSD xmls

Output

* a Swift file which works as SOAP client
	* Swift 4 (Xcode 9)
	* NSURLSession for connection
	* [BrightFutures](https://github.com/Thomvis/BrightFutures) for returning asynchronous requests
	* [Fuzi](https://github.com/cezheng/Fuzi) for fast parsing xmls
	* [AEXML](https://github.com/tadija/AEXML) for generating xmls

## Usage

### Build

```sh
bundle install
bundle exec fastlane archive
```

you can build and debug with WSDL2Swift scheme of the xcodeproj. Archive build is not supported yet.

product executable is portable, as long as shipped with ./Frameworks and ./Stencils.

### Generate

generate WSDL.swift from WSDL and XSD xmls:

```sh
./build/Build/Products/Release/WSDL2Swift --out path/to/WSDL.swift path/to/service.wsdl.xml path/to/service.xsd.xml
```

the order of input files is important.
referenced XSDs should be placed immediately after referencing WSDL.

### Use In App

add WSDL.swift to your project and use:
(note that service type name and requeest type name are vary, depending on source WSDL)

generated code from example by w3schools temperature converter:

```swift
public struct TempConvert: WSDLService {
	:
    public func request(_ parameters: TempConvert_CelsiusToFahrenheit) -> Future<TempConvert_CelsiusToFahrenheitResponse, WSDLOperationError> {
        return requestGeneric(parameters)
    }
    :
}

:

public struct TempConvert_CelsiusToFahrenheit {
    public var Celsius: String?
}

public struct TempConvert_CelsiusToFahrenheitResponse {
    public var CelsiusToFahrenheitResult: String?
}

:
(continued...)
```

code using the generated client:

```swift
let service = TempConvert(endpoint: "http://www.w3schools.com")
service.request(TempConvert_CelsiusToFahrenheit(Celsius: "23.4")).onComplete { r in
    NSLog("%@", "TempConvert_CelsiusToFahrenheit(Celsius: \"23.4\") = \(r)")
}
```

with dependencies:

```ruby
pod 'WSDL2Swift'
```

note that pod WSDL2Swift just introduces runtime dependencies. it does not provide WSDL2Swift executable binary nor generated WSDL client Swift files.

sometimes, somewhere in your dependencies chain (transitive framework dependencies or test bundle), header search paths for libxml2 is required. see podspec to add manually.

## Example

iOSWSDL2Swift target in xcodeproj is an example using WSDL2Swift.
it generates `WSDL+(ServiceName).swift` at the first step of build and use it from ViewController.swift.

you need to place your WSDL and XSD xmls into exampleWSDLS folder.


## Architecture

usage point of view...

* initialize Service with endpoint URL (endpoint URL can be changed after generating `WSDL+(ServiceName).swift`)
* initialize request parameter with `ServiceName_OperationName(...)`
* `Service.request(param)` to get `Future` that will be completed by `NSURLSession` completion
* parameters and models are typed by xsd definition (even with nullability)

