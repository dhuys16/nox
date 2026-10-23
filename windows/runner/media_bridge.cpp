#include "media_bridge.h"

#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Media.Control.h>
#include <winrt/Windows.Storage.Streams.h>
#include <algorithm>
#include <stdexcept>
#include <utility>
#include <vector>

using namespace winrt::Windows::Media::Control;
using namespace winrt::Windows::Storage::Streams;
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;

MediaBridge::MediaBridge(HWND hwnd, flutter::BinaryMessenger* messenger)
    : hwnd_(hwnd) {
  channel_ = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "dev.notch/windows", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "windowHandle") {
      result->Success(Value(static_cast<int64_t>(reinterpret_cast<intptr_t>(hwnd_))));
      return;
    }
    if (call.method_name() != "mediaSnapshot" && call.method_name() != "mediaCommand") {
      result->NotImplemented();
      return;
    }
    std::string action;
    if (call.method_name() == "mediaCommand") {
      const auto* arg = call.arguments();
      const auto* text = arg ? std::get_if<std::string>(arg) : nullptr;
      if (!text || (*text != "play" && *text != "pause" &&
                    *text != "next" && *text != "previous")) {
        result->Error("invalid_command", "Expected play, pause, next or previous.");
        return;
      }
      action = *text;
    }
    {
      std::lock_guard<std::mutex> lock(mutex_);
      if (stopping_ || work_.size() >= 8) {
        result->Error("busy", "Media worker is unavailable.");
        return;
      }
      work_.push_back(Work{call.method_name(), action, std::move(result)});
    }
    wake_.notify_one();
  });
  worker_ = std::thread([this] { Run(); });
}

MediaBridge::~MediaBridge() {
  channel_->SetMethodCallHandler(nullptr);
  {
    std::lock_guard<std::mutex> lock(mutex_);
    stopping_ = true;
    work_.clear();
  }
  wake_.notify_one();
  if (worker_.joinable()) worker_.join();
  // Engine is still alive here. Resolve any completed requests on this thread.
  DrainReplies();
}

void MediaBridge::DrainReplies() {
  std::deque<Reply> replies;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    replies.swap(replies_);
  }
  for (auto& reply : replies) {
    if (reply.error.empty()) reply.result->Success(reply.value);
    else reply.result->Error("windows_media", reply.error);
  }
}

void MediaBridge::Run() {
  bool initialized = false;
  std::string startup_error;
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    initialized = true;
  } catch (const winrt::hresult_error& e) {
    startup_error = winrt::to_string(e.message());
  }
  GlobalSystemMediaTransportControlsSessionManager manager{nullptr};
  GlobalSystemMediaTransportControlsSession previous_session{nullptr};
  std::string artwork_key;
  std::vector<uint8_t> artwork;
  while (true) {
    Work task;
    {
      std::unique_lock<std::mutex> lock(mutex_);
      wake_.wait(lock, [this] { return stopping_ || !work_.empty(); });
      if (stopping_) break;
      task = std::move(work_.front());
      work_.pop_front();
    }
    Reply reply{std::move(task.result), Value(), {}};
    try {
      if (!initialized) throw std::runtime_error(startup_error);
      if (!manager) manager = GlobalSystemMediaTransportControlsSessionManager::RequestAsync().get();
      auto session = manager.GetCurrentSession();
      if (!session) {
        previous_session = nullptr;
        artwork.clear(); artwork_key.clear();
        reply.value = task.method == "mediaSnapshot" ? Value(Map{}) : Value(false);
      } else if (task.method == "mediaCommand") {
        bool accepted = false;
        if (task.action == "play") accepted = session.TryPlayAsync().get();
        else if (task.action == "pause") accepted = session.TryPauseAsync().get();
        else if (task.action == "next") accepted = session.TrySkipNextAsync().get();
        else if (task.action == "previous") accepted = session.TrySkipPreviousAsync().get();
        reply.value = Value(accepted);
      } else {
        auto properties = session.TryGetMediaPropertiesAsync().get();
        auto info = session.GetPlaybackInfo();
        auto controls = info.Controls();
        const auto title = winrt::to_string(properties.Title());
        const auto artist = winrt::to_string(properties.Artist());
        const auto key = winrt::to_string(session.SourceAppUserModelId()) + "\n" +
            title + "\n" + artist + "\n" + winrt::to_string(properties.AlbumTitle());
        if (session != previous_session || key != artwork_key) {
          artwork.clear();
          // Artwork is optional: a broken image must not hide transport controls.
          try {
            const auto thumbnail = properties.Thumbnail();
            if (thumbnail) {
              auto stream = thumbnail.OpenReadAsync().get();
              constexpr uint64_t kMaximumArtworkBytes = 8 * 1024 * 1024;
              if (stream.Size() > 0 && stream.Size() <= kMaximumArtworkBytes) {
                auto reader = DataReader(stream.GetInputStreamAt(0));
                auto count = reader.LoadAsync(static_cast<uint32_t>(stream.Size())).get();
                artwork.resize(count);
                reader.ReadBytes(winrt::array_view<uint8_t>(artwork));
              }
            }
          } catch (const winrt::hresult_error&) { artwork.clear(); }
          previous_session = session;
          artwork_key = key;
        }
        Map data;
        data[Value("title")] = Value(title);
        data[Value("artist")] = Value(artist);
        data[Value("playing")] = Value(info.PlaybackStatus() == GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing);
        data[Value("canPlay")] = Value(controls.IsPlayEnabled());
        data[Value("canPause")] = Value(controls.IsPauseEnabled());
        data[Value("canNext")] = Value(controls.IsNextEnabled());
        data[Value("canPrevious")] = Value(controls.IsPreviousEnabled());
        if (!artwork.empty()) data[Value("artwork")] = Value(artwork);
        reply.value = Value(std::move(data));
      }
    } catch (const winrt::hresult_error& e) {
      reply.error = winrt::to_string(e.message());
      // A disconnected player or revoked manager can be rediscovered next poll.
      manager = nullptr;
      previous_session = nullptr;
    } catch (const std::exception& e) {
      reply.error = e.what();
    }
    {
      std::lock_guard<std::mutex> lock(mutex_);
      replies_.push_back(std::move(reply));
    }
    PostMessage(hwnd_, kReplyMessage, 0, 0);
  }
  manager = nullptr;
  previous_session = nullptr;
  if (initialized) winrt::uninit_apartment();
}
