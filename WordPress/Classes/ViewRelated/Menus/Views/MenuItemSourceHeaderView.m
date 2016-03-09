#import "MenuItemSourceHeaderView.h"
#import "MenusDesign.h"
#import "WPStyleGuide.h"
#import "WPFontManager.h"

@interface MenuItemSourceHeaderView ()

@property (nonatomic, strong) UIStackView *stackView;
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *label;

@end

@implementation MenuItemSourceHeaderView

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
            
            NSLayoutConstraint *top = [stackView.topAnchor constraintEqualToAnchor:self.topAnchor constant:MenusDesignDefaultContentSpacing];
            top.priority = 999;
            
            NSLayoutConstraint *bottom = [stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-MenusDesignDefaultContentSpacing];
            bottom.priority = 999;
            
            [NSLayoutConstraint activateConstraints:@[
                                                      top,
                                                      [stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:MenusDesignDefaultContentSpacing],
                                                      bottom,
                                                      [stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-MenusDesignDefaultContentSpacing]
                                                      ]];
            [stackView setContentCompressionResistancePriority:999 forAxis:UILayoutConstraintAxisVertical];
            self.stackView = stackView;
        }
        {
            UIImageView *iconView = [[UIImageView alloc] init];
            iconView.translatesAutoresizingMaskIntoConstraints = NO;
            iconView.contentMode = UIViewContentModeScaleAspectFit;
            iconView.backgroundColor = [UIColor whiteColor];
            iconView.tintColor = [WPStyleGuide mediumBlue];
            iconView.image = [[UIImage imageNamed:@"icon-menus-arrow"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            
            [self.stackView addArrangedSubview:iconView];
            
            NSLayoutConstraint *widthConstraint = [iconView.widthAnchor constraintEqualToConstant:14.0];
            widthConstraint.active = YES;
                        
            self.iconView = iconView;
        }
        {
            UILabel *label = [[UILabel alloc] init];
            label.translatesAutoresizingMaskIntoConstraints = NO;
            label.numberOfLines = 1;
            label.lineBreakMode = NSLineBreakByTruncatingTail;
            label.font = [WPFontManager openSansRegularFontOfSize:16.0];
            label.backgroundColor = [UIColor whiteColor];
            
            [self.stackView addArrangedSubview:label];
            
            [label setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
            [label setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
            
            self.label = label;
        }
        
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapGesture:)];
        [self addGestureRecognizer:tap];
    }
    
    return self;
}

- (void)setItemType:(NSString *)itemType
{
    if(_itemType != itemType) {
        _itemType = itemType;
        self.label.text = itemType;
        [self.stackView layoutIfNeeded];
    }
}

- (void)tapGesture:(UITapGestureRecognizer *)tapGesture
{
    [self.delegate sourceHeaderViewSelected:self];
}

- (void)drawRect:(CGRect)rect
{    
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetLineWidth(context, 2.0);
    CGContextSetStrokeColorWithColor(context, [[WPStyleGuide greyLighten30] CGColor]);
    CGContextMoveToPoint(context, 0, rect.size.height);
    CGContextAddLineToPoint(context, rect.size.width, rect.size.height);
    CGContextStrokePath(context);
}

@end
