#include "webview_cookie_manager.h"

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <memory>
#include <map>
#include <sstream>

namespace {

constexpr char kChannelName[] = "com.flutter.demo/native_cookie";

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;

void HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result);

void GetCookies(
    const std::string& url,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  
  result->Error(
      "NOT_IMPLEMENTED",
      "WebView2 SDK integration required. "
      "This feature needs Microsoft.Web.WebView2 NuGet package and WebView2 environment setup. "
      "For now, please use manual Cookie extraction method.");
}

void GetCookie(
    const std::string& url,
    const std::string& name,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  
  result->Error(
      "NOT_IMPLEMENTED",
      "WebView2 SDK integration required. Please use manual method.");
}

void HandleMethodCall(
    const flutter::MethodCall<EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  
  const std::string& method = method_call.method_name();
  
  if (method == "getCookies") {
    const auto* arguments = std::get_if<EncodableMap>(method_call.arguments());
    if (!arguments) {
      result->Error("INVALID_ARGUMENT", "Expected a map argument");
      return;
    }
    
    auto url_it = arguments->find(EncodableValue("url"));
    if (url_it == arguments->end()) {
      result->Error("INVALID_ARGUMENT", "Missing 'url' parameter");
      return;
    }
    
    const std::string* url = std::get_if<std::string>(&url_it->second);
    if (!url) {
      result->Error("INVALID_ARGUMENT", "'url' must be a string");
      return;
    }
    
    GetCookies(*url, std::move(result));
    
  } else if (method == "getCookie") {
    const auto* arguments = std::get_if<EncodableMap>(method_call.arguments());
    if (!arguments) {
      result->Error("INVALID_ARGUMENT", "Expected a map argument");
      return;
    }
    
    auto url_it = arguments->find(EncodableValue("url"));
    auto name_it = arguments->find(EncodableValue("name"));
    
    if (url_it == arguments->end() || name_it == arguments->end()) {
      result->Error("INVALID_ARGUMENT", "Missing 'url' or 'name' parameter");
      return;
    }
    
    const std::string* url = std::get_if<std::string>(&url_it->second);
    const std::string* name = std::get_if<std::string>(&name_it->second);
    
    if (!url || !name) {
      result->Error("INVALID_ARGUMENT", "Parameters must be strings");
      return;
    }
    
    GetCookie(*url, *name, std::move(result));
    
  } else {
    result->NotImplemented();
  }
}

}  // namespace

void WebviewCookieManagerPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar_ref) {
  
  flutter::PluginRegistrarWindows* registrar =
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar_ref);
  
  auto channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          registrar->messenger(),
          kChannelName,
          &flutter::StandardMethodCodec::GetInstance());

  channel->SetMethodCallHandler(
      [](const auto& call, auto result) {
        HandleMethodCall(call, std::move(result));
      });
}
