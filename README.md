WSDL2Swift
==========

Swift alternative to WSDL2ObjC making a SOAP request & parsing its response as defined in WSDL.
Objective-C free and libxml free.

## Input & Output

Input

* WSDL 1.1 xmls
* XSD xmls

Output

* a Swift file which works as SOAP client
	* Swift 3.0.1 (Xcode 8.1)
	* NSURLSession for connection
	* [BrightFutures](https://github.com/Thomvis/BrightFutures) for returning asynchronous requests

## Usage

generate WSDL.swift from WSDL and XSD xmls:

```sh
WSDL2Swift --out path/to/WSDL.swift path/to/service.wsdl.xml path/to/service.xsd.xml
```

add WSDL.swift to your project and use:
(note that service type name and requeest type name are vary, depending on source WSDL)

```swift
let auth = AuthenticationServiceService(endpoint: "https://examle.com")
let login = auth.request(AuthenticationServiceService_login(arg0: "alice@example.com", arg1: "password"))
login.onComplete { r in
    NSLog("%@", "result = \(r)")
}
```

with dependencies:

```ruby
pod 'AEXML'
pod 'BrightFutures'
pod 'ISO8601'
```

## Build

build with WSDL2Swift scheme. Archive build is not supported yet.

product executable is portable, as long as shipped with ./Frameworks and ./Stencils.

## Example

iOSWSDL2Swift target in xcodeproj is an example using WSDL2Swift.
it generates WSDL.swift at the first step of build and use it from ViewController.swift.

you need to place your WSDL and XSD xmls into exampleWSDLS folder.


## Architecture

usage point of view...

* initialize Service with endpoint URL (endpoint URL can be changed after generating WSDL.swift)
* initialize request parameter with `ServiceName_OperationName(...)`
* `Service.request(param)` to get `Future` that will be completed by `NSURLSession` completion
* parameters and models are typed by xsd definition (even with nullability)

