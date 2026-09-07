#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>

static NSString *const RVPrefs =
    @"/var/mobile/Library/Preferences/com.samuel.revocc.plist";

static BOOL RVEnabled(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:RVPrefs];
    return d[@"enabled"] ? [d[@"enabled"] boolValue] : YES;
}

static id RVSend0(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}

static void RVSend1(id obj, SEL sel, id arg) {
    if (!obj || ![obj respondsToSelector:sel]) return;
    ((void (*)(id, SEL, id))objc_msgSend)(obj, sel, arg);
}

/*
 RevoCC deliberately uses id for private UIKit classes.
 This avoids Clang's strict distinct-pointer diagnostics when Theos
 generates the CCUIControlCenterViewController declaration.
*/
@interface RVSettings : NSObject
+ (id)provider;
+ (BOOL)available;
+ (NSArray *)enabled;
+ (NSArray *)fixed;
+ (BOOL)save:(NSArray *)order;
@end

@implementation RVSettings

+ (id)provider {
    Class c = NSClassFromString(@"CCSModuleSettingsProvider");
    SEL s = NSSelectorFromString(@"sharedProvider");
    if (!c || ![c respondsToSelector:s]) return nil;
    return RVSend0(c, s);
}

+ (BOOL)available {
    id p = [self provider];
    return p &&
      [p respondsToSelector:NSSelectorFromString(@"orderedUserEnabledModuleIdentifiers")] &&
      [p respondsToSelector:NSSelectorFromString(@"setAndSaveOrderedUserEnabledModuleIdentifiers:")];
}

+ (NSArray *)enabled {
    id p = [self provider];
    id a = RVSend0(p, NSSelectorFromString(@"orderedUserEnabledModuleIdentifiers"));
    return [a isKindOfClass:NSArray.class] ? a : @[];
}

+ (NSArray *)fixed {
    id p = [self provider];
    id a = RVSend0(p, NSSelectorFromString(@"orderedFixedModuleIdentifiers"));
    return [a isKindOfClass:NSArray.class] ? a : @[];
}

+ (BOOL)save:(NSArray *)order {
    if (![self available] || ![order isKindOfClass:NSArray.class]) return NO;

    /* Validate before touching Apple's settings provider. */
    NSMutableOrderedSet *unique = [NSMutableOrderedSet orderedSet];
    for (id value in order) {
        if (![value isKindOfClass:NSString.class] ||
            [(NSString *)value length] == 0) return NO;
        [unique addObject:value];
    }

    if (unique.count != order.count) return NO;

    RVSend1([self provider],
            NSSelectorFromString(@"setAndSaveOrderedUserEnabledModuleIdentifiers:"),
            unique.array);
    return YES;
}

@end

@interface RevoCCEditor : NSObject
@property(nonatomic, weak) id host;
@property(nonatomic, strong) UILongPressGestureRecognizer *gesture;
@property(nonatomic, strong) UIView *panel;
@property(nonatomic, strong) NSMutableArray<UIButton *> *buttons;
@end

@implementation RevoCCEditor

- (instancetype)initWithHost:(id)host {
    self = [super init];
    if (self) {
        _host = host;
        _buttons = [NSMutableArray array];
    }
    return self;
}

- (void)install {
    if (!self.host || !RVEnabled() || ![RVSettings available]) return;

    self.gesture =
      [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(held:)];

    self.gesture.minimumPressDuration = 0.65;
    self.gesture.cancelsTouchesInView = NO;

    id view = RVSend0(self.host, @selector(view));
    if ([view isKindOfClass:UIView.class])
        [(UIView *)view addGestureRecognizer:self.gesture];
}

- (void)held:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan)
        [self begin];
}

- (void)begin {
    id view = RVSend0(self.host, @selector(view));
    if (![view isKindOfClass:UIView.class] || self.panel) return;

    UIView *hostView = (UIView *)view;
    CGFloat width = CGRectGetWidth(hostView.bounds);

    self.panel =
      [[UIView alloc] initWithFrame:CGRectMake(12, 12, width - 24, 160)];

    self.panel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.panel.backgroundColor =
      [UIColor colorWithWhite:0.08 alpha:0.95];
    self.panel.layer.cornerRadius = 22;
    self.panel.layer.zPosition = 10000;
    self.panel.clipsToBounds = YES;

    UILabel *title =
      [[UILabel alloc] initWithFrame:CGRectMake(16, 8, 150, 30)];
    title.text = @"RevoCC";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    [self.panel addSubview:title];

    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    done.frame = CGRectMake(width - 100, 8, 70, 30);
    done.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [done setTitle:@"Done" forState:UIControlStateNormal];
    [done setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [done addTarget:self action:@selector(close)
   forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:done];

    [hostView addSubview:self.panel];
    [self rebuild];
}

- (NSString *)nameFor:(NSString *)identifier {
    NSRange r =
      [identifier rangeOfString:@"/" options:NSBackwardsSearch];

    NSString *s = r.location == NSNotFound ?
      identifier : [identifier substringFromIndex:r.location + 1];

    return s.length > 18 ? [s substringToIndex:18] : s;
}

- (void)rebuild {
    for (UIView *v in self.buttons) [v removeFromSuperview];
    [self.buttons removeAllObjects];

    NSArray *enabled = [RVSettings enabled];
    NSArray *fixed = [RVSettings fixed];

    CGFloat x = 12;
    CGFloat y = 48;
    CGFloat w = 145;
    CGFloat h = 32;
    CGFloat maxX = CGRectGetWidth(self.panel.bounds) - 12;

    for (NSUInteger i = 0; i < enabled.count; i++) {
        if (x + w > maxX) {
            x = 12;
            y += h + 7;
        }

        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.frame = CGRectMake(x, y, w, h);
        b.tag = (NSInteger)i;
        b.layer.cornerRadius = 11;
        b.backgroundColor =
          [UIColor colorWithWhite:1 alpha:0.12];

        NSString *identifier = enabled[i];
        NSString *label = [self nameFor:identifier];

        [b setTitle:label forState:UIControlStateNormal];
        [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        b.titleLabel.font =
          [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];

        /*
         A fixed module remains visible but is not movable.
        */
        if ([fixed containsObject:identifier]) {
            b.alpha = 0.45;
        } else {
            [b addTarget:self action:@selector(moveUp:)
       forControlEvents:UIControlEventTouchUpInside];
        }

        [self.panel addSubview:b];
        [self.buttons addObject:b];

        x += w + 7;
    }

    CGFloat needed = MIN(y + h + 12,
                         CGRectGetHeight(self.panel.superview.bounds) - 24);
    CGRect f = self.panel.frame;
    f.size.height = MAX(110, needed);
    self.panel.frame = f;
}

- (void)moveUp:(UIButton *)sender {
    NSArray *enabled = [RVSettings enabled];
    NSArray *fixed = [RVSettings fixed];

    NSUInteger i = sender.tag;
    if (i >= enabled.count) return;

    NSString *selected = enabled[i];
    if ([fixed containsObject:selected]) return;

    NSMutableArray *order = [enabled mutableCopy];

    NSInteger target = (NSInteger)i - 1;
    while (target >= 0 &&
           [fixed containsObject:order[(NSUInteger)target]]) {
        target--;
    }

    if (target < 0) return;

    [order exchangeObjectAtIndex:i withObjectAtIndex:(NSUInteger)target];

    if ([RVSettings save:order])
        [self rebuild];
}

- (void)close {
    [self.panel removeFromSuperview];
    self.panel = nil;
}

- (void)invalidate {
    [self close];

    id view = RVSend0(self.host, @selector(view));
    if ([view isKindOfClass:UIView.class] && self.gesture)
        [(UIView *)view removeGestureRecognizer:self.gesture];

    self.gesture = nil;
}

@end

static NSHashTable *RVEditors;

%hook CCUIControlCenterViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    if (!RVEnabled() || ![RVSettings available]) return;

    if (!RVEditors)
        RVEditors = [NSHashTable weakObjectsHashTable];

    RevoCCEditor *editor =
      [[RevoCCEditor alloc] initWithHost:(id)self];

    [RVEditors addObject:editor];
    [editor install];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;

    for (RevoCCEditor *editor in RVEditors.allObjects) {
        if (editor.host == (id)self)
            [editor invalidate];
    }
}

%end
