//
//  ReaderPostsViewController.m
//  WordPress
//
//  Created by Eric J on 3/21/13.
//  Copyright (c) 2013 WordPress. All rights reserved.
//

#import <DTCoreText/DTCoreText.h>
#import "DTCoreTextFontDescriptor.h"

#import "WPTableViewControllerSubclass.h"
#import "ReaderPostsViewController.h"
#import "ReaderPostTableViewCell.h"
#import "ReaderTopicsViewController.h"
#import "ReaderPostDetailViewController.h"
#import "ReaderPost.h"
#import "WordPressComApi.h"
#import "WordPressAppDelegate.h"
#import "NSString+XMLExtensions.h"
#import "ReaderReblogFormView.h"
#import "WPFriendFinderViewController.h"
#import "WPFriendFinderNudgeView.h"
#import "WPAccount.h"
#import "WPTableImageSource.h"
#import "WPInfoView.h"
#import "WPCookie.h"
#import "NSString+Helpers.h"
#import "IOS7CorrectedTextView.h"

static CGFloat const RPVCScrollingFastVelocityThreshold = 30.f;
static CGFloat const RPVCHeaderHeightPhone = 10.f;
NSString *const RPVCDisplayedNativeFriendFinder = @"DisplayedNativeFriendFinder";

@interface ReaderPostsViewController ()<ReaderTopicsDelegate, ReaderTextFormDelegate, WPTableImageSourceDelegate> {
	BOOL _hasMoreContent;
	BOOL _loadingMore;
    WPTableImageSource *_featuredImageSource;
	CGFloat keyboardOffset;
    BOOL _isScrollingFast;
    CGFloat _lastOffset;
    UIPopoverController *_popover;
}

@property (nonatomic, strong) ReaderReblogFormView *readerReblogFormView;
@property (nonatomic, strong) WPFriendFinderNudgeView *friendFinderNudgeView;
@property (nonatomic, strong) UINavigationBar *navBar;
@property (nonatomic) BOOL isShowingReblogForm;

@end

@implementation ReaderPostsViewController

+ (void)initialize {
	// DTCoreText will cache font descriptors on a background thread. However, because the font cache
	// updated synchronously, the detail view controller ends up waiting for the fonts to load anyway
	// (at least for the first time). We'll have DTCoreText prime its font cache here so things are ready
	// for the detail view, and avoid a perceived lag. 
	[DTCoreTextFontDescriptor fontDescriptorWithFontAttributes:nil];
    
    [AFImageRequestOperation addAcceptableContentTypes:[NSSet setWithObject:@"image/jpg"]];
}


#pragma mark - Life Cycle methods

- (void)dealloc {
    _featuredImageSource.delegate = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
	self.readerReblogFormView = nil;
	self.friendFinderNudgeView = nil;
}

- (id)init {
	self = [super init];
	if (self) {
		// This is a convenient place to check for the user's blogs and primary blog for reblogging.
		_hasMoreContent = YES;
		self.infiniteScrollEnabled = YES;
        self.incrementalLoadingSupported = YES;
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
    
    [self fetchBlogsAndPrimaryBlog];

    CGFloat maxWidth = self.tableView.bounds.size.width;
    if (IS_IPHONE) {
        maxWidth = MAX(self.tableView.bounds.size.width, self.tableView.bounds.size.height);
    }
    maxWidth -= 20.f; // Container frame
    CGFloat maxHeight = maxWidth * RPTVCMaxImageHeightPercentage;
    _featuredImageSource = [[WPTableImageSource alloc] initWithMaxSize:CGSizeMake(maxWidth, maxHeight)];
    _featuredImageSource.delegate = self;
	self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
	
	// Topics button
	UIBarButtonItem *button = nil;
    if (IS_IOS7) {
        UIButton *topicsButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [topicsButton setImage:[UIImage imageNamed:@"icon-reader-topics"] forState:UIControlStateNormal];
        [topicsButton setImage:[UIImage imageNamed:@"icon-reader-topics-active"] forState:UIControlStateHighlighted];

        CGSize imageSize = [UIImage imageNamed:@"icon-reader-topics"].size;
        topicsButton.frame = CGRectMake(0.0, 0.0, imageSize.width, imageSize.height);
		
        [topicsButton addTarget:self action:@selector(topicsAction:) forControlEvents:UIControlEventTouchUpInside];
        button = [[UIBarButtonItem alloc] initWithCustomView:topicsButton];
    } else {
        UIButton *readButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [readButton setImage:[UIImage imageNamed:@"navbar_read"] forState:UIControlStateNormal];
        
		UIImage *backgroundImage = [[UIImage imageNamed:@"navbar_button_bg"] stretchableImageWithLeftCapWidth:4 topCapHeight:0];
        [readButton setBackgroundImage:backgroundImage forState:UIControlStateNormal];
		
        backgroundImage = [[UIImage imageNamed:@"navbar_button_bg_active"] stretchableImageWithLeftCapWidth:4 topCapHeight:0];
        [readButton setBackgroundImage:backgroundImage forState:UIControlStateHighlighted];
        
        readButton.frame = CGRectMake(0.0f, 0.0f, 44.0f, 30.0f);
		
        [readButton addTarget:self action:@selector(topicsAction:) forControlEvents:UIControlEventTouchUpInside];
        button = [[UIBarButtonItem alloc] initWithCustomView:readButton];
    }
	
    [button setAccessibilityLabel:NSLocalizedString(@"Topics", @"")];
    
    if (IS_IOS7) {
        [WPStyleGuide setRightBarButtonItemWithCorrectSpacing:button forNavigationItem:self.navigationItem];
    } else {
        UIColor *color = [UIColor UIColorFromHex:0x464646];
        button.tintColor = color;
        [self.navigationItem setRightBarButtonItem:button animated:YES];
    }
    
	CGRect frame = CGRectMake(0.0f, self.view.bounds.size.height, self.view.bounds.size.width, [ReaderReblogFormView desiredHeight]);
	self.readerReblogFormView = [[ReaderReblogFormView alloc] initWithFrame:frame];
	_readerReblogFormView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
	_readerReblogFormView.navigationItem = self.navigationItem;
	_readerReblogFormView.delegate = self;
	
	if (_isShowingReblogForm) {
		[self showReblogForm];
	}

    [WPMobileStats trackEventForWPCom:StatsEventReaderOpened properties:[self categoryPropertyForStats]];
    [WPMobileStats pingWPComStatsEndpoint:@"home_page"];
    [WPMobileStats logQuantcastEvent:@"newdash.home_page"];
    [WPMobileStats logQuantcastEvent:@"mobile.home_page"];
    if ([self isCurrentCategoryFreshlyPressed]) {
        [WPMobileStats logQuantcastEvent:@"newdash.freshly"];
        [WPMobileStats logQuantcastEvent:@"mobile.freshly"];
    }
    
    // Sync content as soon as login or creation occurs
    [[NSNotificationCenter defaultCenter] addObserverForName:WordPressComApiDidLoginNotification
                                                      object:nil
                                                       queue:nil
                                                  usingBlock:^(NSNotification *notification){
                                                      [self syncItems];
                                                  }];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	
    [self performSelector:@selector(showFriendFinderNudgeView:) withObject:self afterDelay:3.0];
    	
	self.title = [[[ReaderPost currentTopic] objectForKey:@"title"] capitalizedString];
    [self loadImagesForVisibleRows];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleKeyboardDidShow:) name:UIKeyboardWillShowNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleKeyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    // WPTableViewController's viewDidAppear triggers a sync, but only do it if authenticated
    // (this prevents an attempted sync when the app launches for the first time before authenticating)
    if ([[WordPressAppDelegate sharedWordPressApplicationDelegate] isWPcomAuthenticated]) {
        [super viewDidAppear:animated];
    }

    NSIndexPath *selectedIndexPath = [self.tableView indexPathForSelectedRow];
    if (selectedIndexPath) {
        [self.tableView deselectRowAtIndexPath:selectedIndexPath animated:YES];
    }
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation {
    [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];
    // After rotation, visible images might be scaled up/down
    // Force them to reload so they're pixel perfect
    [self loadImagesForVisibleRows];
}

- (void)setTitle:(NSString *)title {
    [super setTitle:title];
    
    // Reset the tab bar title; this isn't a great solution, but works
    NSInteger tabIndex = [self.tabBarController.viewControllers indexOfObject:self.navigationController];
    UITabBarItem *tabItem = [[[self.tabBarController tabBar] items] objectAtIndex:tabIndex];
    tabItem.title = NSLocalizedString(@"Reader", @"Description of the Reader tab");
}

- (void)dismissPopover {
    if (_popover) {
        [_popover dismissPopoverAnimated:YES];
        _popover = nil;
    }
}

- (void)handleKeyboardDidShow:(NSNotification *)notification {
    UIView *view = self.view.superview;
	CGRect frame = view.frame;
	CGRect startFrame = [[[notification userInfo] objectForKey:UIKeyboardFrameBeginUserInfoKey] CGRectValue];
	CGRect endFrame = [[[notification userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
	
	// Figure out the difference between the bottom of this view, and the top of the keyboard.
	// This should account for any toolbars.
	CGPoint point = [view.window convertPoint:startFrame.origin toView:view];
	keyboardOffset = point.y - (frame.origin.y + frame.size.height);
	
	// if we're upside down, we need to adjust the origin.
	if (endFrame.origin.x == 0 && endFrame.origin.y == 0) {
		endFrame.origin.y = endFrame.origin.x += MIN(endFrame.size.height, endFrame.size.width);
	}
	
	point = [view.window convertPoint:endFrame.origin toView:view];
    CGSize tabBarSize = [self tabBarSize];
	frame.size.height = point.y + tabBarSize.height;
	
	[UIView animateWithDuration:0.3f delay:0.0f options:UIViewAnimationOptionBeginFromCurrentState animations:^{
		view.frame = frame;
	} completion:^(BOOL finished) {
		// BUG: When dismissing a modal view, and the keyboard is showing again, the animation can get clobbered in some cases.
		// When this happens the view is set to the dimensions of its wrapper view, hiding content that should be visible
		// above the keyboard.
		// For now use a fallback animation.
		if (!CGRectEqualToRect(view.frame, frame)) {
			[UIView animateWithDuration:0.3 animations:^{
				view.frame = frame;
			}];
		}
	}];
}

- (void)handleKeyboardWillHide:(NSNotification *)notification {
    UIView *view = self.view.superview;
	CGRect frame = view.frame;
	CGRect keyFrame = [[[notification userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
	
	CGPoint point = [view.window convertPoint:keyFrame.origin toView:view];
	frame.size.height = point.y - (frame.origin.y + keyboardOffset);
	view.frame = frame;
}

- (void)showReblogForm {
	if (_readerReblogFormView.superview != nil)
		return;
	
	NSIndexPath *path = [self.tableView indexPathForSelectedRow];
	_readerReblogFormView.post = (ReaderPost *)[self.resultsController objectAtIndexPath:path];
	
	CGFloat reblogHeight = [ReaderReblogFormView desiredHeight];
	CGRect tableFrame = self.tableView.frame;
	tableFrame.size.height = self.tableView.frame.size.height - reblogHeight;
	self.tableView.frame = tableFrame;
	
	CGFloat y = tableFrame.origin.y + tableFrame.size.height;
	_readerReblogFormView.frame = CGRectMake(0.0f, y, self.view.bounds.size.width, reblogHeight);
	[self.view.superview addSubview:_readerReblogFormView];
	self.isShowingReblogForm = YES;
	[_readerReblogFormView.textView becomeFirstResponder];
}

- (void)hideReblogForm {
	if (_readerReblogFormView.superview == nil)
		return;
	
	[self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:NO];
	
	CGRect tableFrame = self.tableView.frame;
	tableFrame.size.height = self.tableView.frame.size.height + _readerReblogFormView.frame.size.height;
	
	self.tableView.frame = tableFrame;
	[_readerReblogFormView removeFromSuperview];
	self.isShowingReblogForm = NO;
	[self.view endEditing:YES];
}

- (void)loadImagesForVisibleRows {
    NSArray *visiblePaths = [self.tableView indexPathsForVisibleRows];
    for (NSIndexPath *indexPath in visiblePaths) {
        ReaderPost *post = (ReaderPost *)[self.resultsController objectAtIndexPath:indexPath];

        ReaderPostTableViewCell *cell = (ReaderPostTableViewCell *)[self.tableView cellForRowAtIndexPath:indexPath];

        UIImage *image = [post cachedAvatarWithSize:cell.avatarImageView.bounds.size];
        CGSize imageSize = cell.avatarImageView.bounds.size;
        if (image) {
            [cell setAvatar:image];
        } else {
            __weak UITableView *tableView = self.tableView;
            [post fetchAvatarWithSize:imageSize success:^(UIImage *image) {
                if (cell == [tableView cellForRowAtIndexPath:indexPath]) {
                    [cell setAvatar:image];
                }
            }];
        }

        if (post.featuredImageURL) {
            NSURL *imageURL = post.featuredImageURL;
            imageSize = cell.cellImageView.frame.size;
            image = [_featuredImageSource imageForURL:imageURL withSize:imageSize];
            if (image) {
                [cell setFeaturedImage:image];
            } else {
                [_featuredImageSource fetchImageForURL:imageURL withSize:imageSize indexPath:indexPath isPrivate:post.isPrivate];
            }
        }
    }
}


#pragma mark - Actions

- (void)reblogAction:(id)sender {
	NSIndexPath *selectedPath = [self.tableView indexPathForSelectedRow];	
	UITableViewCell *cell = [ReaderPostTableViewCell cellForSubview:sender];
	NSIndexPath *path = [self.tableView indexPathForCell:cell];
	
	// if not showing form, show the form.
	if (!selectedPath) {
		[self.tableView selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
		[self showReblogForm];
		return;
	}
	
	// if showing form && same cell as before, dismiss the form.
	if ([selectedPath compare:path] == NSOrderedSame) {
		[self hideReblogForm];
	} else {
		[self.tableView selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
	}
}

- (void)likeAction:(id)sender {
    ReaderPostTableViewCell *cell = [ReaderPostTableViewCell cellForSubview:sender];
    ReaderPost *post = cell.post;
	[post toggleLikedWithSuccess:^{
        if ([post.isLiked boolValue]) {
            [WPMobileStats trackEventForWPCom:StatsEventReaderLikedPost];
        } else {
            [WPMobileStats trackEventForWPCom:StatsEventReaderUnlikedPost];
        }
	} failure:^(NSError *error) {
		DDLogError(@"Error Liking Post : %@", [error localizedDescription]);
		[cell updateControlBar];
	}];
	
	[cell updateControlBar];
}

- (void)topicsAction:(id)sender {
	ReaderTopicsViewController *controller = [[ReaderTopicsViewController alloc] initWithStyle:UITableViewStyleGrouped];
	controller.delegate = self;
    if (IS_IPAD) {
        if (_popover) {
            [self dismissPopover];
            return;
        }
        
        _popover = [[UIPopoverController alloc] initWithContentViewController:controller];
        
        UIBarButtonItem *shareButton;
        if (IS_IOS7) {
            // For iOS7 there is an added spacing element inserted before the share button to adjust the position of the button.
            shareButton = [self.navigationItem.rightBarButtonItems objectAtIndex:1];
        } else {
            shareButton = self.navigationItem.rightBarButtonItem;
        }
        [_popover presentPopoverFromBarButtonItem:shareButton permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    } else {
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:controller];
        navController.navigationBar.translucent = NO;
        [self presentViewController:navController animated:YES completion:nil];
    }
}

- (void)followAction:(id)sender {
    UIButton *followButton = (UIButton *)sender;
    ReaderPostTableViewCell *cell = [ReaderPostTableViewCell cellForSubview:sender];
    ReaderPost *post = cell.post;
    
    if (![post isFollowable])
        return;

    followButton.selected = ![post.isFollowing boolValue]; // Set it optimistically
	[cell setNeedsLayout];
	[post toggleFollowingWithSuccess:^{
	} failure:^(NSError *error) {
		DDLogError(@"Error Following Blog : %@", [error localizedDescription]);
		[followButton setSelected:[post.isFollowing boolValue]];
		[cell setNeedsLayout];
	}];
}

- (void)commentAction:(id)sender {
    // TODO: allow commenting
}

- (void)tagAction:(id)sender {
    ReaderPostTableViewCell *cell = [ReaderPostTableViewCell cellForSubview:sender];
    ReaderPost *post = cell.post;

    NSString *endpoint = [NSString stringWithFormat:@"read/tags/%@/posts", post.primaryTagSlug];
    NSDictionary *dict = @{@"endpoint" : endpoint,
                           @"title" : post.primaryTagName};
    
	[[NSUserDefaults standardUserDefaults] setObject:dict forKey:ReaderCurrentTopicKey];
	[[NSUserDefaults standardUserDefaults] synchronize];
    [self readerTopicChanged];
}

#pragma mark - ReaderTextForm Delegate Methods

- (void)readerTextFormDidSend:(ReaderTextFormView *)readerTextForm {
	[self hideReblogForm];
}


- (void)readerTextFormDidCancel:(ReaderTextFormView *)readerTextForm {
	[self hideReblogForm];
}


#pragma mark - UIScrollView Delegate Methods

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    CGFloat offset = self.tableView.contentOffset.y;
    // We just take a diff from the last known offset, as the approximation is good enough
    CGFloat velocity = fabsf(offset - _lastOffset);
    if (velocity > RPVCScrollingFastVelocityThreshold && self.isScrolling) {
        _isScrollingFast = YES;
    } else {
        _isScrollingFast = NO;
    }
    _lastOffset = offset;
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    [super scrollViewDidEndDecelerating:scrollView];
    _isScrollingFast = NO;
    [self loadImagesForVisibleRows];

	NSIndexPath *selectedIndexPath = [self.tableView indexPathForSelectedRow];
	if (!selectedIndexPath)
		return;

	__block BOOL found = NO;
	[[self.tableView indexPathsForVisibleRows] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		NSIndexPath *objPath = (NSIndexPath *)obj;
		if ([objPath compare:selectedIndexPath] == NSOrderedSame) {
			found = YES;
		}
		*stop = YES;
	}];
	
	if (found)
        return;
	
	[self hideReblogForm];
}


#pragma mark - WPTableViewSublass methods


- (NSString *)noResultsPrompt {
	NSString *prompt; 
	NSString *endpoint = [ReaderPost currentEndpoint];
	NSArray *endpoints = [ReaderPost readerEndpoints];
	NSInteger idx = [endpoints indexOfObjectPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
		BOOL match = NO;
		
		if ([endpoint isEqualToString:[obj objectForKey:@"endpoint"]]) {
			match = YES;
			*stop = YES;
		}
				
		return match;
	}];
	
	switch (idx) {
		case 1:
			// Blogs I follow
			prompt = NSLocalizedString(@"You are not following any blogs.", @"");
			break;
			
		case 2:
			// Posts I like
			prompt = NSLocalizedString(@"You have not liked any posts.", @"");
			break;
			
		default:
			// Topics // freshly pressed.
			prompt = NSLocalizedString(@"Sorry. No posts yet.", @"");
			break;
			

	}
	return prompt;
}

- (UIView *)createNoResultsView {	
	return [WPInfoView WPInfoViewWithTitle:[self noResultsPrompt] message:nil cancelButton:nil];
}

- (NSString *)entityName {
	return @"ReaderPost";
}

- (NSString *)resultsControllerCacheName {
	return [ReaderPost currentEndpoint];
}

- (NSDate *)lastSyncDate {
	return (NSDate *)[[NSUserDefaults standardUserDefaults] objectForKey:ReaderLastSyncDateKey];
}

- (NSFetchRequest *)fetchRequest {
	NSString *endpoint = [ReaderPost currentEndpoint];
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:[self entityName]];
    fetchRequest.predicate = [NSPredicate predicateWithFormat:@"(endpoint == %@)", endpoint];
    NSSortDescriptor *sortDescriptorDate = [NSSortDescriptor sortDescriptorWithKey:@"sortDate" ascending:NO];
    fetchRequest.sortDescriptors = @[sortDescriptorDate];
	fetchRequest.fetchBatchSize = 10;
	return fetchRequest;
}

- (NSString *)sectionNameKeyPath {
	return nil;
}

- (UITableViewCell *)newCell {
    NSString *cellIdentifier = @"ReaderPostCell";
    ReaderPostTableViewCell *cell = (ReaderPostTableViewCell *)[self.tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil) {
        cell = [[ReaderPostTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIdentifier];
        [cell.reblogButton addTarget:self action:@selector(reblogAction:) forControlEvents:UIControlEventTouchUpInside];
        [cell.likeButton addTarget:self action:@selector(likeAction:) forControlEvents:UIControlEventTouchUpInside];
        [cell.followButton addTarget:self action:@selector(followAction:) forControlEvents:UIControlEventTouchUpInside];
        [cell.commentButton addTarget:self action:@selector(commentAction:) forControlEvents:UIControlEventTouchUpInside];
        [cell.tagButton addTarget:self action:@selector(tagAction:) forControlEvents:UIControlEventTouchUpInside];
    }
	return cell;
}

- (void)configureCell:(UITableViewCell *)aCell atIndexPath:(NSIndexPath *)indexPath {
	if (!aCell)
        return;

	ReaderPostTableViewCell *cell = (ReaderPostTableViewCell *)aCell;
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.accessoryType = UITableViewCellAccessoryNone;
	
	ReaderPost *post = (ReaderPost *)[self.resultsController objectAtIndexPath:indexPath];
	[cell configureCell:post];
    [self setImageForPost:post forCell:cell indexPath:indexPath];

    CGSize imageSize = cell.avatarImageView.bounds.size;
    UIImage *image = [post cachedAvatarWithSize:imageSize];
    if (image) {
        [cell setAvatar:image];
    } else if (!self.tableView.isDragging && !self.tableView.isDecelerating) {
        [post fetchAvatarWithSize:imageSize success:^(UIImage *image) {
            if (cell == [self.tableView cellForRowAtIndexPath:indexPath]) {
                [cell setAvatar:image];
            }
        }];
    }
}

- (void)setImageForPost:(ReaderPost *)post forCell:(ReaderPostTableViewCell *)cell indexPath:(NSIndexPath *)indexPath {
    NSURL *imageURL = post.featuredImageURL;
    if (!imageURL)
        return;

    CGSize imageSize = cell.cellImageView.bounds.size;
    if (CGSizeEqualToSize(imageSize, CGSizeZero)) {
        imageSize.width = self.tableView.bounds.size.width;
        imageSize.height = round(imageSize.width * RPTVCMaxImageHeightPercentage);
    }
    UIImage *image = [_featuredImageSource imageForURL:imageURL withSize:imageSize];
    if (image) {
        [cell setFeaturedImage:image];
    } else if (!_isScrollingFast) {
        [_featuredImageSource fetchImageForURL:imageURL withSize:imageSize indexPath:indexPath isPrivate:post.isPrivate];
    }
}

- (BOOL)hasMoreContent {
	return _hasMoreContent;
}

- (void)syncItemsWithSuccess:(void (^)())success failure:(void (^)(NSError *))failure {
    WPFLogMethod();
    // if needs auth.
    if ([WPCookie hasCookieForURL:[NSURL URLWithString:@"https://wordpress.com"] andUsername:[[WPAccount defaultWordPressComAccount] username]]) {
       [self syncReaderItemsWithSuccess:success failure:failure];
        return;
    }

    [[WordPressAppDelegate sharedWordPressApplicationDelegate] useDefaultUserAgent];
    NSString *username = [[WPAccount defaultWordPressComAccount] username];
    NSString *password = [[WPAccount defaultWordPressComAccount] password];
    NSMutableURLRequest *mRequest = [[NSMutableURLRequest alloc] init];
    NSString *requestBody = [NSString stringWithFormat:@"log=%@&pwd=%@&redirect_to=http://wordpress.com",
                             [username stringByUrlEncoding],
                             [password stringByUrlEncoding]];
    
    [mRequest setURL:[NSURL URLWithString:@"https://wordpress.com/wp-login.php"]];
    [mRequest setHTTPBody:[requestBody dataUsingEncoding:NSUTF8StringEncoding]];
    [mRequest setValue:[NSString stringWithFormat:@"%d", [requestBody length]] forHTTPHeaderField:@"Content-Length"];
    [mRequest addValue:@"*/*" forHTTPHeaderField:@"Accept"];
    [mRequest setHTTPMethod:@"POST"];
    
    
    AFHTTPRequestOperation *authRequest = [[AFHTTPRequestOperation alloc] initWithRequest:mRequest];
    [authRequest setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        [[WordPressAppDelegate sharedWordPressApplicationDelegate] useAppUserAgent];
        [self syncReaderItemsWithSuccess:success failure:failure];
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        [[WordPressAppDelegate sharedWordPressApplicationDelegate] useAppUserAgent];
        [self syncReaderItemsWithSuccess:success failure:failure];
    }];
    
    [authRequest start];    
}

- (void)syncReaderItemsWithSuccess:(void (^)())success failure:(void (^)(NSError *))failure {
    WPFLogMethod();
	NSString *endpoint = [ReaderPost currentEndpoint];
	NSNumber *numberToSync = [NSNumber numberWithInteger:ReaderPostsToSync];
	NSDictionary *params = @{@"number":numberToSync, @"per_page":numberToSync};
	[ReaderPost getPostsFromEndpoint:endpoint
					  withParameters:params
						 loadingMore:_loadingMore
							 success:^(AFHTTPRequestOperation *operation, id responseObject) {
								 if (success) {
									success();
								 }
								 [self onSyncSuccess:operation response:responseObject];
							 }
							 failure:^(AFHTTPRequestOperation *operation, NSError *error) {
								 if (failure) {
									 failure(error);
								 }
							 }];
    [WPMobileStats trackEventForWPCom:StatsEventReaderHomePageRefresh];
    [WPMobileStats pingWPComStatsEndpoint:@"home_page_refresh"];
}

- (void)loadMoreWithSuccess:(void (^)())success failure:(void (^)(NSError *error))failure {
    WPFLogMethod();
	if ([self.resultsController.fetchedObjects count] == 0)
		return;
	
	if (_loadingMore)
        return;
    
	_loadingMore = YES;
	
	ReaderPost *post = self.resultsController.fetchedObjects.lastObject;
	NSNumber *numberToSync = [NSNumber numberWithInteger:ReaderPostsToSync];
	NSString *endpoint = [ReaderPost currentEndpoint];
	id before;
	if ([endpoint isEqualToString:@"freshly-pressed"]) {
		// freshly-pressed wants an ISO string but the rest want a timestamp.
		before = [DateUtils isoStringFromDate:post.date_created_gmt];
	} else {
		before = [NSNumber numberWithInteger:[post.date_created_gmt timeIntervalSince1970]];
	}

	NSDictionary *params = @{@"before":before, @"number":numberToSync, @"per_page":numberToSync};

	[ReaderPost getPostsFromEndpoint:endpoint
					  withParameters:params
						 loadingMore:_loadingMore
							 success:^(AFHTTPRequestOperation *operation, id responseObject) {
								 if (success) {
									 success();
								 }
								 [self onSyncSuccess:operation response:responseObject];
							 }
							 failure:^(AFHTTPRequestOperation *operation, NSError *error) {
								 if (failure) {
									 failure(error);
								 }
							 }];
    
    [WPMobileStats trackEventForWPCom:StatsEventReaderInfiniteScroll properties:[self categoryPropertyForStats]];
    [WPMobileStats logQuantcastEvent:@"newdash.infinite_scroll"];
    [WPMobileStats logQuantcastEvent:@"mobile.infinite_scroll"];
}

- (UITableViewRowAnimation)tableViewRowAnimation {
	return UITableViewRowAnimationNone;
}

- (void)onSyncSuccess:(AFHTTPRequestOperation *)operation response:(id)responseObject {
    WPFLogMethod();
	BOOL wasLoadingMore = _loadingMore;
	_loadingMore = NO;
	
	NSDictionary *resp = (NSDictionary *)responseObject;
	NSArray *postsArr = [resp arrayForKey:@"posts"];
	
	if (!postsArr) {
		if (wasLoadingMore) {
			_hasMoreContent = NO;
		}
		return;
	}
	
	// if # of results is less than # requested then no more content.
	if ([postsArr count] < ReaderPostsToSync && wasLoadingMore) {
		_hasMoreContent = NO;
	}
}


#pragma mark -
#pragma mark TableView Methods

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return [ReaderPostTableViewCell cellHeightForPost:[self.resultsController objectAtIndexPath:indexPath] withWidth:self.tableView.bounds.size.width];
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    if (IS_IPHONE)
        return RPVCHeaderHeightPhone;
    
    return [super tableView:tableView heightForHeaderInSection:section];
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	if (_readerReblogFormView.superview != nil) {
		[self hideReblogForm];
		return nil;
	}
	
	UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
	if ([cell isSelected]) {
		_readerReblogFormView.post = nil;
		[tableView deselectRowAtIndexPath:indexPath animated:NO];
		[self hideReblogForm];
		return nil;
	}
	
	return indexPath;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (IS_IPAD) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
    }

	ReaderPost *post = [self.resultsController.fetchedObjects objectAtIndex:indexPath.row];
	
	ReaderPostDetailViewController *controller = [[ReaderPostDetailViewController alloc] initWithPost:post];
    [self.navigationController pushViewController:controller animated:YES];
    
    [WPMobileStats trackEventForWPCom:StatsEventReaderOpenedArticleDetails];
    [WPMobileStats pingWPComStatsEndpoint:@"details_page"];
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)aCell forRowAtIndexPath:(NSIndexPath *)indexPath {
	[super tableView:tableView willDisplayCell:aCell forRowAtIndexPath:indexPath];

	ReaderPostTableViewCell *cell = (ReaderPostTableViewCell *)aCell;
	ReaderPost *post = (ReaderPost *)[self.resultsController objectAtIndexPath:indexPath];
    [self setImageForPost:post forCell:cell indexPath:indexPath];
}


#pragma mark - ReaderTopicsDelegate Methods

- (void)readerTopicChanged {
	if (IS_IPAD){
        [self dismissPopover];
	}
	
	_loadingMore = NO;
	_hasMoreContent = YES;
	[[(WPInfoView *)self.noResultsView titleLabel] setText:[self noResultsPrompt]];

	[self.tableView setContentOffset:CGPointMake(0, 0) animated:NO];
	[self resetResultsController];
	[self.tableView reloadData];
    [self syncItems];
	
	self.title = [[ReaderPost currentTopic] stringForKey:@"title"];

    if ([WordPressAppDelegate sharedWordPressApplicationDelegate].connectionAvailable == YES && ![self isSyncing] ) {
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:ReaderLastSyncDateKey];
		[NSUserDefaults resetStandardUserDefaults];
    }

    if ([self isCurrentCategoryFreshlyPressed]) {
        [WPMobileStats trackEventForWPCom:StatsEventReaderSelectedFreshlyPressedTopic];
        [WPMobileStats pingWPComStatsEndpoint:@"freshly"];
        [WPMobileStats logQuantcastEvent:@"newdash.fresh"];
        [WPMobileStats logQuantcastEvent:@"mobile.fresh"];
    } else {
        [WPMobileStats trackEventForWPCom:StatsEventReaderSelectedCategory properties:[self categoryPropertyForStats]];
    }
}


#pragma mark - Utility

- (BOOL)isCurrentCategoryFreshlyPressed {
    return [[self currentCategory] isEqualToString:@"freshly-pressed"];
}

- (NSString *)currentCategory {
    NSDictionary *categoryDetails = [[NSUserDefaults standardUserDefaults] objectForKey:ReaderCurrentTopicKey];
    NSString *category = [categoryDetails stringForKey:@"endpoint"];
    if (category == nil)
        return @"reader/following";
    
    return category;
}

- (NSDictionary *)categoryPropertyForStats {
    return @{@"category": [self currentCategory]};
}

- (void)fetchBlogsAndPrimaryBlog {
	NSURL *xmlrpc;
    NSString *username, *password;
    WPAccount *account = [WPAccount defaultWordPressComAccount];
	xmlrpc = [NSURL URLWithString:@"https://wordpress.com/xmlrpc.php"];
	username = account.username;
	password = account.password;
	
    WPXMLRPCClient *api = [WPXMLRPCClient clientWithXMLRPCEndpoint:xmlrpc];
    [api callMethod:@"wp.getUsersBlogs"
         parameters:[NSArray arrayWithObjects:username, password, nil]
            success:^(AFHTTPRequestOperation *operation, id responseObject) {
                NSArray *usersBlogs = responseObject;
				
                if ([usersBlogs count] > 0) {
                    [usersBlogs enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                        NSString *title = [obj valueForKey:@"blogName"];
                        title = [title stringByDecodingXMLCharacters];
                        [obj setValue:title forKey:@"blogName"];
                    }];
                }
				
				[[NSUserDefaults standardUserDefaults] setObject:usersBlogs forKey:@"wpcom_users_blogs"];
				
                [[WordPressComApi sharedApi] getPath:@"me"
                                          parameters:nil
                                             success:^(AFHTTPRequestOperation *operation, id responseObject) {
                                                 if ([usersBlogs count] < 1)
                                                     return;
                                                 
                                                 NSDictionary *dict = (NSDictionary *)responseObject;
                                                 NSString *userID = [dict stringForKey:@"ID"];
                                                 if (userID != nil) {
                                                     [WPMobileStats updateUserIDForStats:userID];
                                                     [[NSUserDefaults standardUserDefaults] setObject:userID forKey:@"wpcom_user_id"];
                                                     [NSUserDefaults resetStandardUserDefaults];
                                                 }
                                                 
                                                 __block NSNumber *preferredBlogId;
                                                 NSNumber *primaryBlog = [dict objectForKey:@"primary_blog"];
                                                 [usersBlogs enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                                                     if ([primaryBlog isEqualToNumber:[obj numberForKey:@"blogid"]]) {
                                                         preferredBlogId = [obj numberForKey:@"blogid"];
                                                         *stop = YES;
                                                     }
                                                 }];
                                                 
                                                 if (!preferredBlogId) {
                                                     NSDictionary *dict = [usersBlogs objectAtIndex:0];
                                                     preferredBlogId = [dict numberForKey:@"blogid"];
                                                 }
                                                 
                                                 [[NSUserDefaults standardUserDefaults] setObject:preferredBlogId forKey:@"wpcom_users_prefered_blog_id"];
                                                 [NSUserDefaults resetStandardUserDefaults];
                                                 
                                             } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
                                                 // TODO: Handle Failure. Retry maybe?
                                             }];
                
                if ([usersBlogs count] == 0) {
                    return;
                }

			} failure:^(AFHTTPRequestOperation *operation, NSError *error) {
				// Fail silently.
            }];
}

- (CGSize)tabBarSize {
    CGSize tabBarSize = CGSizeZero;
    if ([self tabBarController]) {
        tabBarSize = [[[self tabBarController] tabBar] bounds].size;
    }

    return tabBarSize;
}


#pragma mark - Friend Finder Button

- (BOOL)shouldDisplayfriendFinderNudgeView {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    return ![userDefaults boolForKey:RPVCDisplayedNativeFriendFinder] && self.friendFinderNudgeView == nil;
}

- (void)showFriendFinderNudgeView:(id)sender {
    if ([self shouldDisplayfriendFinderNudgeView]) {
        NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
        
        [userDefaults setBool:YES forKey:RPVCDisplayedNativeFriendFinder];
        [userDefaults synchronize];
        
        CGRect buttonFrame = CGRectMake(0,self.navigationController.view.frame.size.height,self.view.frame.size.width, 0.f);
        WPFriendFinderNudgeView *nudgeView = [[WPFriendFinderNudgeView alloc] initWithFrame:buttonFrame];
        self.friendFinderNudgeView = nudgeView;
        self.friendFinderNudgeView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
        [self.navigationController.view addSubview:self.friendFinderNudgeView];
        
        CGSize tabBarSize = [self tabBarSize];
        
        buttonFrame = self.friendFinderNudgeView.frame;
        buttonFrame.origin.y = self.navigationController.view.frame.size.height - buttonFrame.size.height - tabBarSize.height;
        
        [self.friendFinderNudgeView.cancelButton addTarget:self action:@selector(hideFriendFinderNudgeView:) forControlEvents:UIControlEventTouchUpInside];
        [self.friendFinderNudgeView.confirmButton addTarget:self action:@selector(openFriendFinder:) forControlEvents:UIControlEventTouchUpInside];
        
        [UIView animateWithDuration:0.2 animations:^{
            self.friendFinderNudgeView.frame = buttonFrame;
        }];
    }
}

- (void)hideFriendFinderNudgeView:(id)sender {
    if (self.friendFinderNudgeView == nil)
        return;
    
    CGRect buttonFrame = self.friendFinderNudgeView.frame;
    CGRect viewFrame = self.view.frame;
    buttonFrame.origin.y = viewFrame.size.height + 1.f;
    [UIView animateWithDuration:0.1 animations:^{
        self.friendFinderNudgeView.frame = buttonFrame;
    } completion:^(BOOL finished) {
        [self.friendFinderNudgeView removeFromSuperview];
        self.friendFinderNudgeView = nil;
    }];
}

- (void)openFriendFinder:(id)sender {
    [self hideFriendFinderNudgeView:sender];
    WPFriendFinderViewController *controller = [[WPFriendFinderViewController alloc] initWithNibName:@"WPWebViewController" bundle:nil];
	
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:controller];
    navController.navigationBar.translucent = NO;
    if (IS_IPAD) {
        navController.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
		navController.modalPresentationStyle = UIModalPresentationFormSheet;
    }
	
    [self presentViewController:navController animated:YES completion:nil];
}


#pragma mark - WPTableImageSourceDelegate

- (void)tableImageSource:(WPTableImageSource *)tableImageSource imageReady:(UIImage *)image forIndexPath:(NSIndexPath *)indexPath {
    if (!_isScrollingFast) {
        ReaderPostTableViewCell *cell = (ReaderPostTableViewCell *)[self.tableView cellForRowAtIndexPath:indexPath];
        [cell setFeaturedImage:image];
    }
}

@end
