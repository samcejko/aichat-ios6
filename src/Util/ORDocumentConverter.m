#import "ORDocumentConverter.h"
#import "ORCommon.h"
#include <zlib.h>
#include <ctype.h>
#include <string.h>

static const NSUInteger kMaxOutputChars = 2 * 1024 * 1024;
static const NSInteger kMaxSheetRows = 400;
static const NSInteger kMaxSheetCols = 40;

#pragma mark - ZIP

@interface ORZipEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) uint16_t method;
@property (nonatomic) uint32_t compressedSize;
@property (nonatomic) uint32_t uncompressedSize;
@property (nonatomic) uint32_t localHeaderOffset;
@end
@implementation ORZipEntry
@end

@interface ORZipArchive ()
@property (nonatomic, strong) NSData *data;
@property (nonatomic, strong) NSMutableDictionary *entries;
@property (nonatomic, strong) NSMutableArray *order;
@end

static inline uint16_t rd16(const uint8_t *p) { return (uint16_t)(p[0] | (p[1] << 8)); }
static inline uint32_t rd32(const uint8_t *p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }

@implementation ORZipArchive

- (instancetype)initWithData:(NSData *)data
{
    self = [super init];
    if (self) {
        _data = data;
        _entries = [NSMutableDictionary dictionary];
        _order = [NSMutableArray array];
        if (![self parseCentralDirectory]) return nil;
    }
    return self;
}

- (BOOL)parseCentralDirectory
{
    const uint8_t *bytes = (const uint8_t *)self.data.bytes;
    NSUInteger len = self.data.length;
    if (len < 22) return NO;
    // End of central directory record: scan backwards (comment can be up to 65535 bytes).
    NSInteger eocd = -1;
    NSInteger minPos = (NSInteger)len - 22 - 65535;
    if (minPos < 0) minPos = 0;
    for (NSInteger i = (NSInteger)len - 22; i >= minPos; i--) {
        if (rd32(bytes + i) == 0x06054b50) { eocd = i; break; }
    }
    if (eocd < 0) return NO;
    uint16_t total = rd16(bytes + eocd + 10);
    uint32_t cdSize = rd32(bytes + eocd + 12);
    uint32_t cdOffset = rd32(bytes + eocd + 16);
    if ((NSUInteger)cdOffset + cdSize > len) return NO;

    NSUInteger pos = cdOffset;
    for (uint16_t n = 0; n < total; n++) {
        if (pos + 46 > len || rd32(bytes + pos) != 0x02014b50) break;
        ORZipEntry *e = [[ORZipEntry alloc] init];
        e.method = rd16(bytes + pos + 10);
        e.compressedSize = rd32(bytes + pos + 20);
        e.uncompressedSize = rd32(bytes + pos + 24);
        uint16_t nameLen = rd16(bytes + pos + 28);
        uint16_t extraLen = rd16(bytes + pos + 30);
        uint16_t commentLen = rd16(bytes + pos + 32);
        e.localHeaderOffset = rd32(bytes + pos + 42);
        if (pos + 46 + nameLen > len) break;
        NSString *name = [[NSString alloc] initWithBytes:bytes + pos + 46 length:nameLen encoding:NSUTF8StringEncoding];
        if (!name) name = [[NSString alloc] initWithBytes:bytes + pos + 46 length:nameLen encoding:NSISOLatin1StringEncoding];
        e.name = name ?: @"";
        self.entries[e.name] = e;
        [self.order addObject:e.name];
        pos += 46 + nameLen + extraLen + commentLen;
    }
    return self.entries.count > 0;
}

- (NSArray *)entryNames
{
    return [self.order copy];
}

- (NSData *)dataForEntry:(NSString *)name
{
    ORZipEntry *e = self.entries[name];
    if (!e) return nil;
    const uint8_t *bytes = (const uint8_t *)self.data.bytes;
    NSUInteger len = self.data.length;
    NSUInteger lh = e.localHeaderOffset;
    if (lh + 30 > len || rd32(bytes + lh) != 0x04034b50) return nil;
    uint16_t nameLen = rd16(bytes + lh + 26);
    uint16_t extraLen = rd16(bytes + lh + 28);
    NSUInteger start = lh + 30 + nameLen + extraLen;
    if (start + e.compressedSize > len) return nil;
    const uint8_t *src = bytes + start;

    if (e.method == 0) {
        return [NSData dataWithBytes:src length:e.compressedSize];
    }
    if (e.method != 8) return nil;
    if (e.uncompressedSize > 64 * 1024 * 1024) return nil;

    NSMutableData *out = [NSMutableData dataWithLength:e.uncompressedSize ? e.uncompressedSize : 1];
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    if (inflateInit2(&strm, -MAX_WBITS) != Z_OK) return nil;
    strm.next_in = (Bytef *)src;
    strm.avail_in = e.compressedSize;
    strm.next_out = (Bytef *)out.mutableBytes;
    strm.avail_out = (uInt)out.length;
    int ret = inflate(&strm, Z_FINISH);
    NSUInteger produced = strm.total_out;
    inflateEnd(&strm);
    if (ret != Z_STREAM_END && ret != Z_OK && ret != Z_BUF_ERROR) return nil;
    if (produced == 0 && e.uncompressedSize > 0) return nil;
    out.length = produced;
    return out;
}

@end

#pragma mark - XML text extraction

typedef NS_ENUM(NSInteger, ORXMLFlavor) {
    ORXMLFlavorDocx,
    ORXMLFlavorPptx,
    ORXMLFlavorOpenDocument,
};

// Collects paragraphs and tables from an OOXML / ODF XML part.
@interface ORXMLTextExtractor : NSObject <NSXMLParserDelegate>
@property (nonatomic) ORXMLFlavor flavor;
@property (nonatomic, strong) NSMutableString *output;
@property (nonatomic, strong) NSMutableString *paragraph;
@property (nonatomic, strong) NSMutableArray *currentRow;      // NSMutableString cells
@property (nonatomic, strong) NSMutableString *currentCell;
@property (nonatomic) NSInteger tableDepth;
@property (nonatomic) NSInteger tableRowsEmitted;
@property (nonatomic) BOOL inText;
@property (nonatomic, copy) NSString *paragraphPrefix;
@property (nonatomic) BOOL headerRowDone;
@end

static NSString *ORLocalName(NSString *qname)
{
    NSRange r = [qname rangeOfString:@":" options:NSBackwardsSearch];
    return r.location == NSNotFound ? qname : [qname substringFromIndex:r.location + 1];
}

@implementation ORXMLTextExtractor

- (instancetype)initWithFlavor:(ORXMLFlavor)flavor
{
    self = [super init];
    if (self) {
        _flavor = flavor;
        _output = [NSMutableString string];
        _paragraph = [NSMutableString string];
    }
    return self;
}

- (NSString *)extractFromData:(NSData *)data
{
    if (!data) return nil;
    NSXMLParser *parser = [[NSXMLParser alloc] initWithData:data];
    parser.delegate = self;
    [parser parse];
    [self flushParagraph];
    return self.output;
}

- (void)flushParagraph
{
    NSString *text = [self.paragraph stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (self.currentCell) {
        if (text.length) {
            if (self.currentCell.length) [self.currentCell appendString:@" "];
            [self.currentCell appendString:text];
        }
    } else if (text.length) {
        if (self.paragraphPrefix.length) [self.output appendString:self.paragraphPrefix];
        [self.output appendString:text];
        [self.output appendString:@"\n"];
        if (![self.paragraphPrefix hasPrefix:@"-"] && ![self.paragraphPrefix hasPrefix:@"1"]) [self.output appendString:@"\n"];
    }
    [self.paragraph setString:@""];
    self.paragraphPrefix = nil;
}

- (void)emitRow
{
    if (!self.currentRow) return;
    if (self.tableRowsEmitted < kMaxSheetRows) {
        NSMutableArray *cells = [NSMutableArray array];
        for (NSString *c in self.currentRow) {
            NSString *s = [c stringByReplacingOccurrencesOfString:@"|" withString:@"\\|"];
            s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
            [cells addObject:s];
        }
        [self.output appendFormat:@"| %@ |\n", [cells componentsJoinedByString:@" | "]];
        if (!self.headerRowDone) {
            NSMutableArray *seps = [NSMutableArray array];
            for (NSUInteger i = 0; i < cells.count; i++) [seps addObject:@"---"];
            [self.output appendFormat:@"| %@ |\n", [seps componentsJoinedByString:@" | "]];
            self.headerRowDone = YES;
        }
    }
    self.tableRowsEmitted++;
    self.currentRow = nil;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    NSString *n = ORLocalName(elementName);
    if (self.flavor == ORXMLFlavorDocx) {
        if ([n isEqualToString:@"p"]) {
            [self flushParagraph];
        } else if ([n isEqualToString:@"t"]) {
            self.inText = YES;
        } else if ([n isEqualToString:@"tab"]) {
            [self.paragraph appendString:@"\t"];
        } else if ([n isEqualToString:@"br"] || [n isEqualToString:@"cr"]) {
            [self.paragraph appendString:@"\n"];
        } else if ([n isEqualToString:@"pStyle"]) {
            NSString *val = [attributeDict[@"w:val"] lowercaseString];
            if ([val hasPrefix:@"heading"] || [val hasPrefix:@"nadpis"] || [val hasPrefix:@"title"]) {
                NSInteger level = [[val stringByTrimmingCharactersInSet:[NSCharacterSet letterCharacterSet]] integerValue];
                if (level < 1) level = 1;
                if (level > 6) level = 6;
                self.paragraphPrefix = [[@"" stringByPaddingToLength:level withString:@"#" startingAtIndex:0] stringByAppendingString:@" "];
            }
        } else if ([n isEqualToString:@"numPr"]) {
            if (!self.paragraphPrefix) self.paragraphPrefix = @"- ";
        } else if ([n isEqualToString:@"tbl"]) {
            [self flushParagraph];
            self.tableDepth++;
            self.headerRowDone = NO;
            self.tableRowsEmitted = 0;
            [self.output appendString:@"\n"];
        } else if ([n isEqualToString:@"tr"]) {
            self.currentRow = [NSMutableArray array];
        } else if ([n isEqualToString:@"tc"]) {
            self.currentCell = [NSMutableString string];
        }
    } else if (self.flavor == ORXMLFlavorPptx) {
        if ([n isEqualToString:@"p"]) {
            [self flushParagraph];
        } else if ([n isEqualToString:@"t"]) {
            self.inText = YES;
        } else if ([n isEqualToString:@"br"]) {
            [self.paragraph appendString:@"\n"];
        } else if ([n isEqualToString:@"tbl"]) {
            [self flushParagraph];
            self.tableDepth++;
            self.headerRowDone = NO;
            self.tableRowsEmitted = 0;
            [self.output appendString:@"\n"];
        } else if ([n isEqualToString:@"tr"]) {
            self.currentRow = [NSMutableArray array];
        } else if ([n isEqualToString:@"tc"]) {
            self.currentCell = [NSMutableString string];
        }
    } else {
        // OpenDocument: text:p, text:h, text:span, text:s, text:tab, text:line-break, table:table-row, table:table-cell
        if ([n isEqualToString:@"p"] || [n isEqualToString:@"h"]) {
            [self flushParagraph];
            if ([n isEqualToString:@"h"]) {
                NSInteger level = [attributeDict[@"text:outline-level"] integerValue];
                if (level < 1) level = 1;
                if (level > 6) level = 6;
                self.paragraphPrefix = [[@"" stringByPaddingToLength:level withString:@"#" startingAtIndex:0] stringByAppendingString:@" "];
            }
            self.inText = YES;
        } else if ([n isEqualToString:@"span"] || [n isEqualToString:@"a"]) {
            self.inText = YES;
        } else if ([n isEqualToString:@"s"]) {
            [self.paragraph appendString:@" "];
        } else if ([n isEqualToString:@"tab"]) {
            [self.paragraph appendString:@"\t"];
        } else if ([n isEqualToString:@"line-break"]) {
            [self.paragraph appendString:@"\n"];
        } else if ([n isEqualToString:@"list-item"]) {
            self.paragraphPrefix = @"- ";
        } else if ([n isEqualToString:@"table"]) {
            [self flushParagraph];
            self.tableDepth++;
            self.headerRowDone = NO;
            self.tableRowsEmitted = 0;
            NSString *name = attributeDict[@"table:name"];
            if (name.length) [self.output appendFormat:@"\n## %@\n\n", name];
            else [self.output appendString:@"\n"];
        } else if ([n isEqualToString:@"table-row"]) {
            self.currentRow = [NSMutableArray array];
        } else if ([n isEqualToString:@"table-cell"] || [n isEqualToString:@"covered-table-cell"]) {
            self.currentCell = [NSMutableString string];
        }
    }
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    if (!self.inText) return;
    if (self.output.length + self.paragraph.length > kMaxOutputChars) return;
    [self.paragraph appendString:string];
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    NSString *n = ORLocalName(elementName);
    if (self.flavor == ORXMLFlavorDocx || self.flavor == ORXMLFlavorPptx) {
        if ([n isEqualToString:@"t"]) {
            self.inText = NO;
        } else if ([n isEqualToString:@"p"]) {
            [self flushParagraph];
        } else if ([n isEqualToString:@"tc"]) {
            [self flushParagraph];
            if (self.currentCell) [self.currentRow addObject:self.currentCell];
            self.currentCell = nil;
        } else if ([n isEqualToString:@"tr"]) {
            [self emitRow];
        } else if ([n isEqualToString:@"tbl"]) {
            self.tableDepth--;
            [self.output appendString:@"\n"];
        }
    } else {
        if ([n isEqualToString:@"p"] || [n isEqualToString:@"h"]) {
            [self flushParagraph];
            self.inText = NO;
        } else if ([n isEqualToString:@"table-cell"] || [n isEqualToString:@"covered-table-cell"]) {
            [self flushParagraph];
            if (self.currentCell) [self.currentRow addObject:self.currentCell];
            self.currentCell = nil;
        } else if ([n isEqualToString:@"table-row"]) {
            [self emitRow];
        } else if ([n isEqualToString:@"table"]) {
            self.tableDepth--;
            [self.output appendString:@"\n"];
        }
    }
}

@end

#pragma mark - XLSX

@interface ORSharedStringsParser : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableArray *strings;
@property (nonatomic, strong) NSMutableString *current;
@property (nonatomic) BOOL inT;
@end

@implementation ORSharedStringsParser
- (NSArray *)parse:(NSData *)data
{
    self.strings = [NSMutableArray array];
    if (!data) return self.strings;
    NSXMLParser *p = [[NSXMLParser alloc] initWithData:data];
    p.delegate = self;
    [p parse];
    return self.strings;
}
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    NSString *n = ORLocalName(elementName);
    if ([n isEqualToString:@"si"]) self.current = [NSMutableString string];
    else if ([n isEqualToString:@"t"]) self.inT = YES;
}
- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    if (self.inT && self.current) [self.current appendString:string];
}
- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    NSString *n = ORLocalName(elementName);
    if ([n isEqualToString:@"t"]) self.inT = NO;
    else if ([n isEqualToString:@"si"]) {
        [self.strings addObject:self.current ?: @""];
        self.current = nil;
    }
}
@end

@interface ORSheetParser : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSArray *sharedStrings;
@property (nonatomic, strong) NSMutableString *output;
@property (nonatomic, strong) NSMutableDictionary *rowCells;   // column index -> text
@property (nonatomic) NSInteger currentCol;
@property (nonatomic, copy) NSString *cellType;
@property (nonatomic, strong) NSMutableString *value;
@property (nonatomic) BOOL inValue;
@property (nonatomic) NSInteger rowsEmitted;
@property (nonatomic) NSInteger maxCol;
@property (nonatomic) BOOL headerDone;
@end

static NSInteger ORColumnIndex(NSString *ref)
{
    NSInteger col = 0;
    for (NSUInteger i = 0; i < ref.length; i++) {
        unichar c = [ref characterAtIndex:i];
        if (c >= 'A' && c <= 'Z') col = col * 26 + (c - 'A' + 1);
        else if (c >= 'a' && c <= 'z') col = col * 26 + (c - 'a' + 1);
        else break;
    }
    return col - 1;
}

@implementation ORSheetParser
- (NSString *)parse:(NSData *)data
{
    self.output = [NSMutableString string];
    if (!data) return self.output;
    NSXMLParser *p = [[NSXMLParser alloc] initWithData:data];
    p.delegate = self;
    [p parse];
    return self.output;
}
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    NSString *n = ORLocalName(elementName);
    if ([n isEqualToString:@"row"]) {
        self.rowCells = [NSMutableDictionary dictionary];
        self.currentCol = -1;
    } else if ([n isEqualToString:@"c"]) {
        NSString *ref = attributeDict[@"r"];
        NSInteger col = ref ? ORColumnIndex(ref) : self.currentCol + 1;
        self.currentCol = col;
        self.cellType = attributeDict[@"t"] ?: @"n";
        self.value = [NSMutableString string];
    } else if ([n isEqualToString:@"v"] || [n isEqualToString:@"t"]) {
        self.inValue = YES;
    }
}
- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string
{
    if (self.inValue && self.value) [self.value appendString:string];
}
- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName
{
    NSString *n = ORLocalName(elementName);
    if ([n isEqualToString:@"v"] || [n isEqualToString:@"t"]) {
        self.inValue = NO;
    } else if ([n isEqualToString:@"c"]) {
        NSString *text = self.value ?: @"";
        if ([self.cellType isEqualToString:@"s"]) {
            NSInteger idx = [text integerValue];
            text = (idx >= 0 && (NSUInteger)idx < self.sharedStrings.count) ? self.sharedStrings[idx] : @"";
        } else if ([self.cellType isEqualToString:@"b"]) {
            text = [text isEqualToString:@"1"] ? @"TRUE" : @"FALSE";
        }
        if (self.currentCol >= 0 && self.currentCol < kMaxSheetCols && self.rowCells) {
            self.rowCells[@(self.currentCol)] = text;
            if (self.currentCol > self.maxCol) self.maxCol = self.currentCol;
        }
        self.value = nil;
    } else if ([n isEqualToString:@"row"]) {
        if (self.rowCells.count && self.rowsEmitted < kMaxSheetRows) {
            NSInteger cols = MIN(self.maxCol + 1, kMaxSheetCols);
            NSMutableArray *cells = [NSMutableArray array];
            for (NSInteger i = 0; i < cols; i++) {
                NSString *c = self.rowCells[@(i)] ?: @"";
                c = [c stringByReplacingOccurrencesOfString:@"|" withString:@"\\|"];
                c = [c stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
                [cells addObject:c];
            }
            [self.output appendFormat:@"| %@ |\n", [cells componentsJoinedByString:@" | "]];
            if (!self.headerDone) {
                NSMutableArray *seps = [NSMutableArray array];
                for (NSInteger i = 0; i < cols; i++) [seps addObject:@"---"];
                [self.output appendFormat:@"| %@ |\n", [seps componentsJoinedByString:@" | "]];
                self.headerDone = YES;
            }
        }
        if (self.rowCells.count) self.rowsEmitted++;
        self.rowCells = nil;
    }
}
@end

// Extracts <sheet name="" r:id=""/> order from workbook.xml and Id->Target from the rels part.
@interface ORWorkbookParser : NSObject <NSXMLParserDelegate>
@property (nonatomic, strong) NSMutableArray *sheets;   // dict name, rid
@property (nonatomic, strong) NSMutableDictionary *rels; // rid -> target
@end
@implementation ORWorkbookParser
- (void)parseData:(NSData *)data
{
    if (!data) return;
    NSXMLParser *p = [[NSXMLParser alloc] initWithData:data];
    p.delegate = self;
    [p parse];
}
- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict
{
    NSString *n = ORLocalName(elementName);
    if ([n isEqualToString:@"sheet"]) {
        if (!self.sheets) self.sheets = [NSMutableArray array];
        NSString *rid = attributeDict[@"r:id"];
        if (!rid) {
            for (NSString *k in attributeDict) if ([k hasSuffix:@":id"]) { rid = attributeDict[k]; break; }
        }
        [self.sheets addObject:@{ @"name": attributeDict[@"name"] ?: @"Sheet", @"rid": rid ?: @"" }];
    } else if ([n isEqualToString:@"Relationship"]) {
        if (!self.rels) self.rels = [NSMutableDictionary dictionary];
        NSString *rid = attributeDict[@"Id"], *target = attributeDict[@"Target"];
        if (rid && target) self.rels[rid] = target;
    }
}
@end

#pragma mark - Converter

@implementation ORDocumentConverter

+ (NSSet *)extensions
{
    static NSSet *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [NSSet setWithArray:@[ @"docx", @"xlsx", @"pptx", @"odt", @"ods", @"odp", @"html", @"htm", @"xhtml", @"rtf" ]];
    });
    return s;
}

+ (BOOL)canConvertPath:(NSString *)path
{
    return [[self extensions] containsObject:[[path pathExtension] lowercaseString]];
}

+ (NSString *)markdownForFileAtPath:(NSString *)path
{
    NSString *ext = [[path pathExtension] lowercaseString];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;
    @try {
        if ([ext isEqualToString:@"docx"]) return [self convertDocx:data];
        if ([ext isEqualToString:@"xlsx"]) return [self convertXlsx:data];
        if ([ext isEqualToString:@"pptx"]) return [self convertPptx:data];
        if ([ext isEqualToString:@"odt"] || [ext isEqualToString:@"ods"] || [ext isEqualToString:@"odp"]) return [self convertOpenDocument:data];
        if ([ext isEqualToString:@"html"] || [ext isEqualToString:@"htm"] || [ext isEqualToString:@"xhtml"]) return [self convertHTML:data];
        if ([ext isEqualToString:@"rtf"]) return [self convertRTF:data];
    } @catch (NSException *ex) {
        ORLog(@"Document conversion failed: %@", ex);
    }
    return nil;
}

+ (NSString *)convertDocx:(NSData *)data
{
    ORZipArchive *zip = [[ORZipArchive alloc] initWithData:data];
    NSData *doc = [zip dataForEntry:@"word/document.xml"];
    if (!doc) return nil;
    ORXMLTextExtractor *ex = [[ORXMLTextExtractor alloc] initWithFlavor:ORXMLFlavorDocx];
    NSMutableString *out = [NSMutableString stringWithString:[ex extractFromData:doc] ?: @""];
    // Footnotes are worth keeping; headers/footers usually are not.
    NSData *foot = [zip dataForEntry:@"word/footnotes.xml"];
    if (foot) {
        ORXMLTextExtractor *fx = [[ORXMLTextExtractor alloc] initWithFlavor:ORXMLFlavorDocx];
        NSString *f = [[fx extractFromData:foot] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (f.length) [out appendFormat:@"\n---\n%@\n", f];
    }
    return out;
}

+ (NSString *)convertPptx:(NSData *)data
{
    ORZipArchive *zip = [[ORZipArchive alloc] initWithData:data];
    NSMutableArray *slides = [NSMutableArray array];
    for (NSString *name in [zip entryNames]) {
        if ([name hasPrefix:@"ppt/slides/slide"] && [name hasSuffix:@".xml"]) [slides addObject:name];
    }
    if (!slides.count) return nil;
    [slides sortUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        NSInteger na = [[[a lastPathComponent] stringByTrimmingCharactersInSet:[NSCharacterSet letterCharacterSet]] integerValue];
        NSInteger nb = [[[b lastPathComponent] stringByTrimmingCharactersInSet:[NSCharacterSet letterCharacterSet]] integerValue];
        if (na == nb) return NSOrderedSame;
        return na < nb ? NSOrderedAscending : NSOrderedDescending;
    }];
    NSMutableString *out = [NSMutableString string];
    NSInteger i = 1;
    for (NSString *name in slides) {
        ORXMLTextExtractor *ex = [[ORXMLTextExtractor alloc] initWithFlavor:ORXMLFlavorPptx];
        NSString *text = [[ex extractFromData:[zip dataForEntry:name]] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        [out appendFormat:@"## Slide %ld\n\n%@\n\n", (long)i, text ?: @""];
        NSString *notes = [NSString stringWithFormat:@"ppt/notesSlides/notesSlide%ld.xml", (long)i];
        NSData *nd = [zip dataForEntry:notes];
        if (nd) {
            ORXMLTextExtractor *nx = [[ORXMLTextExtractor alloc] initWithFlavor:ORXMLFlavorPptx];
            NSString *nt = [[nx extractFromData:nd] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (nt.length) [out appendFormat:@"*Notes:* %@\n\n", nt];
        }
        i++;
        if (out.length > kMaxOutputChars) break;
    }
    return out;
}

+ (NSString *)convertXlsx:(NSData *)data
{
    ORZipArchive *zip = [[ORZipArchive alloc] initWithData:data];
    if (!zip) return nil;
    NSArray *shared = [[[ORSharedStringsParser alloc] init] parse:[zip dataForEntry:@"xl/sharedStrings.xml"]];
    ORWorkbookParser *wb = [[ORWorkbookParser alloc] init];
    [wb parseData:[zip dataForEntry:@"xl/workbook.xml"]];
    [wb parseData:[zip dataForEntry:@"xl/_rels/workbook.xml.rels"]];

    NSMutableArray *sheetFiles = [NSMutableArray array];   // dicts name, entry
    for (NSDictionary *s in wb.sheets) {
        NSString *target = wb.rels[s[@"rid"]];
        if (target) {
            if ([target hasPrefix:@"/"]) target = [target substringFromIndex:1];
            else if (![target hasPrefix:@"xl/"]) target = [@"xl/" stringByAppendingString:target];
            [sheetFiles addObject:@{ @"name": s[@"name"], @"entry": target }];
        }
    }
    if (!sheetFiles.count) {
        NSInteger n = 1;
        for (NSString *name in [zip entryNames]) {
            if ([name hasPrefix:@"xl/worksheets/sheet"] && [name hasSuffix:@".xml"]) {
                [sheetFiles addObject:@{ @"name": [NSString stringWithFormat:@"Sheet %ld", (long)n++], @"entry": name }];
            }
        }
    }
    NSMutableString *out = [NSMutableString string];
    for (NSDictionary *s in sheetFiles) {
        ORSheetParser *sp = [[ORSheetParser alloc] init];
        sp.sharedStrings = shared;
        NSString *table = [sp parse:[zip dataForEntry:s[@"entry"]]];
        [out appendFormat:@"## %@\n\n%@\n", s[@"name"], table.length ? table : @"(empty)\n"];
        if (sp.rowsEmitted > kMaxSheetRows) [out appendFormat:@"(%ld more rows omitted)\n\n", (long)(sp.rowsEmitted - kMaxSheetRows)];
        if (out.length > kMaxOutputChars) break;
    }
    return out;
}

+ (NSString *)convertOpenDocument:(NSData *)data
{
    ORZipArchive *zip = [[ORZipArchive alloc] initWithData:data];
    NSData *content = [zip dataForEntry:@"content.xml"];
    if (!content) return nil;
    ORXMLTextExtractor *ex = [[ORXMLTextExtractor alloc] initWithFlavor:ORXMLFlavorOpenDocument];
    return [ex extractFromData:content];
}

+ (NSString *)decodeEntities:(NSString *)s
{
    NSDictionary *map = @{ @"&nbsp;": @" ", @"&amp;": @"&", @"&lt;": @"<", @"&gt;": @">", @"&quot;": @"\"", @"&#39;": @"'", @"&apos;": @"'", @"&#160;": @" " };
    NSMutableString *m = [s mutableCopy];
    for (NSString *k in map) [m replaceOccurrencesOfString:k withString:map[k] options:NSCaseInsensitiveSearch range:NSMakeRange(0, m.length)];
    // Numeric entities
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"&#(x?[0-9a-fA-F]+);" options:0 error:NULL];
    NSArray *matches = [re matchesInString:m options:0 range:NSMakeRange(0, m.length)];
    for (NSTextCheckingResult *r in [matches reverseObjectEnumerator]) {
        NSString *num = [m substringWithRange:[r rangeAtIndex:1]];
        unsigned int code = 0;
        if ([num hasPrefix:@"x"] || [num hasPrefix:@"X"]) {
            NSScanner *sc = [NSScanner scannerWithString:[num substringFromIndex:1]];
            [sc scanHexInt:&code];
        } else {
            code = (unsigned int)[num integerValue];
        }
        if (code > 0 && code < 0x110000) {
            NSString *ch = [[NSString alloc] initWithBytes:&code length:4 encoding:NSUTF32LittleEndianStringEncoding];
            if (ch) [m replaceCharactersInRange:r.range withString:ch];
        }
    }
    return m;
}

+ (NSString *)convertHTML:(NSData *)data
{
    NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!html) html = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (!html) return nil;
    NSMutableString *s = [html mutableCopy];
    NSArray *dropBlocks = @[ @"<script[^>]*>[\\s\\S]*?</script>", @"<style[^>]*>[\\s\\S]*?</style>", @"<!--[\\s\\S]*?-->", @"<head[^>]*>[\\s\\S]*?</head>" ];
    for (NSString *pat in dropBlocks) {
        NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pat options:NSRegularExpressionCaseInsensitive error:NULL];
        [re replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@""];
    }
    NSRegularExpression *br = [NSRegularExpression regularExpressionWithPattern:@"<(br|/p|/div|/li|/tr|/h[1-6]|/table|/blockquote|/pre)\\s*/?>" options:NSRegularExpressionCaseInsensitive error:NULL];
    [br replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"\n"];
    NSRegularExpression *li = [NSRegularExpression regularExpressionWithPattern:@"<li[^>]*>" options:NSRegularExpressionCaseInsensitive error:NULL];
    [li replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@"- "];
    NSRegularExpression *td = [NSRegularExpression regularExpressionWithPattern:@"</t[dh]>" options:NSRegularExpressionCaseInsensitive error:NULL];
    [td replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@" | "];
    NSRegularExpression *h = [NSRegularExpression regularExpressionWithPattern:@"<h([1-6])[^>]*>" options:NSRegularExpressionCaseInsensitive error:NULL];
    NSArray *hm = [h matchesInString:s options:0 range:NSMakeRange(0, s.length)];
    for (NSTextCheckingResult *r in [hm reverseObjectEnumerator]) {
        NSInteger level = [[s substringWithRange:[r rangeAtIndex:1]] integerValue];
        NSString *prefix = [[@"\n" stringByAppendingString:[@"" stringByPaddingToLength:level withString:@"#" startingAtIndex:0]] stringByAppendingString:@" "];
        [s replaceCharactersInRange:r.range withString:prefix];
    }
    NSRegularExpression *tags = [NSRegularExpression regularExpressionWithPattern:@"<[^>]+>" options:0 error:NULL];
    [tags replaceMatchesInString:s options:0 range:NSMakeRange(0, s.length) withTemplate:@""];
    NSString *out = [self decodeEntities:s];
    NSRegularExpression *blank = [NSRegularExpression regularExpressionWithPattern:@"[ \\t]*\\n[ \\t]*(\\n[ \\t]*)+" options:0 error:NULL];
    out = [blank stringByReplacingMatchesInString:out options:0 range:NSMakeRange(0, out.length) withTemplate:@"\n\n"];
    NSRegularExpression *spaces = [NSRegularExpression regularExpressionWithPattern:@"[ \\t]{2,}" options:0 error:NULL];
    out = [spaces stringByReplacingMatchesInString:out options:0 range:NSMakeRange(0, out.length) withTemplate:@" "];
    return [out stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (NSString *)convertRTF:(NSData *)data
{
    NSString *rtf = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
    if (!rtf) rtf = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    if (!rtf) return nil;
    NSMutableString *out = [NSMutableString string];
    NSUInteger i = 0, n = rtf.length;
    NSInteger skipDepth = -1, depth = 0;
    while (i < n) {
        unichar c = [rtf characterAtIndex:i];
        if (c == '{') { depth++; i++; continue; }
        if (c == '}') { if (skipDepth == depth) skipDepth = -1; depth--; i++; continue; }
        if (c == '\\') {
            i++;
            if (i >= n) break;
            unichar d = [rtf characterAtIndex:i];
            if (d == '\'' && i + 2 < n) {
                unsigned int code = 0;
                [[NSScanner scannerWithString:[rtf substringWithRange:NSMakeRange(i + 1, 2)]] scanHexInt:&code];
                if (skipDepth < 0) [out appendFormat:@"%C", (unichar)code];
                i += 3;
                continue;
            }
            if (d == '*' ) { skipDepth = depth; i++; continue; }
            if (!isalpha(d)) { if (skipDepth < 0 && (d == '\\' || d == '{' || d == '}')) [out appendFormat:@"%C", d]; i++; continue; }
            NSUInteger start = i;
            while (i < n && isalpha([rtf characterAtIndex:i])) i++;
            NSString *word = [rtf substringWithRange:NSMakeRange(start, i - start)];
            NSInteger param = 0; BOOL hasParam = NO, neg = NO;
            if (i < n && [rtf characterAtIndex:i] == '-') { neg = YES; i++; }
            while (i < n && isdigit([rtf characterAtIndex:i])) { hasParam = YES; param = param * 10 + ([rtf characterAtIndex:i] - '0'); i++; }
            if (neg) param = -param;
            if (i < n && [rtf characterAtIndex:i] == ' ') i++;
            if ([word isEqualToString:@"fonttbl"] || [word isEqualToString:@"colortbl"] || [word isEqualToString:@"stylesheet"] ||
                [word isEqualToString:@"info"] || [word isEqualToString:@"pict"] || [word isEqualToString:@"header"] || [word isEqualToString:@"footer"]) {
                skipDepth = depth;
            } else if (skipDepth < 0) {
                if ([word isEqualToString:@"par"] || [word isEqualToString:@"line"]) [out appendString:@"\n"];
                else if ([word isEqualToString:@"tab"]) [out appendString:@"\t"];
                else if ([word isEqualToString:@"u"] && hasParam) { [out appendFormat:@"%C", (unichar)(param < 0 ? param + 65536 : param)]; if (i < n) i++; }
            }
            continue;
        }
        if (skipDepth < 0 && c != '\r' && c != '\n') [out appendFormat:@"%C", c];
        i++;
    }
    return out;
}

@end
