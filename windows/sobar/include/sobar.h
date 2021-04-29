//
// sobar; simple pdfium wrapper
//
// (C) Takashi Kawasaki (@espresso3389)
// https://github.com/espresso3389/sobar_pdf

#ifndef _sobar_pdf_h_
#define _sobar_pdf_h_

#include <stddef.h>

#ifdef __cplusplus
extern "C"
{
#endif

#if defined(_WIN32)
//
// For Windows (Win32/Win64)
//
#define sbr_API __stdcall
#define sbr_EXPORT
#else
//
// For UNIX platforms using gcc/clang
//
#define sbr_API
#ifdef sbr_BUILD_LIBRARY
#define sbr_EXPORT __attribute__((visibility("default")))
#else
#define sbr_EXPORT
#endif
#endif

#ifndef sbr_BUILD_LIBRARY
	typedef struct sbr_PdfDocumentStruct *sbr_PdfDocument;
	typedef struct sbr_PdfPageStruct *sbr_PdfPage;
	typedef struct sbr_PdfBitmapStruct *sbr_PdfBitmap;
#endif

	sbr_EXPORT void sbr_API sbr_Initialize();
	sbr_EXPORT void sbr_API sbr_Finalize();

	sbr_EXPORT sbr_PdfDocument sbr_API sbr_PdfDocumentOpenFile(
		const char *utf8FileName, const char *utf8Password);
	sbr_EXPORT sbr_PdfDocument sbr_API sbr_PdfDocumentOpenMemory(
		const void *data, unsigned int size, const char *utf8Password);

	typedef unsigned int (*sbr_ContextReadCallback)(void *context, void *buffer, unsigned int offset, unsigned int length);
	typedef void (*sbr_ContextReleaseCallback)(void *context);

	sbr_EXPORT sbr_PdfDocument sbr_API sbr_PdfDocumentOpenCustom(
		void *context, unsigned int size, sbr_ContextReadCallback read, sbr_ContextReleaseCallback release, const char *utf8Password);
	sbr_EXPORT void sbr_API sbr_PdfDocumentClose(sbr_PdfDocument doc);
	sbr_EXPORT int sbr_API sbr_PdfDocumentGetPageCount(sbr_PdfDocument doc);
	sbr_EXPORT sbr_PdfPage sbr_API sbr_PdfDocumentLoadPage(sbr_PdfDocument doc, int pageIndex);

	sbr_EXPORT void sbr_API sbr_PdfPageClose(sbr_PdfPage page);
	sbr_EXPORT double sbr_API sbr_PdfPageGetWidth(sbr_PdfPage page);
	sbr_EXPORT double sbr_API sbr_PdfPageGetHeight(sbr_PdfPage page);
	sbr_EXPORT int sbr_API sbr_PdfPageGetRotation(sbr_PdfPage page);

	enum sbr_PixelFormat
	{
		sbr_PixelFormat_invalid = 0,
		sbr_PixelFormat_gray,
		sbr_PixelFormat_bgr,
		sbr_PixelFormat_bgra,
		sbr_PixelFormat_rgb,
		sbr_PixelFormat_rgba
	};

	typedef void (*sbr_PdfBitmapOnReleaseCallback)(void *context);

	enum sbr_RotateClockwise
	{
		sbr_RotateClockwise_0 = 0,	 // normal
		sbr_RotateClockwise_90 = 1,	 // 90 degree clockwise
		sbr_RotateClockwise_180 = 2, // 180 degree
		sbr_RotateClockwise_270 = 3, // 270 degree clockwise
	};

	// Page rendering flags. They can be combined with bit-wise OR.
	enum sbr_RenderFlags : unsigned int
	{
		// Set if annotations are to be rendered.
		sbr_rfAnnot = 1,
		// Set if using text rendering optimized for LCD display.
		sbr_rfTextLCD = 2,
		// Don't use the native text output available on some platforms
		sbr_rfNoNativeTextRendering = 4,
		// Grayscale output.
		sbr_rfGrayscale = 8,
		// Set if you want to get some debug info.
		sbr_rfDebug = 0x80,
		// Set if you don't want to catch exceptions.
		sbr_rfNoCatch = 0x100,
		// Limit image cache size.
		sbr_rfLimitedCache = 0x200,
		// Always use halftone for image stretching.
		sbr_rfHalfTone = 0x400,
		// Render for printing.
		sbr_rfForPrinting = 0x800,
		// Set to disable anti-aliasing on text.
		sbr_rfNoSmoothText = 0x1000,
		// Set to disable anti-aliasing on images.
		sbr_rfNoSmoothImage = 0x2000,
		// Set to disable anti-aliasing on paths.
		sbr_rfNoSmoothPath = 0x4000,
		// Set whether to render in a reverse Byte order, this flag is only used when
		// rendering to a bitmap.
		sbr_rfReverseByteOrder = 0x10,
		// Don't white-fill before rendering actual image.
		sbr_rfNoWhiteFill = 0x20,
	};

	sbr_EXPORT int sbr_API sbr_PdfPageRender(
		sbr_PdfPage page,
		sbr_PdfBitmap bmp, int x, int y,
		int width, int height,
		sbr_RotateClockwise rotate,
		int flags);

	sbr_EXPORT sbr_PdfBitmap sbr_API sbr_PdfBitmapCreate(
		int width, int height, sbr_PixelFormat format, long stride, void *scan0,
		sbr_PdfBitmapOnReleaseCallback callback, void *context);
	sbr_EXPORT void sbr_API sbr_PdfBitmapRelease(sbr_PdfBitmap bmp);
	sbr_EXPORT sbr_PixelFormat sbr_API sbr_PdfBitmapGetPixelFormat(sbr_PdfBitmap bmp);
	sbr_EXPORT unsigned char *sbr_API sbr_PdfBitmapGetScan0Pointer(sbr_PdfBitmap bmp);
	sbr_EXPORT long sbr_API sbr_PdfBitmapGetStride(sbr_PdfBitmap bmp);
	sbr_EXPORT int sbr_API sbr_PdfBitmapGetWidth(sbr_PdfBitmap bmp);
	sbr_EXPORT int sbr_API sbr_PdfBitmapGetHeight(sbr_PdfBitmap bmp);

#ifdef __cplusplus
}
#endif

#endif // _sobar_pdf_h_
