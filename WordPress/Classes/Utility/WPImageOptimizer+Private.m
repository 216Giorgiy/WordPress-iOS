#import "WPImageOptimizer+Private.h"
#import "UIImage+Resize.h"
#import <ImageIO/ImageIO.h>

static const CGFloat CompressionQuality = 0.7;

@implementation WPImageOptimizer (Private)

- (NSData *)rawDataFromAssetRepresentation:(ALAssetRepresentation *)representation
                          stripGeoLocation:(BOOL) stripGeoLocation
{
    CGImageRef sourceImage = [self newImageFromAssetRepresentation:representation];
    NSDictionary *metadata = representation.metadata;
    NSString *type = representation.UTI;
    if (stripGeoLocation) {
        metadata = [self metadataWithoutLocation:metadata];
    }
    NSData *optimizedData = [self dataWithImage:sourceImage compressionQuality:1.0  type:type andMetadata:metadata];

    CGImageRelease(sourceImage);
    sourceImage = nil;

    return optimizedData;
}

- (NSData *)resizedDataFromAssetRepresentation:(ALAssetRepresentation *)representation
                                   fittingSize:(CGSize)targetSize
                              stripGeoLocation:(BOOL) stripGeoLocation
{
    CGImageRef sourceImage = [self newImageFromAssetRepresentation:representation];
    CGImageRef resizedImage = [self resizedImageWithImage:sourceImage scale:representation.scale orientation:representation.orientation fittingSize:targetSize];
    NSDictionary *metadata = [self metadataFromRepresentation:representation];
    if (stripGeoLocation) {
        metadata = [self metadataWithoutLocation:metadata];
    }
    NSString *type = representation.UTI;
    NSData *imageData = [self dataWithImage:resizedImage compressionQuality:CompressionQuality type:type andMetadata:metadata];

    CGImageRelease(sourceImage);
    sourceImage = nil;

    return imageData;
}

- (CGImageRef)newImageFromAssetRepresentation:(ALAssetRepresentation *)representation
{
    CGImageRef fullResolutionImage = CGImageRetain(representation.fullResolutionImage);
    NSString *adjustmentXMP = [representation.metadata objectForKey:@"AdjustmentXMP"];

    NSData *adjustmentXMPData = [adjustmentXMP dataUsingEncoding:NSUTF8StringEncoding];
    NSError *__autoreleasing error = nil;
    CGRect extend = CGRectZero;
    extend.size = representation.dimensions;
    NSArray *filters = nil;
    if (adjustmentXMPData) {
        filters = [CIFilter filterArrayFromSerializedXMP:adjustmentXMPData inputImageExtent:extend error:&error];
    }
    if (filters) {
        CIImage *image = [CIImage imageWithCGImage:fullResolutionImage];
        CIContext *context = [CIContext contextWithOptions:nil];
        for (CIFilter *filter in filters) {
            [filter setValue:image forKey:kCIInputImageKey];
            image = [filter outputImage];
        }

        CGImageRelease(fullResolutionImage);
        fullResolutionImage = [context createCGImage:image fromRect:image.extent];
    }
    return fullResolutionImage;
}

- (CGImageRef)resizedImageWithImage:(CGImageRef)image scale:(CGFloat)scale orientation:(UIImageOrientation)orientation fittingSize:(CGSize)targetSize
{
    UIImage *originalImage = [UIImage imageWithCGImage:image scale:scale orientation:orientation];
    CGSize originalSize = originalImage.size;
    CGSize newSize = [self sizeForOriginalSize:originalSize fittingSize:targetSize];
    UIImage *resizedImage = [originalImage resizedImageWithContentMode:UIViewContentModeScaleAspectFit
                                                                bounds:newSize
                                                  interpolationQuality:kCGInterpolationHigh];
    return resizedImage.CGImage;
}

- (CGSize)sizeForOriginalSize:(CGSize)originalSize fittingSize:(CGSize)targetSize
{
    CGFloat widthRatio = MIN(targetSize.width, originalSize.width) / originalSize.width;
    CGFloat heightRatio = MIN(targetSize.height, originalSize.height) / originalSize.height;
    CGFloat ratio = MIN(widthRatio, heightRatio);
    return CGSizeMake(round(ratio * originalSize.width), round(ratio * originalSize.height));
}

- (NSDictionary *)metadataFromRepresentation:(ALAssetRepresentation *)representation
{
    NSString * const orientationKey = @"Orientation";
    NSString * const xmpKey = @"AdjustmentXMP";

    NSMutableDictionary *metadata = [representation.metadata mutableCopy];

    // Remove XMP data since filters have already been applied to the image
    [metadata removeObjectForKey:xmpKey];

    // Remove rotation data, since the image is already rotated
    [metadata removeObjectForKey:orientationKey];

    if (metadata[(NSString *)kCGImagePropertyTIFFDictionary]) {
        NSMutableDictionary *tiffMetadata = [metadata[(NSString *)kCGImagePropertyTIFFDictionary] mutableCopy];
        tiffMetadata[(NSString *)kCGImagePropertyTIFFOrientation] = @1;
        metadata[(NSString *)kCGImagePropertyTIFFDictionary] = [NSDictionary dictionaryWithDictionary:tiffMetadata];
    }

    return [NSDictionary dictionaryWithDictionary:metadata];
}

- (NSData *)dataWithImage:(CGImageRef)image
       compressionQuality:(CGFloat)quality 
                     type:(NSString *)type
              andMetadata:(NSDictionary *)metadata
{
    NSMutableData *destinationData = [NSMutableData data];

    NSDictionary *properties = @{(__bridge NSString *)kCGImageDestinationLossyCompressionQuality: @(quality)};

    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)destinationData, (__bridge CFStringRef)type, 1, NULL);
    CGImageDestinationSetProperties(destination, (__bridge CFDictionaryRef)properties);
    CGImageDestinationAddImage(destination, image, (__bridge CFDictionaryRef) metadata);
    if (!CGImageDestinationFinalize(destination)) {
        DDLogError(@"Image destination couldn't be written");
    }
    CFRelease(destination);

    return [NSData dataWithData:destinationData];
}

- (NSDictionary *) metadataWithoutLocation:(NSDictionary *) originalMetadata
{
    if (!originalMetadata[(NSString *)kCGImagePropertyGPSDictionary]) {
        return originalMetadata;
    }
    NSMutableDictionary * metadata = [NSMutableDictionary dictionaryWithDictionary:originalMetadata];
    [metadata removeObjectForKey:(NSString *)kCGImagePropertyGPSDictionary];
    return [NSDictionary dictionaryWithDictionary:metadata];
}

@end
