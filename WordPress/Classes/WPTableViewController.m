/*
 * WPTableViewController.m
 *
 * Copyright (c) 2013 WordPress. All rights reserved.
 *
 * Licensed under GNU General Public License 2.0.
 * Some rights reserved. See license.txt
 */

#import "WPTableViewController.h"
#import "WPTableViewControllerSubclass.h"
#import "EditSiteViewController.h"
#import "WPWebViewController.h"
#import "WPNoResultsView.h"
#import "SupportViewController.h"
#import "ContextManager.h"
#import "UIView+Subviews.h"

NSTimeInterval const WPTableViewControllerRefreshTimeout = 300; // 5 minutes
CGFloat const WPTableViewTopMargin = 40;
NSString * const WPBlogRestorationKey = @"WPBlogRestorationKey";

@interface WPTableViewController ()

@property (nonatomic, strong) NSFetchedResultsController *resultsController;
@property (nonatomic) BOOL swipeActionsEnabled;
@property (nonatomic) BOOL infiniteScrollEnabled;
@property (nonatomic, strong, readonly) UIView *swipeView;
@property (nonatomic, strong) UITableViewCell *swipeCell;
@property (nonatomic, strong) UIView *noResultsView;
@property (nonatomic, strong) UIActivityIndicatorView *noResultsActivityIndicator;

@end

@implementation WPTableViewController {
    EditSiteViewController *editSiteViewController;
    UIView *noResultsView;
    NSIndexPath *_indexPathSelectedBeforeUpdates;
    NSIndexPath *_indexPathSelectedAfterUpdates;
    UISwipeGestureRecognizer *_leftSwipeGestureRecognizer;
    UISwipeGestureRecognizer *_rightSwipeGestureRecognizer;
    UISwipeGestureRecognizerDirection _swipeDirection;
    UIActivityIndicatorView *_activityFooter;
    BOOL _animatingRemovalOfModerationSwipeView;
    BOOL didPromptForCredentials;
    BOOL _isSyncing;
    BOOL _isLoadingMore;
    BOOL didTriggerRefresh;
    CGPoint savedScrollOffset;
}

@synthesize blog = _blog;
@synthesize resultsController = _resultsController;
@synthesize swipeActionsEnabled = _swipeActionsEnabled;
@synthesize infiniteScrollEnabled = _infiniteScrollEnabled;
@synthesize swipeView = _swipeView;
@synthesize swipeCell = _swipeCell;
@synthesize noResultsView;

+ (UIViewController *)viewControllerWithRestorationIdentifierPath:(NSArray *)identifierComponents coder:(NSCoder *)coder {
    NSString *blogID = [coder decodeObjectForKey:WPBlogRestorationKey];
    if (!blogID)
        return nil;
    
    NSManagedObjectContext *context = [[ContextManager sharedInstance] mainContext];
    NSManagedObjectID *objectID = [context.persistentStoreCoordinator managedObjectIDForURIRepresentation:[NSURL URLWithString:blogID]];
    if (!objectID)
        return nil;
    
    NSError *error = nil;
    Blog *restoredBlog = (Blog *)[context existingObjectWithID:objectID error:&error];
    if (error || !restoredBlog) {
        return nil;
    }
    
    WPTableViewController *viewController = [[self alloc] initWithStyle:UITableViewStyleGrouped];
    viewController.blog = restoredBlog;
    
    return viewController;
}

- (id)initWithStyle:(UITableViewStyle)style {
    self = [super initWithStyle:style];
    
    if (self) {
        self.restorationIdentifier = NSStringFromClass([self class]);
        self.restorationClass = [self class];
    }
    
    return self;
}

- (void)dealloc {
    _resultsController.delegate = nil;
    editSiteViewController.delegate = nil;
}

- (void)encodeRestorableStateWithCoder:(NSCoder *)coder {
    [coder encodeObject:[[self.blog.objectID URIRepresentation] absoluteString] forKey:WPBlogRestorationKey];
    [super encodeRestorableStateWithCoder:coder];
}

- (void)viewDidLoad {
    [super viewDidLoad];

    UIRefreshControl *refreshControl = [[UIRefreshControl alloc] init];
    [refreshControl addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
    self.refreshControl = refreshControl;

    self.tableView.allowsSelectionDuringEditing = YES;
    [WPStyleGuide configureColorsForView:self.view andTableView:self.tableView];
    
    if (self.swipeActionsEnabled) {
        [self enableSwipeGestureRecognizer];
    }

    if (self.infiniteScrollEnabled) {
        [self enableInfiniteScrolling];
    }

    [self configureNoResultsView];
    
    // Remove one-pixel gap resulting from a top-aligned grouped table view
    if (IS_IPHONE) {
        UIEdgeInsets tableInset = [self.tableView contentInset];
        tableInset.top = -1;
        self.tableView.contentInset = tableInset;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    CGSize contentSize = self.tableView.contentSize;
    if(contentSize.height > savedScrollOffset.y) {
        [self.tableView scrollRectToVisible:CGRectMake(savedScrollOffset.x, savedScrollOffset.y, 0.0, 0.0) animated:NO];
    } else {
        [self.tableView scrollRectToVisible:CGRectMake(0.0, contentSize.height, 0.0, 0.0) animated:NO];
    }
    if ([self.tableView indexPathForSelectedRow]) {
        [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
    }
    [self configureNoResultsView];
}

- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
    WordPressAppDelegate *appDelegate = [WordPressAppDelegate sharedWordPressApplicationDelegate];
    if( appDelegate.connectionAvailable == NO ) return; //do not start auto-synch if connection is down

    // Don't try to refresh if we just canceled editing credentials
    if (didPromptForCredentials) {
        return;
    }
    NSDate *lastSynced = [self lastSyncDate];
    if (lastSynced == nil || ABS([lastSynced timeIntervalSinceNow]) > WPTableViewControllerRefreshTimeout) {
        // Update in the background
        [self syncItems];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if (IS_IPHONE) {
        savedScrollOffset = self.tableView.contentOffset;
    }
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [self removeSwipeView:NO];
    [super setEditing:editing animated:animated];
}

#pragma mark - No Results View

- (NSString *)noResultsTitleText
{
    NSString *ttl = NSLocalizedString(@"No %@ yet", @"A string format. The '%@' will be replaced by the relevant type of object, posts, pages or comments.");
	ttl = [NSString stringWithFormat:ttl, [self.title lowercaseString]];
    return ttl;
}

- (NSString *)noResultsMessageText
{
	return nil;
}

- (UIView *)noResultsAccessoryView
{
    return nil;
}

- (NSString *)noResultsButtonText
{
    return nil;
}

#pragma mark - Property accessors

- (void)setBlog:(Blog *)blog {
    if (_blog == blog) {
        return;
    }

    _blog = blog;

    self.resultsController = nil;
    [self.tableView reloadData];
    WordPressAppDelegate *appDelegate = [WordPressAppDelegate sharedWordPressApplicationDelegate];
    if (!(appDelegate.connectionAvailable == YES && [self.resultsController.fetchedObjects count] == 0 && ![self isSyncing])) {
        [self configureNoResultsView];
    }
}

- (void)setSwipeActionsEnabled:(BOOL)swipeActionsEnabled {
    if (swipeActionsEnabled == _swipeActionsEnabled) {
        return;
    }

    _swipeActionsEnabled = swipeActionsEnabled;
    if (self.isViewLoaded) {
        if (_swipeActionsEnabled) {
            [self enableSwipeGestureRecognizer];
        } else {
            [self disableSwipeGestureRecognizer];
        }
    }
}

- (BOOL)swipeActionsEnabled {
    return _swipeActionsEnabled && !self.editing;
}

- (UIView *)swipeView {
    if (_swipeView) {
        return _swipeView;
    }

    _swipeView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, kCellHeight)];
    _swipeView.backgroundColor = [UIColor colorWithPatternImage:[UIImage imageNamed:@"background.png"]];
    
    UIImage *shadow = [[UIImage imageNamed:@"inner-shadow.png"] stretchableImageWithLeftCapWidth:0 topCapHeight:0];
    UIImageView *shadowImageView = [[UIImageView alloc] initWithFrame:_swipeView.frame];
    shadowImageView.alpha = 0.5;
    shadowImageView.image = shadow;
    shadowImageView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    [_swipeView insertSubview:shadowImageView atIndex:0];  

    return _swipeView;
}

- (void)setInfiniteScrollEnabled:(BOOL)infiniteScrollEnabled {
    if (infiniteScrollEnabled == _infiniteScrollEnabled) {
        return;
    }

    _infiniteScrollEnabled = infiniteScrollEnabled;
    if (self.isViewLoaded) {
        if (_infiniteScrollEnabled) {
            [self enableInfiniteScrolling];
        } else {
            [self disableInfiniteScrolling];
        }
    }
}

- (BOOL)infiniteScrollEnabled {
    return _infiniteScrollEnabled;
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return [[self.resultsController sections] count];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    id <NSFetchedResultsSectionInfo> sectionInfo = [[self.resultsController sections] objectAtIndex:section];
    return [sectionInfo name];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    id <NSFetchedResultsSectionInfo> sectionInfo = nil;
    sectionInfo = [[self.resultsController sections] objectAtIndex:section];
    return [sectionInfo numberOfObjects];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [self newCell];

    if (IS_IPAD || self.tableView.isEditing) {
		cell.accessoryType = UITableViewCellAccessoryNone;
	} else {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    
    [self configureCell:cell atIndexPath:indexPath];

    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
	if (IS_IPAD) {
		cell.accessoryType = UITableViewCellAccessoryNone;
	}

    // Are we approaching the end of the table?
    if ((indexPath.section + 1 == [self numberOfSectionsInTableView:tableView]) && (indexPath.row + 4 >= [self tableView:tableView numberOfRowsInSection:indexPath.section]) && [self tableView:tableView numberOfRowsInSection:indexPath.section] > 10) {
        // Only 3 rows till the end of table
        
        if ([self hasMoreContent] && !_isLoadingMore) {
            if (![self isSyncing] || self.incrementalLoadingSupported) {
                [_activityFooter startAnimating];
                _isLoadingMore = YES;
                [self loadMoreWithSuccess:^{
                    _isLoadingMore = NO;
                    [_activityFooter stopAnimating];
                } failure:^(NSError *error) {
                    _isLoadingMore = NO;
                    [_activityFooter stopAnimating];
                }];
            }
        }
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return kCellHeight;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    id <NSFetchedResultsSectionInfo> sectionInfo = nil;
    sectionInfo = [[self.resultsController sections] objectAtIndex:section];

    // Don't show section headers if there are no named sections
    NSString *sectionTitle = [self tableView:tableView titleForHeaderInSection:section];
    if ([[self.resultsController sections] count] <= 1 && [sectionTitle length] == 0) {
        return IS_IPHONE ? 1 : WPTableViewTopMargin;
    }

    return kSectionHeaderHight;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

- (NSIndexPath *)tableView:(UITableView *)theTableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!self.editing) {
        [self removeSwipeView:YES];
    }
    return indexPath;
}

#pragma mark - Fetched results controller

- (UITableViewRowAnimation)tableViewRowAnimation {
	return UITableViewRowAnimationFade;
}

- (NSString *)resultsControllerCacheName {
    return nil;
}

- (NSFetchedResultsController *)resultsController {
    if (_resultsController != nil) {
        return _resultsController;
    }

    NSManagedObjectContext *moc = [self managedObjectContext];
    _resultsController = [[NSFetchedResultsController alloc] initWithFetchRequest:[self fetchRequest]
                                                             managedObjectContext:moc
                                                               sectionNameKeyPath:[self sectionNameKeyPath]
                                                                        cacheName:[self resultsControllerCacheName]];
    _resultsController.delegate = self;
        
    NSError *error = nil;
    if (![_resultsController performFetch:&error]) {
        DDLogError(@"%@ couldn't fetch %@: %@", self, [self entityName], [error localizedDescription]);
        _resultsController = nil;
    }
    
    return _resultsController;
}

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller {
    _indexPathSelectedBeforeUpdates = [self.tableView indexPathForSelectedRow];
    [self.tableView beginUpdates];
}

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller {
    [self.tableView endUpdates];
    if (_indexPathSelectedAfterUpdates) {
        [self.tableView selectRowAtIndexPath:_indexPathSelectedAfterUpdates animated:NO scrollPosition:UITableViewScrollPositionNone];

        _indexPathSelectedBeforeUpdates = nil;
        _indexPathSelectedAfterUpdates = nil;
    }
    
    [self configureNoResultsView];
}

- (void)controller:(NSFetchedResultsController *)controller
   didChangeObject:(id)anObject
       atIndexPath:(NSIndexPath *)indexPath
     forChangeType:(NSFetchedResultsChangeType)type
      newIndexPath:(NSIndexPath *)newIndexPath {

    if (NSFetchedResultsChangeUpdate == type && newIndexPath && ![newIndexPath isEqual:indexPath]) {
        // Seriously, Apple?
        // http://developer.apple.com/library/ios/#releasenotes/iPhone/NSFetchedResultsChangeMoveReportedAsNSFetchedResultsChangeUpdate/_index.html
        type = NSFetchedResultsChangeMove;
    }
    if (newIndexPath == nil) {
        // It seems in some cases newIndexPath can be nil for updates
        newIndexPath = indexPath;
    }

    switch(type) {            
        case NSFetchedResultsChangeInsert:
            [self.tableView insertRowsAtIndexPaths:[NSArray arrayWithObject:newIndexPath] withRowAnimation:[self tableViewRowAnimation]];
            break;
            
        case NSFetchedResultsChangeDelete:
            [self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] withRowAnimation:[self tableViewRowAnimation]];
            if ([_indexPathSelectedBeforeUpdates isEqual:indexPath]) {
                [self.navigationController popToViewController:self animated:YES];
            }
            break;
            
        case NSFetchedResultsChangeUpdate:
            [self configureCell:[self.tableView cellForRowAtIndexPath:indexPath] atIndexPath:newIndexPath];
            break;
            
        case NSFetchedResultsChangeMove:
            [self.tableView deleteRowsAtIndexPaths:[NSArray
                                                       arrayWithObject:indexPath] withRowAnimation:[self tableViewRowAnimation]];
            [self.tableView insertRowsAtIndexPaths:[NSArray
                                                       arrayWithObject:newIndexPath] withRowAnimation:[self tableViewRowAnimation]];
            if ([_indexPathSelectedBeforeUpdates isEqual:indexPath] && _indexPathSelectedAfterUpdates == nil) {
                _indexPathSelectedAfterUpdates = newIndexPath;
            }
            break;
    }    
}

- (void)controller:(NSFetchedResultsController *)controller didChangeSection:(id )sectionInfo atIndex:(NSUInteger)sectionIndex forChangeType:(NSFetchedResultsChangeType)type {
    switch(type) {
        case NSFetchedResultsChangeInsert:
            [self.tableView insertSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:[self tableViewRowAnimation]];
            break;
            
        case NSFetchedResultsChangeDelete:
            [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:sectionIndex] withRowAnimation:[self tableViewRowAnimation]];
            break;
    }
}

#pragma mark - UIRefreshControl Methods

- (void)refresh {
    
    if (![self userCanRefresh]) {
        [self.refreshControl endRefreshing];
        return;
    }
    
    didTriggerRefresh = YES;
	[self syncItemsViaUserInteraction];
    [noResultsView removeFromSuperview];
}

- (BOOL)userCanRefresh {
    return YES;
}

#pragma mark - UIScrollViewDelegate Methods

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    _isScrolling = YES;
    if (self.swipeActionsEnabled) {
        [self removeSwipeView:YES];
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    _isScrolling = NO;
}


#pragma mark - UIAlertViewDelegate

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex { 
	switch(buttonIndex) {
		case 0: {
            SupportViewController *supportViewController = [[SupportViewController alloc] init];

            // Probably should be modal
            UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:supportViewController];
            navController.navigationBar.translucent = NO;
            if (IS_IPAD) {
                navController.modalPresentationStyle = UIModalPresentationFormSheet;
                navController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
            }
            [self.navigationController presentViewController:navController animated:YES completion:nil];

			break;
		}
		case 1:
            if (alertView.tag == 30){
                NSString *path = nil;
                NSError *error = NULL;
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"http\\S+writing.php" options:NSRegularExpressionCaseInsensitive error:&error];
                NSString *msg = [alertView message];
                NSRange rng = [regex rangeOfFirstMatchInString:msg options:0 range:NSMakeRange(0, [msg length])];
                
                if (rng.location == NSNotFound) {
                    path = self.blog.url;
                    if (![path hasPrefix:@"http"]) {
                        path = [NSString stringWithFormat:@"http://%@", path];
                    } else if ([self.blog isWPcom] && [path rangeOfString:@"wordpress.com"].location == NSNotFound) {
                        path = [self.blog.xmlrpc stringByReplacingOccurrencesOfString:@"xmlrpc.php" withString:@""];
                    }
                    path = [path stringByReplacingOccurrencesOfString:@"xmlrpc.php" withString:@""];
                    path = [path stringByAppendingFormat:@"/wp-admin/options-writing.php"];
                    
                } else {
                    path = [msg substringWithRange:rng];
                }
                
                WPWebViewController *webViewController = [[WPWebViewController alloc] init];
                webViewController.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Cancel", nil) style:UIBarButtonItemStylePlain target:self action:@selector(dismissModal:)];
                [webViewController setUrl:[NSURL URLWithString:path]];
                [webViewController setUsername:self.blog.username];
                [webViewController setPassword:self.blog.password];
                [webViewController setWpLoginURL:[NSURL URLWithString:self.blog.loginUrl]];
                webViewController.shouldScrollToBottom = YES;
                // Probably should be modal.
                UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:webViewController];
                navController.navigationBar.translucent = NO;
                if (IS_IPAD) {
                    navController.modalPresentationStyle = UIModalPresentationFormSheet;
                    navController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
                }
                [self.navigationController presentViewController:navController animated:YES completion:nil];
            }
			break;
		default:
			break;
	}
}

#pragma mark - SettingsViewControllerDelegate

- (void)controllerDidDismiss:(UIViewController *)controller cancelled:(BOOL)cancelled {
    if (editSiteViewController == controller) {
        didPromptForCredentials = cancelled;
        editSiteViewController = nil;
    }
}

#pragma mark - Private Methods

- (void)configureNoResultsView {
    if (![self isViewLoaded]) {
        return;
    }
    
    [self.noResultsView removeFromSuperview];
    [self.noResultsActivityIndicator stopAnimating];
    [self.noResultsActivityIndicator removeFromSuperview];
    
    if (self.resultsController && [[_resultsController fetchedObjects] count] == 0) {
        if (self.isSyncing) {
            // Show activity indicator view when syncing is occuring
            // and the fetched results controller has no objects
            
            if (self.noResultsActivityIndicator == nil) {
                self.noResultsActivityIndicator = [self createNoResultsActivityIndicator];
            }
            
            [self.noResultsActivityIndicator startAnimating];
            [self.tableView addSubview:self.noResultsActivityIndicator];
        } else {
            // Show no results view if the fetched results controller
            // has no objects and syncing is not happening.
            
            if (self.noResultsView == nil) {
                self.noResultsView = [self createNoResultsView];
            }
            [self.tableView addSubviewWithFadeAnimation:self.noResultsView];
        }
    }
}

- (UIView *)createNoResultsView {
	
    WPNoResultsView *view = [WPNoResultsView noResultsViewWithTitle:[self noResultsTitleText] message:[self noResultsMessageText] accessoryView:[self noResultsAccessoryView] buttonTitle:[self noResultsButtonText]];
    view.delegate = self;
    
	return view;
}

- (UIActivityIndicatorView *)createNoResultsActivityIndicator {
    
    UIActivityIndicatorView *activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    activityIndicator.hidesWhenStopped = YES;
    activityIndicator.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    activityIndicator.center = [self.tableView convertPoint:self.tableView.center fromView:self.tableView.superview];
    
	return activityIndicator;
}

- (void)hideRefreshHeader {
    [self.refreshControl endRefreshing];
    didTriggerRefresh = NO;
}

- (void)dismissModal:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)syncItems {
    [self syncItemsViaUserInteraction:NO];
}

- (void)syncItemsViaUserInteraction {
    [self syncItemsViaUserInteraction:YES];
}

- (void)syncItemsViaUserInteraction:(BOOL)userInteraction {
    if ([self isSyncing]) {
        return;
    }

    _isSyncing = YES;
    [self syncItemsWithSuccess:^{
        [self hideRefreshHeader];
        _isSyncing = NO;
        [self configureNoResultsView];
    } failure:^(NSError *error) {
        [self hideRefreshHeader];
        _isSyncing = NO;
        [self configureNoResultsView];
        if (self.blog) {
            if ([error.domain isEqualToString:@"XMLRPC"]) {
                if (error.code == 405) {
                    // Prompt to enable XML-RPC using the default message provided from the WordPress site.
                    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Couldn't sync", @"")
                                                                        message:[error localizedDescription]
                                                                       delegate:self
                                                              cancelButtonTitle:NSLocalizedString(@"Need Help?", @"")
                                                              otherButtonTitles:NSLocalizedString(@"Enable Now", @""), nil];

                    alertView.tag = 30;
                    [alertView show];

                } else if (error.code == 403 && editSiteViewController == nil) {
                    [self promptForPassword];
                } else if (error.code == 425 && editSiteViewController == nil) {
                    [self promptForPasswordWithMessage:[error localizedDescription]];
                } else if (userInteraction) {
                    [WPError showAlertWithError:error title:NSLocalizedString(@"Couldn't sync", @"")];
                }
            } else {
                [WPError showAlertWithError:error];
            }
        } else {
          // For non-blog tables (notifications), just show the error for now
          [WPError showAlertWithError:error];
        }
    }];
}

- (void)promptForPassword {
    [self promptForPasswordWithMessage:nil];
}

- (void)promptForPasswordWithMessage:(NSString *)message {
    if (message == nil) {
        message = NSLocalizedString(@"The username or password stored in the app may be out of date. Please re-enter your password in the settings and try again.", @"");
    }
	UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Couldn't Connect", @"")
														message:message
													   delegate:nil
											  cancelButtonTitle:nil
											  otherButtonTitles:NSLocalizedString(@"OK", @""), nil];
	[alertView show];
	
	// bad login/pass combination
	editSiteViewController = [[EditSiteViewController alloc] initWithBlog:self.blog];
	editSiteViewController.isCancellable = YES;
	editSiteViewController.delegate = self;
	UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:editSiteViewController];
    navController.navigationBar.translucent = NO;
	
	if(IS_IPAD) {
		navController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
		navController.modalPresentationStyle = UIModalPresentationFormSheet;
	}
	
    [self.navigationController presentViewController:navController animated:YES completion:nil];
}

#pragma mark - Swipe gestures

- (void)enableSwipeGestureRecognizer {
    [self disableSwipeGestureRecognizer]; // Disable any existing gesturerecognizers before initing new ones to avoid leaks.
    
    _leftSwipeGestureRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeLeft:)];
    _leftSwipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionLeft;
    [self.tableView addGestureRecognizer:_leftSwipeGestureRecognizer];

    _rightSwipeGestureRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(swipeRight:)];
    _rightSwipeGestureRecognizer.direction = UISwipeGestureRecognizerDirectionRight;
    [self.tableView addGestureRecognizer:_rightSwipeGestureRecognizer];
}

- (void)disableSwipeGestureRecognizer {
    if (_leftSwipeGestureRecognizer) {
        [self.tableView removeGestureRecognizer:_leftSwipeGestureRecognizer];
        _leftSwipeGestureRecognizer = nil;
    }

    if (_rightSwipeGestureRecognizer) {
        [self.tableView removeGestureRecognizer:_rightSwipeGestureRecognizer];
        _rightSwipeGestureRecognizer = nil;
    }
}

- (void)removeSwipeView:(BOOL)animated {
    if (!self.swipeActionsEnabled || !_swipeCell || (self.swipeCell.frame.origin.x == 0 && self.swipeView.superview == nil)) return;
    
    if (animated)
    {
        _animatingRemovalOfModerationSwipeView = YES;
        [UIView animateWithDuration:0.2
                         animations:^{
                             if (_swipeDirection == UISwipeGestureRecognizerDirectionRight)
                             {
                                 self.swipeView.frame = CGRectMake(-self.swipeView.frame.size.width + 5.0,self.swipeView.frame.origin.y, self.swipeView.frame.size.width, self.swipeView.frame.size.height);
                                 self.swipeCell.frame = CGRectMake(5.0, self.swipeCell.frame.origin.y, self.swipeCell.frame.size.width, self.swipeCell.frame.size.height);
                             }
                             else
                             {
                                 self.swipeView.frame = CGRectMake(self.swipeView.frame.size.width - 5.0,self.swipeView.frame.origin.y,self.swipeView.frame.size.width, self.swipeView.frame.size.height);
                                 self.swipeCell.frame = CGRectMake(-5.0, self.swipeCell.frame.origin.y, self.swipeCell.frame.size.width, self.swipeCell.frame.size.height);
                             }
                         }
                         completion:^(BOOL finished) {
                             [UIView animateWithDuration:0.1
                                              animations:^{
                                                  if (_swipeDirection == UISwipeGestureRecognizerDirectionRight)
                                                  {
                                                      self.swipeView.frame = CGRectMake(-self.swipeView.frame.size.width + 10.0,self.swipeView.frame.origin.y,self.swipeView.frame.size.width, self.swipeView.frame.size.height);
                                                      self.swipeCell.frame = CGRectMake(10.0, self.swipeCell.frame.origin.y, self.swipeCell.frame.size.width, self.swipeCell.frame.size.height);
                                                  }
                                                  else
                                                  {
                                                      self.swipeView.frame = CGRectMake(self.swipeView.frame.size.width - 10.0,self.swipeView.frame.origin.y,self.swipeView.frame.size.width, self.swipeView.frame.size.height);
                                                      self.swipeCell.frame = CGRectMake(-10.0, self.swipeCell.frame.origin.y, self.swipeCell.frame.size.width, self.swipeCell.frame.size.height);
                                                  }
                                              } completion:^(BOOL finished) {
                                                  [UIView animateWithDuration:0.1
                                                                   animations:^{
                                                                       if (_swipeDirection == UISwipeGestureRecognizerDirectionRight)
                                                                       {
                                                                           self.swipeView.frame = CGRectMake(-self.swipeView.frame.size.width ,self.swipeView.frame.origin.y,self.swipeView.frame.size.width, self.swipeView.frame.size.height);
                                                                           self.swipeCell.frame = CGRectMake(0, self.swipeCell.frame.origin.y, self.swipeCell.frame.size.width, self.swipeCell.frame.size.height);
                                                                       }
                                                                       else
                                                                       {
                                                                           self.swipeView.frame = CGRectMake(self.swipeView.frame.size.width ,self.swipeView.frame.origin.y,self.swipeView.frame.size.width, self.swipeView.frame.size.height);
                                                                           self.swipeCell.frame = CGRectMake(0, self.swipeCell.frame.origin.y, self.swipeCell.frame.size.width, self.swipeCell.frame.size.height);
                                                                       }
                                                                   }
                                                                   completion:^(BOOL finished) {
                                                                       _animatingRemovalOfModerationSwipeView = NO;
                                                                       self.swipeCell = nil;
                                                                       [_swipeView removeFromSuperview];
                                                                        _swipeView = nil;
                                                                   }];
                                              }];
                         }];
    }
    else
    {
        [self.swipeView removeFromSuperview];
         _swipeView = nil;
        self.swipeCell.frame = CGRectMake(0,self.swipeCell.frame.origin.y,self.swipeCell.frame.size.width, self.swipeCell.frame.size.height);
        self.swipeCell = nil;
    }
}

- (void)swipe:(UISwipeGestureRecognizer *)recognizer direction:(UISwipeGestureRecognizerDirection)direction
{
    if (!self.swipeActionsEnabled) {
        return;
    }
    if (recognizer && recognizer.state == UIGestureRecognizerStateEnded)
    {
        if (_animatingRemovalOfModerationSwipeView) return;
        
        CGPoint location = [recognizer locationInView:self.tableView];
        NSIndexPath* indexPath = [self.tableView indexPathForRowAtPoint:location];
        UITableViewCell* cell = [self.tableView cellForRowAtIndexPath:indexPath];
        
        if (cell.frame.origin.x != 0)
        {
            [self removeSwipeView:YES];
            return;
        }
        [self removeSwipeView:NO];
        
        if (cell != self.swipeCell)
        {
            [self configureSwipeView:self.swipeView forIndexPath:indexPath];
            
            [self.tableView addSubview:self.swipeView];
            self.swipeCell = cell;
            CGRect cellFrame = cell.frame;
            _swipeDirection = direction;
            self.swipeView.frame = CGRectMake(direction == UISwipeGestureRecognizerDirectionRight ? -cellFrame.size.width : cellFrame.size.width, cellFrame.origin.y, cellFrame.size.width, cellFrame.size.height);
            
            [UIView animateWithDuration:0.2 animations:^{
                self.swipeView.frame = CGRectMake(0, cellFrame.origin.y, cellFrame.size.width, cellFrame.size.height);
                cell.frame = CGRectMake(direction == UISwipeGestureRecognizerDirectionRight ? cellFrame.size.width : -cellFrame.size.width, cellFrame.origin.y, cellFrame.size.width, cellFrame.size.height);
            }];
        }
    }
}

- (void)swipeLeft:(UISwipeGestureRecognizer *)recognizer
{
    [self swipe:recognizer direction:UISwipeGestureRecognizerDirectionLeft];
}

- (void)swipeRight:(UISwipeGestureRecognizer *)recognizer
{
    [self swipe:recognizer direction:UISwipeGestureRecognizerDirectionRight];
}

#pragma mark - Infinite scrolling

- (void)enableInfiniteScrolling {
    if (_activityFooter == nil) {
        CGRect rect = CGRectMake(145.0, 10.0, 30.0, 30.0);
        _activityFooter = [[UIActivityIndicatorView alloc] initWithFrame:rect];
        _activityFooter.activityIndicatorViewStyle = UIActivityIndicatorViewStyleGray;
        _activityFooter.hidesWhenStopped = YES;
        _activityFooter.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
        [_activityFooter stopAnimating];
    }
    UIView *footerView = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 320.0, 50.0)];
    footerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [footerView addSubview:_activityFooter];
    self.tableView.tableFooterView = footerView;
}

- (void)disableInfiniteScrolling {
    self.tableView.tableFooterView = nil;
    _activityFooter = nil;
}

#pragma mark - Subclass methods

- (BOOL)userCanCreateEntity {
	return NO;
}

- (NSManagedObjectContext *)managedObjectContext {
    return [[ContextManager sharedInstance] mainContext];
}

#define AssertNoBlogSubclassMethod() NSAssert(self.blog, @"You must override %@ in a subclass if there is no blog", NSStringFromSelector(_cmd))

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wreturn-type"

- (NSString *)entityName {
    AssertSubclassMethod();
}

- (NSDate *)lastSyncDate {
    AssertSubclassMethod();
}

- (NSFetchRequest *)fetchRequest {
    AssertNoBlogSubclassMethod();
}

#pragma clang diagnostic pop

- (NSString *)sectionNameKeyPath {
    return nil;
}

- (void)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    AssertSubclassMethod();
}

- (void)syncItemsWithSuccess:(void (^)())success failure:(void (^)(NSError *))failure {
    AssertSubclassMethod();
}

- (void)syncItemsViaUserInteractionWithSuccess:(void (^)())success failure:(void (^)(NSError *error))failure {
    // By default, sync items the same way. Subclasses can override if they need different behavior.
    [self syncItemsWithSuccess:success failure:failure];
}

- (BOOL)isSyncing {
    return _isSyncing;
}

- (UITableViewCell *)newCell {
    // To comply with apple ownership and naming conventions, returned cell should have a retain count > 0, so retain the dequeued cell.
    NSString *cellIdentifier = [NSString stringWithFormat:@"_WPTable_%@_Cell", [self entityName]];
    UITableViewCell *cell = [self.tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
    }
    return cell;
}

- (BOOL)hasMoreContent {
    return NO;
}

- (void)loadMoreWithSuccess:(void (^)())success failure:(void (^)(NSError *error))failure {
    AssertSubclassMethod();
}

- (void)resetResultsController {
    [NSFetchedResultsController deleteCacheWithName:[self resultsControllerCacheName]];
	_resultsController.delegate = nil;
	_resultsController = nil;
}

@end
