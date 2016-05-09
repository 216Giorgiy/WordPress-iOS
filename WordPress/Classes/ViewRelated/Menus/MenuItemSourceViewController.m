#import "MenuItemSourceViewController.h"
#import "MenuItemSourceHeaderView.h"
#import "MenuItemPagesViewController.h"
#import "MenuItemLinkViewController.h"
#import "MenuItemCategoriesViewController.h"
#import "MenuItemTagsViewController.h"
#import "MenuItemPostsViewController.h"
#import "Menu.h"

@interface MenuItemSourceViewController () <MenuItemSourceHeaderViewDelegate, MenuItemSourceResultsViewControllerDelegate>

@property (nonatomic, strong, readonly) UIStackView *stackView;
@property (nonatomic, strong, readonly) MenuItemSourceHeaderView *headerView;
@property (nonatomic, strong) MenuItemSourceResultsViewController *sourceViewController;
@property (nonatomic, strong, readonly) NSCache *sourceViewControllerCache;
@property (nonatomic, assign) BOOL itemNameWasUpdatedExternally;

@end

@implementation MenuItemSourceViewController

- (void)awakeFromNib
{
    [super awakeFromNib];
    
    self.view.backgroundColor = [UIColor whiteColor];
    self.view.translatesAutoresizingMaskIntoConstraints = NO;
    _sourceViewControllerCache = [[NSCache alloc] init];
    
    [self setupStackView];
    [self setupHeaderView];
}

- (void)setupStackView
{
    UIStackView *stackView = [[UIStackView alloc] init];
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    stackView.distribution = UIStackViewDistributionFill;
    stackView.alignment = UIStackViewAlignmentFill;
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.spacing = 0;
    [self.view addSubview:stackView];
    
    [NSLayoutConstraint activateConstraints:@[
                                              [stackView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
                                              [stackView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
                                              [stackView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
                                              [stackView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
                                              [stackView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor]
                                              ]];
    
    _stackView = stackView;
}

- (void)setupHeaderView
{
    MenuItemSourceHeaderView *headerView = [[MenuItemSourceHeaderView alloc] init];
    headerView.delegate = self;
    
    NSAssert(_stackView != nil, @"stackView is nil");
    [_stackView addArrangedSubview:headerView];
    
    NSLayoutConstraint *height = [headerView.heightAnchor constraintEqualToConstant:60.0];
    height.priority = 999;
    height.active = YES;
    
    [headerView setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisVertical];
    [headerView setContentHuggingPriority:UILayoutPriorityDefaultHigh forAxis:UILayoutConstraintAxisVertical];
    
    _headerView = headerView;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];
    
    if (IS_IPAD || self.view.frame.size.width > self.view.frame.size.height) {
        [self setHeaderViewHidden:YES];
    } else  {
        [self setHeaderViewHidden:NO];
    }
}

- (void)setHeaderViewHidden:(BOOL)hidden
{
    if (self.headerView.hidden != hidden) {
        self.headerView.hidden = hidden;
        self.headerView.alpha = hidden ? 0.0 : 1.0;
    }
}

- (void)setItem:(MenuItem *)item
{
    if (_item != item) {
        _item = item;
        [self updateSourceSelectionForItemType:item.type];
    }
}

- (void)updateSourceSelectionForItemType:(NSString *)itemType
{
    self.headerView.titleLabel.text = [MenuItem labelForType:itemType blog:[self blog]];
    [self showSourceViewForItemType:itemType];
}

- (void)refreshForUpdatedItemName
{
    self.itemNameWasUpdatedExternally = YES;
}

- (void)showSourceViewForItemType:(NSString *)itemType
{
    MenuItemSourceResultsViewController *sourceViewController = [self.sourceViewControllerCache objectForKey:itemType];
    if (self.sourceViewController) {
        if (self.sourceViewController == sourceViewController) {
            // No update needed.
            return;
        }
        
        [self.sourceViewController willMoveToParentViewController:nil];
        [self.stackView removeArrangedSubview:self.sourceViewController.view];
        [self.sourceViewController.view removeFromSuperview];
        [self.sourceViewController removeFromParentViewController];
        self.sourceViewController = nil;
    }
    
    BOOL sourceViewSetupRequired = NO;
    if (!sourceViewController) {
        if ([itemType isEqualToString:MenuItemTypePage]) {
            sourceViewController = [[MenuItemPagesViewController alloc] init];
        } else if ([itemType isEqualToString:MenuItemTypeCustom]) {
            sourceViewController = [[MenuItemLinkViewController alloc] init];
        } else if ([itemType isEqualToString:MenuItemTypeCategory]) {
            sourceViewController = [[MenuItemCategoriesViewController alloc] init];
        } else if ([itemType isEqualToString:MenuItemTypeTag]) {
            sourceViewController = [[MenuItemTagsViewController alloc] init];
        } else {
            // Default to a post view that will load posts of postType == itemType.
            MenuItemPostsViewController *postView = [[MenuItemPostsViewController alloc] init];
            postView.postType = itemType;
            sourceViewController = postView;
        }
        sourceViewController.delegate = self;
        [sourceViewController.view setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisVertical];
        [self.sourceViewControllerCache setObject:sourceViewController forKey:itemType];
        sourceViewSetupRequired = YES;
    }
    
    [self addChildViewController:sourceViewController];
    [self.stackView addArrangedSubview:sourceViewController.view];
    [sourceViewController didMoveToParentViewController:self];
    self.sourceViewController = sourceViewController;
    
    if (sourceViewSetupRequired) {
        // Set the blog and item after it's been added as an arrangedSubview.
        sourceViewController.blog = self.blog;
        sourceViewController.item = self.item;
    } else {
        [sourceViewController refresh];
    }
}

#pragma mark - MenuItemSourceHeaderViewDelegate

- (void)sourceHeaderViewSelected:(MenuItemSourceHeaderView *)headerView
{
    [self.sourceViewController resignFirstResponder];
    [self.delegate sourceViewControllerTypeHeaderViewWasPressed:self];
}

#pragma mark - MenuItemSourceResultsViewControllerDelegate

- (BOOL)sourceResultsViewControllerCanOverrideItemName:(MenuItemSourceResultsViewController *)sourceResultsViewController
{
    // If the name is already empty or is using the default text, it can be overridden.
    if ([self.item nameIsEmptyOrDefault]) {
        if (self.itemNameWasUpdatedExternally) {
            /*
             If the item was previously updated externally, it's empty now.
             It can overridden again unless updated again externally. (see method: refreshForUpdatedItemName)
             */
            self.itemNameWasUpdatedExternally = NO;
        }
        return YES;
    }
    // If the name was not updated externally, such as the MenuItemEditingHeaderView, it can be overridden.
    if (!self.itemNameWasUpdatedExternally) {
        return YES;
    }
    return NO;
}

- (void)sourceResultsViewControllerDidUpdateItem:(MenuItemSourceResultsViewController *)sourceResultsViewController
{
    [self.delegate sourceResultsViewControllerDidUpdateItem:self];
}

- (void)sourceResultsViewControllerDidBeginEditingWithKeyBoard:(MenuItemSourceResultsViewController *)sourceResultsViewController
{
    [self.delegate sourceViewControllerDidBeginEditingWithKeyboard:self];
}

- (void)sourceResultsViewControllerDidEndEditingWithKeyboard:(MenuItemSourceResultsViewController *)sourceResultsViewController
{
    [self.delegate sourceViewControllerDidEndEditingWithKeyboard:self];
}

@end
