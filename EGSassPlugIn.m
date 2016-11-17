//
//  EGSassPlugIn.m
//  Sass
//
//  Created by Ryan Krug on 2/16/14.
//
//

#import "EGSassPlugIn.h"
#import "EGPreferencesController.h"
#import "CodaPlugInsController.h"

#include <glob.h>
#include "libsass/sass_interface.h"

@interface ERSassPlugIn ()
@property (nonatomic, strong) CodaPlugInsController *controller;
@property (nonatomic, strong) NSObject<CodaPlugInBundle> *plugInBundle;
@property (nonatomic, strong) EGPreferencesController *preferencesController;
@end

@implementation ERSassPlugIn

- (instancetype)initWithPlugInController:(CodaPlugInsController*)aController
                            plugInBundle:(NSObject <CodaPlugInBundle> *)aPlugInBundle
{
    self = [super init];
    
    if (!self) {
        return nil;
    }
    
    _controller = aController;
    _plugInBundle = aPlugInBundle;
    
    [_controller registerActionWithTitle:@"Sass Preferences…"
                                  target:self
                                selector:@selector(openSassPreferences:)];
    
    return self;
}

#pragma mark - CodaPlugIn

- (NSString*)name
{
	return @"Sass";
}

- (void)textViewDidSave:(CodaTextView*)textView
{
    NSString *file = [textView path];
    if ([self isFileScss:file]) {
        for (NSString* scssFile in [self scssFilesForScssFile:file withSearchPath:[_controller siteLocalPath]]) {
            [self generateCssForScssFile:scssFile];
        }
    }
}

#pragma mark - UI

- (void)openSassPreferences:(id)sender
{
    if (!self.preferencesController) {
        self.preferencesController = [[EGPreferencesController alloc] init];
    }
    [self.preferencesController showWindow:self];
}

#pragma mark - libsass

- (BOOL)isFileScss:(NSString*)file
{
    NSString *fileExtension = [[file pathExtension] lowercaseString];

	return [fileExtension isEqualToString:@"scss"] || [fileExtension isEqualToString:@"sass"];
}

- (BOOL)isScssFileScssPartial:(NSString*)scssFile
{
	return [[scssFile lastPathComponent] hasPrefix:@"_"];
}

- (NSArray*)scssFilesForSccsRootDirectory:(NSString*) rootDirectory
{
	NSMutableArray* files = [[NSMutableArray alloc] init];
	NSRegularExpression* isSassFile = [NSRegularExpression regularExpressionWithPattern:@"^[^_]*.s[ca]ss$" options:NSRegularExpressionCaseInsensitive error:nil];
	// http://stackoverflow.com/questions/5749488/iterating-through-files-in-a-folder-with-nested-folders-cocoa
	NSFileManager *fileManager = [NSFileManager defaultManager];
	NSURL *directoryURL = [NSURL fileURLWithPath:rootDirectory isDirectory:YES]; // URL pointing to the directory you want to browse
	NSArray *keys = [NSArray arrayWithObject:NSURLIsDirectoryKey];
	
	NSDirectoryEnumerator *enumerator = [fileManager
										 enumeratorAtURL:directoryURL
										 includingPropertiesForKeys:keys
										 options:0
										 errorHandler:^(NSURL *url, NSError *error) {
											 // Handle the error.
											 // Return YES if the enumeration should continue after the error.
											 return YES;
										 }];
	
	for (NSURL *url in enumerator) {
		NSError *error;
		NSNumber *isDirectory = nil;
		if (! [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:&error]) {
			// handle error
		}
		else if (! [isDirectory boolValue]) {
			// No error and it’s not a directory; do something with the file
			NSString *fileName = [[url absoluteString] lastPathComponent];
			
			if([isSassFile numberOfMatchesInString:fileName options:0 range:NSMakeRange(0, [fileName length])] ) {
				[files addObject:[url path]];
			}
		}
	}
	
	return files;
}

- (NSArray*)scssFilesForScssDirectory:(NSString*)scssDirectory
{
	NSString *pattern = @"[!_]*.s[ca]ss";
	NSString *fullPattern = [scssDirectory stringByAppendingPathComponent:pattern];
    
	glob_t gt;
	const char *cPattern = [fullPattern UTF8String];
	NSMutableArray *paths = [NSMutableArray array];
	if (glob(cPattern, GLOB_NOSORT, NULL, &gt) == 0) {
		for (int i = 0; i < gt.gl_matchc; i++) {
			[paths addObject:[NSString stringWithUTF8String:gt.gl_pathv[i]]];
		}
	}
	globfree(&gt);
	
	if ([paths count] == 0 && [[scssDirectory pathComponents] count] > 1) {
		return [self scssFilesForScssDirectory:[scssDirectory stringByDeletingLastPathComponent]];
	}
	
	return paths;
}

- (NSArray*)scssFilesForScssFile:(NSString*)scssFile withSearchPath:(NSString*) searchPath;
{
	if (![self isScssFileScssPartial:scssFile]) {
		return [NSArray arrayWithObject:scssFile];
	}
	
	if(searchPath) {
		return [self scssFilesForSccsRootDirectory:searchPath];
	}
	
	return [self scssFilesForScssDirectory:[scssFile stringByDeletingLastPathComponent]];
}

- (NSString*)cssDirectoryForScssDirectory:(NSString*)scssDirectory
{
	NSString *pattern = @"{css,styles,stylesheets,style}";
	NSString *fullPattern = [scssDirectory stringByAppendingPathComponent:pattern];
	
	glob_t gt;
	const char *cPattern = [fullPattern UTF8String];
	NSString *cssDirectory = nil;
	if (glob(cPattern, GLOB_BRACE|GLOB_NOSORT, NULL, &gt) == 0) {
		for (int i = 0; i < gt.gl_matchc; i++) {
			cssDirectory = [NSString stringWithUTF8String:gt.gl_pathv[i]];
			break;
		}
	}
	globfree(&gt);
	
	if (cssDirectory == nil && [[scssDirectory pathComponents] count] > 1) {
		return [self cssDirectoryForScssDirectory:[scssDirectory stringByDeletingLastPathComponent]];
	}
	
	return cssDirectory;
}

- (NSString*)cssFileForScssFile:(NSString*)scssFile
{
	NSString *dir = [scssFile stringByDeletingLastPathComponent];
	NSString *scssFileName = [scssFile lastPathComponent];
    NSString *scssFileExtension = [scssFileName pathExtension];
	
	NSString *cssFileName = [scssFileName stringByReplacingOccurrencesOfString:scssFileExtension
																	withString:@"css"
																	   options:NSCaseInsensitiveSearch
																		 range:NSMakeRange(0, [scssFileName length])];
	
	NSString *cssFile = [dir stringByAppendingPathComponent:cssFileName];
	
	if (![[NSFileManager defaultManager] fileExistsAtPath:cssFile]) {
		NSString *cssDirectory = [self cssDirectoryForScssDirectory:dir];
		
		if (cssDirectory != nil) {
			cssFile = [cssDirectory stringByAppendingPathComponent:cssFileName];
		}
	}
	
	return cssFile;
}


- (void)generateCssForScssFile:(NSString*)scssFile
{
	if (scssFile == nil) {
		return;
	}
	
	NSString *cssFile = [self cssFileForScssFile:scssFile];
	if (cssFile == nil) {
		return;
	}
    
	NSString *mapFile = [[cssFile stringByDeletingPathExtension] stringByAppendingPathExtension:@"map"];

    struct sass_options options = { 0 };
	
	NSInteger outputStyle = [[NSUserDefaults standardUserDefaults] integerForKey:EG_PREF_OUTPUT_STYLE];
	options.output_style = outputStyle;

	NSInteger debugStyle = [[NSUserDefaults standardUserDefaults] integerForKey:EG_PREF_DEBUG_STYLE];
    
    if (debugStyle == EG_SASS_SOURCE_COMMENTS_DEBUG) {
        options.source_comments = true;
        options.omit_source_map_url = true;
    }
    else if (debugStyle == EG_SASS_SOURCE_COMMENTS_MAP) {
        options.source_comments = false;
        options.omit_source_map_url = false;
        options.source_map_file = (char*)[mapFile UTF8String];
    }
    else {
        options.source_comments = false;
        options.omit_source_map_url = true;
    }
    
	options.include_paths = [[self.plugInBundle.resourcePath stringByAppendingPathComponent:@"scss"] UTF8String];
    
	struct sass_file_context *ctx = sass_new_file_context();
	
	ctx->options = options;
	ctx->input_path = [scssFile UTF8String];
	
	sass_compile_file(ctx);
	
	if (ctx->error_status) {
		NSString *error = [NSString stringWithUTF8String:ctx->error_message];
		NSAlert *alert = [NSAlert alertWithMessageText:@"Sass could not be completed."
										 defaultButton:@"OK"
									   alternateButton:nil
										   otherButton:nil
							 informativeTextWithFormat:@"%@", error];
		[alert runModal];
	}
	
	if (!ctx->error_status && ctx->output_string) {
		NSString *cssResult = [NSString stringWithUTF8String:ctx->output_string];
		[cssResult writeToFile:cssFile atomically:YES encoding:NSUTF8StringEncoding error:NULL];
		
		if (ctx->source_map_string) {
			NSString *mapResult = [NSString stringWithUTF8String:ctx->source_map_string];
			[mapResult writeToFile:mapFile atomically:YES encoding:NSUTF8StringEncoding error:NULL];
		}
	}
	
	sass_free_file_context(ctx);
}

@end
