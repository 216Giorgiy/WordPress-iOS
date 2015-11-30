#import "LocalCoreDataService.h"

@class Blog;
@class WPAccount;
@class Menu;
@class MenuLocation;

typedef void(^MenusServiceSuccessBlock)();
typedef void(^MenusServiceMenuRequestSuccessBlock)(Menu *menu);
typedef void(^MenusServiceMenusRequestSuccessBlock)(NSArray<Menu *> *menus);
typedef void(^MenusServiceLocationsRequestSuccessBlock)(NSArray<MenuLocation *> *locations);
typedef void(^MenusServiceFailureBlock)(NSError *error);

@interface MenusService : LocalCoreDataService

#pragma mark - Menus availability

/**
 *  @brief      Call this method to know if a certain blog supports menus customization.
 *  @details    Right now only blogs with WP.com or connected via Jetpack support menus customization.
 *
 *  @param      blog        The blog to query for menus customization support.  Cannot be nil.
 *
 *  @returns    YES if the blog supports menus customization, NO otherwise.
 */
- (BOOL)blogSupportsMenusCustomization:(Blog *)blog;

#pragma mark - Getting menus and locations

/**
 *  @brief      Syncs the available menu and location objects for a specific blog.
 *
 *  @param      blog        The blog to get the available menus for.  Cannot be nil.
 *  @param      success     The success handler.  Can be nil.
 *  @param      failure     The failure handler.  Can be nil.
 *
 */
- (void)syncMenusForBlog:(Blog *)blog
                 success:(MenusServiceSuccessBlock)success
                 failure:(MenusServiceFailureBlock)failure;

#pragma mark - Creating and updating menus

/**
 *  @brief      Creates a menu.
 *
 *  @param      menuName  The name to create a new menu with.  Cannot be nil.
 *  @param      blog      The blog to create a menu on.  Cannot be nil.
 *  @param      success   The success handler.  Can be nil.
 *  @param      failure   The failure handler.  Can be nil.
 *
 */
- (void)createMenuWithName:(NSString *)menuName
                      blog:(Blog *)blog
                   success:(MenusServiceMenuRequestSuccessBlock)success
                   failure:(MenusServiceFailureBlock)failure;

/**
 *  @brief      Updates a menu.
 *
 *  @param      menu      The updated menu object to update with local storage and remotely.  Cannot be nil.
 *  @param      blog      The blog to update a single menu on.  Cannot be nil.
 *  @param      success   The success handler.  Can be nil.
 *  @param      failure   The failure handler.  Can be nil.
 *
 */
- (void)updateMenu:(Menu *)menu
           forBlog:(Blog *)blog
           success:(MenusServiceMenuRequestSuccessBlock)success
           failure:(MenusServiceFailureBlock)failure;

/**
 *  @brief      Delete a menu.
 *
 *  @param      menu      The menu object to delete from local storage and remotely.  Cannot be nil.
 *  @param      blog      The blog to delete a single menu from.  Cannot be nil.
 *  @param      success   The success handler.  Can be nil.
 *  @param      failure   The failure handler.  Can be nil.
 *
 */
- (void)deleteMenu:(Menu *)menu
           forBlog:(Blog *)blog
           success:(MenusServiceSuccessBlock)success
           failure:(MenusServiceFailureBlock)failure;

@end
