//
//  SFTSiftDeviceInfo.m
//  SiftIOS
//
//  Created by Joey Robinson on 8/14/14.
//  Copyright (c) 2014 Sift Science. All rights reserved.
//

#import "SFTSiftDeviceInfo.h"
#import "SFTDeviceInfo.h"
#import "SFTConstants.h"
#import "SFTFieldNames.h"
#import "SFTUtil.h"
#import "SFTDebugHelper.h"
#import <UNIRest.h>

NSPredicate* userIdPattern = nil;
NSOperationQueue* queue = nil;

@interface SFTSiftDeviceInfo (SFTPrivateSiftDeviceInfo)

@property (copy) NSString* userName;
@property (copy) NSString* apiKey;
-(void) infoUpdater;
-(void) addDeviceInfo: (NSMutableDictionary*) dict;
-(void) addStaticInfo: (NSMutableDictionary*) dict;
-(int) sendEvent: (NSString*) data;
-(NSMutableDictionary*) readState;
-(void) writeState: (NSMutableDictionary*) dict;
-(NSString*) userKey;

@end

@implementation SFTSiftDeviceInfo (SFTPrivateSiftDeviceInfo)

NSString* _userName;
NSString* _apiKey;

-(NSString*) userName {
    return _userName;
}

-(void) setUserName:(NSString *)userName {
    _userName = userName;
}

-(NSString*) apiKey {
    return _apiKey;
}

-(void) setApiKey:(NSString *)apiKey {
    _apiKey = apiKey;
}

-(void) infoUpdater {
    NSMutableDictionary* data = [NSMutableDictionary new];
    [self addDeviceInfo: data];
    [self addStaticInfo: data];

    if ([data isEqualToDictionary: self.readState]) {
        // Device info has not changed, no need to send update.
        [SFTDebugHelper logIfDebug: @"%@", @"No updates."];
        return;
    }
    NSString* json = [SFTUtil dictionaryToJSON: data];
    [SFTDebugHelper logIfDebug: @"%@", json];

    int result = 0;
    int iters = 0;
    while (true) {
        result = [self sendEvent: json];
        [SFTDebugHelper logIfDebug:@"%d", result];
        if (result) {
            break;
        }
        iters++;
        if (iters > MAX_RETRIES) {
            break;
        }
        [NSThread sleepForTimeInterval: RETRY_FREQUENCY];
    }
    if (result) {
        [SFTDebugHelper logIfDebug: @"%@", @"Update sent successfully."];
        [self writeState: data];
    } else {
        [SFTDebugHelper logIfDebug: @"%@", @"Unable to send update."];
    }
}

-(void) addDeviceInfo:(NSMutableDictionary *)dict {
    SFTDeviceInfo* info = [SFTDeviceInfo new];
    [dict setValue:info.identifierForVendor forKey:IDENTIFIER_FOR_VENDOR];

    [dict setValue:info.deviceLocalizedModel forKey:DEVICE_LOCALIZED_MODEL];
    [dict setValue:info.deviceModel forKey:DEVICE_MODEL];
    [dict setValue:info.deviceName forKey:DEVICE_NAME];
    [dict setValue:info.deviceSystemName forKey:DEVICE_SYSTEM_NAME];
    [dict setValue:info.deviceSystemVersion forKey:DEVICE_SYSTEM_VERSION];

    [dict setValue:info.defaultLanguage forKey:DEFAULT_LANGUAGE];
    [dict setValue:[NSNumber numberWithBool: info.jailbreakStatus] forKey:JAILBREAK_STATUS];
}

-(void) addStaticInfo:(NSMutableDictionary *)dict {
    [dict setValue: IOS_EVENT forKey:EVENT_TYPE];
    [dict setValue: self.apiKey forKey:MOBILE_API_KEY];
    [dict setValue: self.userName forKey:USER_ID];
    [dict setValue: [NSNumber numberWithInt:SIFT_SDK_VERSION] forKey:SDK_VERSION];
}

/**
 * Makes a POST request to API_ENDPOINT and returns the response code.
 */
-(int) sendEvent:(NSString *)data {
    [UNIRest timeout:POST_TIMEOUT];
    UNIHTTPJsonResponse *response = [[UNIRest post:^(UNISimpleRequest *request) {
        [request setUrl:API_ENDPOINT];
    }] asJson];
    return (int) response.code;
}

/**
 * Reads the saved state from NSUserDefaults as a NSMutableDictionary*.
 */
-(NSMutableDictionary*) readState {
    return [[NSUserDefaults standardUserDefaults] valueForKey:self.userKey];
}

/**
 * Writes the saved state to NSUserDefaults from a NSMutableDictionary*.
 */
-(void) writeState: (NSMutableDictionary*) dict {
    [[NSUserDefaults standardUserDefaults] setObject:dict forKey:self.userKey];
}

/**
 * Returns a key to be used to lookup and store state information for a given user.
 */
-(NSString*) userKey {
    return [NSString stringWithFormat: @"%@%@", SIFT_STATE_PREFIX,
            [SFTUtil hashString: self.userName]];
}

@end

@implementation SFTSiftDeviceInfo

+(void) initialize {
    [super initialize];
    if (!userIdPattern) {
        userIdPattern = [NSPredicate predicateWithFormat:@"SELF MATCHES %@", USER_ID_PATTERN];
    }
    if (!queue) {
        queue = [NSOperationQueue new];
        [queue setMaxConcurrentOperationCount:1];
    }
}

-(id) initWithUser: (NSString*) aUser apiKey: (NSString*) anApiKey {
    self = [super init];
    if (self) {
        self.userName = aUser;
        self.apiKey = anApiKey;
    }
    return self;
}

-(BOOL) updateInfo {
    if ([userIdPattern evaluateWithObject: self.userName]){
        // Add task to queue to be processed sequentially on a background thread
        NSInvocationOperation* operation = [[NSInvocationOperation alloc] initWithTarget:self
                                                                                selector:@selector(infoUpdater)
                                                                                  object:nil];
        [queue addOperation:operation];
        return YES;
    }
    return NO;
}

@end