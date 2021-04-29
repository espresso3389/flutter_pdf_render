#include "include/pdf_render/pdf_render_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>

// For getPlatformVersion; remove unless needed for your plugin implementation.
#include <VersionHelpers.h>

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include "sobar.h"

#include <map>
#include <memory>
#include <sstream>

namespace
{

  class PdfRenderPlugin : public flutter::Plugin
  {
  public:
    static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

    PdfRenderPlugin();

    virtual ~PdfRenderPlugin();

  private:
    // Called when a method is called on this plugin's channel from Dart.
    void HandleMethodCall(
        const flutter::MethodCall<flutter::EncodableValue> &method_call,
        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  };

  // static
  void PdfRenderPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarWindows *registrar)
  {
    auto channel =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "pdf_render",
            &flutter::StandardMethodCodec::GetInstance());

    auto plugin = std::make_unique<PdfRenderPlugin>();

    channel->SetMethodCallHandler(
        [plugin_pointer = plugin.get()](const auto &call, auto result) {
          plugin_pointer->HandleMethodCall(call, std::move(result));
        });

    registrar->AddPlugin(std::move(plugin));
  }

  PdfRenderPlugin::PdfRenderPlugin()
  {
    sbr_Initialize();
  }

  PdfRenderPlugin::~PdfRenderPlugin()
  {
    sbr_Finalize();
  }

  void PdfRenderPlugin::HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result)
  {
    if (method_call.method_name().compare("file") == 0)
    {
      result->Success(flutter::EncodableValue(reinterpret_cast<uint32_t>(sbr_PdfDocumentOpenFile())));
    }
    else if (method_call.method_name().compare("asset") == 0)
    {
      result->Success(flutter::EncodableValue(0));
    }
    else if (method_call.method_name().compare("data") == 0)
    {

      result->Success(flutter::EncodableValue(0));
    }
    else if (method_call.method_name().compare("close") == 0)
    {

      result->Success(flutter::EncodableValue(0));
    }
    else
    {
      result->NotImplemented();
    }
  }

} // namespace

void PdfRenderPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar)
{
  PdfRenderPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
