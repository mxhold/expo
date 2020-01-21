//  Copyright © 2019 650 Industries. All rights reserved.

#import <EXUpdates/EXUpdatesAppController.h>
#import <EXUpdates/EXUpdatesAppLoaderEmbedded.h>
#import <EXUpdates/EXUpdatesDatabase.h>
#import <EXUpdates/EXUpdatesUpdate.h>
#import <EXUpdates/EXUpdatesUtils.h>
#import <React/RCTConvert.h>

NS_ASSUME_NONNULL_BEGIN

@interface EXUpdatesUpdate ()

@property (nonatomic, strong, readwrite) NSUUID *updateId;
@property (nonatomic, strong, readwrite) NSDate *commitTime;
@property (nonatomic, strong, readwrite) NSString *runtimeVersion;
@property (nonatomic, strong, readwrite) NSDictionary * _Nullable metadata;
@property (nonatomic, assign, readwrite) EXUpdatesUpdateStatus status;
@property (nonatomic, assign, readwrite) BOOL keep;
@property (nonatomic, strong, readwrite) NSURL *bundleUrl;
@property (nonatomic, strong, readwrite) NSArray<EXUpdatesAsset *>*assets;

@property (nonatomic, strong, readwrite) NSDictionary *rawManifest;

@property (nonatomic, strong) NSURL *bundledAssetBaseUrl;

@end

@implementation EXUpdatesUpdate

- (instancetype)_initWithRawManifest:(NSDictionary *)manifest
{
  if (self = [super init]) {
    _rawManifest = manifest;
    _bundledAssetBaseUrl = [NSURL URLWithString:@"https://d1wp6m56sqw74a.cloudfront.net/~assets/"];
  }
  return self;
}

+ (instancetype)updateWithId:(NSUUID *)updateId
    commitTime:(NSDate *)commitTime
runtimeVersion:(NSString *)runtimeVersion
      metadata:(NSDictionary * _Nullable)metadata
        status:(EXUpdatesUpdateStatus)status
          keep:(BOOL)keep
{
  // for now, we store the entire managed manifest in the metadata field
  EXUpdatesUpdate *update = [[self alloc] _initWithRawManifest:metadata];
  update.updateId = updateId;
  update.commitTime = commitTime;
  update.runtimeVersion = runtimeVersion;
  update.metadata = metadata;
  update.status = status;
  update.keep = keep;
  return update;
}

+ (instancetype)updateWithBareManifest:(NSDictionary *)bareManifest
{
  EXUpdatesUpdate *update = [[self alloc] _initWithRawManifest:bareManifest];

  id updateId = bareManifest[@"id"];
  id commitTime = bareManifest[@"commitTime"];
  id runtimeVersion = bareManifest[@"runtimeVersion"];
  id metadata = bareManifest[@"metadata"];
  id bundleUrlString = bareManifest[@"bundleUrl"];
  id assets = bareManifest[@"assets"];

  NSAssert([updateId isKindOfClass:[NSString class]], @"update ID should be a string");
  NSAssert([commitTime isKindOfClass:[NSNumber class]], @"commitTime should be a number");
  NSAssert([runtimeVersion isKindOfClass:[NSString class]], @"runtimeVersion should be a string");
  NSAssert(!metadata || [metadata isKindOfClass:[NSDictionary class]], @"metadata should be null or an object");
  NSAssert([bundleUrlString isKindOfClass:[NSString class]], @"bundleUrl should be a string");
  NSAssert(assets && [assets isKindOfClass:[NSArray class]], @"assets should be a nonnull array");

  NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:(NSString *)updateId];
  NSAssert(uuid, @"update ID should be a valid UUID");
  NSURL *bundleUrl = [NSURL URLWithString:bundleUrlString];
  NSAssert(bundleUrl, @"bundleUrl should be a valid URL");

  NSMutableArray<EXUpdatesAsset *>*processedAssets = [NSMutableArray new];
  EXUpdatesAsset *jsBundleAsset = [[EXUpdatesAsset alloc] initWithUrl:bundleUrl type:kEXUpdatesEmbeddedBundleFileType];
  jsBundleAsset.isLaunchAsset = YES;
  jsBundleAsset.nsBundleFilename = kEXUpdatesEmbeddedBundleFilename;
  jsBundleAsset.filename = [NSString stringWithFormat:@"%@.%@",
                              [EXUpdatesUtils sha1WithData:[[bundleUrl absoluteString] dataUsingEncoding:NSUTF8StringEncoding]],
                              kEXUpdatesEmbeddedBundleFileType];
  [processedAssets addObject:jsBundleAsset];

  for (NSDictionary *assetDict in (NSArray *)assets) {
    NSAssert([assetDict isKindOfClass:[NSDictionary class]], @"assets must be objects");
    id urlString = assetDict[@"url"];
    id type = assetDict[@"type"];
    id metadata = assetDict[@"metadata"];
    id nsBundleFilename = assetDict[@"nsBundleFilename"];
    NSAssert(urlString && [urlString isKindOfClass:[NSString class]], @"asset url should be a nonnull string");
    NSAssert(type && [type isKindOfClass:[NSString class]], @"asset type should be a nonnull string");
    NSURL *url = [NSURL URLWithString:(NSString *)urlString];
    NSAssert(url, @"asset url should be a valid URL");

    EXUpdatesAsset *asset = [[EXUpdatesAsset alloc] initWithUrl:url type:(NSString *)type];

    if (metadata) {
      NSAssert([metadata isKindOfClass:[NSDictionary class]], @"asset metadata should be an object");
      asset.metadata = (NSDictionary *)metadata;
    }

    if (nsBundleFilename) {
      NSAssert([nsBundleFilename isKindOfClass:[NSString class]], @"asset localPath should be a string");
      asset.nsBundleFilename = (NSString *)nsBundleFilename;
    }

    asset.filename = [NSString stringWithFormat:@"%@.%@",
                        [EXUpdatesUtils sha1WithData:[(NSString *)urlString dataUsingEncoding:NSUTF8StringEncoding]],
                        type];

    [processedAssets addObject:asset];
  }

  update.updateId = uuid;
  update.commitTime = [NSDate dateWithTimeIntervalSince1970:[(NSNumber *)commitTime doubleValue] / 1000];
  update.runtimeVersion = (NSString *)runtimeVersion;
  if (metadata) {
    update.metadata = (NSDictionary *)metadata;
  }
  update.status = EXUpdatesUpdateStatusPending;
  update.keep = YES;
  update.bundleUrl = bundleUrl;
  update.assets = processedAssets;

  return update;
}

+ (instancetype)updateWithManagedManifest:(NSDictionary *)managedManifest
{
  EXUpdatesUpdate *update = [[self alloc] _initWithRawManifest:managedManifest];

  id updateId = managedManifest[@"releaseId"];
  id commitTime = managedManifest[@"commitTime"];
  id bundleUrlString = managedManifest[@"bundleUrl"];
  id assets = managedManifest[@"bundledAssets"];

  id sdkVersion = managedManifest[@"sdkVersion"];
  id runtimeVersion = managedManifest[@"runtimeVersion"];
  if (runtimeVersion && [runtimeVersion isKindOfClass:[NSDictionary class]]) {
    id runtimeVersionIos = ((NSDictionary *)runtimeVersion)[@"ios"];
    NSAssert([runtimeVersionIos isKindOfClass:[NSString class]], @"runtimeVersion['ios'] should be a string");
    update.runtimeVersion = (NSString *)runtimeVersionIos;
  } else if (runtimeVersion && [runtimeVersion isKindOfClass:[NSString class]]) {
    update.runtimeVersion = (NSString *)runtimeVersion;
  } else {
    NSAssert([sdkVersion isKindOfClass:[NSString class]], @"sdkVersion should be a string");
    update.runtimeVersion = (NSString *)sdkVersion;
  }

  NSAssert([updateId isKindOfClass:[NSString class]], @"update ID should be a string");
  NSAssert([commitTime isKindOfClass:[NSString class]], @"commitTime should be a string");
  NSAssert([bundleUrlString isKindOfClass:[NSString class]], @"bundleUrl should be a string");
  NSAssert(assets && [assets isKindOfClass:[NSArray class]], @"assets should be a nonnull array");

  NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:(NSString *)updateId];
  NSAssert(uuid, @"update ID should be a valid UUID");
  NSURL *bundleUrl = [NSURL URLWithString:bundleUrlString];
  NSAssert(bundleUrl, @"bundleUrl should be a valid URL");

  NSMutableArray<EXUpdatesAsset *>*processedAssets = [NSMutableArray new];
  EXUpdatesAsset *jsBundleAsset = [[EXUpdatesAsset alloc] initWithUrl:bundleUrl type:kEXUpdatesEmbeddedBundleFileType];
  jsBundleAsset.isLaunchAsset = YES;
  jsBundleAsset.nsBundleFilename = kEXUpdatesEmbeddedBundleFilename;
  jsBundleAsset.filename = [NSString stringWithFormat:@"%@.%@",
                              [EXUpdatesUtils sha1WithData:[[bundleUrl absoluteString] dataUsingEncoding:NSUTF8StringEncoding]],
                              kEXUpdatesEmbeddedBundleFileType];
  [processedAssets addObject:jsBundleAsset];

  for (NSString *bundledAsset in (NSArray *)assets) {
    NSAssert([bundledAsset isKindOfClass:[NSString class]], @"bundledAssets must be an array of strings");

    NSRange extensionStartRange = [bundledAsset rangeOfString:@"." options:NSBackwardsSearch];
    NSUInteger prefixLength = [@"asset_" length];
    NSString *filename;
    NSString *hash;
    NSString *type;
    if (extensionStartRange.location == NSNotFound) {
      filename = bundledAsset;
      hash = [bundledAsset substringFromIndex:prefixLength];
      type = @"";
    } else {
      filename = [bundledAsset substringToIndex:extensionStartRange.location];
      NSRange hashRange = NSMakeRange(prefixLength, extensionStartRange.location - prefixLength);
      hash = [bundledAsset substringWithRange:hashRange];
      type = [bundledAsset substringFromIndex:extensionStartRange.location + 1];
    }

    NSURL *url = [update.bundledAssetBaseUrl URLByAppendingPathComponent:hash];

    EXUpdatesAsset *asset = [[EXUpdatesAsset alloc] initWithUrl:url type:(NSString *)type];
    asset.nsBundleFilename = filename;

    asset.filename = [NSString stringWithFormat:@"%@.%@",
                        [EXUpdatesUtils sha1WithData:[[url absoluteString] dataUsingEncoding:NSUTF8StringEncoding]],
                        type];

    [processedAssets addObject:asset];
  }

  update.updateId = uuid;
  update.commitTime = [RCTConvert NSDate:commitTime];
  update.metadata = managedManifest;
  update.status = EXUpdatesUpdateStatusPending;
  update.keep = YES;
  update.bundleUrl = bundleUrl;
  update.assets = processedAssets;

  return update;
}

- (NSArray<EXUpdatesAsset *>*)assets
{
  if (!_assets) {
    EXUpdatesDatabase *db = [EXUpdatesAppController sharedInstance].database;
    NSError *error;
    _assets = [db assetsWithUpdateId:_updateId error:&error];
    NSAssert(_assets, @"Assets should be nonnull when selected from DB: %@", error.localizedDescription);
  }
  return _assets;
}

@end

NS_ASSUME_NONNULL_END
