/*
 RevoCC 0.3.0
 Clean-room Control Center editor for rootless iOS 16.

 Features:
 - Plus button opens a real module editor.
 - Long-pressing Control Center also opens the editor.
 - Editor can reorder enabled modules by dragging.
 - Editor can remove enabled modules.
 - Editor can add available fixed/native modules.
 - Save writes the native CCSModuleSettingsProvider ordering.
 - Vertical page selector is aligned to the actual module collection height.
 - Page selector is interactive ONLY when Control Center is fully open (state 2).
 - Page switching uses UIScrollView contentOffset when available instead of
   applying a transform to the collection layer.
*/

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const RVPrefsPath =
    @"/var/mobile/Library/Preferences/com.samuel.revocc.plist";

static NSInteger const RVQuickAccessTag = 181000;
static NSInteger const RVAddButtonTag = 181001;
static NSInteger const RVPowerButtonTag = 181002;
static NSInteger const RVPageSelectorTag = 181030;
static NSInteger const RVEditorOverlayTag = 181100;

static BOOL gRVCCPresented = NO;
static NSUInteger gRVCCPresentationState = 0;
static NSUInteger gRVCurrentPage = 0;
static NSUInteger gRVPageCount = 1;
static NSHashTable *gRVEditors;

static BOOL RVEnabled(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:RVPrefsPath];
    return d[@"enabled"] ? [d[@"enabled"] boolValue] : YES;
}

static id RVSend0(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static void RVSend1(id object, SEL selector, id argument) {
    if (!object || ![object respondsToSelector:selector]) return;
    ((void (*)(id, SEL, id))objc_msgSend)(object, selector, argument);
}

#pragma mark - Native module settings

@interface RVSettings : NSObject
+ (id)provider;
+ (NSArray *)enabled;
+ (NSArray *)fixed;
+ (BOOL)save:(NSArray *)order;
@end

@implementation RVSettings

+ (id)provider {
    Class cls = NSClassFromString(@"CCSModuleSettingsProvider");
    SEL sel = NSSelectorFromString(@"sharedProvider");
    return cls && [cls respondsToSelector:sel] ? RVSend0(cls, sel) : nil;
}

+ (NSArray *)enabled {
    id provider = [self provider];
    id value = RVSend0(provider,
        NSSelectorFromString(@"orderedUserEnabledModuleIdentifiers"));
    return [value isKindOfClass:NSArray.class] ? value : @[];
}

+ (NSArray *)fixed {
    id provider = [self provider];
    id value = RVSend0(provider,
        NSSelectorFromString(@"orderedFixedModuleIdentifiers"));
    return [value isKindOfClass:NSArray.class] ? value : @[];
}

+ (BOOL)save:(NSArray *)order {
    id provider = [self provider];
    SEL sel = NSSelectorFromString(
        @"setAndSaveOrderedUserEnabledModuleIdentifiers:");
    if (!provider || ![provider respondsToSelector:sel]) return NO;

    NSMutableOrderedSet *unique = [NSMutableOrderedSet orderedSet];
    for (id item in order) {
        if (![item isKindOfClass:NSString.class] ||
            [(NSString *)item length] == 0) return NO;
        [unique addObject:item];
    }
    if (unique.count != order.count) return NO;

    RVSend1(provider, sel, unique.array);
    return YES;
}

@end

#pragma mark - Helpers

static BOOL RVIsCCOverlay(id controller) {
    if (!controller) return NO;
    NSString *name = NSStringFromClass([controller class]);
    return [name containsString:@"CCUIModularControlCenterOverlayViewController"];
}

static UIScrollView *RVFindModuleScrollView(UIView *root) {
    if (!root) return nil;

    NSMutableArray *queue = [NSMutableArray arrayWithObject:root];
    while (queue.count) {
        UIView *v = queue.firstObject;
        [queue removeObjectAtIndex:0];

        NSString *name = NSStringFromClass(v.class);
        if ([name containsString:@"CCUIModuleCollectionView"] &&
            [v isKindOfClass:UIScrollView.class])
            return (UIScrollView *)v;

        for (UIView *sub in v.subviews)
            [queue addObject:sub];
    }
    return nil;
}

static NSString *RVPrettyModuleName(NSString *identifier) {
    NSString *s = [identifier copy];
    NSArray *parts = [s componentsSeparatedByString:@"."];
    s = parts.lastObject ?: s;
    s = [s stringByReplacingOccurrencesOfString:@"Module" withString:@""];
    s = [s stringByReplacingOccurrencesOfString:@"Control" withString:@""];
    s = [s stringByReplacingOccurrencesOfString:@"CCUI" withString:@""];
    s = [s stringByReplacingOccurrencesOfString:@"-" withString:@" "];
    return s.length ? s : identifier;
}

#pragma mark - Editor

@interface RVModuleCell : UIControl
@property(nonatomic, copy) NSString *identifier;
@property(nonatomic, strong) UILabel *label;
@property(nonatomic, strong) UIButton *removeButton;
@end

@implementation RVModuleCell

- (instancetype)initWithIdentifier:(NSString *)identifier {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;

    _identifier = [identifier copy];
    self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    self.layer.cornerRadius = 14.0;
    self.layer.masksToBounds = YES;

    _label = [[UILabel alloc] initWithFrame:CGRectZero];
    _label.text = RVPrettyModuleName(identifier);
    _label.textColor = UIColor.whiteColor;
    _label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    _label.translatesAutoresizingMaskIntoConstraints = NO;

    UILabel *handle = [[UILabel alloc] initWithFrame:CGRectZero];
    handle.text = @"≡";
    handle.textColor = [UIColor colorWithWhite:1 alpha:0.65];
    handle.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    handle.translatesAutoresizingMaskIntoConstraints = NO;

    _removeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_removeButton setTitle:@"−" forState:UIControlStateNormal];
    _removeButton.titleLabel.font = [UIFont systemFontOfSize:24 weight:UIFontWeightBold];
    _removeButton.tintColor = UIColor.whiteColor;
    _removeButton.translatesAutoresizingMaskIntoConstraints = NO;

    [self addSubview:handle];
    [self addSubview:_label];
    [self addSubview:_removeButton];

    [NSLayoutConstraint activateConstraints:@[
        [handle.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:12],
        [handle.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [handle.widthAnchor constraintEqualToConstant:25],

        [_label.leadingAnchor constraintEqualToAnchor:handle.trailingAnchor constant:8],
        [_label.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_label.trailingAnchor constraintLessThanOrEqualToAnchor:_removeButton.leadingAnchor constant:-8],

        [_removeButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-10],
        [_removeButton.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [_removeButton.widthAnchor constraintEqualToConstant:32],
        [_removeButton.heightAnchor constraintEqualToConstant:32]
    ]];

    return self;
}

@end

@interface RVEditor : NSObject <UIGestureRecognizerDelegate>
@property(nonatomic, weak) id host;
@property(nonatomic, strong) UILongPressGestureRecognizer *editGesture;
@property(nonatomic, strong) UIView *quickHost;
@property(nonatomic, strong) UIView *pageHost;
@property(nonatomic, strong) NSMutableArray<UIButton *> *pageButtons;

@property(nonatomic, strong) UIView *editorOverlay;
@property(nonatomic, strong) UIView *editorPanel;
@property(nonatomic, strong) UIScrollView *editorScroll;
@property(nonatomic, strong) NSMutableArray<NSString *> *editOrder;
@property(nonatomic, strong) NSMutableArray<RVModuleCell *> *editCells;
@property(nonatomic, strong) UILabel *editorTitle;
@end

@implementation RVEditor

- (instancetype)initWithHost:(id)host {
    self = [super init];
    if (self) {
        _host = host;
        _pageButtons = [NSMutableArray array];
        _editCells = [NSMutableArray array];
    }
    return self;
}

- (UIView *)hostView {
    id v = RVSend0(self.host, @selector(view));
    return [v isKindOfClass:UIView.class] ? v : nil;
}

- (void)install {
    UIView *view = [self hostView];
    if (!view || !RVEnabled()) return;

    [self installQuickButtons];
    [self installPageSelector];

    self.editGesture = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(editHeld:)];
    self.editGesture.minimumPressDuration = 0.65;
    self.editGesture.cancelsTouchesInView = NO;
    self.editGesture.delegate = self;
    [view addGestureRecognizer:self.editGesture];

    [self refresh];
}

#pragma mark Quick buttons

- (UIButton *)roundButtonWithSymbol:(NSString *)symbol tag:(NSInteger)tag {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = tag;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.layer.cornerRadius = 20;
    button.layer.masksToBounds = YES;
    button.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.82];

    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:17
                                                          weight:UIImageSymbolWeightSemibold];
    [button setImage:[UIImage systemImageNamed:symbol withConfiguration:cfg]
            forState:UIControlStateNormal];
    button.tintColor = UIColor.whiteColor;
    return button;
}

- (void)installQuickButtons {
    UIView *view = [self hostView];
    if (!view || [view viewWithTag:RVQuickAccessTag]) return;

    UIView *host = [[UIView alloc] initWithFrame:CGRectZero];
    host.tag = RVQuickAccessTag;
    host.translatesAutoresizingMaskIntoConstraints = NO;
    host.backgroundColor = UIColor.clearColor;
    host.userInteractionEnabled = YES;
    host.layer.zPosition = 9000;
    [view addSubview:host];
    self.quickHost = host;

    UIButton *add = [self roundButtonWithSymbol:@"plus" tag:RVAddButtonTag];
    [add addTarget:self action:@selector(addPressed:)
  forControlEvents:UIControlEventTouchUpInside];

    UIButton *power = [self roundButtonWithSymbol:@"power" tag:RVPowerButtonTag];
    [power addTarget:self action:@selector(powerPressed:)
    forControlEvents:UIControlEventTouchUpInside];

    [host addSubview:add];
    [host addSubview:power];

    [NSLayoutConstraint activateConstraints:@[
        [host.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [host.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [host.topAnchor constraintEqualToAnchor:view.topAnchor],
        [host.heightAnchor constraintEqualToConstant:76],

        [add.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:22],
        [add.topAnchor constraintEqualToAnchor:host.topAnchor constant:18],
        [add.widthAnchor constraintEqualToConstant:40],
        [add.heightAnchor constraintEqualToConstant:40],

        [power.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-22],
        [power.topAnchor constraintEqualToAnchor:host.topAnchor constant:18],
        [power.widthAnchor constraintEqualToConstant:40],
        [power.heightAnchor constraintEqualToConstant:40]
    ]];
}

- (void)addPressed:(UIButton *)sender {
    if (gRVCCPresentationState != 2) return;
    [self beginEditing];
}

- (void)powerPressed:(UIButton *)sender {
    if (!gRVCCPresented) return;

    Class factory = NSClassFromString(@"SBUIPowerDownViewControllerFactory");
    NSArray *selectors = @[
        @"newPowerDownViewController",
        @"powerDownViewController"
    ];

    id controller = nil;
    for (NSString *name in selectors) {
        SEL sel = NSSelectorFromString(name);
        if (factory && [factory respondsToSelector:sel]) {
            controller = RVSend0(factory, sel);
            if (controller) break;
        }
    }

    if (!controller) {
        // Fallback: use the SpringBoard controller if the private factory
        // is not present on this iOS build.
        Class cls = NSClassFromString(@"SBUIPowerDownViewController");
        SEL initSel = NSSelectorFromString(@"init");
        if (cls && [cls instancesRespondToSelector:initSel])
            controller = RVSend0([cls alloc], initSel);
    }

    if (!controller) return;

    id presenter = self.host;
    if (![presenter respondsToSelector:
          @selector(presentViewController:animated:completion:)])
        return;

    if ([controller respondsToSelector:@selector(setModalPresentationStyle:)])
        [controller setModalPresentationStyle:UIModalPresentationFullScreen];

    [presenter presentViewController:controller animated:YES completion:nil];
}

- (void)editHeld:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan &&
        gRVCCPresentationState == 2)
        [self beginEditing];
}

#pragma mark Editor UI

- (void)beginEditing {
    if (gRVCCPresentationState != 2) return;

    UIView *root = [self hostView];
    if (!root) return;

    if ([root viewWithTag:RVEditorOverlayTag]) {
        [self closeEditor:nil];
        return;
    }

    self.editOrder = [[RVSettings enabled] mutableCopy];
    if (!self.editOrder) self.editOrder = [NSMutableArray array];

    UIView *overlay = [[UIView alloc] initWithFrame:root.bounds];
    overlay.tag = RVEditorOverlayTag;
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                UIViewAutoresizingFlexibleHeight;
    overlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.42];
    overlay.layer.zPosition = 10000;
    [root addSubview:overlay];
    self.editorOverlay = overlay;

    UIView *panel = [[UIView alloc] initWithFrame:CGRectZero];
    panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.96];
    panel.layer.cornerRadius = 24;
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    [overlay addSubview:panel];
    self.editorPanel = panel;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.text = @"Edit Control Center";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:title];
    self.editorTitle = title;

    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:@"Done" forState:UIControlStateNormal];
    done.tintColor = UIColor.whiteColor;
    done.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    done.translatesAutoresizingMaskIntoConstraints = NO;
    [done addTarget:self action:@selector(saveEditor:)
   forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:done];

    UIButton *add = [UIButton buttonWithType:UIButtonTypeSystem];
    [add setTitle:@"Add Control" forState:UIControlStateNormal];
    add.tintColor = UIColor.whiteColor;
    add.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
    add.layer.cornerRadius = 14;
    add.translatesAutoresizingMaskIntoConstraints = NO;
    [add addTarget:self action:@selector(addControlPressed:)
   forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:add];

    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectZero];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    [panel addSubview:scroll];
    self.editorScroll = scroll;

    [NSLayoutConstraint activateConstraints:@[
        [panel.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor constant:20],
        [panel.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor constant:-20],
        [panel.topAnchor constraintEqualToAnchor:overlay.safeAreaLayoutGuide.topAnchor constant:16],
        [panel.bottomAnchor constraintEqualToAnchor:overlay.safeAreaLayoutGuide.bottomAnchor constant:-16],

        [title.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:20],
        [title.topAnchor constraintEqualToAnchor:panel.topAnchor constant:18],

        [done.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-18],
        [done.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],

        [add.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:18],
        [add.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-18],
        [add.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:14],
        [add.heightAnchor constraintEqualToConstant:44],

        [scroll.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:14],
        [scroll.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-14],
        [scroll.topAnchor constraintEqualToAnchor:add.bottomAnchor constant:12],
        [scroll.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-12]
    ]];

    [self rebuildEditorCells];
}

- (void)rebuildEditorCells {
    for (UIView *v in self.editorScroll.subviews)
        [v removeFromSuperview];
    [self.editCells removeAllObjects];

    CGFloat y = 8;
    for (NSUInteger i = 0; i < self.editOrder.count; i++) {
        NSString *identifier = self.editOrder[i];

        RVModuleCell *cell = [[RVModuleCell alloc] initWithIdentifier:identifier];
        cell.frame = CGRectMake(0, y,
                                MAX(1, self.editorScroll.bounds.size.width - 8),
                                56);
        cell.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [cell.removeButton addTarget:self
                              action:@selector(removeCell:)
                    forControlEvents:UIControlEventTouchUpInside];

        UILongPressGestureRecognizer *drag =
            [[UILongPressGestureRecognizer alloc]
                initWithTarget:self action:@selector(dragCell:)];
        drag.minimumPressDuration = 0.15;
        [cell addGestureRecognizer:drag];

        [self.editorScroll addSubview:cell];
        [self.editCells addObject:cell];
        y += 64;
    }
    self.editorScroll.contentSize =
        CGSizeMake(self.editorScroll.bounds.size.width, y + 8);
}

- (void)removeCell:(UIButton *)button {
    RVModuleCell *cell = (RVModuleCell *)button.superview;
    NSUInteger idx = [self.editCells indexOfObject:cell];
    if (idx == NSNotFound || idx >= self.editOrder.count) return;

    [self.editOrder removeObjectAtIndex:idx];
    [self rebuildEditorCells];
}

- (void)dragCell:(UILongPressGestureRecognizer *)gesture {
    RVModuleCell *cell = (RVModuleCell *)gesture.view;
    NSUInteger from = [self.editCells indexOfObject:cell];
    if (from == NSNotFound) return;

    if (gesture.state == UIGestureRecognizerStateBegan) {
        cell.alpha = 0.65;
        [cell.superview bringSubviewToFront:cell];
        return;
    }

    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint p = [gesture locationInView:self.editorScroll];
        CGFloat center = p.y;

        NSUInteger to = MIN(self.editOrder.count - 1,
                            MAX(0, (NSUInteger)MAX(0, floor((center - 8) / 64.0))));

        if (to != from) {
            NSString *moved = self.editOrder[from];
            [self.editOrder removeObjectAtIndex:from];
            [self.editOrder insertObject:moved atIndex:to];
            [self rebuildEditorCells];
        }
        return;
    }

    if (gesture.state == UIGestureRecognizerStateEnded ||
        gesture.state == UIGestureRecognizerStateCancelled) {
        cell.alpha = 1.0;
    }
}

- (void)addControlPressed:(UIButton *)button {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Add Control"
                                             message:@"Select a native Control Center module."
                                      preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray *enabled = [RVSettings enabled];
    NSArray *fixed = [RVSettings fixed];

    NSMutableOrderedSet *available = [NSMutableOrderedSet orderedSet];
    for (NSString *item in fixed) {
        if (![enabled containsObject:item])
            [available addObject:item];
    }

    if (available.count == 0) {
        [alert addAction:[UIAlertAction actionWithTitle:@"No controls available"
                                                   style:UIAlertActionStyleDefault
                                                 handler:nil]];
    } else {
        for (NSString *identifier in available.array) {
            [alert addAction:[UIAlertAction
                actionWithTitle:RVPrettyModuleName(identifier)
                          style:UIAlertActionStyleDefault
                        handler:^(__unused UIAlertAction *action) {
                if (![self.editOrder containsObject:identifier]) {
                    [self.editOrder addObject:identifier];
                    [self rebuildEditorCells];
                }
            }]];
        }
    }

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                               style:UIAlertActionStyleCancel
                                             handler:nil]];

    [self.host presentViewController:alert animated:YES completion:nil];
}

- (void)saveEditor:(UIButton *)button {
    if ([RVSettings save:self.editOrder]) {
        [self closeEditor:nil];
        [self reloadNativeModules];
    } else {
        UIAlertController *alert =
            [UIAlertController alertControllerWithTitle:@"RevoCC"
                                                 message:@"Could not save the Control Center module order."
                                          preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                   style:UIAlertActionStyleDefault
                                                 handler:nil]];
        [self.host presentViewController:alert animated:YES completion:nil];
    }
}

- (void)closeEditor:(UIButton *)button {
    [self.editorOverlay removeFromSuperview];
    self.editorOverlay = nil;
    self.editorPanel = nil;
    self.editorScroll = nil;
    self.editCells = nil;
    self.editOrder = nil;
}

- (void)reloadNativeModules {
    UIScrollView *scroll = RVFindModuleScrollView([self hostView]);
    if ([scroll respondsToSelector:@selector(reloadData)])
        [(id)scroll reloadData];

    // Give ControlCenter a moment to consume the provider update.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self rebuildPageButtons];
        [self refresh];
    });
}

#pragma mark Page selector

- (void)installPageSelector {
    UIView *view = [self hostView];
    if (!view || [view viewWithTag:RVPageSelectorTag]) return;

    UIView *host = [[UIView alloc] initWithFrame:CGRectZero];
    host.tag = RVPageSelectorTag;
    host.translatesAutoresizingMaskIntoConstraints = NO;
    host.backgroundColor = UIColor.clearColor;
    host.layer.zPosition = 8999;
    [view addSubview:host];
    self.pageHost = host;

    [NSLayoutConstraint activateConstraints:@[
        [host.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-8],
        [host.topAnchor constraintEqualToAnchor:view.topAnchor],
        [host.bottomAnchor constraintEqualToAnchor:view.bottomAnchor],
        [host.widthAnchor constraintEqualToConstant:38]
    ]];

    [self rebuildPageButtons];
}

- (NSUInteger)calculatePageCount {
    UIScrollView *scroll = RVFindModuleScrollView([self hostView]);
    if (!scroll) return 1;

    CGFloat pageHeight = CGRectGetHeight(scroll.bounds);
    CGFloat contentHeight = scroll.contentSize.height;

    if (pageHeight < 1 || contentHeight < 1)
        return 1;

    return MAX(1, MIN(12,
        (NSUInteger)ceil(contentHeight / pageHeight)));
}

- (void)rebuildPageButtons {
    if (!self.pageHost) return;

    for (UIButton *b in self.pageButtons)
        [b removeFromSuperview];
    [self.pageButtons removeAllObjects];

    gRVPageCount = [self calculatePageCount];
    if (gRVCurrentPage >= gRVPageCount)
        gRVCurrentPage = gRVPageCount - 1;

    if (gRVPageCount <= 1) {
        self.pageHost.hidden = YES;
        return;
    }

    self.pageHost.hidden = NO;

    CGFloat diameter = 26.0;
    CGFloat gap = 6.0;
    CGFloat total = gRVPageCount * diameter +
                    (gRVPageCount - 1) * gap;
    CGFloat top = MAX(90.0,
        (CGRectGetHeight(self.pageHost.bounds) - total) * 0.5);

    for (NSUInteger page = 0; page < gRVPageCount; page++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.frame = CGRectMake(6,
                                  top + page * (diameter + gap),
                                  diameter,
                                  diameter);

        UIImageSymbolConfiguration *cfg =
            [UIImageSymbolConfiguration configurationWithPointSize:
                page == gRVCurrentPage ? 12 : 8
                                                              weight:
                UIImageSymbolWeightSemibold];

        NSString *symbol = page == gRVCurrentPage ? @"circle.fill" : @"circle";
        [button setImage:[UIImage systemImageNamed:symbol
                              withConfiguration:cfg]
                forState:UIControlStateNormal];

        button.tintColor = page == gRVCurrentPage ?
            UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:0.58];
        button.tag = 3000 + page;
        button.accessibilityLabel =
            [NSString stringWithFormat:@"Control Center page %lu",
             (unsigned long)(page + 1)];

        [button addTarget:self action:@selector(pageTapped:)
         forControlEvents:UIControlEventTouchUpInside];

        [self.pageHost addSubview:button];
        [self.pageButtons addObject:button];
    }

    BOOL enabled = gRVCCPresentationState == 2;
    self.pageHost.userInteractionEnabled = enabled;
    for (UIButton *b in self.pageButtons)
        b.userInteractionEnabled = enabled;
}

- (void)pageTapped:(UIButton *)button {
    if (gRVCCPresentationState != 2) return;

    NSUInteger target = (NSUInteger)(button.tag - 3000);
    if (target >= gRVPageCount) return;

    UIScrollView *scroll = RVFindModuleScrollView([self hostView]);
    if (!scroll) return;

    CGFloat pageHeight = CGRectGetHeight(scroll.bounds);
    if (pageHeight < 1) return;

    gRVCurrentPage = target;

    CGPoint offset = scroll.contentOffset;
    offset.y = MIN(target * pageHeight,
                   MAX(0, scroll.contentSize.height - scroll.bounds.size.height));

    [scroll setContentOffset:offset animated:YES];
    [self rebuildPageButtons];
}

- (void)refresh {
    if (!gRVCCPresented) {
        self.quickHost.hidden = YES;
        self.pageHost.hidden = YES;
        return;
    }

    self.quickHost.hidden = NO;

    UIScrollView *scroll = RVFindModuleScrollView([self hostView]);
    if (scroll) {
        CGFloat h = CGRectGetHeight(scroll.bounds);
        if (h > 1 && scroll.contentSize.height > 1) {
            gRVPageCount = MAX(1, MIN(12,
                (NSUInteger)ceil(scroll.contentSize.height / h)));

            CGFloat page = scroll.contentOffset.y / h;
            gRVCurrentPage = MIN(gRVPageCount - 1,
                                  (NSUInteger)llround(page));
        }
    }

    [self rebuildPageButtons];

    BOOL canSelect = gRVCCPresentationState == 2;
    self.pageHost.userInteractionEnabled = canSelect;
    for (UIButton *b in self.pageButtons)
        b.userInteractionEnabled = canSelect;
}

- (void)invalidate {
    UIView *view = [self hostView];
    if (view && self.editGesture)
        [view removeGestureRecognizer:self.editGesture];

    [self.quickHost removeFromSuperview];
    [self.pageHost removeFromSuperview];
    [self.editorOverlay removeFromSuperview];

    self.quickHost = nil;
    self.pageHost = nil;
    self.editGesture = nil;
    self.editorOverlay = nil;
}

@end

#pragma mark - Presentation state

%hook SBControlCenterController

- (void)controlCenterViewController:(id)controller
          didChangePresentationState:(NSUInteger)state {
    %orig;

    gRVCCPresentationState = state;
    gRVCCPresented = state != 0;

    for (RVEditor *editor in gRVEditors.allObjects)
        [editor refresh];
}

%end

#pragma mark - Overlay lifecycle

%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;

    if (!RVEnabled() || !RVIsCCOverlay(self))
        return;

    if (!gRVEditors)
        gRVEditors = [NSHashTable weakObjectsHashTable];

    RVEditor *existing = nil;
    for (RVEditor *editor in gRVEditors.allObjects) {
        if (editor.host == self) {
            existing = editor;
            break;
        }
    }

    RVEditor *editor = existing ?: [[RVEditor alloc] initWithHost:self];
    if (!existing) {
        [gRVEditors addObject:editor];
        [editor install];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (editor.host) [editor refresh];
    });
}

- (void)viewDidLayoutSubviews {
    %orig;

    if (!RVIsCCOverlay(self) || !gRVCCPresented)
        return;

    for (RVEditor *editor in gRVEditors.allObjects) {
        if (editor.host != self) continue;

        UIView *root = [editor hostView];
        UIView *quick = [root viewWithTag:RVQuickAccessTag];
        UIView *pages = [root viewWithTag:RVPageSelectorTag];

        if (quick) [root bringSubviewToFront:quick];
        if (pages) [root bringSubviewToFront:pages];

        [editor refresh];
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;

    if (!RVIsCCOverlay(self))
        return;

    for (RVEditor *editor in gRVEditors.allObjects)
        if (editor.host == self)
            [editor invalidate];
}

%end
