#import "SSELibraryEntry.h"

#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <SnoizeMIDI/SnoizeMIDI.h>

#import "BDAlias.h"
#import "SSELibrary.h"


@interface SSELibraryEntry (Private)

+ (NSString *)_manufacturerNameFromMessages:(NSArray *)messages;
+ (NSNumber *)_sizeFromMessages:(NSArray *)messages;
+ (NSNumber *)_messageCountFromMessages:(NSArray *)messages;

- (void)_takeValuesFromDictionary:(NSDictionary *)dict;

- (void)_updateDerivedInformationFromMessages:(NSArray *)messages;

- (void)_setManufacturerName:(NSString *)value;
- (void)_setSize:(NSNumber *)value;
- (void)_setMessageCount:(NSNumber *)value;

@end


@implementation SSELibraryEntry

- (id)initWithLibrary:(SSELibrary *)library;
{
    if (![super init])
        return nil;

    nonretainedLibrary = library;
    flags.hasLookedForFile = NO;
    flags.isFilePresent = NO;

    return self;
}

- (id)initWithLibrary:(SSELibrary *)library dictionary:(NSDictionary *)dict;
{
    if (![self initWithLibrary:library])
        return nil;

    [self _takeValuesFromDictionary:dict];
    
    return self;
}

- (id)init;
{
    OBRejectUnusedImplementation(self, _cmd);
    return nil;
}

- (void)dealloc
{
    nonretainedLibrary = nil;

    [name release];
    name = nil;
    [alias release];
    alias = nil;

    [manufacturerName release];
    manufacturerName = nil;
    [sizeNumber release];
    sizeNumber = nil;
    [messageCountNumber release];
    messageCountNumber = nil;
    
    [super dealloc];
}

- (NSDictionary *)dictionaryValues;
{
    NSMutableDictionary *dict;

    dict = [NSMutableDictionary dictionary];
    if (alias)
        [dict setObject:[alias aliasData] forKey:@"alias"];
    if (name)
        [dict setObject:name forKey:@"name"];

    if (manufacturerName)
        [dict setObject:manufacturerName forKey:@"manufacturerName"];
    if (sizeNumber)
        [dict setObject:sizeNumber forKey:@"size"];
    if (messageCountNumber)
        [dict setObject:messageCountNumber forKey:@"messageCount"];

    return dict;
}

- (NSString *)path;
{
    BOOL wasFilePresent;
    NSString *path;

    wasFilePresent = flags.hasLookedForFile && flags.isFilePresent;
    
    path = [alias fullPath];

    flags.hasLookedForFile = YES;
    flags.isFilePresent = (path && [[NSFileManager defaultManager] fileExistsAtPath:path]);

    if (flags.isFilePresent != wasFilePresent)
        [nonretainedLibrary noteEntryChanged];

    return path;
}

- (void)setPath:(NSString *)value;
{
    [alias release];
    alias = [[BDAlias alloc] initWithPath:value];

    [nonretainedLibrary noteEntryChanged];
}

- (NSString *)name;
{
    return name;
}

- (void)setName:(NSString *)value;
{
    // TODO should we also rename the file that the alias points to? maybe...
    if (name != value) {
        [name release];
        name = [value retain];

        [nonretainedLibrary noteEntryChanged];
    }
}

- (void)setNameFromFile;
{
    NSString *path;
    NSString *newName;

    if ((path = [self path]))
        newName = [[NSFileManager defaultManager] displayNameAtPath:path];

    if (!newName)
        newName = @"Unknown";
        // TODO do we really want this when the file isn't present?
        // TODO localize

    [self setName:newName];
}

- (NSArray *)messages;
{
    NSString *path;
    SSELibraryFileType fileType;
    NSArray *messages;

    path = [self path];
    if (!path)
        return nil;

    fileType = [nonretainedLibrary typeOfFileAtPath:path];

    if (fileType == SSELibraryFileTypeStandardMIDI) {
        messages = [SMSystemExclusiveMessage systemExclusiveMessagesInStandardMIDIFile:path];
    } else if (fileType == SSELibraryFileTypeRaw) {
        NSData *data;

        if ((data = [NSData dataWithContentsOfFile:path]))
            messages = [SMSystemExclusiveMessage systemExclusiveMessagesInData:data];
    }

    // Always update this stuff when we read the messages
    [self _updateDerivedInformationFromMessages:messages];
    
    return messages;
}

- (NSString *)manufacturerName;
{
    return manufacturerName;
}

- (unsigned int)size;
{
    return [sizeNumber unsignedIntValue];
}

- (unsigned int)messageCount;
{
    return [messageCountNumber unsignedIntValue];
}

- (BOOL)isFilePresent;
{
    if (!flags.hasLookedForFile)
        [self path];

    OBASSERT(flags.hasLookedForFile);
    return flags.isFilePresent;
}

@end


@implementation SSELibraryEntry (Private)

+ (NSString *)_manufacturerNameFromMessages:(NSArray *)messages;
{
    unsigned int messageIndex;
    NSString *newName = nil;

    messageIndex = [messages count];
    while (messageIndex--) {
        NSString *messageManufacturerName;

        messageManufacturerName = [[messages objectAtIndex:messageIndex] manufacturerName];
        if (!messageManufacturerName)
            continue;

        if (!newName) {
            newName = messageManufacturerName;
        } else if (![messageManufacturerName isEqualToString:newName]) {
            newName = @"Various";
            // TODO localize
            break;
        }
    }

    if (!newName)
        newName = @"Unknown";	// TODO localize or get from SnoizeMIDI framework

    return newName;
}

+ (NSNumber *)_sizeFromMessages:(NSArray *)messages;
{
    unsigned int messageIndex;
    unsigned int size = 0;

    messageIndex = [messages count];
    while (messageIndex--)
        size += [[messages objectAtIndex:messageIndex] fullMessageDataLength];

    return [NSNumber numberWithUnsignedInt:size];
}

+ (NSNumber *)_messageCountFromMessages:(NSArray *)messages;
{
    return [NSNumber numberWithUnsignedInt:[messages count]];
}

- (void)_takeValuesFromDictionary:(NSDictionary *)dict;
{
    id data, string, number;

    OBASSERT(alias == nil);
    data = [dict objectForKey:@"alias"];
    if (data && [data isKindOfClass:[NSData class]])
        alias = [[BDAlias alloc] initWithData:data];

    OBASSERT(name == nil);
    string = [dict objectForKey:@"name"];
    if (string && [string isKindOfClass:[NSString class]]) {
        name = [string retain];
    } else {
        [self setNameFromFile];
    }

    OBASSERT(manufacturerName == nil);
    string = [dict objectForKey:@"manufacturerName"];
    if (string && [string isKindOfClass:[NSString class]]) {
        manufacturerName = [string retain];
    }

    OBASSERT(sizeNumber == nil);
    number = [dict objectForKey:@"size"];
    if (number && [number isKindOfClass:[NSNumber class]]) {
        sizeNumber = [number retain];
    }

    OBASSERT(messageCountNumber == nil);
    number = [dict objectForKey:@"messageCount"];
    if (number && [number isKindOfClass:[NSNumber class]]) {
        messageCountNumber = [number retain];
    }
}

- (void)_updateDerivedInformationFromMessages:(NSArray *)messages;
{
    [self _setManufacturerName:[[self class] _manufacturerNameFromMessages:messages]];
    [self _setSize:[[self class] _sizeFromMessages:messages]];
    [self _setMessageCount:[[self class] _messageCountFromMessages:messages]];
}

- (void)_setManufacturerName:(NSString *)value;
{
    if (value != manufacturerName && ![manufacturerName isEqualToString:value]) {
        [manufacturerName release];
        manufacturerName = [value retain];

        [nonretainedLibrary noteEntryChanged];
    }
}

- (void)_setSize:(NSNumber *)value;
{
    if (value != sizeNumber && ![sizeNumber isEqual:value]) {
        [sizeNumber release];
        sizeNumber = [value retain];
        
        [nonretainedLibrary noteEntryChanged];
    }
}

- (void)_setMessageCount:(NSNumber *)value;
{
    if (value != messageCountNumber && ![messageCountNumber isEqual:value]) {
        [messageCountNumber release];
        messageCountNumber = [value retain];

        [nonretainedLibrary noteEntryChanged];
    }
}

@end
