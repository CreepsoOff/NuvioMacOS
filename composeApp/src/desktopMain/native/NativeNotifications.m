#import <Foundation/Foundation.h>
#import <UserNotifications/UserNotifications.h>
#import <jni.h>

static JavaVM *cachedJvm = NULL;
static jmethodID handleDeepLinkMethod = NULL;
static jclass cachedNotificationClass = NULL;

// MARK: - JNI Helpers

static NSString* jstringToNSString(JNIEnv *env, jstring jstr) {
    if (jstr == NULL) return nil;
    const jchar *chars = (*env)->GetStringChars(env, jstr, NULL);
    jsize len = (*env)->GetStringLength(env, jstr);
    NSString *result = [[NSString alloc] initWithCharacters:chars length:len];
    (*env)->ReleaseStringChars(env, jstr, chars);
    return result;
}

static void callKotlinHandleDeepLink(NSString *deepLink) {
    if (!cachedJvm || !handleDeepLinkMethod || !cachedNotificationClass) return;
    JNIEnv *env;
    jint attachResult = (*cachedJvm)->AttachCurrentThread(cachedJvm, (void**)&env, NULL);
    if (attachResult != JNI_OK) return;
    jstring jUrl = (*env)->NewStringUTF(env, [deepLink UTF8String]);
    (*env)->CallStaticVoidMethod(env, cachedNotificationClass, handleDeepLinkMethod, jUrl);
    (*env)->DeleteLocalRef(env, jUrl);
}

// MARK: - Backdrop Download

static NSString* downloadBackdrop(NSString *imageUrl, NSString *requestId) {
    if (!imageUrl || [imageUrl length] == 0) return nil;
    NSURL *url = [NSURL URLWithString:imageUrl];
    if (!url) return nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:NULL];
    if (!data) return nil;
    NSString *ext = [[imageUrl lastPathComponent] pathExtension];
    if ([ext length] < 2 || [ext length] > 5) ext = @"jpg";
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"nuvio_notify_attachments"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", requestId, ext]];
    if ([data writeToFile:path atomically:YES]) return path;
    return nil;
}

static UNNotificationAttachment* createAttachment(NSString *imagePath, NSString *identifier) {
    if (!imagePath) return nil;
    NSURL *fileUrl = [NSURL fileURLWithPath:imagePath];
    return [UNNotificationAttachment attachmentWithIdentifier:identifier URL:fileUrl options:nil error:NULL];
}

// MARK: - Notification Delegate

@interface NotificationDelegate : NSObject <UNUserNotificationCenterDelegate>
@end

@implementation NotificationDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
    completionHandler(UNNotificationPresentationOptionAlert | UNNotificationPresentationOptionSound);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler {
    NSString *deepLink = response.notification.request.content.userInfo[@"deepLink"];
    if (deepLink) callKotlinHandleDeepLink(deepLink);
    completionHandler();
}

@end

// MARK: - JNI_OnLoad

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
    cachedJvm = vm;
    JNIEnv *env;
    if ((*vm)->GetEnv(vm, (void**)&env, JNI_VERSION_1_6) != JNI_OK) return JNI_VERSION_1_6;
    jclass cls = (*env)->FindClass(env, "com/nuvio/app/features/notifications/NativeNotifications");
    if (cls) {
        cachedNotificationClass = (jclass)(*env)->NewGlobalRef(env, cls);
        handleDeepLinkMethod = (*env)->GetStaticMethodID(env, cachedNotificationClass, "nativeHandleDeepLink", "(Ljava/lang/String;)V");
    }
    static NotificationDelegate *delegate = nil;
    if (!delegate) {
        delegate = [[NotificationDelegate alloc] init];
        [[UNUserNotificationCenter currentNotificationCenter] setDelegate:delegate];
    }
    return JNI_VERSION_1_6;
}

// MARK: - JNI Functions

JNIEXPORT jboolean JNICALL
Java_com_nuvio_app_features_notifications_NativeNotifications_nativeCheck(JNIEnv *env, jclass cls) {
    __block jboolean result = JNI_FALSE;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[UNUserNotificationCenter currentNotificationCenter] getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *settings) {
        result = (settings.authorizationStatus == UNAuthorizationStatusAuthorized ||
                  settings.authorizationStatus == UNAuthorizationStatusProvisional) ? JNI_TRUE : JNI_FALSE;
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    return result;
}

JNIEXPORT jboolean JNICALL
Java_com_nuvio_app_features_notifications_NativeNotifications_nativeRequestAuthorization(JNIEnv *env, jclass cls) {
    __block jboolean result = JNI_FALSE;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge) completionHandler:^(BOOL granted, NSError *error) {
        result = granted ? JNI_TRUE : JNI_FALSE;
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    return result;
}

static UNMutableNotificationContent* buildContent(NSString *title, NSString *body, NSString *deepLink, NSString *backdropUrl, NSString *requestId) {
    UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
    content.title = title;
    content.body = body;
    content.sound = [UNNotificationSound defaultSound];
    if (deepLink) content.userInfo = @{@"deepLink": deepLink};
    if (backdropUrl && requestId) {
        NSString *imagePath = downloadBackdrop(backdropUrl, requestId);
        UNNotificationAttachment *attachment = createAttachment(imagePath, requestId);
        if (attachment) content.attachments = @[attachment];
    }
    return content;
}

JNIEXPORT void JNICALL
Java_com_nuvio_app_features_notifications_NativeNotifications_nativeShow(JNIEnv *env, jclass cls, jstring title, jstring body, jstring deepLink, jstring backdropUrl) {
    NSString *nsTitle = jstringToNSString(env, title);
    NSString *nsBody = jstringToNSString(env, body);
    NSString *nsDeepLink = jstringToNSString(env, deepLink);
    NSString *nsBackdrop = jstringToNSString(env, backdropUrl);
    NSString *reqId = [[NSUUID UUID] UUIDString];

    UNMutableNotificationContent *content = buildContent(nsTitle, nsBody, nsDeepLink, nsBackdrop, reqId);
    UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:1 repeats:NO];
    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:reqId content:content trigger:trigger];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:^(NSError *error) {
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
}

JNIEXPORT void JNICALL
Java_com_nuvio_app_features_notifications_NativeNotifications_nativeClear(JNIEnv *env, jclass cls) {
    [[UNUserNotificationCenter currentNotificationCenter] removeAllPendingNotificationRequests];
}

JNIEXPORT void JNICALL
Java_com_nuvio_app_features_notifications_NativeNotifications_nativeScheduleFromJson(JNIEnv *env, jclass cls, jstring json) {
    NSString *nsJson = jstringToNSString(env, json);
    if (nsJson == nil) return;

    NSData *data = [nsJson dataUsingEncoding:NSUTF8StringEncoding];
    NSError *parseError = nil;
    NSArray *items = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
    if (parseError || ![items isKindOfClass:[NSArray class]]) return;

    dispatch_group_t group = dispatch_group_create();

    for (NSDictionary *item in items) {
        NSString *itemId = item[@"id"];
        NSString *itemTitle = item[@"title"];
        NSString *itemBody = item[@"body"];
        NSString *dateIso = item[@"dateIso"];
        NSString *deepLink = item[@"deepLink"];
        NSString *backdropUrl = item[@"backdropUrl"];

        if (!itemId || !itemTitle || !itemBody || !dateIso) continue;

        NSArray *parts = [dateIso componentsSeparatedByString:@"-"];
        if ([parts count] != 3) continue;

        NSDateComponents *dc = [[NSDateComponents alloc] init];
        dc.year = [parts[0] integerValue];
        dc.month = [parts[1] integerValue];
        dc.day = [parts[2] integerValue];
        dc.hour = 9;
        dc.minute = 0;

        UNMutableNotificationContent *content = buildContent(itemTitle, itemBody, deepLink, backdropUrl, itemId);
        UNCalendarNotificationTrigger *trigger = [UNCalendarNotificationTrigger triggerWithDateMatchingComponents:dc repeats:NO];
        UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:itemId content:content trigger:trigger];

        dispatch_group_enter(group);
        [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:^(NSError *error) {
            dispatch_group_leave(group);
        }];
    }

    dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
}
