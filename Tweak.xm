/*
 RevoCC 0.1.0
 Clean-room implementation.

 RevoCC uses Apple's private Control Center settings provider as the
 configuration boundary. It does not copy CCAster source code.

 Main configuration API used when available:
   CCSModuleSettingsProvider
   +sharedProvider
   -orderedUserEnabledModuleIdentifiers
   -orderedFixedModuleIdentifiers
   -setAndSaveOrderedUserEnabledModuleIdentifiers:

 The editor is deliberately small and fail-closed: if the provider or
 selectors are absent, RevoCC does nothing instead of touching Control Center.
*/

#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString * const kPrefsPath =
    @"/var/mobile/Library/Preferences/com.samuel.revocc.plist";

static BOOL RVBool(NSString *key, BOOL fallback) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];
    id v = d[key];
    return v ? [v boolValue] : fallback;
}

static id RVSend0(id obj, SEL sel) {
    if (!obj || ![obj respondsToSelector:sel]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(obj, sel);
}

static void RVSend1(id obj, SEL sel, id arg) {
    if (!obj || ![obj respondsToSelector:sel]) return;
    ((void (*)(id, SEL, id))objc_msgSend)(obj, sel, arg);
}

@interface RVSettings : NSObject
+ (id)provider;
+ (BOOL)available;
+ (NSArray *)enabled;
+ (NSArray *)fixed;
+ (BOOL)saveEnabled:(NSArray *)identifiers;
@end

@implementation RVSettings

+ (id)provider {
    Class cls = NSClassFromString(@"CCSModuleSettingsProvider");
    SEL selector = NSSelectorFromString(@"sharedProvider");

    if (!cls || ![cls respondsToSelector:selector])
        return nil;

    return RVSend0(cls, selector);
}

+ (BOOL)available {
    id provider = [self provider];

    return provider &&
           [provider respondsToSelector:
                        NSSelectorFromString(@"orderedUserEnabledModuleIdentifiers")] &&
           [provider respondsToSelector:
                        NSSelectorFromString(@"setAndSaveOrderedUserEnabledModuleIdentifiers:")];
}

+ (NSArray *)enabled {
    id provider = [self provider];
    id value = RVSend0(provider,
                       NSSelectorFromString(@"orderedUserEnabledModuleIdentifiers"));

    return [value isKindOfClass:[NSArray class]] ? value : @[];
}

+ (NSArray *)fixed {
    id provider = [self provider];
    id value = RVSend0(provider,
                       NSSelectorFromString(@"orderedFixedModuleIdentifiers"));

    return [value isKindOfClass:[NSArray class]] ? value : @[];
}

+ (BOOL)saveEnabled:(NSArray *)identifiers {
    if (![self available] || !identifiers)
        return NO;

    id provider = [self provider];

    RVSend1(provider,
            NSSelectorFromString(
                @"setAndSaveOrderedUserEnabledModuleIdentifiers:"),
            identifiers);

    return YES;
}

@end


@interface RevoCCEditor : NSObject
@property(nonatomic, weak) UIViewController *viewController;
@property(nonatomic, strong) UILongPressGestureRecognizer *gesture;
@property(nonatomic, strong) UIView *editorView;
@property(nonatomic, strong) NSMutableArray<UIButton *> *buttons;
@property(nonatomic, assign) BOOL editing;
@end

@implementation RevoCCEditor

- (instancetype)initWithViewController:(UIViewController *)vc {
    self = [super init];

    if (self) {
        _viewController = vc;
        _buttons = [NSMutableArray array];
    }

    return self;
}

- (void)install {
    if (!RVBool(@"enabled", YES))
        return;

    if (![RVSettings available])
        return;

    if (self.gesture)
        return;

    self.gesture =
        [[UILongPressGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(longPressed:)];

    self.gesture.minimumPressDuration = 0.65;
    self.gesture.cancelsTouchesInView = NO;

    [self.viewController.view addGestureRecognizer:self.gesture];
}

- (void)longPressed:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan)
        return;

    if (self.editing)
        return;

    [self beginEditing];
}

- (void)beginEditing {
    if (!self.viewController.view.window)
        return;

    if (![RVSettings available])
        return;

    self.editing = YES;

    CGFloat width = CGRectGetWidth(self.viewController.view.bounds);

    self.editorView =
        [[UIView alloc] initWithFrame:CGRectMake(12, 12, width - 24, 150)];

    self.editorView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.editorView.backgroundColor =
        [UIColor colorWithWhite:0.08 alpha:0.94];

    self.editorView.layer.cornerRadius = 22.0;
    self.editorView.clipsToBounds = YES;
    self.editorView.layer.zPosition = 10000;

    UILabel *title =
        [[UILabel alloc] initWithFrame:CGRectMake(16, 10, 180, 30)];

    title.text = @"RevoCC";
    title.textColor = UIColor.whiteColor;
    title.font =
        [UIFont systemFontOfSize:18 weight:UIFontWeightBold];

    [self.editorView addSubview:title];

    UILabel *subtitle =
        [[UILabel alloc] initWithFrame:CGRectMake(16, 38, width - 130, 22)];

    subtitle.text = @"Control Center modules";
    subtitle.textColor =
        [UIColor colorWithWhite:1.0 alpha:0.60];
    subtitle.font = [UIFont systemFontOfSize:11];

    [self.editorView addSubview:subtitle];

    UIButton *done =
        [UIButton buttonWithType:UIButtonTypeSystem];

    done.frame =
        CGRectMake(CGRectGetWidth(self.editorView.bounds) - 78,
                    10,
                    64,
                    32);

    done.autoresizingMask =
        UIViewAutoresizingFlexibleLeftMargin;

    [done setTitle:@"Done"
           forState:UIControlStateNormal];

    [done setTitleColor:UIColor.whiteColor
               forState:UIControlStateNormal];

    [done addTarget:self
             action:@selector(endEditing)
   forControlEvents:UIControlEventTouchUpInside];

    [self.editorView addSubview:done];

    [self.viewController.view addSubview:self.editorView];

    [self rebuildButtons];
}

- (NSString *)displayName:(NSString *)identifier {
    if (![identifier isKindOfClass:[NSString class]])
        return @"Module";

    NSString *name = identifier;

    NSRange range =
        [name rangeOfString:@"/"
                    options:NSBackwardsSearch];

    if (range.location != NSNotFound)
        name = [name substringFromIndex:range.location + 1];

    if (name.length > 20)
        name = [name substringToIndex:20];

    return name.length ? name : @"Module";
}

- (void)rebuildButtons {
    for (UIView *view in self.buttons)
        [view removeFromSuperview];

    [self.buttons removeAllObjects];

    NSArray *enabled = [RVSettings enabled];

    CGFloat x = 12.0;
    CGFloat y = 68.0;
    CGFloat buttonWidth = 145.0;
    CGFloat buttonHeight = 32.0;

    CGFloat maxX =
        CGRectGetWidth(self.editorView.bounds) - 12.0;

    for (NSUInteger i = 0; i < enabled.count; i++) {
        UIButton *button =
            [UIButton buttonWithType:UIButtonTypeSystem];

        if (x + buttonWidth > maxX) {
            x = 12.0;
            y += 38.0;
        }

        button.frame =
            CGRectMake(x, y, buttonWidth, buttonHeight);

        button.tag = (NSInteger)i;

        button.backgroundColor =
            [UIColor colorWithWhite:1.0 alpha:0.12];

        button.layer.cornerRadius = 12.0;

        NSString *identifier = enabled[i];

        [button setTitle:[self displayName:identifier]
                forState:UIControlStateNormal];

        [button setTitleColor:UIColor.whiteColor
                      forState:UIControlStateNormal];

        button.titleLabel.font =
            [UIFont systemFontOfSize:11
                              weight:UIFontWeightMedium];

        [button addTarget:self
                   action:@selector(moduleTapped:)
         forControlEvents:UIControlEventTouchUpInside];

        [self.editorView addSubview:button];
        [self.buttons addObject:button];

        x += buttonWidth + 8.0;
    }

    CGRect frame = self.editorView.frame;

    CGFloat requiredHeight = y + buttonHeight + 12.0;

    frame.size.height =
        MIN(MAX(requiredHeight, 120.0),
            CGRectGetHeight(self.viewController.view.bounds) - 24.0);

    self.editorView.frame = frame;
}

- (void)moduleTapped:(UIButton *)button {
    NSArray *enabled = [RVSettings enabled];
    NSArray *fixed = [RVSettings fixed];

    NSUInteger index = button.tag;

    if (index >= enabled.count)
        return;

    NSString *identifier = enabled[index];

    /*
     Never reorder a module the system marks fixed.
     This is intentionally checked against the provider on every action.
    */
    if ([fixed containsObject:identifier])
        return;

    NSMutableArray *newOrder = [enabled mutableCopy];

    /*
     Move the selected movable module one position upward.
     Fixed modules are skipped rather than displaced.
    */
    NSInteger target = (NSInteger)index - 1;

    while (target >= 0 &&
           [fixed containsObject:newOrder[(NSUInteger)target]]) {
        target--;
    }

    if (target < 0)
        return;

    [newOrder exchangeObjectAtIndex:index
                   withObjectAtIndex:(NSUInteger)target];

    /*
     Basic validation: don't write duplicate identifiers or empty strings.
    */
    NSMutableOrderedSet *unique =
        [NSMutableOrderedSet orderedSet];

    for (id item in newOrder) {
        if ([item isKindOfClass:[NSString class]] &&
            [(NSString *)item length] > 0) {
            [unique addObject:item];
        }
    }

    NSArray *validated = unique.array;

    if (validated.count != newOrder.count)
        return;

    if ([RVSettings saveEnabled:validated]) {
        [self rebuildButtons];

        UIImpactFeedbackGenerator *feedback =
            [[UIImpactFeedbackGenerator alloc]
                initWithStyle:UIImpactFeedbackStyleLight];

        [feedback impactOccurred];
    }
}

- (void)endEditing {
    self.editing = NO;

    [self.editorView removeFromSuperview];
    self.editorView = nil;

    [self.buttons removeAllObjects];
}

- (void)invalidate {
    [self endEditing];

    if (self.gesture) {
        [self.viewController.view
            removeGestureRecognizer:self.gesture];
    }

    self.gesture = nil;
}

@end


static NSHashTable *RVEditors;

%hook CCUIControlCenterViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    if (!RVBool(@"enabled", YES))
        return;

    if (![RVSettings available])
        return;

    if (!RVEditors)
        RVEditors = [NSHashTable weakObjectsHashTable];

    RevoCCEditor *editor =
        [[RevoCCEditor alloc]
            initWithViewController:self];

    [RVEditors addObject:editor];

    [editor install];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;

    for (RevoCCEditor *editor in RVEditors.allObjects) {
        if (editor.viewController == self)
            [editor invalidate];
    }
}

%end
