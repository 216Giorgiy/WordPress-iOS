#import "MenuItemTypeView.h"
#import "MenusDesign.h"
#import "WPStyleGuide.h"
#import "WPFontManager.h"

@interface MenuItemTypeView ()

@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UIImageView *arrowView;

@end

@implementation MenuItemTypeView

- (id)init
{
    self = [super init];
    if(self) {
        
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = [UIColor whiteColor];
        self.contentMode = UIViewContentModeRedraw;
        {
            UIStackView *stackView = [[UIStackView alloc] init];
            stackView.translatesAutoresizingMaskIntoConstraints = NO;
            stackView.alignment = UIStackViewAlignmentFill;
            stackView.distribution = UIStackViewDistributionFill;
            stackView.axis = UILayoutConstraintAxisHorizontal;
            stackView.spacing = MenusDesignDefaultContentSpacing;
            
            [self addSubview:stackView];
            
            NSLayoutConstraint *leading = [stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:MenusDesignDefaultContentSpacing];
            leading.priority = UILayoutPriorityDefaultHigh;
            
            NSLayoutConstraint *trailing = [stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-MenusDesignDefaultContentSpacing];
            trailing.priority = UILayoutPriorityDefaultHigh;
            
            [NSLayoutConstraint activateConstraints:@[
                                                      leading,
                                                      [stackView.topAnchor constraintEqualToAnchor:self.topAnchor constant:MenusDesignDefaultContentSpacing],
                                                      trailing,
                                                      [stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-MenusDesignDefaultContentSpacing]
                                                      ]];
            self.stackView = stackView;
        }
        {
            UIImageView *iconView = [[UIImageView alloc] init];
            iconView.translatesAutoresizingMaskIntoConstraints = NO;
            iconView.contentMode = UIViewContentModeScaleAspectFit;
            iconView.backgroundColor = [UIColor whiteColor];
            iconView.tintColor = [WPStyleGuide mediumBlue];
            
            [self.stackView addArrangedSubview:iconView];
            
            NSLayoutConstraint *widthConstraint = [iconView.widthAnchor constraintEqualToConstant:14.0];
            widthConstraint.priority = 999;
            widthConstraint.active = YES;
            
            self.iconView = iconView;
        }
        {
            UILabel *label = [[UILabel alloc] init];
            label.translatesAutoresizingMaskIntoConstraints = NO;
            label.numberOfLines = 5;
            label.lineBreakMode = NSLineBreakByTruncatingTail;
            label.font = [WPFontManager openSansRegularFontOfSize:16.0];
            label.backgroundColor = [UIColor whiteColor];
            
            [self.stackView addArrangedSubview:label];
            
            [label setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
            [label setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
            
            self.label = label;
        }
        {
            UIImageView *iconView = [[UIImageView alloc] init];
            iconView.translatesAutoresizingMaskIntoConstraints = NO;
            iconView.contentMode = UIViewContentModeScaleAspectFit;
            iconView.backgroundColor = [UIColor clearColor];
            iconView.tintColor = [WPStyleGuide mediumBlue];
            iconView.image = [[UIImage imageNamed:@"icon-menus-arrow"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            iconView.transform = CGAffineTransformMakeRotation(M_PI);
            
            [self.stackView addArrangedSubview:iconView];
            
            NSLayoutConstraint *widthConstraint = [iconView.widthAnchor constraintEqualToConstant:14.0];
            widthConstraint.priority = 999;
            widthConstraint.active = YES;
            
            self.arrowView = iconView;
        }
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tellDelegateTypeWasSelected)];
        [self addGestureRecognizer:tap];
    }
    
    return self;
}

- (void)setHidden:(BOOL)hidden
{
    [super setHidden:hidden];
    [self setNeedsDisplay];
}

- (void)setItemType:(MenuItemType)itemType
{
    if(_itemType != itemType) {
        _itemType = itemType;
        [self updatedItemType];
    }
}

- (void)setDrawsSelected:(BOOL)drawsSelected
{
    if(_drawsSelected != drawsSelected) {
        _drawsSelected = drawsSelected;
        [self updateSelection];
    }
}

- (void)updatedItemType
{
    self.label.text = [self title];
    self.iconView.image = [[UIImage imageNamed:[self iconImageName]] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [self updateSelection];

    [self setNeedsLayout];
    [self setNeedsDisplay];
}

- (void)updateSelection
{
    self.label.textColor = self.drawsSelected ? [WPStyleGuide mediumBlue] : [WPStyleGuide greyDarken30];
    if(self.drawsSelected && !(self.delegate && [self.delegate typeViewRequiresCompactLayout:self])) {
        self.arrowView.hidden = NO;
    }else {
        self.arrowView.hidden = YES;
    }
    
    [self setNeedsLayout];
    [self setNeedsDisplay];
}

- (NSString *)title
{
    NSString *title = nil;
    switch (self.itemType) {
        case MenuItemTypePage:
            title = NSLocalizedString(@"Page", @"");
            break;
        case MenuItemTypeLink:
            title = NSLocalizedString(@"Link", @"");
            break;
        case MenuItemTypeCategory:
            title = NSLocalizedString(@"Category", @"");
            break;
        case MenuItemTypeTag:
            title = NSLocalizedString(@"Tag", @"");
            break;
        case MenuItemTypePost:
            title = NSLocalizedString(@"Post", @"");
            break;
        default:
            break;
    }
    
    return title;
}

- (NSString*)iconImageName
{
    NSString *icon = nil;
    icon = @"icon-menus-document";
    return icon;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];
    [self updateSelection];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect
{
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    
    CGContextSetLineWidth(context, 2.0);
    CGContextSetStrokeColorWithColor(context, [[WPStyleGuide greyLighten30] CGColor]);
    
    if(self.drawsSelected) {
        
        if(!self.designIgnoresDrawingTopBorder) {
            CGContextMoveToPoint(context, 0, 0);
            CGContextAddLineToPoint(context, rect.size.width, 0);
        }
        
        CGContextMoveToPoint(context, 0, rect.size.height);
        CGContextAddLineToPoint(context, rect.size.width, rect.size.height);
        CGContextStrokePath(context);

    }else {
        
        CGContextMoveToPoint(context, rect.size.width, 0);
        CGContextAddLineToPoint(context, rect.size.width, rect.size.height);
        CGContextStrokePath(context);
    }
    
    CGContextRestoreGState(context);
}

#pragma mark - delegate

- (void)tellDelegateTypeWasSelected
{
    [self.delegate typeViewPressedForSelection:self];
}

@end
