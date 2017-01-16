@import AEXML;
#import "XMLParserObjCSwiftBridge.h"

@implementation XMLParserObjCSwiftBridge

- (instancetype)init {
    if (self = [super init]) {
        self.currentValue = [NSMutableString stringWithCapacity: 4 * 1024];
    }
    return self;
}

// NOTE: just implementing methods AEXMLParser implements

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(nullable NSString *)namespaceURI qualifiedName:(nullable NSString *)qName attributes:(NSDictionary<NSString *, NSString *> *)attributeDict;
{
    [self.currentValue setString: @""];

    // avoid BridgeFromObjectiveC for empty dictionary
    if (attributeDict.count == 0) {
        [self.delegate parser:parser didStartElement:elementName namespaceURI: namespaceURI qualifiedName: qName];
    } else {
        [self.delegate parser:parser didStartElement:elementName namespaceURI: namespaceURI qualifiedName: qName attributes: attributeDict];
    }
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(nullable NSString *)namespaceURI qualifiedName:(nullable NSString *)qName;
{
    [self.delegate parser:parser didEndElement:elementName namespaceURI:namespaceURI qualifiedName:qName];
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string;
{
    [self.currentValue appendString: string];
    NSString *newValue = [self.currentValue stringByTrimmingCharactersInSet: NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [self.delegate parser:parser foundCharactersAccumulated:newValue];
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError;
{
    [self.delegate parser:parser parseErrorOccurred:parseError];
}

@end
