#import "WordPressXMLRPCAPIFacade.h"
#import <wpxmlrpc/WPXMLRPC.h>
#import "WordPress-Swift.h"


@interface WordPressXMLRPCAPIFacade ()


@end


@implementation WordPressXMLRPCAPIFacade

- (void)guessXMLRPCURLForSite:(NSString *)url
                      success:(void (^)(NSURL *xmlrpcURL))success
                      failure:(void (^)(NSError *error))failure
{
    WordPressOrgXMLRPCValidator *validator = [[WordPressOrgXMLRPCValidator alloc] init];
    [validator guessXMLRPCURLForSite:url success:success failure:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            failure(error);
        });
    }];
}

- (void)getBlogOptionsWithEndpoint:(NSURL *)xmlrpc
                         username:(NSString *)username
                         password:(NSString *)password
                          success:(void (^)(id options))success
                          failure:(void (^)(NSError *error))failure;
{
    
    WordPressOrgXMLRPCApi *api = [[WordPressOrgXMLRPCApi alloc] initWithEndpoint:xmlrpc userAgent:[WPUserAgent wordPressUserAgent]];
    [api checkCredentials:username password:password success:^(id responseObject, NSHTTPURLResponse *httpResponse) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                success(responseObject);
            }
        });

    } failure:^(NSError *error, NSHTTPURLResponse *httpResponse) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (failure) {
                failure(error);
            }
        });
    }];
}

@end
