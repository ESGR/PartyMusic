//
//  Device.h
//  PartyMusic
//
//  Created by Tom Irving on 12/02/2013.
//  Copyright (c) 2013 Tom Irving. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString * const kDeviceUUIDKeyName;
extern NSString * const kDeviceInterfaceOrientationKeyName;
extern NSString * const kDeviceIsOutputKeyName;
extern NSString * const kDeviceActionKeyName;
extern NSString * const kDeviceSearchIdentifierKeyName;
extern NSString * const kDeviceSearchArtistsKeyName;
extern NSString * const kDeviceSearchAlbumsKeyName;
extern NSString * const kDeviceSearchSongsKeyName;
extern NSString * const kDeviceSongIdentifierKeyName;
extern NSString * const kDeviceQueueChangeResultKeyName;

typedef NS_ENUM(NSInteger, DevicePayloadType){
	DevicePayloadTypeDeviceStatus = 0,
	DevicePayloadTypeAction = 1,
	DevicePayloadTypeBrowseRequest = 2,
	DevicePayloadTypeBrowseResults = 3,
	DevicePayloadTypeSearchRequest = 4,
	DevicePayloadTypeSearchResults = 5,
	DevicePayloadTypeSongRequest = 6,
	DevicePayloadTypeSongCancel = 7,
	DevicePayloadTypeSongResult = 8,
	DevicePayloadTypeQueueChange = 9,
	DevicePayloadTypeQueueChangeResult = 10,
	DevicePayloadTypeQueueStatus = 11,
	DevicePayloadTypeAlbumsRequest = 12,
	DevicePayloadTypeAlbumsResults = 13,
	DevicePayloadTypeSongsRequest = 14,
	DevicePayloadTypeSongsResults = 15,
};

typedef NS_ENUM(NSInteger, DeviceSearchType){
	DeviceSearchTypeAll = 0,
	DeviceSearchTypeArtists = 1,
	DeviceSearchTypeAlbums = 2,
	DeviceSearchTypeSongs = 3,
};

typedef NS_ENUM(NSInteger, DeviceSongType){
	DeviceSongTypeMusicLibrary = 0,
	DeviceSongTypeYouTube = 1,
	DeviceSongTypeSoundCloud = 2,
};

typedef NS_ENUM(NSInteger, DeviceAction){
	DeviceActionShake = 0,
	DeviceActionVibrate = 1,
	DeviceActionHarlemShake = 2,
};

typedef void (^DeviceSearchCallback)(NSDictionary * results);
typedef void (^DeviceSongCallback)(NSData * songData, BOOL moreComing);
typedef void (^DeviceQueueCallback)(BOOL successful);

@protocol DeviceDelegate;
@class GCDAsyncSocket, DevicePacket, MusicQueueItem;
@interface Device : NSObject <NSNetServiceDelegate>
@property (nonatomic, weak) id <DeviceDelegate> delegate;
@property (nonatomic, readonly) NSNetService * netService;
@property (nonatomic, readonly) GCDAsyncSocket * outgoingSocket;
@property (nonatomic, strong) GCDAsyncSocket * incomingSocket;
@property (nonatomic, copy) NSString * UUID;
@property (nonatomic, assign, readonly) UIUserInterfaceIdiom interfaceIdiom;
@property (nonatomic, assign) UIInterfaceOrientation interfaceOrientation;
@property (nonatomic, assign) BOOL isOutput;
@property (nonatomic, readonly) BOOL isOwnDevice;
@property (weak, nonatomic, readonly) NSString * name;

- (id)initWithNetService:(NSNetService *)service;

- (void)sendDictionary:(NSDictionary *)dictionary payloadType:(DevicePayloadType)payloadType identifier:(NSString *)identifier;

- (void)sendAction:(DeviceAction)action;

- (void)sendSearchRequest:(NSString *)searchString callback:(DeviceSearchCallback)callback;
- (void)sendBrowseLibraryRequestWithCallback:(DeviceSearchCallback)callback;
- (void)sendAlbumsForArtistRequest:(NSNumber *)persistentID callback:(DeviceSearchCallback)callback;
- (void)sendSongsForAlbumRequest:(NSNumber *)persistentID callback:(DeviceSearchCallback)callback;

- (void)sendSearchResults:(NSDictionary *)results identifier:(NSString *)identifier;
- (void)sendBrowseLibraryResults:(NSDictionary *)results identifier:(NSString *)identifier;
- (void)sendAlbumsForArtistResults:(NSArray *)results identifier:(NSString *)identifier;
- (void)sendSongsForAlbumResults:(NSArray *)results identifier:(NSString *)identifier;

- (void)sendSongRequest:(NSNumber *)persistentID callback:(DeviceSongCallback)callback;
- (void)cancelSongRequest:(NSNumber *)persistentID;
- (void)sendSongResult:(NSData *)song identifier:(NSString *)identifier moreComing:(BOOL)moreComing;

- (void)sendQueueStatus:(NSDictionary *)queueStatus;
- (void)queueItem:(MusicQueueItem *)item callback:(DeviceQueueCallback)callback;

@end

@interface OwnDevice : Device
@property (weak, nonatomic, readonly) NSDictionary * deviceStatusDictionary;
- (void)broadcastDeviceStatus;
- (void)getSongURLForPersistentID:(NSNumber *)persistentID callback:(void (^)(NSURL * URL))callback;
@end

@protocol DeviceDelegate <NSObject>
@optional
- (void)device:(Device *)device didChangeOutputStatus:(BOOL)isOutput;
- (void)device:(Device *)device didChangeInterfaceOrienation:(UIInterfaceOrientation)interfaceOrientation;
- (void)device:(Device *)device didReceiveAction:(DeviceAction)action;
- (NSDictionary *)device:(Device *)device didReceiveBrowseRequestWithIdentifier:(NSString *)identifier;
- (NSDictionary *)device:(Device *)device didReceiveSearchRequest:(NSString *)searchString identifier:(NSString *)identifier;
- (NSArray *)device:(Device *)device didReceiveAlbumsForArtistRequest:(NSNumber *)persistentID identifier:(NSString *)identifier;
- (NSArray *)device:(Device *)device didReceiveSongsForAlbumRequest:(NSNumber *)persistentID identifier:(NSString *)identifier;
- (void)device:(Device *)device didReceiveSongRequest:(NSNumber *)persistentID identifier:(NSString *)identifier;
- (void)device:(Device *)device didReceiveSongCancel:(NSNumber *)persistentID;
- (void)device:(Device *)device didReceiveQueue:(NSDictionary *)queue;
@end

#pragma pack(push, 1)
typedef struct {
	DevicePayloadType payloadType;
	NSUInteger payloadLength;
	char identifier[36];
	BOOL moreComing;
} DevicePacketHeader;
#pragma pack(pop)

DevicePacketHeader DevicePacketHeaderMake(DevicePayloadType type, NSUInteger payloadLength, NSString * identifier, BOOL moreComing);
NSData * DevicePacketHeaderToData(DevicePacketHeader header, NSData * payloadData);

@interface DevicePacket : NSObject
@property (nonatomic, readonly) DevicePayloadType payloadType;
@property (nonatomic, readonly) NSString * identifier;
@property (nonatomic, readonly) NSUInteger lengthRequired;
@property (weak, nonatomic, readonly) NSData * data;
@property (nonatomic, readonly) BOOL moreComing;

- (id)initWithDevicePacketHeader:(DevicePacketHeader)header;
- (BOOL)appendData:(NSData *)data;
@end