#import "PdfRenderPlugin.h"
#import <pdf_render/pdf_render-Swift.h>

@implementation PdfRenderPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftPdfRenderPlugin registerWithRegistrar:registrar];
}
@end
