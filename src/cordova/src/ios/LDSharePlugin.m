#import "LDSharePlugin.h"
@import Social;
@import Accounts;

static NSDictionary * errorToDic(NSError * error)
{
    return @{@"code":[NSNumber numberWithInteger:error.code], @"message":error.localizedDescription};
}

@implementation LDSharePlugin
{
    
}

- (void)pluginInitialize
{
}

-(void) share:(NSString *) text image:(UIImage*) image activityType: (NSString*) socialMedia url:(NSString*) url callbackId:(NSString*) callbackId
{
    NSMutableArray *items = [NSMutableArray new];
    [items addObject:text];
    if (image) {
        [items addObject:image];
    }
    else if (url)
    {
        NSURL *formattedUrl = [NSURL URLWithString:[NSString stringWithFormat:@"%@", url]];
        [items addObject:formattedUrl];
    }
    UIActivityViewController * activityController = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    
    NSMutableArray *exclusions = [NSMutableArray arrayWithObjects:
                                  UIActivityTypePostToFacebook,
                                  UIActivityTypePostToTwitter,
                                  UIActivityTypePostToWeibo,
                                  UIActivityTypeMessage,
                                  UIActivityTypeMail,
                                  UIActivityTypePrint,
                                  UIActivityTypeCopyToPasteboard,
                                  UIActivityTypeAssignToContact,
                                  UIActivityTypeSaveToCameraRoll,
                                  UIActivityTypeAddToReadingList,
                                  UIActivityTypePostToFlickr,
                                  UIActivityTypePostToVimeo,
                                  UIActivityTypePostToTencentWeibo,
                                  UIActivityTypeAirDrop, nil, nil];

    NSString* includeSpecificActivity;
    if([socialMedia  isEqualToString: @"facebook"]) {
        includeSpecificActivity = UIActivityTypePostToFacebook;
    }
    
    [exclusions removeObject:includeSpecificActivity];
    
    // Exclude activities that are irrelevant
    activityController.excludedActivityTypes = exclusions;
    
    if ([activityController respondsToSelector:@selector(completionWithItemsHandler)]) {
        activityController.completionWithItemsHandler = ^(NSString *activityType, BOOL completed, NSArray *returnedItems, NSError *error) {
            // When completed flag is YES, user performed specific activity
            
            NSMutableArray * array = [NSMutableArray arrayWithObjects:activityType?:@"", [NSNumber numberWithBool:completed],nil];
            if (error) {
                [array addObject:errorToDic(error)];
            }
            
            CDVPluginResult * result = [CDVPluginResult resultWithStatus:error ? CDVCommandStatus_ERROR : CDVCommandStatus_OK messageAsArray:array];
            [self.commandDelegate sendPluginResult:result callbackId:callbackId];
        };
    } else {
        activityController.completionHandler = ^(NSString *activityType, BOOL completed) {
            CDVPluginResult * result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:@[activityType?:@"", [NSNumber numberWithBool:completed]]];
            [self.commandDelegate sendPluginResult:result callbackId:callbackId];
        };
    }
    
    [self.viewController presentViewController:activityController animated:YES completion:nil];
    
    //iPad compatibility
    if ([activityController respondsToSelector:@selector(popoverPresentationController)]) {
        UIPopoverPresentationController * pop = activityController.popoverPresentationController;
        if (pop) {
            pop.sourceView = self.viewController.view;
        }
    }

}

-(UIImage*)getImage: (NSString *)imageName {
    UIImage *image = nil;
    if (imageName) {
        if ([imageName hasPrefix:@"http"]) {
            image = [UIImage imageWithData:[NSData dataWithContentsOfURL:[NSURL URLWithString:imageName]]];
        } else if ([imageName hasPrefix:@"www/"]) {
            image = [UIImage imageNamed:imageName];
        } else if ([imageName hasPrefix:@"file://"]) {
            image = [UIImage imageWithData:[NSData dataWithContentsOfFile:[[NSURL URLWithString:imageName] path]]];
        } else if ([imageName hasPrefix:@"data:"]) {
            // using a base64 encoded string
            NSURL *imageURL = [NSURL URLWithString:imageName];
            NSData *imageData = [NSData dataWithContentsOfURL:imageURL];
            image = [UIImage imageWithData:imageData];
        } else if ([imageName hasPrefix:@"assets-library://"]) {
            // use assets-library
            NSURL *imageURL = [NSURL URLWithString:imageName];
            NSData *imageData = [NSData dataWithContentsOfURL:imageURL];
            image = [UIImage imageWithData:imageData];
        } else {
            // assume anywhere else, on the local filesystem
            image = [UIImage imageWithData:[NSData dataWithContentsOfFile:imageName]];
        }
    }
    return image;
} 

-(void) jobInBackground:(CDVInvokedUrlCommand*) command
{
    NSDictionary * dic = [command argumentAtIndex:0 withDefault:@{} andClass:[NSDictionary class]];
    NSString * text = [dic objectForKey:@"message"];
    NSString * imageName = [dic objectForKey:@"image"];
    NSString * url = [dic objectForKey:@"url"];
    UIImage * image;
    NSString * socialMedia = [dic objectForKey:@"socialMedia"];
    
    if([socialMedia isEqualToString:@"twitter"]) {
        [self postImage: url message: text callbackId:command.callbackId];
    }
    else {
        image = [self getImage:imageName];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self share:text image:image activityType:socialMedia url: url callbackId:command.callbackId];
        });
    }
}

-(void)postImage:(NSString*) imageName message: (NSString*) message callbackId:(NSString*) callbackId {
    if(imageName == nil) return;
    NSURL *imageURL = [NSURL URLWithString:imageName];
    ACAccountStore *account = [[ACAccountStore alloc] init];
    ACAccountType *accountType = [account accountTypeWithAccountTypeIdentifier:
                                  ACAccountTypeIdentifierTwitter];
    
    [account requestAccessToAccountsWithType:accountType
                                     options:nil
                                  completion:^(BOOL granted, NSError *error)
    {
        if (granted == YES)
        {
            NSArray *arrayOfAccounts = [account
                                        accountsWithAccountType:accountType];
            
            if ([arrayOfAccounts count] > 0)
            {
                ACAccount *twitterAccount =
                [arrayOfAccounts lastObject];
                
                NSData *imageData = [NSData dataWithContentsOfURL:imageURL];
                NSURL *requestURL = [NSURL URLWithString:@"https://upload.twitter.com/1.1/media/upload.json"];
                
                SLRequest *postRequest = [SLRequest
                                          requestForServiceType:SLServiceTypeTwitter
                                          requestMethod:SLRequestMethodPOST
                                          URL:requestURL parameters:nil];
                                          
                                          postRequest.account = twitterAccount;
                                          [postRequest addMultipartData:imageData
                                                               withName:@"media"
                                                                   type:@"image/gif"
                                                               filename:@"test.gif"];
                
                [postRequest performRequestWithHandler:^(NSData *responseData, NSHTTPURLResponse *urlResponse, NSError *error)
                 {
                     if(error != nil) {
                         NSLog(@"Error thrown");
                     }
                     
                     
                     NSDictionary *json = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:nil];
                     NSString *mediaID = [json objectForKey:@"media_id_string"];
                     
                     NSURL *requestURL2 = [NSURL URLWithString:@"https://api.twitter.com/1.1/statuses/update.json"];
                     NSDictionary *message2 = @{@"status": @"Mustang Customizer",
                                                @"media_ids": mediaID };
                     
                     SLRequest *postRequest2 = [SLRequest
                                                requestForServiceType:SLServiceTypeTwitter
                                                requestMethod:SLRequestMethodPOST
                                                URL:requestURL2 parameters:message2];
                     postRequest2.account = twitterAccount;
                     
                     [postRequest2 performRequestWithHandler:^(NSData *responseData,
                                                               NSHTTPURLResponse *urlResponse, NSError *error) {
                         
                         
                         
                         NSString* errorResult;
                         if(error != nil) {
                             errorResult = @"Error thrown";
                         }
                         else {
                             errorResult = @"";
                         }

                         CDVPluginResult * result = [CDVPluginResult resultWithStatus:error ? CDVCommandStatus_ERROR : CDVCommandStatus_OK messageAsArray: @[@"TwitterShare", errorResult]];
                         [self.commandDelegate sendPluginResult:result callbackId:callbackId];
                         
                     }];
                 }];
            }
        }
    }];
}

-(void) share:(CDVInvokedUrlCommand*) command
{
    [self performSelectorInBackground:@selector(jobInBackground:) withObject:command];
}

@end

