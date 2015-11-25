#import "MenusSelectionDetailView.h"
#import "WPStyleGuide.h"
#import "MenusDesign.h"
#import "MenusSelectionView.h"

@interface MenusSelectionIconView : UIView

@property (nonatomic, strong) UIImage *image;
@property (nonatomic, strong) UIColor *drawColor;

@end

@implementation MenusSelectionIconView

- (void)drawRect:(CGRect)rect
{
    [super drawRect:rect];
    
    CGRect imageRect = CGRectZero;
    UIColor *drawColor = self.drawColor;
    UIImage *image = self.image;
    {
        CGContextRef context = UIGraphicsGetCurrentContext();
        CGContextSaveGState(context);
        
        CGContextSetFillColorWithColor(context, [drawColor CGColor]);
        
        imageRect.size.width = rect.size.width;
        imageRect.size.height = ((image.size.height * imageRect.size.width) / image.size.width);
        if(imageRect.size.height != rect.size.height) {
            imageRect.origin.y = -((rect.size.height / 2) - (imageRect.size.height / 2));
        }
        
        imageRect = CGRectIntegral(imageRect);
        
        CGContextTranslateCTM(context, 0, imageRect.size.height);
        CGContextScaleCTM(context, 1.0, -1.0);
        
        CGContextClipToMask(context, imageRect, [image CGImage]);
        CGContextFillRect(context, imageRect);
        
        CGContextRestoreGState(context);
    }
}

@end

@interface MenusSelectionDetailView ()

@property (nonatomic, weak) IBOutlet UIStackView *stackView;
@property (nonatomic, strong) UILabel *textLabel;
@property (nonatomic, strong) MenusSelectionIconView *iconView;
@property (nonatomic, strong) MenusSelectionIconView *accessoryView;

@end

@implementation MenusSelectionDetailView

- (void)awakeFromNib
{
    [super awakeFromNib];
    
    [self setupArrangedViews];
    [self setupStyling];
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tellDelegateTapGestureRecognized:)];
    [self addGestureRecognizer:tap];
}

- (void)updatewithAvailableItems:(NSUInteger)numItemsAvailable selectedItem:(MenusSelectionViewItem *)selectedItem
{
    NSString *localizedFormat = nil;
    if([selectedItem isMenuLocation]) {
        
        if(numItemsAvailable > 1) {
            localizedFormat = NSLocalizedString(@"%i menu areas in this theme", @"The number of menu areas available in the theme");
        }else {
            localizedFormat = NSLocalizedString(@"%i menu area in this theme", @"One menu area available in the theme");
        }
        self.iconView.image = [UIImage imageNamed:@"icon-menus-locations"];
        
    }else if([selectedItem isMenu]) {
        
        if(numItemsAvailable > 1) {
            localizedFormat = NSLocalizedString(@"%i menus available", @"The number of menus on the site and area.");
        }else {
            localizedFormat = NSLocalizedString(@"%i menu available", @"One menu is available in the site and area");
        }
        self.iconView.image = [UIImage imageNamed:@"icon-menus-menus"];
    }
    
    [self setTitleText:selectedItem.displayName subTitleText:[NSString stringWithFormat:localizedFormat, numItemsAvailable]];
    [self.iconView setNeedsDisplay];
}

- (void)setupStyling
{
    self.backgroundColor = [UIColor clearColor];
}

- (void)setupArrangedViews
{
    self.translatesAutoresizingMaskIntoConstraints = NO;
    
    UIEdgeInsets margins = UIEdgeInsetsZero;
    margins.left = MenusDesignDefaultContentSpacing;
    margins.right = MenusDesignDefaultContentSpacing;
    self.stackView.layoutMargins = margins;
    self.stackView.layoutMarginsRelativeArrangement = YES;
    self.stackView.distribution = UIStackViewDistributionFillProportionally;
    self.stackView.alignment = UIStackViewAlignmentCenter;
    self.stackView.spacing = MenusDesignDefaultContentSpacing;
    
    {
        MenusSelectionIconView *iconView = [[MenusSelectionIconView alloc] init];
        iconView.backgroundColor = [UIColor clearColor];
        iconView.image = [UIImage imageNamed:@"icon-menus-menus"];
        iconView.drawColor = [WPStyleGuide darkBlue];
        
        [iconView.widthAnchor constraintEqualToConstant:30].active = YES;
        [iconView.heightAnchor constraintEqualToConstant:30].active = YES;
        
        [self.stackView addArrangedSubview:iconView];
        self.iconView = iconView;
    }
    {
        UILabel *label = [[UILabel alloc] init];
        label.numberOfLines = 0;
        self.textLabel = label;
        [self.stackView addArrangedSubview:label];
        [label.heightAnchor constraintEqualToAnchor:self.heightAnchor].active = YES;
    }
    {
        MenusSelectionIconView *accessoryView = [[MenusSelectionIconView alloc] init];
        accessoryView.backgroundColor = [UIColor clearColor];
        accessoryView.image = [UIImage imageNamed:@"icon-menus-expand"];
        accessoryView.drawColor = [WPStyleGuide mediumBlue];
        
        [accessoryView.widthAnchor constraintEqualToConstant:12].active = YES;
        [accessoryView.heightAnchor constraintEqualToConstant:12].active = YES;
        
        [self.stackView addArrangedSubview:accessoryView];
        self.accessoryView = accessoryView;
    }
}

- (void)setShowsDesignActive:(BOOL)showsDesignActive
{
    if(_showsDesignActive != showsDesignActive) {
        _showsDesignActive = showsDesignActive;
        
        if(showsDesignActive) {
            self.accessoryView.transform = CGAffineTransformMakeScale(0.5, 0.5);
            self.accessoryView.alpha = 0.0;
        }else {
            self.accessoryView.transform = CGAffineTransformIdentity;
            self.accessoryView.alpha = 1.0;
        }
    }
}

- (void)setTitleText:(NSString *)title subTitleText:(NSString *)subtitle
{
    NSMutableAttributedString *mutableAttributedString = [[NSMutableAttributedString alloc] init];
    {
        NSDictionary *attributes =  @{NSFontAttributeName: [WPStyleGuide subtitleFont], NSForegroundColorAttributeName: [WPStyleGuide grey]};
        NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:subtitle attributes:attributes];
        [mutableAttributedString appendAttributedString:attributedString];
    }
    [mutableAttributedString.mutableString appendString:@"\n"];
    {
        NSDictionary *attributes =  @{NSFontAttributeName: [WPStyleGuide regularTextFontSemiBold], NSForegroundColorAttributeName: [WPStyleGuide darkGrey]};
        NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:title attributes:attributes];
        [mutableAttributedString appendAttributedString:attributedString];
    }
    
    self.textLabel.attributedText = mutableAttributedString;
}

#pragma mark - overrides

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [self tellDelegateTouchesHighlightedStateChanged:YES];
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [self tellDelegateTouchesHighlightedStateChanged:NO];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
    [self tellDelegateTouchesHighlightedStateChanged:NO];
}

#pragma mark - delegate helpers

- (void)tellDelegateTapGestureRecognized:(UITapGestureRecognizer *)tap
{
    if([self.delegate respondsToSelector:@selector(selectionDetailView:tapGestureRecognized:)]) {
        [self.delegate selectionDetailView:self tapGestureRecognized:tap];
    }
}

- (void)tellDelegateTouchesHighlightedStateChanged:(BOOL)highlighted
{
    if([self.delegate respondsToSelector:@selector(selectionDetailView:touchesHighlightedStateChanged:)]) {
        [self.delegate selectionDetailView:self touchesHighlightedStateChanged:highlighted];
    }
}

@end
