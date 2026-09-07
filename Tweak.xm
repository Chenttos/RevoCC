/*
 AsterCC 0.2
 Clean-room implementation.

 This project independently implements an editable Control Center configuration
 layer. It does NOT copy CCAster source. The public CCAster repository was
 consulted only to identify Apple's private configuration provider and its
 publicly observable API surface.

 Core idea:
   CCSModuleSettingsProvider
        -> orderedUserEnabledModuleIdentifiers
        -> orderedFixedModuleIdentifiers
        -> setAndSaveOrderedUserEnabledModuleIdentifiers:

 We use that provider as the persistence boundary. Native module controllers
 remain Apple's objects; AsterCC only changes their ordered identifier list and
 adds a lightweight editor overlay.
*/

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const kPrefsPath = @"/var/mobile/Library/Preferences/com.samuel.astercc.plist";
static NSString *const kChanged = @"com.samuel.astercc/preferencesChanged";
static NSString *const kReset = @"com.samuel.astercc/reset";

static BOOL PrefBool(NSString *key, BOOL fallback) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];
    return d[key] ? [d[key] boolValue] : fallback;
}
static NSInteger PrefInt(NSString *key, NSInteger fallback) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];
    return d[key] ? [d[key] integerValue] : fallback;
}
static CGFloat PrefFloat(NSString *key, CGFloat fallback) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];
    return d[key] ? [d[key] doubleValue] : fallback;
}

static id Send0(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}
static void Send1(id obj, SEL sel, id arg) {
    if (!obj || ![obj respondsToSelector:sel]) return;
    ((void (*)(id, SEL, id))objc_msgSend)(obj, sel, arg);
}

@interface AsterProvider : NSObject
+ (id)provider;
+ (NSArray<NSString *> *)enabled;
+ (NSArray<NSString *> *)fixed;
+ (BOOL)save:(NSArray<NSString *> *)ids;
+ (BOOL)available;
@end

@implementation AsterProvider
+ (id)provider {
    Class c = NSClassFromString(@"CCSModuleSettingsProvider");
    SEL s = NSSelectorFromString(@"sharedProvider");
    return c && [c respondsToSelector:s] ? Send0(c, s) : nil;
}
+ (BOOL)available {
    id p = [self provider];
    return p && [p respondsToSelector:NSSelectorFromString(@"orderedUserEnabledModuleIdentifiers")] &&
           [p respondsToSelector:NSSelectorFromString(@"setAndSaveOrderedUserEnabledModuleIdentifiers:")];
}
+ (NSArray *)enabled {
    id p = [self provider];
    id a = Send0(p, NSSelectorFromString(@"orderedUserEnabledModuleIdentifiers"));
    return [a isKindOfClass:NSArray.class] ? a : @[];
}
+ (NSArray *)fixed {
    id p = [self provider];
    id a = Send0(p, NSSelectorFromString(@"orderedFixedModuleIdentifiers"));
    return [a isKindOfClass:NSArray.class] ? a : @[];
}
+ (BOOL)save:(NSArray *)ids {
    id p = [self provider];
    if (!p || ![ids isKindOfClass:NSArray.class]) return NO;
    Send1(p, NSSelectorFromString(@"setAndSaveOrderedUserEnabledModuleIdentifiers:"), ids);
    return YES;
}
@end

@interface AsterCCEditor : NSObject
@property(nonatomic, weak) UIViewController *host;
@property(nonatomic, strong) UIView *bar;
@property(nonatomic, strong) UIVisualEffectView *panel;
@property(nonatomic, strong) NSMutableArray<UIButton *> *chips;
@property(nonatomic, strong) UILongPressGestureRecognizer *longPress;
@property(nonatomic) BOOL editing;
@end

@implementation AsterCCEditor

- (instancetype)initWithHost:(UIViewController *)host {
    if (!host) return nil;
    self = [super init];
    if (!self) return nil;
    _host = host;
    _chips = [NSMutableArray array];
    return self;
}

- (void)install {
    if (!PrefBool(@"enabled", YES) || !PrefBool(@"editGesture", YES)) return;
    if (![AsterProvider available]) return;
    if (self.longPress) return;

    self.longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                                    action:@selector(held:)];
    self.longPress.minimumPressDuration = 0.65;
    self.longPress.cancelsTouchesInView = NO;
    [self.host.view addGestureRecognizer:self.longPress];
}

- (void)held:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan || self.editing) return;
    [self enter];
}

- (void)enter {
    if (self.editing || !self.host.view.window || ![AsterProvider available]) return;
    self.editing = YES;

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark];
    self.panel = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.panel.layer.cornerRadius = 20;
    self.panel.clipsToBounds = YES;
    self.panel.frame = CGRectMake(12, 12, CGRectGetWidth(self.host.view.bounds)-24, 96);
    self.panel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.panel.layer.zPosition = 5000;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, 180, 28)];
    title.text = @"AsterCC";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    [self.panel.contentView addSubview:title];

    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    done.frame = CGRectMake(CGRectGetWidth(self.panel.bounds)-72, 7, 58, 30);
    done.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [done setTitle:@"Done" forState:UIControlStateNormal];
    done.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [done addTarget:self action:@selector(done) forControlEvents:UIControlEventTouchUpInside];
    [self.panel.contentView addSubview:done];

    UILabel *hint = [[UILabel alloc] initWithFrame:CGRectMake(16, 37, CGRectGetWidth(self.panel.bounds)-32, 20)];
    hint.text = @"Tap a module below to move it up or down";
    hint.textColor = [UIColor colorWithWhite:1 alpha:.68];
    hint.font = [UIFont systemFontOfSize:11];
    hint.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.panel.contentView addSubview:hint];

    [self.host.view addSubview:self.panel];
    [self rebuildChips];
}

- (void)rebuildChips {
    for (UIView *v in self.chips) [v removeFromSuperview];
    [self.chips removeAllObjects];

    NSArray *ids = [AsterProvider enabled];
    CGFloat y = 68;
    CGFloat x = 12;

    for (NSUInteger i = 0; i < ids.count; i++) {
        NSString *identifier = ids[i];
        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(x, y, 140, 32);
        b.backgroundColor = [UIColor colorWithWhite:1 alpha:.12];
        b.layer.cornerRadius = 12;
        b.tag = (NSInteger)i;
        b.accessibilityIdentifier = identifier;
        [b setTitle:[self shortName:identifier] forState:UIControlStateNormal];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        b.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        [b addTarget:self action:@selector(chipTap:) forControlEvents:UIControlEventTouchUpInside];

        UIButton *up = [UIButton buttonWithType:UIButtonTypeSystem];
        up.frame = CGRectMake(98, 0, 42, 32);
        up.tag = (NSInteger)i;
        [up setTitle:@"↑" forState:UIControlStateNormal];
        [up setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        [up addTarget:self action:@selector(moveUp:) forControlEvents:UIControlEventTouchUpInside];
        [b addSubview:up];

        [self.panel.contentView addSubview:b];
        [self.chips addObject:b];

        x += 148;
        if (x + 140 > CGRectGetWidth(self.panel.bounds)) {
            x = 12;
            y += 40;
        }
    }
}

- (NSString *)shortName:(NSString *)identifier {
    NSString *s = identifier;
    NSRange slash = [s rangeOfString:@"/" options:NSBackwardsSearch];
    if (slash.location != NSNotFound) s = [s substringFromIndex:slash.location+1];
    if (s.length > 18) s = [s substringToIndex:18];
    return s.length ? s : @"Control";
}

- (void)chipTap:(UIButton *)sender {
    NSUInteger i = sender.tag;
    NSArray *ids = [AsterProvider enabled];
    if (i >= ids.count) return;

    NSArray *fixed = [AsterProvider fixed];
    NSString *identifier = ids[i];

    // Fixed modules are never reordered by AsterCC.
    if ([fixed containsObject:identifier]) {
        UIImpactFeedbackGenerator *h = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [h impactOccurred];
        return;
    }

    // Tapping a normal module toggles its position with the next movable module.
    NSMutableArray *m = [ids mutableCopy];
    NSUInteger next = NSNotFound;
    for (NSUInteger j = i + 1; j < m.count; j++) {
        if (![fixed containsObject:m[j]]) { next = j; break; }
    }
    if (next != NSNotFound) {
        [m exchangeObjectAtIndex:i withObjectAtIndex:next];
        if ([AsterProvider save:m]) {
            [self rebuildChips];
            [self requestReload];
        }
    }
}

- (void)moveUp:(UIButton *)sender {
    NSUInteger i = sender.tag;
    NSArray *ids = [AsterProvider enabled];
    NSArray *fixed = [AsterProvider fixed];
    if (i >= ids.count || [fixed containsObject:ids[i]]) return;

    NSInteger j = (NSInteger)i - 1;
    while (j >= 0 && [fixed containsObject:ids[j]]) j--;
    if (j < 0) return;

    NSMutableArray *m = [ids mutableCopy];
    [m exchangeObjectAtIndex:i withObjectAtIndex:j];
    if ([AsterProvider save:m]) {
        [self rebuildChips];
        [self requestReload];
    }
}

- (void)requestReload {
    // The provider persists the configuration. The native CC hierarchy is
    // allowed to decide when to consume it; we don't tear down its controllers.
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                          CFSTR("com.apple.controlcenter.settingsChanged"),
                                          NULL, NULL, YES);
}

- (void)done {
    self.editing = NO;
    [self.panel removeFromSuperview];
    self.panel = nil;
    [self.chips removeAllObjects];
}

- (void)reset {
    if (![AsterProvider available]) return;

    NSString *path = kPrefsPath;
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:path] ?: [NSMutableDictionary dictionary];
    [d removeObjectForKey:@"savedOrder"];
    [d removeObjectForKey:@"savedRemoved"];
    [d writeToFile:path atomically:YES];

    // Do not fabricate an "original" order. Apple's provider remains the
    // source of truth. Reset therefore only clears AsterCC's own bookkeeping.
    [self done];
}

@end

static NSHashTable *gEditors;

%hook CCUIControlCenterViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    if (!PrefBool(@"enabled", YES)) return;
    if (![AsterProvider available]) return;

    if (!gEditors) gEditors = [NSHashTable weakObjectsHashTable];

    AsterCCEditor *editor = [[AsterCCEditor alloc] initWithHost:self];
    [gEditors addObject:editor];
    [editor install];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;

    for (AsterCCEditor *editor in gEditors.allObjects) {
        if (editor.host == self) [editor done];
    }
}

%end

static void AsterPrefsChanged(CFNotificationCenterRef center,
                              void *observer,
                              CFStringRef name,
                              const void *object,
                              CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        // Existing editors are deliberately left alone. This avoids mutating
        // the active CC hierarchy from a preference callback.
    });
}

%ctor {
    @autoreleasepool {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                         NULL, AsterPrefsChanged,
                                         (__bridge CFStringRef)kChanged,
                                         NULL, CFNotificationSuspensionBehaviorCoalesce);

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                         NULL, AsterPrefsChanged,
                                         (__bridge CFStringRef)kReset,
                                         NULL, CFNotificationSuspensionBehaviorCoalesce);
    }
}
