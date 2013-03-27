//
//  Device.m
//  PartyMusic
//
//  Created by Tom Irving on 12/02/2013.
//  Copyright (c) 2013 Tom Irving. All rights reserved.
//

#import "Device.h"
#import "DevicesManager.h"
#import "GCDAsyncSocket.h"
#import "NSNetService+Additions.h"
#import "MusicQueueController.h"

NSString * const kDeviceUUIDKeyName = @"DeviceUUIDKeyName";
NSString * const kDeviceInterfaceOrientationKeyName = @"DeviceInterfaceOrientationKeyName";
NSString * const kDeviceIsOutputKeyName = @"DeviceIsOutputKeyName";
NSString * const kDeviceActionKeyName = @"DeviceActionKeyName";
NSString * const kDeviceSearchIdentifierKeyName = @"DeviceSearchIdentifierKeyName";
NSString * const kDeviceSearchArtistsKeyName = @"DeviceSearchArtistsKeyName";
NSString * const kDeviceSearchAlbumsKeyName = @"DeviceSearchResultAlbumsKeyName";
NSString * const kDeviceSearchSongsKeyName = @"DeviceSearchSongsKeyName";
NSString * const kDeviceSongIdentifierKeyName = @"DeviceSongIdentifierKeyName";
NSString * const kDeviceQueueChangeResultKeyName = @"DeviceQueueChangeResultKeyName";

NSInteger const kSocketReadTagHead = 0;
NSInteger const kSocketReadTagBody = 1;

@interface Device () <GCDAsyncSocketDelegate>
@property (nonatomic, retain) DevicePacket * incomingPacket;
- (void)sendData:(NSData *)data;
- (BOOL)connect:(NSError **)error;
- (void)handlePacketReceived:(DevicePacket *)packet;
- (void)handleOutputChange:(NSDictionary *)payload;
- (void)handleInterfaceOrientationChange:(NSDictionary *)payload;
@end

@implementation Device
@synthesize delegate;
@synthesize netService;
@synthesize outgoingSocket;
@synthesize incomingSocket;
@synthesize UUID;
@synthesize interfaceIdiom;
@synthesize interfaceOrientation;
@synthesize isOutput;
@synthesize incomingPacket;

#pragma mark - Init
- (id)initWithNetService:(NSNetService *)service {
	
	if ((self = [super init])){
		
		netService = [service retain];
		incomingQueue = nil;
		outgoingQueue = dispatch_queue_create("com.partymusic.device.outgoingsocketqueue", NULL);
		outgoingSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:outgoingQueue];
		interfaceIdiom = [[netService.TXTRecordDictionary objectForKey:kUserInterfaceIdiomTXTRecordKeyName] integerValue];
		isOutput = NO;
		callbacks = [[NSMutableDictionary alloc] init];
		
		[self connect:NULL];
	}
	
	return self;
}

#pragma mark - Property Overrides
- (BOOL)isOwnDevice {
	return NO;
}

- (void)setIncomingSocket:(GCDAsyncSocket *)socket {
	
	if (!incomingQueue) incomingQueue = dispatch_queue_create("com.partymusic.device.incomingsocketqueue", NULL);
	
	[socket retain];
	[incomingSocket release];
	incomingSocket = socket;
	
	[incomingSocket setDelegate:self delegateQueue:incomingQueue];
	[incomingSocket readDataToLength:sizeof(DevicePacketHeader) withTimeout:-1 tag:kSocketReadTagHead];
}

- (NSString *)name {
	return netService.name;
}

#pragma mark - Instance Methods
- (BOOL)connect:(NSError **)error {
	return [outgoingSocket connectToAddress:[netService.addresses objectAtIndex:0] error:error];
}

#pragma mark - Convenient Senders
- (void)sendData:(NSData *)data {
	[outgoingSocket writeData:data withTimeout:10 tag:0];
}

- (void)sendDictionary:(NSDictionary *)dictionary payloadType:(DevicePayloadType)payloadType identifier:(NSString *)identifier {
	
	NSData * dictionaryData = (dictionary ? [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:NULL] : nil);
	DevicePacketHeader packetHeader = DevicePacketHeaderMake(payloadType, dictionaryData.length, identifier, NO);
	[self sendData:DevicePacketHeaderToData(packetHeader, dictionaryData)];
}

- (void)sendAction:(DeviceAction)action {
	[self sendDictionary:@{kDeviceActionKeyName : [NSNumber numberWithInteger:action]} payloadType:DevicePayloadTypeAction identifier:nil];
}

- (void)sendSearchRequest:(NSString *)searchString callback:(DeviceSearchCallback)callback {
	
	NSString * identifier = [NSString UUID];
	[callbacks setObject:[[callback copy] autorelease] forKey:identifier];
	[self sendDictionary:@{kDeviceSearchIdentifierKeyName : searchString} payloadType:DevicePayloadTypeSearchRequest identifier:identifier];
}

- (void)sendBrowseLibraryRequestWithCallback:(DeviceSearchCallback)callback {
	
	NSString * identifier = [NSString UUID];
	[callbacks setObject:[[callback copy] autorelease] forKey:identifier];
	[self sendDictionary:nil payloadType:DevicePayloadTypeBrowseRequest identifier:identifier];
}

- (void)sendAlbumsForArtistRequest:(NSNumber *)persistentID callback:(DeviceSearchCallback)callback {
	
	NSString * identifier = [NSString UUID];
	[callbacks setObject:[[callback copy] autorelease] forKey:identifier];
	[self sendDictionary:@{kDeviceSearchIdentifierKeyName : persistentID} payloadType:DevicePayloadTypeAlbumsRequest identifier:identifier];
}

- (void)sendSongsForAlbumRequest:(NSNumber *)persistentID callback:(DeviceSearchCallback)callback {
	
	NSString * identifier = [NSString UUID];
	[callbacks setObject:[[callback copy] autorelease] forKey:identifier];
	[self sendDictionary:@{kDeviceSearchIdentifierKeyName : persistentID} payloadType:DevicePayloadTypeSongsRequest identifier:identifier];
}

- (void)sendSearchResults:(NSDictionary *)results identifier:(NSString *)identifier {
	[self sendDictionary:results payloadType:DevicePayloadTypeSearchResults identifier:identifier];
}

- (void)sendBrowseLibraryResults:(NSDictionary *)results identifier:(NSString *)identifier {
	[self sendDictionary:results payloadType:DevicePayloadTypeBrowseResults identifier:identifier];
}

- (void)sendAlbumsForArtistResults:(NSArray *)results identifier:(NSString *)identifier {
	[self sendDictionary:@{kDeviceSearchAlbumsKeyName : results} payloadType:DevicePayloadTypeAlbumsResults identifier:identifier];
}

- (void)sendSongsForAlbumResults:(NSArray *)results identifier:(NSString *)identifier {
	[self sendDictionary:@{kDeviceSearchSongsKeyName : results} payloadType:DevicePayloadTypeSongsResults identifier:identifier];
}

- (void)sendSongRequest:(NSNumber *)persistentID callback:(DeviceSongCallback)callback {
	
	NSString * identifier = [NSString UUID];
	[callbacks setObject:[[callback copy] autorelease] forKey:identifier];
	[self sendDictionary:@{kDeviceSongIdentifierKeyName : persistentID} payloadType:DevicePayloadTypeSongRequest identifier:identifier];
}

- (void)cancelSongRequest:(NSNumber *)persistentID {
	[self sendDictionary:@{kDeviceSongIdentifierKeyName : persistentID} payloadType:DevicePayloadTypeSongCancel identifier:nil];
}

- (void)sendSongResult:(NSData *)song identifier:(NSString *)identifier moreComing:(BOOL)moreComing {
	
	DevicePacketHeader packetHeader = DevicePacketHeaderMake(DevicePayloadTypeSongResult, song.length, identifier, moreComing);
	[self sendData:DevicePacketHeaderToData(packetHeader, song)];
}

- (void)sendQueueStatus:(NSDictionary *)queueStatus {
	[self sendDictionary:queueStatus payloadType:DevicePayloadTypeQueueStatus identifier:nil];
}

- (void)queueItem:(MusicQueueItem *)item callback:(DeviceQueueCallback)callback {
	
	NSString * identifier = [NSString UUID];
	[callbacks setObject:[[callback copy] autorelease] forKey:identifier];
	[self sendDictionary:item.JSONDictionary payloadType:DevicePayloadTypeQueueChange identifier:identifier];
}

#pragma mark - Socket Delegate
- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
	if (sock == outgoingSocket)
		[self sendDictionary:[[[DevicesManager sharedManager] ownDevice] deviceStatusDictionary] payloadType:DevicePayloadTypeDeviceStatus identifier:nil];
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
	
	if (tag == kSocketReadTagHead){
		
		DevicePacketHeader packetHeader;
		[data getBytes:&packetHeader length:sizeof(packetHeader)];
		
		DevicePacket * packet = [[DevicePacket alloc] initWithDevicePacketHeader:packetHeader];
		[self setIncomingPacket:packet];
		[packet release];
		
		if (packetHeader.payloadLength){
			[sock readDataToLength:incomingPacket.lengthRequired withTimeout:-1 tag:kSocketReadTagBody];
		}
		else
		{
			[self handlePacketReceived:packet];
			[self setIncomingPacket:nil];
		}
	}
	else if (tag == kSocketReadTagBody){
		
		if ([incomingPacket appendData:data]){
			[self handlePacketReceived:incomingPacket];
			[self setIncomingPacket:nil];
			[sock readDataToLength:sizeof(DevicePacketHeader) withTimeout:-1 tag:kSocketReadTagHead];
		}
		else
		{
			[sock readDataToLength:incomingPacket.lengthRequired withTimeout:-1 tag:kSocketReadTagBody];
		}
	}
}

#pragma mark - Socket Read Helpers
- (void)handlePacketReceived:(DevicePacket *)packet {
	
	DevicePayloadType type = packet.payloadType;
	NSDictionary * payload = (incomingPacket.payloadType != DevicePayloadTypeSongResult ? incomingPacket.data.JSONValue : nil);
	
	if (type == DevicePayloadTypeDeviceStatus){
		[self setUUID:[payload objectForKey:kDeviceUUIDKeyName]];
		[self handleInterfaceOrientationChange:payload];
		[self handleOutputChange:payload];
	}
	else if (type == DevicePayloadTypeAction){
		if ([delegate respondsToSelector:@selector(device:didReceiveAction:)]){
			dispatch_async(dispatch_get_main_queue(), ^{
				[delegate device:self didReceiveAction:[[payload objectForKey:kDeviceActionKeyName] integerValue]];
			});
		}
	}
	else if (type == DevicePayloadTypeBrowseRequest){
		
		NSDictionary * results = nil;
		if ([delegate respondsToSelector:@selector(device:didReceiveBrowseRequestWithIdentifier:)]){
			results = [delegate device:self didReceiveBrowseRequestWithIdentifier:packet.identifier];
		}
		
		if (results) [self sendBrowseLibraryResults:results identifier:packet.identifier];
	}
	else if (type == DevicePayloadTypeBrowseResults || type == DevicePayloadTypeSearchResults || type == DevicePayloadTypeAlbumsResults || type == DevicePayloadTypeSongsResults){
		
		DeviceSearchCallback callback = [callbacks objectForKey:packet.identifier];
		if (callback) callback(payload);
		if (packet.identifier) [callbacks removeObjectForKey:packet.identifier];
	}
	else if (type == DevicePayloadTypeSearchRequest){
		
		NSDictionary * results = nil;
		if ([delegate respondsToSelector:@selector(device:didReceiveSearchRequest:identifier:)]){
			results = [delegate device:self didReceiveSearchRequest:[payload objectForKey:kDeviceSearchIdentifierKeyName] identifier:packet.identifier];
		}
		
		if (results) [self sendSearchResults:results identifier:packet.identifier];
	}
	else if (type == DevicePayloadTypeSongRequest){
		
		if ([delegate respondsToSelector:@selector(device:didReceiveSongRequest:identifier:)]){
			[delegate device:self didReceiveSongRequest:[payload objectForKey:kDeviceSongIdentifierKeyName] identifier:packet.identifier];
		}
	}
	else if (type == DevicePayloadTypeSongCancel){
		
		if ([delegate respondsToSelector:@selector(device:didReceiveSongCancel:)]){
			[delegate device:self didReceiveSongCancel:[payload objectForKey:kDeviceSongIdentifierKeyName]];
		}
	}
	else if (type == DevicePayloadTypeSongResult){
		
		DeviceSongCallback callback = [callbacks objectForKey:packet.identifier];
		if (callback) callback(packet.data, packet.moreComing);
		if (packet.identifier && !packet.moreComing) [callbacks removeObjectForKey:packet.identifier];
	}
	else if (type == DevicePayloadTypeQueueChange){
		
		MusicQueueItem * item = [[MusicQueueItem alloc] initWithJSONDictionary:payload];
		BOOL successful = [[MusicQueueController sharedController] queueItem:item];
		[item release];
		
		[self sendDictionary:@{kDeviceQueueChangeResultKeyName : [NSNumber numberWithBool:successful]}
				 payloadType:DevicePayloadTypeQueueChangeResult identifier:packet.identifier];
	}
	else if (type == DevicePayloadTypeQueueChangeResult){
	
		DeviceQueueCallback callback = [callbacks objectForKey:packet.identifier];
		if (callback) callback([[payload objectForKey:kDeviceQueueChangeResultKeyName] boolValue]);
		if (packet.identifier) [callbacks removeObjectForKey:packet.identifier];
	}
	else if (type == DevicePayloadTypeQueueStatus){
		
		if ([delegate respondsToSelector:@selector(device:didReceiveQueue:)]){
			dispatch_async(dispatch_get_main_queue(), ^{[delegate device:self didReceiveQueue:payload];});
		}
	}
	else if (type == DevicePayloadTypeAlbumsRequest){
		
		NSArray * results = nil;
		if ([delegate respondsToSelector:@selector(device:didReceiveAlbumsForArtistRequest:identifier:)]){
			results = [delegate device:self didReceiveAlbumsForArtistRequest:[payload objectForKey:kDeviceSearchIdentifierKeyName] identifier:packet.identifier];
		}
		
		if (results) [self sendAlbumsForArtistResults:results identifier:packet.identifier];
	}
	else if (type == DevicePayloadTypeSongsRequest){
		
		NSArray * results = nil;
		if ([delegate respondsToSelector:@selector(device:didReceiveSongsForAlbumRequest:identifier:)]){
			results = [delegate device:self didReceiveSongsForAlbumRequest:[payload objectForKey:kDeviceSearchIdentifierKeyName] identifier:packet.identifier];
		}
		
		if (results) [self sendSongsForAlbumResults:results identifier:packet.identifier];
	}
}

- (void)handleOutputChange:(NSDictionary *)payload {
	
	BOOL newOutput = [[payload objectForKey:kDeviceIsOutputKeyName] boolValue];
	Device * oldOutputDevice = (newOutput ? [[DevicesManager sharedManager] outputDevice] : nil);
	
	BOOL oldOutput = (isOutput ? YES : NO);
	[self setIsOutput:newOutput];
	
	if (oldOutput != newOutput){
		if ([delegate respondsToSelector:@selector(device:didChangeOutputStatus:)]){
			dispatch_async(dispatch_get_main_queue(), ^{[delegate device:self didChangeOutputStatus:newOutput];});
		}
	}
	
	if (newOutput){
		
		[oldOutputDevice setIsOutput:NO];
		if ([oldOutputDevice.delegate respondsToSelector:@selector(device:didChangeOutputStatus:)]){
			dispatch_async(dispatch_get_main_queue(), ^{[oldOutputDevice.delegate device:oldOutputDevice didChangeOutputStatus:NO];});
		}
	}
}

- (void)handleInterfaceOrientationChange:(NSDictionary *)payload {
	
	[self setInterfaceOrientation:[[payload objectForKey:kDeviceInterfaceOrientationKeyName] integerValue]];
	if ([delegate respondsToSelector:@selector(device:didChangeInterfaceOrienation:)]){
		dispatch_async(dispatch_get_main_queue(), ^{
			[delegate device:self didChangeInterfaceOrienation:interfaceOrientation];
		});
	}
}

#pragma mark - Dealloc
- (void)dealloc {
	[netService release];
	[outgoingSocket release];
	[incomingSocket release];
	[UUID release];
	[callbacks release];
	dispatch_release(incomingQueue);
	dispatch_release(outgoingQueue);
	[incomingPacket release];
	[super dealloc];
}

@end

#pragma mark - OwnDevice Implementation -
@implementation OwnDevice
#pragma mark - Init
- (id)init {
	
	if ((self = [super init])){
		interfaceIdiom = UI_USER_INTERFACE_IDIOM();
		interfaceOrientation = [[UIApplication sharedApplication] statusBarOrientation];
		isOutput = NO;
	}
	
	return self;
}

- (id)initWithNetService:(NSNetService *)service {
	return [self init];
}

#pragma mark - Property Overrides
- (BOOL)isOwnDevice {
	return YES;
}

- (NSString *)name {
	return [[UIDevice currentDevice] name];
}

- (NSDictionary *)deviceStatusDictionary {
	return (@{
			kDeviceUUIDKeyName : self.UUID,
			kDeviceInterfaceOrientationKeyName : [NSNumber numberWithInteger:[[UIApplication sharedApplication] statusBarOrientation]],
			kDeviceIsOutputKeyName : [NSNumber numberWithBool:isOutput]
			});
}

- (BOOL)isConnected {
	return YES;
}

- (NSString *)UUID {
	return [[UIDevice currentDevice] UUID];
}

- (void)setIsOutput:(BOOL)flag {
	
	isOutput = flag;
	if (isOutput){
		
		[[[DevicesManager sharedManager] devices] enumerateObjectsUsingBlock:^(Device * device, NSUInteger idx, BOOL *stop) {
			[device setIsOutput:NO];
			if ([device.delegate respondsToSelector:@selector(device:didChangeOutputStatus:)]){
				[device.delegate device:device didChangeOutputStatus:NO];
			}
		}];
		
		[self broadcastDeviceStatus];
	}
	
	if ([delegate respondsToSelector:@selector(device:didChangeOutputStatus:)]){
		dispatch_async(dispatch_get_main_queue(), ^{[delegate device:self didChangeOutputStatus:isOutput];});
	}
}

#pragma mark - Instance Overrides
- (void)queueItem:(MusicQueueItem *)item callback:(DeviceQueueCallback)callback {
	if (callback) callback([[MusicQueueController sharedController] queueItem:item]);
}

- (void)sendAlbumsForArtistRequest:(NSNumber *)persistentID callback:(DeviceSearchCallback)callback {
	
	dispatch_queue_t searchQueue = dispatch_queue_create("com.partymusic.albumssearchqueue", NULL);
	dispatch_async(searchQueue, ^{
		
		NSArray * albums = [MusicContainer albumsForArtistPersistentID:persistentID dictionary:NO];
		dispatch_async(dispatch_get_main_queue(), ^{callback(@{kDeviceSearchAlbumsKeyName : albums});});
	});
	dispatch_release(searchQueue);
}

- (void)sendSongsForAlbumRequest:(NSNumber *)persistentID callback:(DeviceSearchCallback)callback {
	
	dispatch_queue_t searchQueue = dispatch_queue_create("com.partymusic.songssearchqueue", NULL);
	dispatch_async(searchQueue, ^{
		
		NSArray * songs = [MusicContainer songsForAlbumPersistentID:persistentID dictionary:NO];
		dispatch_async(dispatch_get_main_queue(), ^{callback(@{kDeviceSearchSongsKeyName : songs});});
	});
	dispatch_release(searchQueue);
}

#pragma mark - OwnDevice Instance Methods
- (void)broadcastDeviceStatus {
	[[DevicesManager sharedManager] broadcastDictionary:self.deviceStatusDictionary payloadType:DevicePayloadTypeDeviceStatus];
}

- (void)getSongURLForPersistentID:(NSNumber *)persistentID callback:(void (^)(NSURL * URL))callback {
	
	if (persistentID && callback){
		dispatch_queue_t searchQueue = dispatch_queue_create("com.partymusic.songsearchqueue", NULL);
		dispatch_async(searchQueue, ^{
			
			MPMediaQuery * songsQuery = [MPMediaQuery songsQuery];
			
			NSNumber * persistentIDNumber = [NSNumber numberWithUnsignedLongLong:strtoull(persistentID.stringValue.UTF8String, NULL, 0)];
			[songsQuery addFilterPredicate:[MPMediaPropertyPredicate predicateWithValue:persistentIDNumber forProperty:MPMediaItemPropertyPersistentID]];
			NSArray * songs = songsQuery.items;
			
			MPMediaItem * item = songs.count ? [songs objectAtIndex:0] : nil;
			dispatch_async(dispatch_get_main_queue(), ^{
				callback([item valueForProperty:MPMediaItemPropertyAssetURL]);
			});
		});
		dispatch_release(searchQueue);
	}
}

@end
#pragma mark - DevicePacket Implementation -
DevicePacketHeader DevicePacketHeaderMake(DevicePayloadType type, NSUInteger payloadLength, NSString * identifier, BOOL moreComing){
	
	DevicePacketHeader header;
	header.payloadType = type;
	header.payloadLength = payloadLength;
	header.moreComing = moreComing;
	
	if (identifier){
		NSUInteger numberOfBytes = [identifier lengthOfBytesUsingEncoding:NSUnicodeStringEncoding];
		NSRange range = NSMakeRange(0, identifier.length);
		[identifier getBytes:&header.identifier maxLength:numberOfBytes usedLength:NULL
					encoding:NSUTF8StringEncoding options:0 range:range remainingRange:NULL];
	}
	
	return header;
}

NSData * DevicePacketHeaderToData(DevicePacketHeader header, NSData * payloadData){
	
	// Sending a zero byte payload results in nonsense of the utmost order.
	if (!payloadData){
		payloadData = [GCDAsyncSocket CRLFData];
		header.payloadLength = payloadData.length;
	}
	
	NSMutableData * data = [[NSMutableData alloc] initWithCapacity:(sizeof(header) + header.payloadLength)];
	[data appendBytes:&header length:sizeof(header)];
	[data appendData:payloadData];
	return [data autorelease];
}

@implementation DevicePacket
@synthesize payloadType;
@synthesize identifier;
@synthesize moreComing;

- (id)initWithDevicePacketHeader:(DevicePacketHeader)header {
	
	if ((self = [super init])){
		payloadType = header.payloadType;
		expectedLength = header.payloadLength;
		identifier = [[NSString UT8StringWithBytes:header.identifier length:36] retain];
		incomingData = [[NSMutableData alloc] initWithCapacity:expectedLength];
		moreComing = header.moreComing;
	}
	
	return self;
}

- (NSUInteger)lengthRequired {
	return expectedLength - incomingData.length;
}

- (NSData *)data {
	return incomingData;
}

- (BOOL)appendData:(NSData *)data {
	[incomingData appendData:data];
	return incomingData.length >= expectedLength;
}

- (void)dealloc {
	[identifier release];
	[incomingData release];
	[super dealloc];
}

@end