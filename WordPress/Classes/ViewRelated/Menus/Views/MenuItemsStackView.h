#import <UIKit/UIKit.h>

@class Menu;
@class MenuItem;

@protocol MenuItemsStackViewDelegate;

@interface MenuItemsStackView : UIView

@property (nonatomic, weak) id <MenuItemsStackViewDelegate> delegate;
@property (nonatomic, strong) Menu *menu;

@end

@protocol MenuItemsStackViewDelegate <NSObject>

- (void)itemsView:(MenuItemsStackView *)itemsView requiresScrollingToCenterView:(UIView *)viewForScrolling;
- (void)itemsView:(MenuItemsStackView *)itemsView prefersScrollingEnabled:(BOOL)enabled;
- (void)itemsView:(MenuItemsStackView *)itemsView prefersAdjustingScrollingOffsetForAnimatingView:(UIView *)view;
- (void)itemsViewAnimatingContentSizeChanges:(MenuItemsStackView *)itemsView focusedRect:(CGRect)focusedRect updatedFocusRect:(CGRect)updatedFocusRect;

@end
