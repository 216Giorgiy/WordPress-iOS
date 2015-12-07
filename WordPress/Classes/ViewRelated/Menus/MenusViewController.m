#import "MenusViewController.h"
#import "Blog.h"
#import "MenusService.h"
#import "Menu.h"
#import "MenuLocation.h"
#import "MenuItem.h"
#import "WPStyleGuide.h"
#import "MenusHeaderView.h"
#import "MenuDetailsView.h"
#import "MenuItemsStackView.h"

typedef NS_ENUM(NSInteger) {
    MenusSectionSelection = 0,
    MenusSectionMenuItems
    
}MenusSection;

static NSString * const MenusSectionMenuItemsKey = @"menu_items";

@implementation NSDictionary (Menus)

- (NSMutableArray *)menuItems
{
    return self[MenusSectionMenuItemsKey];
}

@end

@interface MenusViewController () <UIScrollViewDelegate, MenusHeaderViewDelegate, MenuDetailsViewDelegate, MenuItemsStackViewDelegate>

@property (weak, nonatomic) IBOutlet UIScrollView *scrollView;
@property (weak, nonatomic) IBOutlet UIStackView *stackView;
@property (weak, nonatomic) IBOutlet MenusHeaderView *headerView;
@property (weak, nonatomic) IBOutlet MenuDetailsView *detailsView;
@property (weak, nonatomic) IBOutlet MenuItemsStackView *itemsView;

@property (nonatomic, strong) Blog *blog;
@property (nonatomic, strong) MenusService *menusService;
@property (nonatomic, strong) UIActivityIndicatorView *activity;

@end

@implementation MenusViewController

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (id)initWithBlog:(Blog *)blog
{
    NSParameterAssert([blog isKindOfClass:[Blog class]]);
    self = [super initWithNibName:NSStringFromClass([self class]) bundle:nil];
    if(self) {
        
        // using a new child context to keep local changes disacardable
        // using main queue as we still want processing done on the main thread
        NSManagedObjectContext *context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        context.parentContext = blog.managedObjectContext;
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy;
        
        // set local blog from local context
        self.blog = [context objectWithID:blog.objectID];

        MenusService *service = [[MenusService alloc] initWithManagedObjectContext:context];
        self.menusService = service;
    }
    
    return self;
}

- (void)loadView
{
    [super loadView];
    
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.view.backgroundColor = [WPStyleGuide greyLighten30];
    self.scrollView.backgroundColor = self.view.backgroundColor;
    self.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.scrollView.alpha = 0.0;
    
    // add a bit of padding to the scrollable content
    self.stackView.layoutMargins = UIEdgeInsetsMake(0, 0, 10, 0);
    self.stackView.layoutMarginsRelativeArrangement = YES;
    
    self.headerView.delegate = self;
    self.detailsView.delegate = self;
    self.itemsView.delegate = self;
    
    UIActivityIndicatorView *activity = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    activity.hidesWhenStopped = YES;
    [self.view addSubview:activity];
    self.activity = activity;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardWillChangeFrameNotification:) name:UIKeyboardWillChangeFrameNotification object:nil];
    
    self.automaticallyAdjustsScrollViewInsets = NO;
    self.navigationItem.title = NSLocalizedString(@"Menus", @"Title for screen that allows configuration of your site's menus");
    
    [self syncWithBlogMenus];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    
    [self updateScrollViewContentSize];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self.activity.center = self.scrollView.center;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator
{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

#pragma mark - Views setup

- (void)updateScrollViewContentSize
{
    self.scrollView.contentSize = CGSizeMake(self.stackView.frame.size.width, self.stackView.frame.size.height);
}

#pragma mark - local updates

- (void)syncWithBlogMenus
{
    [self.activity startAnimating];
    [self.menusService syncMenusForBlog:self.blog
                                success:^{
                                    [self.activity stopAnimating];
                                    [self didSyncBlog];
                                }
                                failure:^(NSError *error) {
                                    DDLogDebug(@"MenusViewController could not sync menus for blog");
                                    [self.navigationController popViewControllerAnimated:YES];
                                }];
}

- (void)didSyncBlog
{
    [self.headerView updateWithMenusForBlog:self.blog];
    [self setViewsWithMenu:[self.blog.menus firstObject]];
    
    [UIView animateWithDuration:0.20 animations:^{
        
        self.scrollView.alpha = 1.0;
    }];
}

- (void)setViewsWithMenu:(Menu *)menu
{
    self.detailsView.menu = menu;
    self.itemsView.menu = menu;
}

#pragma mark - UIScrollView

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{

}

#pragma mark - MenusHeaderViewDelegate

- (void)headerViewSelectionChangedWithSelectedLocation:(MenuLocation *)location
{
    if(location.menu) {
        [self setViewsWithMenu:location.menu];
    }else {
        [self setViewsWithMenu:[self.blog.menus firstObject]];
    }
}

- (void)headerViewSelectionChangedWithSelectedMenu:(Menu *)menu
{
    [self setViewsWithMenu:menu];
}

#pragma mark - MenuDetailsViewDelegate

- (void)detailsViewUpdatedMenuName:(MenuDetailsView *)menuDetailView
{
    [self.headerView refreshMenuViewsUsingMenu:menuDetailView.menu];
}

#pragma mark - MenuItemsStackViewDelegate

- (void)itemsView:(MenuItemsStackView *)itemsView prefersScrollingEnabled:(BOOL)enabled
{
    self.scrollView.scrollEnabled = enabled;
}

- (void)itemsView:(MenuItemsStackView *)itemsView prefersAdjustingScrollingOffsetForAnimatingView:(UIView *)view
{
    // adjust the scrollView offset to ensure this view is easily viewable
    const CGFloat padding = 10.0;
    CGRect viewRectWithinScrollViewWindow = [self.scrollView.window convertRect:view.frame fromView:view.superview];
    CGRect visibleContentRect = [self.scrollView.window convertRect:self.scrollView.frame fromView:self.view];
    
    CGPoint offset = self.scrollView.contentOffset;
    
    visibleContentRect.origin.y += offset.y;
    viewRectWithinScrollViewWindow.origin.y += offset.y;
    
    BOOL updated = NO;
    
    if(viewRectWithinScrollViewWindow.origin.y < visibleContentRect.origin.y + padding) {
        
        offset.y -= viewRectWithinScrollViewWindow.size.height;
        updated = YES;
        
    }else if(viewRectWithinScrollViewWindow.origin.y + viewRectWithinScrollViewWindow.size.height > (visibleContentRect.origin.y + visibleContentRect.size.height) - padding) {
        offset.y += viewRectWithinScrollViewWindow.size.height;
        updated = YES;
    }
    
    if(updated) {
        [UIView animateWithDuration:0.25 animations:^{
            self.scrollView.contentOffset = offset;
        }];
    }
}

- (void)itemsViewAnimatingContentSizeChanges:(MenuItemsStackView *)itemsView focusedRect:(CGRect)focusedRect updatedFocusRect:(CGRect)updatedFocusRect
{
    CGPoint offset = self.scrollView.contentOffset;
    offset.y += updatedFocusRect.origin.y - focusedRect.origin.y;
    self.scrollView.contentOffset = offset;
}

#pragma mark - notifications

- (void)keyboardWillChangeFrameNotification:(NSNotification *)notification
{
    CGRect frame = [[notification.userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    frame = [self.view.window convertRect:frame toView:self.view];
    
    CGFloat insetPadding = 10.0;
    UIEdgeInsets inset = self.scrollView.contentInset;
    UIEdgeInsets scrollInset = self.scrollView.scrollIndicatorInsets;

    if(frame.origin.y > self.view.frame.size.height) {
        inset.bottom = 0.0;
        scrollInset.bottom = 0.0;
    }else {
        inset.bottom = self.view.frame.size.height - frame.origin.y;
        scrollInset.bottom = inset.bottom;
        inset.bottom += insetPadding;
    }
    self.scrollView.contentInset = inset;
    self.scrollView.scrollIndicatorInsets = scrollInset;
}

@end
