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
@import MachO;

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
    // Find the embedded object mach-o by looking for the second 0xfeedfacf
    void* metalDylibDataPtr = (void*)metalDylibData.bytes;
    void* metalDylibEndPtr = metalDylibDataPtr + metalDylibData.length;
    uint32_t* ptr = metalDylibDataPtr;
    int count = 0;
    bool found = false;
    while ((void*)ptr < metalDylibEndPtr) {
        if (*ptr == 0xfeedfacf) {
            if (++count == 2) {
                found = true;
                break;
            }
        }
        ptr++;
    }
    if (!found) {
        return nil;
    }
    // Find the __text segment and extract its offset and size
    struct mach_header_64* mh = (struct mach_header_64*)ptr;
    struct load_command* cmd = (struct load_command*)((uint8_t*)mh + sizeof(struct mach_header_64));
    uint64_t textoff = 0;
    uint64_t textsize = 0;
    for (unsigned int index = 0; index < mh->ncmds; index++) {
        switch (cmd->cmd) {
            case LC_SEGMENT_64: {
                struct segment_command_64* segCmd = (struct segment_command_64*)cmd;
                struct section_64* sections = (struct section_64*)(((uint8_t*)cmd) + sizeof(struct segment_command_64));
                for (unsigned int sindex = 0; sindex < segCmd->nsects; sindex++) {
                    struct section_64* sec = sections + sindex;
                    if (!strcmp(sec->sectname, "__text")) {
                        textoff = sec->offset;
                        textsize = sec->size;
                    }
                }
                break;
            }
        }
        cmd = (struct load_command*)((char*)cmd + cmd->cmdsize);
    }
    if (textsize == 0) {
        return nil;
    }
    // create an NSData holding just the __text sectioh
    return [metalDylibData subdataWithRange:
            NSMakeRange((((void*)ptr) - metalDylibDataPtr) + textoff, textsize)];
}


extern void
agx_disassemble(void *_code, size_t maxlen, FILE *fp);

static NSString* DisassembleShaderInstructions(NSData* instructionData) {
    NSMutableData* instructionWithStop = [instructionData mutableCopy];
    // Add a stop instruction to make agx_disassemble happy
    static const char stopBytes[] = {0x88, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00};
    [instructionWithStop appendBytes:stopBytes length:sizeof(stopBytes)];
    NSMutableData* outputBuf = [NSMutableData dataWithLength:0x100000];
    FILE* outputFile = fmemopen(outputBuf.mutableBytes, outputBuf.length, "w");
    
    agx_disassemble((void*)instructionWithStop.bytes, instructionWithStop.length, outputFile);
    return [NSString stringWithUTF8String:outputBuf.mutableBytes];
}

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    setenv("ASAHI_VERBOSE", "1", true);
    // Override point for customization after application launch.
    self.webServer = [GCDWebServer new];
    __weak AppDelegate* weakSelf = self;
    [self.webServer addHandlerForMethod:@"POST" path:@"/compile" requestClass:[GCDWebServerDataRequest class] processBlock:^GCDWebServerDataResponse*(GCDWebServerDataRequest* request) {
        AppDelegate* strongSelf = weakSelf;
        if (!strongSelf) return nil;
        return [GCDWebServerDataResponse responseWithText:
                [strongSelf compileAndDisassembleShader:request.text]];
    }];
    [self.webServer addGETHandlerForPath:@"/"
                                filePath:[[NSBundle mainBundle] pathForResource:@"index" ofType:@"html"]
                            isAttachment:false cacheAge:100000 allowRangeRequests:true];
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
