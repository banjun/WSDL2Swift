// exception for ``Pure Swift''...
// BridgeFromObjectiveC in Swift 3 consume cpu time between NSXMLParser and its delegate methods.

@import Foundation;
@class AEXMLDocument;

NS_ASSUME_NONNULL_BEGIN

@protocol XMLParserObjCSwiftBridgeDelegate<NSXMLParserDelegate>

// for empty attributes
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(nullable NSString *)namespaceURI qualifiedName:(nullable NSString *)qName;
// replaces parser:foundCharacters: with trim whitespaces in NSString
- (void)parser:(NSXMLParser *)parser foundCharactersAccumulated:(NSString *)string;

@end

/// just for performance workaround, caused by BridgeFromObjectiveC(NSDictionary)
@interface XMLParserObjCSwiftBridge: NSObject<NSXMLParserDelegate>

@property (nullable, assign) id <XMLParserObjCSwiftBridgeDelegate> delegate;

@property NSMutableString *currentValue;

@end

NS_ASSUME_NONNULL_END
