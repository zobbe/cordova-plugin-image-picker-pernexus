//
//  SOSPicker.m
//  SyncOnSet
//
//  Created by Christopher Sullivan on 10/25/13.
//
//

#import "SOSPicker.h"
#import "ELCAlbumPickerController.h"
#import "ELCImagePickerController.h"
#import "ELCAssetTablePicker.h"
#import <ImageIO/CGImageSource.h>
#import <ImageIO/CGImageProperties.h>
#import <ImageIO/CGImageDestination.h>
#import <objc/message.h>

#define CDV_PHOTO_PREFIX @"cdv_photo_"

@implementation SOSPicker

@synthesize callbackId;

- (void) getPictures:(CDVInvokedUrlCommand *)command {
    NSDictionary *options = [command.arguments objectAtIndex: 0];
    
    NSInteger maximumImagesCount = [[options objectForKey:@"maximumImagesCount"] integerValue];
    self.width = [[options objectForKey:@"width"] integerValue];
    self.height = [[options objectForKey:@"height"] integerValue];
    self.quality = [[options objectForKey:@"quality"] integerValue];
    
    // Create the an album controller and image picker
    ELCAlbumPickerController *albumController = [[ELCAlbumPickerController alloc] init];
    
    if (maximumImagesCount == 1) {
        albumController.immediateReturn = true;
        albumController.singleSelection = true;
    } else {
        albumController.immediateReturn = false;
        albumController.singleSelection = false;
    }
    
    ELCImagePickerController *imagePicker = [[ELCImagePickerController alloc] initWithRootViewController:albumController];
    imagePicker.maximumImagesCount = maximumImagesCount;
    imagePicker.returnsOriginalImage = 1;
    imagePicker.imagePickerDelegate = self;
    
    albumController.parent = imagePicker;
    self.callbackId = command.callbackId;
    // Present modally
    [self.viewController presentViewController:imagePicker
                                      animated:YES
                                    completion:nil];
}


- (void)elcImagePickerController:(ELCImagePickerController *)picker didFinishPickingMediaWithInfo:(NSArray *)info {
    __block CDVPluginResult* result = nil;
    NSMutableArray *resultStrings = [[NSMutableArray alloc] init];
    NSData* data = nil;
    NSString* docsPath = [NSTemporaryDirectory()stringByStandardizingPath];
    __block NSError* err = nil;
    NSFileManager* fileMgr = [[NSFileManager alloc] init];
    ALAsset* asset = nil;
    UIImageOrientation orientation = UIImageOrientationUp;;
    CGSize targetSize = CGSizeMake(self.width, self.height);
    __block int infoIndex = 0;
    __block NSString *jsonWithExif = nil;
    for (NSDictionary *dict in info) {
        asset = [dict objectForKey:@"ALAsset"];
        // From ELCImagePickerController.m
        
        @autoreleasepool {
            ALAssetRepresentation *assetRep = [asset defaultRepresentation];
            CGImageRef imgRef = NULL;
            
            //defaultRepresentation returns image as it appears in photo picker, rotated and sized,
            //so use UIImageOrientationUp when creating our image below.
            if (picker.returnsOriginalImage) {
                imgRef = [assetRep fullResolutionImage];
                orientation = [assetRep orientation];
            } else {
                imgRef = [assetRep fullScreenImage];
            }
            
            UIImage* image = [UIImage imageWithCGImage:imgRef scale:1.0f orientation:orientation];
            if (self.width == 0 && self.height == 0) {
                data = UIImageJPEGRepresentation(image, self.quality/100.0f);
            } else {
                UIImage* scaledImage = [self imageByScalingNotCroppingForSize:image toSize:targetSize];
                data = UIImageJPEGRepresentation(scaledImage, self.quality/100.0f);
            }
        
            // METADATA
            NSURL *assetURL = [dict objectForKey:UIImagePickerControllerReferenceURL];
            
            ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
            [library assetForURL:assetURL
                     resultBlock:^(ALAsset *asset)  {
                         NSString* filePath;
                         
                         int i = 1;
                         
                         do {
                             filePath = [NSString stringWithFormat:@"%@/%@%03d.%@", docsPath, CDV_PHOTO_PREFIX, i++, @"jpg"];
                         } while ([fileMgr fileExistsAtPath:filePath]);
                         
                         NSDictionary *metadata = asset.defaultRepresentation.metadata;
                         
                         self.metadata = [[NSMutableDictionary alloc] init];
                         
                         NSMutableDictionary *EXIFDictionary = [[metadata objectForKey:(NSString*)kCGImagePropertyExifDictionary]mutableCopy];
                         if (EXIFDictionary) {
                             [self.metadata setObject:EXIFDictionary forKey:(NSString*)kCGImagePropertyExifDictionary];
                         }
                         
                         
                         NSMutableDictionary *TIFFDictionary = [[metadata objectForKey:(NSString*)kCGImagePropertyTIFFDictionary]mutableCopy];
                         if (TIFFDictionary) {
                             [self.metadata setObject:TIFFDictionary forKey:(NSString*)kCGImagePropertyTIFFDictionary];
                         }
                         
                         
                         NSMutableDictionary *GPSDictionary = [[metadata objectForKey:(NSString*)kCGImagePropertyGPSDictionary]mutableCopy];
                         if (GPSDictionary)  {
                             [self.metadata setObject:GPSDictionary forKey:(NSString*)kCGImagePropertyGPSDictionary];
                         }
                         
                         
                         /*
                          
                          // this gets ALL image metadata, occasional errors converting this to JSON, so best to be selective
                          self.metadata = [[NSMutableDictionary alloc] initWithDictionary:metadata];
                          [self.metadata addEntriesFromDictionary:metadata];
                          
                          */
                         
                         NSError* error;
                         NSString* jsonString = nil;
                         bool ok;
                         
                         if (self.metadata){
                             
                             // add metadata to image that is written to temp file
                             
                             CGImageSourceRef sourceImage = CGImageSourceCreateWithData((__bridge_retained CFDataRef)data, NULL);
                             CFStringRef sourceType = CGImageSourceGetType(sourceImage);
                             
                             CGImageDestinationRef destinationImage = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, sourceType, 1, NULL);
                             CGImageDestinationAddImageFromSource(destinationImage, sourceImage, 0, (__bridge CFDictionaryRef)self.metadata);
                             
                             ok = CGImageDestinationFinalize(destinationImage);
                             
                            #ifdef __REM_CoreImage__
                             
                             if (ok) {
                                 CIImage *testImage = [CIImage imageWithData:data];
                                 NSDictionary *propDict = [testImage properties];
                                 NSLog(@"Image properties after adding metadata %@", propDict);
                             }
                            #endif
                             
                             CFRelease(sourceImage);
                             CFRelease(destinationImage);
                             
                             
                             NSData* jsonData = [NSJSONSerialization dataWithJSONObject:self.metadata
                                                                                options:0
                                                                                  error:&error];
                             
                             if (!jsonData){
                                 NSLog(@"Error converting to JSON: %@",error);
                                 jsonString = @"{}";
                             } else {
                                 jsonString = [[NSString alloc] initWithData: jsonData encoding:NSUTF8StringEncoding];
                             }
                             
                         } else {
                             jsonString = @"{}";
                         }
                         
                         NSMutableDictionary* thisResult = [[NSMutableDictionary alloc] init];
                         [thisResult setObject:[[self urlTransformer:[NSURL fileURLWithPath:filePath]]absoluteString] forKey:@"filename"];
                         [thisResult setObject: jsonString forKey:@"json_metadata"];
                         
                         NSError *jsonError = nil;
                         if ([NSJSONSerialization isValidJSONObject:thisResult]) {
                             NSData *thisJsonResult = [NSJSONSerialization dataWithJSONObject:thisResult options:0 error:&jsonError];
                             jsonWithExif = [[NSString alloc] initWithData:thisJsonResult encoding:NSUTF8StringEncoding];
                             NSLog(@"JSON with exif: %@",jsonWithExif);
                             infoIndex++;
                             NSLog(@"INDEXINFO: %i",infoIndex);
                             [resultStrings addObject:jsonWithExif];
                         }
                         
                         if (infoIndex >= info.count) {
                             NSLog(@"Went through all images");
                             result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:resultStrings];
                             [self.commandDelegate sendPluginResult:result callbackId:self.callbackId];
                         }
                         if (![data writeToFile:filePath options:NSAtomicWrite error:&err]) {
                             result = [CDVPluginResult resultWithStatus:CDVCommandStatus_IO_EXCEPTION messageAsString:[err localizedDescription]];
                         }

                     }
                    failureBlock:^(NSError *error) {
                    }];
        }
    
    }

    
    [self.viewController dismissViewControllerAnimated:YES completion:nil];

}

- (NSURL*) urlTransformer:(NSURL*)url
{
    NSURL* urlToTransform = url;
    
    // for backwards compatibility - we check if this property is there
    SEL sel = NSSelectorFromString(@"urlTransformer");
    if ([self.commandDelegate respondsToSelector:sel]) {
        // grab the block from the commandDelegate
        NSURL* (^urlTransformer)(NSURL*) = ((id(*)(id, SEL))objc_msgSend)(self.commandDelegate, sel);
        // if block is not null, we call it
        if (urlTransformer) {
            urlToTransform = urlTransformer(url);
        }
    }
    
    return urlToTransform;
}

- (void)elcImagePickerControllerDidCancel:(ELCImagePickerController *)picker {
    [self.viewController dismissViewControllerAnimated:YES completion:nil];
    CDVPluginResult* pluginResult = nil;
    NSArray* emptyArray = [NSArray array];
    pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:emptyArray];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:self.callbackId];
}

- (UIImage*)imageByScalingNotCroppingForSize:(UIImage*)anImage toSize:(CGSize)frameSize
{
    UIImage* sourceImage = anImage;
    UIImage* newImage = nil;
    CGSize imageSize = sourceImage.size;
    CGFloat width = imageSize.width;
    CGFloat height = imageSize.height;
    CGFloat targetWidth = frameSize.width;
    CGFloat targetHeight = frameSize.height;
    CGFloat scaleFactor = 0.0;
    CGSize scaledSize = frameSize;
    
    if (CGSizeEqualToSize(imageSize, frameSize) == NO) {
        CGFloat widthFactor = targetWidth / width;
        CGFloat heightFactor = targetHeight / height;
        
        // opposite comparison to imageByScalingAndCroppingForSize in order to contain the image within the given bounds
        if (widthFactor == 0.0) {
            scaleFactor = heightFactor;
        } else if (heightFactor == 0.0) {
            scaleFactor = widthFactor;
        } else if (widthFactor > heightFactor) {
            scaleFactor = heightFactor; // scale to fit height
        } else {
            scaleFactor = widthFactor; // scale to fit width
        }
        scaledSize = CGSizeMake(width * scaleFactor, height * scaleFactor);
    }
    
    UIGraphicsBeginImageContext(scaledSize); // this will resize
    
    [sourceImage drawInRect:CGRectMake(0, 0, scaledSize.width, scaledSize.height)];
    
    newImage = UIGraphicsGetImageFromCurrentImageContext();
    if (newImage == nil) {
        NSLog(@"could not scale image");
    }
    
    // pop the context to get back to the default
    UIGraphicsEndImageContext();
    return newImage;
}

@end
