//
//  AppDelegate.m
//  ShaderExplorer
//
//  Created by Zhuowei Zhang on 2021-01-10.
//

#import "AppDelegate.h"
#import "GCDWebServer.h"
#import "GCDWebServerDataRequest.h"
#import "GCDWebServerDataResponse.h"
@import Metal;

@interface AppDelegate ()
@property (strong, nonatomic) GCDWebServer* webServer;
@property (strong, nonatomic) id<MTLDevice> mtlDevice;
@end

static NSData* CompileMetalLibrary(id<MTLDevice> device, NSString* programString, NSError** outError) {
    MTLCompileOptions *options = [MTLCompileOptions new];
    options.libraryType = MTLLibraryTypeDynamic;
    options.installName = [NSString stringWithFormat:@"@executable_path/userCreatedDylib.metallib"];
    NSError* error;
    id<MTLLibrary> lib = [device newLibraryWithSource:programString
                                               options:options
                                                 error:&error];
    if(!lib && error)
    {
        *outError = error;
        return nil;
    }
    
    id<MTLDynamicLibrary> dynamicLib = [device newDynamicLibrary:lib
                                                            error:&error];
    if(!dynamicLib && error)
    {
        *outError = error;
        return nil;
    }
    
    NSURL* url = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].lastObject URLByAppendingPathComponent:@"output_metal.dylib"];
    [dynamicLib serializeToURL:url error:&error];
    if(error)
    {
        *outError = error;
        return nil;
    }
    NSData* data = [NSData dataWithContentsOfURL:url options:0 error:&error];
    if(error)
    {
        *outError = error;
        return nil;
    }
    return data;
}

static NSData* ExtractInstructionData(NSData* metalDylibData) {
    // TODO(zhuowei): Find the embedded Mach-O
    return metalDylibData;
}

static NSString* DisassembleShaderInstructions(NSData* instructionData) {
    return @"Nope";
}

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    self.webServer = [GCDWebServer new];
    __weak AppDelegate* weakSelf = self;
    [self.webServer addHandlerForMethod:@"POST" path:@"/compile" requestClass:[GCDWebServerDataRequest class] processBlock:^GCDWebServerDataResponse*(GCDWebServerDataRequest* request) {
        AppDelegate* strongSelf = weakSelf;
        if (!strongSelf) return nil;
        return [GCDWebServerDataResponse responseWithText:
                [strongSelf compileAndDisassembleShader:request.text]];
    }];
    [self.webServer startWithPort:8080 bonjourName:nil];
    return YES;
}


#pragma mark - UISceneSession lifecycle


- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options {
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}


- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions {
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
}

- (NSString*)compileAndDisassembleShader:(NSString*)shader {
    id<MTLDevice> device = self.mtlDevice;
    if (!device) {
        device = MTLCreateSystemDefaultDevice();
        self.mtlDevice = device;
    }
    NSError* error;
    NSData* data = CompileMetalLibrary(device, shader, &error);
    if (error) {
        return error.description;
    }
    NSData* instructionData = ExtractInstructionData(data);
    if (!instructionData) {
        return @"Can't find shader instructions?";
    }
    NSString* disasm = DisassembleShaderInstructions(instructionData);
    return disasm;
}

- (NSURL*)serverUrl {
    return self.webServer.serverURL;
}

@end
