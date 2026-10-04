#import "ExperimentalOTA.h"
#import <CommonCrypto/CommonDigest.h>
#import <TargetConditionals.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <dirent.h>
#include <errno.h>

NSString *TIOExperimentalOTASHA(void){return @"8353e7bf1ff5c49d2123c3476661f33faad1b40a090ad40646de6c9fe39dfaa8";}
static id Fail(NSError **error,NSString *message){if(error)*error=[NSError errorWithDomain:@"TurboIO.ExperimentalOTA" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];return nil;}
NSDictionary *TIOCheckExperimentalOTA(NSData *data,NSError **error){
    if(data.length!=9300019)return Fail(error,@"File size does not match. Only accept this TFP1 experiment ZIP, Not Saved, Not Sent.");
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *hex=[NSMutableString new];for(NSUInteger i=0;i<sizeof(digest);i++)[hex appendFormat:@"%02x",digest[i]];
    if(![hex isEqual:TIOExperimentalOTASHA()])return Fail(error,@"SHA-256 does not match. Unknown, old or modified packages are rejected and not sent.");
    // The exact archive has independently passed full ZIP/manifest/AP auditing
    // on Mac. This is exact-byte identity, not a generic ZIP manifest parser.
    return @{@"schema":@1,@"candidate":@"Turbo WeRead TFP1",@"baseFirmware":@"1.0.4.12",
             @"archiveSHA256":hex,@"archiveBytes":@(data.length),@"changedPayloads":@[@"nuttx_ap.bin"],
             @"unchangedPayloadCount":@13,@"integrityPassed":@YES,@"sent":@NO,
             @"runtimeValidated":@NO,@"officialDispatchConnected":@NO};
}
static NSData *Read(NSURL *source,NSError **error){
    if(!source.isFileURL)return Fail(error,@"Only local files are accepted.");
    NSInputStream *stream=[NSInputStream inputStreamWithURL:source];[stream open];
    NSMutableData *data=[NSMutableData new];uint8_t buffer[65536];NSInteger n;
    while((n=[stream read:buffer maxLength:sizeof(buffer)])>0){
        if(data.length+(NSUInteger)n>9300019){[stream close];return Fail(error,@"The file is too large; Not Saved and not sent.");}
        [data appendBytes:buffer length:(NSUInteger)n];
    }
    NSError *readError=stream.streamError;[stream close];
    if(n<0||readError){if(error)*error=readError?:[NSError errorWithDomain:@"TurboIO.ExperimentalOTA" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Unable to read file"}];return nil;}
    return TIOCheckExperimentalOTA(data,error)?data:nil;
}
NSDictionary *TIOReadExperimentalOTA(NSURL *file,NSError **error){NSData *data=Read(file,error);return data?TIOCheckExperimentalOTA(data,error):nil;}
NSDictionary *TIOImportExperimentalOTA(NSURL *source,NSURL *directory,NSError **error){
    if(!directory.isFileURL)return Fail(error,@"Only local Table of Contents is accepted.");
    NSData *data=Read(source,error);if(!data)return nil;
    NSDictionary *result=TIOCheckExperimentalOTA(data,error);
    NSFileManager *fm=NSFileManager.defaultManager;
    if(![fm createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error])return nil;
    if(![directory setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:error])return nil;
    NSURL *destination=[directory URLByAppendingPathComponent:[TIOExperimentalOTASHA() stringByAppendingString:@".zip"]];
    if([fm fileExistsAtPath:destination.path]){
        if(!TIOReadExperimentalOTA(destination,error))return nil;
    }else{
        // Exclusive creation; no official cache or existing imported file replaced.
        if(![data writeToURL:destination options:NSDataWritingWithoutOverwriting error:error])return nil;
    }
    if(![fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:destination.path error:error])return nil;
#if TARGET_OS_IPHONE
    if(![fm setAttributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:destination.path error:error])return nil;
#endif
    return result;
}

static NSDictionary *PayloadPins(void){return @{
    @"OtaFileInfo.json":@[@2515,@"cf55c94c1cff4479859e38387b1acbd14b417f7d3b1188f0af120b5c783cc0d7"],
    @"cb_fw_venus.bin":@[@114592,@"8799f12071bdac082218e3601c24ab0989275fc2f7db74e37b8314a225c2cf7d"],
    @"fac_test_img.bin":@[@1821552,@"18eb0901c3e0daeae48dd5f015252b6931ea7368f0160c2c985c4e74296d17eb"],
    @"images.bin":@[@324283,@"192fefaa70545856884c89a9186e3f86d8f99a0738b201e116a11bc63011c158"],
    @"lotties.bin":@[@651481,@"ad66d83a3394034f825a12769aad292fc03e59fa865fe06bc43536b918a0b32b"],
    @"nuttx_ap.bin":@[@9558216,@"0f5c468fb56c5b38f3143a0eea805eff5fa240bd4e8ba8f1b4e259a46e4e96e5"],
    @"nuttx_apc1.bin":@[@1420248,@"97d56ffc6dd575ad3d8bf7739d49e491ad7e4a959db8770b653f5302e171fb5c"],
    @"nuttx_audio.bin":@[@1461920,@"549a72c032595e3829da7d63b7e1fd13cceda1a55dfefa7a7cad02db5a9b42ab"],
    @"nuttx_bth.bin":@[@1160160,@"a8f4594868bffbd3bc08a38d1f3899571608e2d57869d147de3d06f3e4f7a12a"],
    @"ota_installer_progress.bin":@[@5616,@"6fd65d296a667e1a7d94ec129adfd26458a4008ef403b331f855192c36eb3e3f"],
    @"pil_algo_up_demo_nand.dll":@[@504388,@"e266726fe055ac6ec6f785a9440e8da7421402f2b4d3d7889039ad9b94e119c2"],
    @"pil_algo_vad_demo.dll":@[@433432,@"7ac5b5191202adea20c62642987fa0049024dde9c386ba6cd08a1f29ddd5c92c"],
    @"pil_algo_wakeup_dll_nand.dll":@[@287560,@"d1594cb8658b228e52c2606d02f1eab696d35a11ed42ddcb725e76a745f5550f"],
    @"rives.bin":@[@689431,@"836bc019f7152890b94cafafe2edaa024f317526318349f7833319e41158b104"],
    @"smf.json":@[@23510,@"2713dc3a302a65c101fa981500cd8b217766c526b6045bf02db5e9e6763d076d"]};}
static BOOL SameStat(struct stat a,struct stat b){return a.st_dev==b.st_dev&&a.st_ino==b.st_ino&&a.st_size==b.st_size&&a.st_mode==b.st_mode&&a.st_nlink==b.st_nlink&&a.st_mtimespec.tv_sec==b.st_mtimespec.tv_sec&&a.st_mtimespec.tv_nsec==b.st_mtimespec.tv_nsec&&a.st_ctimespec.tv_sec==b.st_ctimespec.tv_sec&&a.st_ctimespec.tv_nsec==b.st_ctimespec.tv_nsec;}
NSDictionary<NSString *,NSData *> *TIOCopyExperimentalOTAPayloads(NSURL *directory,NSError **error){
    if(!TIOCheckExperimentalOTADirectory(directory,error))return nil;
    NSMutableDictionary *copy=[NSMutableDictionary new];NSDictionary *pins=PayloadPins();
    for(NSString *name in pins){
        NSData *data=[NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:name] options:0 error:error];
        if(!data||data.length!=[pins[name][0] unsignedIntegerValue])return Fail(error,@"File to be transferred changed while frozen; sending without authorization.");
        uint8_t digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
        NSMutableString *hex=[NSMutableString new];for(NSUInteger i=0;i<sizeof(digest);i++)[hex appendFormat:@"%02x",digest[i]];
        if(![hex isEqual:pins[name][1]])return Fail(error,@"The digest of the file to be transferred does not match when it is frozen; sending is not authorized.");
        copy[name]=data;
    }
    return TIOCheckExperimentalOTADirectory(directory,error)?[copy copy]:nil;
}
NSDictionary *TIOCheckExperimentalOTADirectory(NSURL *directory,NSError **error){
    if(!directory.isFileURL)return Fail(error,@"Only local Table of Contents to be transferred is accepted.");
    // Open a directory handle and use openat/O_NOFOLLOW for every member. Never
    // follow a member symlink, FIFO or device. Do not modify old OTA caches.
    int root=open(directory.path.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if(root<0)return Fail(error,@"The Table of Contents to be transferred does not exist, is unreadable, or is a symbolic link; it has not been sent.");
    struct stat before,after;BOOL ok=fstat(root,&before)==0;NSDictionary *pins=PayloadPins();NSMutableSet *names=[NSMutableSet new];
    int copy=dup(root);DIR *stream=copy>=0?fdopendir(copy):NULL;if(!stream){if(copy>=0)close(copy);ok=NO;}
    if(stream){struct dirent *item;errno=0;while((item=readdir(stream))){if(!strcmp(item->d_name,".")||!strcmp(item->d_name,".."))continue;NSString *name=[NSString stringWithUTF8String:item->d_name];if(!name||names.count>=15||!pins[name]){ok=NO;break;}[names addObject:name];errno=0;}if(errno)ok=NO;closedir(stream);}
    if(names.count!=pins.count)ok=NO;
    NSMutableDictionary *identities=[NSMutableDictionary new];NSString *problem=@"File collection does not match TFP1, may be old cache or incomplete Table of Contents; not sent.";
    for(NSString *name in [pins.allKeys sortedArrayUsingSelector:@selector(compare:)]){
        if(!ok)break;
        int fd=openat(root,name.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);
        if(fd<0){ok=NO;break;}struct stat first,last;
        NSUInteger expected=[pins[name][0] unsignedIntegerValue];
        ok=fstat(fd,&first)==0&&S_ISREG(first.st_mode)&&first.st_nlink==1&&first.st_size==(off_t)expected;
        if(ok){CC_SHA256_CTX context;CC_SHA256_Init(&context);uint8_t buffer[65536],digest[CC_SHA256_DIGEST_LENGTH];NSUInteger total=0;ssize_t n=0;
            while(total<expected){n=read(fd,buffer,MIN(sizeof(buffer),expected-total));if(n<0&&errno==EINTR)continue;if(n<=0){ok=NO;break;}CC_SHA256_Update(&context,buffer,(CC_LONG)n);total+=(NSUInteger)n;}
            if(ok){n=read(fd,buffer,1);ok=n==0;}CC_SHA256_Final(digest,&context);
            NSMutableString *hash=[NSMutableString new];for(NSUInteger i=0;i<sizeof(digest);i++)[hash appendFormat:@"%02x",digest[i]];
            ok=ok&&[hash isEqual:pins[name][1]]&&fstat(fd,&last)==0&&SameStat(first,last);
            if(ok)identities[name]=[NSData dataWithBytes:&last length:sizeof(last)];
        }
        close(fd);if(!ok)problem=[NSString stringWithFormat:@"%@ is inconsistent with fixed TFP1 or changed during read; not sent.",name];
    }
    // A second pass catches names/inodes replaced after an earlier file was read.
    for(NSString *name in identities){struct stat prior,current;[identities[name] getBytes:&prior length:sizeof(prior)];if(fstatat(root,name.fileSystemRepresentation,&current,AT_SYMLINK_NOFOLLOW)||!SameStat(prior,current))ok=NO;}
    ok=ok&&fstat(root,&after)==0&&SameStat(before,after);
    struct stat currentPath;if(lstat(directory.path.fileSystemRepresentation,&currentPath)||!SameStat(before,currentPath))ok=NO;
    close(root);if(!ok)return Fail(error,problem);
    return @{@"candidate":@"Turbo WeRead TFP1",@"checkedMembers":@15,@"integrityPassed":@YES,@"snapshotOnly":@YES,@"transferSessionBound":@NO,@"sent":@NO,@"flashAuthorized":@NO};
}
