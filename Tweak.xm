/*
 RevoCC 0.2.2
 Clean-room implementation of the requested Control Center chrome:
 - top editing/add button
 - top power button
 - vertical page selector
 - page selection is interactive ONLY after Control Center is fully open
 - while opening or closing, the page selector is locked.

 The implementation is independently written. It uses the public CCAster
 repository only as a behavioral reference for the requested UI concepts.
*/

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const RVPrefsPath =
    @"/var/mobile/Library/Preferences/com.samuel.revocc.plist";

static NSInteger const RVQuickAccessTag = 181000;
static NSInteger const RVPageSelectorTag = 181030;
static NSInteger const RVAddButtonTag = 181001;
static NSInteger const RVPowerButtonTag = 181002;

static BOOL gRVCCPresented = NO;
/*
 iOS 16 Control Center presentation states used by this tweak:
 0 = dismissed
 1 = presenting/opening
 2 = presented/settled
 3 = dismissing
*/
static NSUInteger gRVCCPresentationState = 0;
static NSUInteger gRVCurrentPage = 0;
static NSUInteger gRVPageCount = 1;
static CGFloat gRVPageSpan = 0.0;

static NSHashTable *gRVEditors;

static BOOL RVEnabled(void) {
    NSDictionary *d =
        [NSDictionary dictionaryWithContentsOfFile:RVPrefsPath];

    return d[@"enabled"] ? [d[@"enabled"] boolValue] : YES;
}

static id RVSend0(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector])
        return nil;

    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static void RVSend1(id object, SEL selector, id argument) {
    if (!object || ![object respondsToSelector:selector])
        return;

    ((void (*)(id, SEL, id))objc_msgSend)(object, selector, argument);
}

#pragma mark - Native module settings provider

@interface RVSettings : NSObject
+ (id)provider;
+ (BOOL)available;
+ (NSArray *)enabled;
+ (NSArray *)fixed;
+ (BOOL)save:(NSArray *)order;
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
            NSSelectorFromString(
                @"orderedUserEnabledModuleIdentifiers")] &&
        [provider respondsToSelector:
            NSSelectorFromString(
                @"setAndSaveOrderedUserEnabledModuleIdentifiers:")];
}

+ (NSArray *)enabled {
    id provider = [self provider];

    id value =
        RVSend0(provider,
                NSSelectorFromString(
                    @"orderedUserEnabledModuleIdentifiers"));

    return [value isKindOfClass:NSArray.class] ? value : @[];
}

+ (NSArray *)fixed {
    id provider = [self provider];

    id value =
        RVSend0(provider,
                NSSelectorFromString(
                    @"orderedFixedModuleIdentifiers"));

    return [value isKindOfClass:NSArray.class] ? value : @[];
}

+ (BOOL)save:(NSArray *)order {
    if (![self available] ||
        ![order isKindOfClass:NSArray.class])
        return NO;

    NSMutableOrderedSet *unique =
        [NSMutableOrderedSet orderedSet];

    for (id item in order) {
        if (![item isKindOfClass:NSString.class] ||
            [(NSString *)item length] == 0)
            return NO;

        [unique addObject:item];
    }

    if (unique.count != order.count)
        return NO;

    RVSend1([self provider],
            NSSelectorFromString(
                @"setAndSaveOrderedUserEnabledModuleIdentifiers:"),
            unique.array);

    return YES;
}

@end

#pragma mark - RevoCC chrome

static BOOL RVIsControlCenterOverlayController(id controller) {
    if (!controller)
        return NO;

    NSString *name = NSStringFromClass([controller class]);

    // iOS 16 Control Center's actual modular overlay is the object that
    // owns the module collection. Do not depend on CCUIControlCenterViewController,
    // which is not the overlay on all iOS 16 builds.
    return [name isEqualToString:@"CCUIModularControlCenterOverlayViewController"] ||
           [name containsString:@"CCUIModularControlCenterOverlayViewController"];
}

@interface RVEditor : NSObject
@property(nonatomic, weak) id host;
@property(nonatomic, strong) UILongPressGestureRecognizer *editGesture;
@property(nonatomic, strong) UIView *quickHost;
@property(nonatomic, strong) UIView *pageHost;
@property(nonatomic, strong) NSMutableArray<UIButton *> *pageButtons;
@end

static BOOL gRVPresentationStateIsFullyOpen(void);

@implementation RVEditor

- (instancetype)initWithHost:(id)host {
    self = [super init];

    if (self) {
        _host = host;
        _pageButtons = [NSMutableArray array];
    }

    return self;
}

- (UIView *)hostView {
    id view = RVSend0(self.host, @selector(view));

    return [view isKindOfClass:UIView.class] ?
        (UIView *)view : nil;
}

- (void)install {
    if (!self.host || !RVEnabled())
        return;

    UIView *view = [self hostView];

    if (!view)
        return;

    [self installQuickButtons];
    [self installPageSelector];

    self.editGesture =
        [[UILongPressGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(editHeld:)];

    self.editGesture.minimumPressDuration = 0.65;
    self.editGesture.cancelsTouchesInView = NO;

    [view addGestureRecognizer:self.editGesture];

    [self refresh];
}

#pragma mark Quick buttons

- (UIButton *)roundButtonWithSymbol:(NSString *)symbol
                               tag:(NSInteger)tag {
    UIButton *button =
        [UIButton buttonWithType:UIButtonTypeSystem];

    button.tag = tag;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.layer.cornerRadius = 20.0;
    button.backgroundColor =
        [UIColor colorWithWhite:0.08 alpha:0.82];

    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration
            configurationWithPointSize:17.0
                                weight:UIImageSymbolWeightSemibold];

    UIImage *image =
        [UIImage systemImageNamed:symbol
                withConfiguration:configuration];

    [button setImage:image forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor;

    return button;
}

- (void)installQuickButtons {
    UIView *view = [self hostView];

    if (!view)
        return;

    if ([view viewWithTag:RVQuickAccessTag])
        return;

    UIView *host =
        [[UIView alloc]
            initWithFrame:CGRectMake(0, 0,
                                     CGRectGetWidth(view.bounds),
                                     76)];

    host.tag = RVQuickAccessTag;
    host.autoresizingMask =
        UIViewAutoresizingFlexibleWidth;
    host.backgroundColor = UIColor.clearColor;
    host.userInteractionEnabled = YES;
    host.layer.zPosition = 9000;

    [view addSubview:host];

    UIButton *add =
        [self roundButtonWithSymbol:@"plus"
                                tag:RVAddButtonTag];

    [add addTarget:self
            action:@selector(addPressed:)
  forControlEvents:UIControlEventTouchUpInside];

    UIButton *power =
        [self roundButtonWithSymbol:@"power"
                                tag:RVPowerButtonTag];

    [power addTarget:self
              action:@selector(powerPressed:)
    forControlEvents:UIControlEventTouchUpInside];

    [host addSubview:add];
    [host addSubview:power];

    [NSLayoutConstraint activateConstraints:@[
        [add.leadingAnchor constraintEqualToAnchor:
            host.leadingAnchor constant:22.0],

        [add.topAnchor constraintEqualToAnchor:
            host.topAnchor constant:18.0],

        [add.widthAnchor constraintEqualToConstant:40.0],
        [add.heightAnchor constraintEqualToConstant:40.0],

        [power.trailingAnchor constraintEqualToAnchor:
            host.trailingAnchor constant:-22.0],

        [power.topAnchor constraintEqualToAnchor:
            host.topAnchor constant:18.0],

        [power.widthAnchor constraintEqualToConstant:40.0],
        [power.heightAnchor constraintEqualToConstant:40.0]
    ]];
}

- (void)addPressed:(UIButton *)sender {
    if (!gRVCCPresented)
        return;

    /*
     RevoCC's editing entry point is deliberately kept separate from
     the native module configuration provider.
    */
    [self beginEditing];
}

- (void)powerPressed:(UIButton *)sender {
    if (!gRVCCPresented)
        return;

    Class factory =
        NSClassFromString(@"SBUIPowerDownViewControllerFactory");

    SEL selector =
        NSSelectorFromString(@"newPowerDownViewController");

    if (!factory ||
        ![factory respondsToSelector:selector])
        return;

    id controller =
        RVSend0(factory, selector);

    id presenter = self.host;

    if (!controller || !presenter ||
        ![presenter respondsToSelector:
            @selector(presentViewController:animated:completion:)])
        return;

    [controller setModalPresentationStyle:
        UIModalPresentationFullScreen];

    [presenter presentViewController:controller
                            animated:YES
                          completion:nil];
}

- (void)editHeld:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan)
        return;

    if (!gRVCCPresented)
        return;

    [self beginEditing];
}

- (void)beginEditing {
    /*
     Keep the existing RevoCC editor entry point. A later layout editor
     can replace this without changing the page selector/chrome layer.
    */
    NSLog(@"[RevoCC] edit mode requested");
}

#pragma mark Page selector

- (void)installPageSelector {
    UIView *view = [self hostView];

    if (!view)
        return;

    if ([view viewWithTag:RVPageSelectorTag])
        return;

    UIView *host =
        [[UIView alloc]
            initWithFrame:CGRectMake(
                CGRectGetWidth(view.bounds) - 52,
                0,
                52,
                CGRectGetHeight(view.bounds))];

    host.tag = RVPageSelectorTag;
    host.autoresizingMask =
        UIViewAutoresizingFlexibleLeftMargin |
        UIViewAutoresizingFlexibleHeight;

    host.backgroundColor = UIColor.clearColor;
    host.userInteractionEnabled = YES;
    host.layer.zPosition = 8999;

    [view addSubview:host];
    self.pageHost = host;

    [self rebuildPageButtons];
}

- (NSUInteger)calculatePageCount {
    UIView *view = [self hostView];

    if (!view)
        return 1;

    /*
     Find the native module collection without relying on a concrete
     private header. This is intentionally runtime-only.
    */
    NSMutableArray *queue =
        [NSMutableArray arrayWithObject:view];

    UIView *collectionView = nil;
    CGFloat maximumY = CGRectGetHeight(view.bounds);

    while (queue.count) {
        UIView *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];

        NSString *className =
            NSStringFromClass(candidate.class);

        if ([className containsString:@"CCUIModuleCollectionView"]) {
            collectionView = candidate;
            break;
        }

        [queue addObjectsFromArray:candidate.subviews];
    }

    if (!collectionView)
        return 1;

    maximumY =
        MAX(maximumY,
            CGRectGetMaxY(collectionView.bounds));

    /*
     A conservative page span based on the actual CC height. This avoids
     hard-coding CCAster's grid constants and keeps the calculation
     independent of its implementation.
    */
    CGFloat pageSpan =
        MAX(CGRectGetHeight(view.bounds) * 0.82, 500.0);

    gRVPageSpan = pageSpan;

    NSUInteger pages =
        (NSUInteger)ceil(maximumY / pageSpan);

    return MAX(1, MIN(pages, 9));
}

- (void)rebuildPageButtons {
    if (!self.pageHost)
        return;

    for (UIView *view in self.pageButtons)
        [view removeFromSuperview];

    [self.pageButtons removeAllObjects];

    gRVPageCount = [self calculatePageCount];

    if (gRVPageCount <= 1) {
        self.pageHost.hidden = YES;
        return;
    }

    self.pageHost.hidden = NO;

    CGFloat step =
        MIN(42.0,
            CGRectGetHeight(self.pageHost.bounds) /
                (CGFloat)gRVPageCount);

    for (NSUInteger page = 0;
         page < gRVPageCount;
         page++) {

        UIButton *button =
            [UIButton buttonWithType:UIButtonTypeSystem];

        button.frame =
            CGRectMake(6,
                       page * step,
                       40,
                       step);

        UIImageSymbolConfiguration *configuration =
            [UIImageSymbolConfiguration
                configurationWithPointSize:
                    page == gRVCurrentPage ? 13.0 : 9.0
                                  weight:
                    UIImageSymbolWeightSemibold];

        NSString *symbol =
            page == gRVCurrentPage ?
                @"circle.fill" :
                @"circle";

        [button setImage:
            [UIImage systemImageNamed:symbol
                   withConfiguration:configuration]
               forState:UIControlStateNormal];

        button.tintColor =
            page == gRVCurrentPage ?
                UIColor.whiteColor :
                [UIColor colorWithWhite:1.0 alpha:0.55];

        button.tag = 3000 + page;

        /*
         IMPORTANT:
         The page buttons exist visually all the time, but interaction is
         only enabled while Control Center is opening (state == 1).
        */
        button.userInteractionEnabled =
            gRVCCPresentationState == 2;

        [button addTarget:self
                   action:@selector(pageTapped:)
         forControlEvents:UIControlEventTouchUpInside];

        [self.pageHost addSubview:button];
        [self.pageButtons addObject:button];
    }

    self.pageHost.userInteractionEnabled =
        gRVCCPresentationState == 2;
}

- (void)pageTapped:(UIButton *)button {
    /*
     Hard gate: once the native presentation is fully open, page switching
     is disabled. This is checked at touch time as well as during layout.
    */
    if (gRVPresentationStateIsFullyOpen())
        return;

    if (gRVCCPresentationState != 2)
        return;

    NSUInteger target =
        (NSUInteger)(button.tag - 3000);

    if (target >= gRVPageCount)
        return;

    [self switchToPage:target animated:YES];
}

static BOOL gRVPresentationStateIsFullyOpen(void) {
    return gRVCCPresentationState == 2;
}

- (UIView *)moduleCollectionView {
    UIView *root = [self hostView];

    if (!root)
        return nil;

    NSMutableArray *queue =
        [NSMutableArray arrayWithObject:root];

    while (queue.count) {
        UIView *candidate = queue.firstObject;
        [queue removeObjectAtIndex:0];

        if ([NSStringFromClass(candidate.class)
                containsString:@"CCUIModuleCollectionView"])
            return candidate;

        [queue addObjectsFromArray:candidate.subviews];
    }

    return nil;
}

- (void)switchToPage:(NSUInteger)page
            animated:(BOOL)animated {
    UIView *collection = [self moduleCollectionView];

    if (!collection)
        return;

    if (page >= gRVPageCount)
        return;

    gRVCurrentPage = page;

    CGFloat offset =
        -(CGFloat)page * gRVPageSpan;

    /*
     Apply the page movement to the collection's layer instead of
     manipulating individual CC modules. This keeps the operation atomic.
    */
    CATransform3D transform = CATransform3DIdentity;
    transform =
        CATransform3DTranslate(transform, 0, offset, 0);

    if (animated) {
        [UIView animateWithDuration:0.22
                              delay:0
                            options:
                                UIViewAnimationOptionCurveEaseInOut |
                                UIViewAnimationOptionBeginFromCurrentState |
                                UIViewAnimationOptionAllowUserInteraction
                         animations:^{
            collection.layer.transform = transform;
        } completion:nil];
    } else {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        collection.layer.transform = transform;
        [CATransaction commit];
    }

    [self rebuildPageButtons];
}

- (void)refresh {
    if (!gRVCCPresented) {
        if (self.quickHost)
            self.quickHost.hidden = YES;

        if (self.pageHost)
            self.pageHost.hidden = YES;

        return;
    }

    if (!self.quickHost)
        self.quickHost =
            [[self hostView] viewWithTag:RVQuickAccessTag];

    if (!self.pageHost)
        self.pageHost =
            [[self hostView] viewWithTag:RVPageSelectorTag];

    if (self.quickHost)
        self.quickHost.hidden = NO;

    [self rebuildPageButtons];

    /*
     Page selector interaction is deliberately enabled only at the fully-open
     settled boundary (presentation state 2).
    */
    BOOL canSelect =
        gRVCCPresentationState == 2;

    self.pageHost.userInteractionEnabled = canSelect;

    for (UIButton *button in self.pageButtons)
        button.userInteractionEnabled = canSelect;
}

- (void)invalidate {
    UIView *view = [self hostView];

    if (view && self.editGesture)
        [view removeGestureRecognizer:self.editGesture];

    [self.quickHost removeFromSuperview];
    [self.pageHost removeFromSuperview];

    self.quickHost = nil;
    self.pageHost = nil;
    self.editGesture = nil;
}

@end

#pragma mark - Control Center presentation state

%hook SBControlCenterController

- (void)controlCenterViewController:(id)controller
             didChangePresentationState:(NSUInteger)state {
    %orig;

    gRVCCPresentationState = state;
    gRVCCPresented = state != 0;

    for (RVEditor *editor in gRVEditors.allObjects) {
        [editor refresh];
    }
}

%end

#pragma mark - Overlay lifecycle

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    if (!RVEnabled() || !RVIsControlCenterOverlayController(self))
        return;

    if (!gRVEditors)
        gRVEditors = [NSHashTable weakObjectsHashTable];

    RVEditor *existing = nil;
    for (RVEditor *editor in gRVEditors.allObjects) {
        if (editor.host == (id)self) {
            existing = editor;
            break;
        }
    }

    RVEditor *editor = existing ?: [[RVEditor alloc] initWithHost:(id)self];

    if (!existing) {
        [gRVEditors addObject:editor];
        [editor install];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (editor.host)
            [editor refresh];
    });
}

- (void)viewDidLayoutSubviews {
    %orig;

    if (!RVIsControlCenterOverlayController(self) || !gRVCCPresented)
        return;

    for (RVEditor *editor in gRVEditors.allObjects) {
        if (editor.host != (id)self)
            continue;

        UIView *view = [editor hostView];
        if (!view)
            continue;

        UIView *quick = [view viewWithTag:RVQuickAccessTag];
        UIView *pages = [view viewWithTag:RVPageSelectorTag];

        if (quick)
            [view bringSubviewToFront:quick];

        if (pages)
            [view bringSubviewToFront:pages];

        [editor refresh];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;

    if (!RVIsControlCenterOverlayController(self))
        return;

    for (RVEditor *editor in gRVEditors.allObjects) {
        if (editor.host == (id)self)
            [editor invalidate];
    }
}

%end
