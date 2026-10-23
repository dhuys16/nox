#ifndef RUNNER_MEDIA_BRIDGE_H_
#define RUNNER_MEDIA_BRIDGE_H_

#include <windows.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <condition_variable>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

// All WinRT waits run on a dedicated MTA. Replies are marshalled back to the
// platform thread through a window message; Flutter's messenger is never called
// from the worker. Shutdown joins the worker before destroying its owner.
class MediaBridge {
 public:
  static constexpr UINT kReplyMessage = WM_APP + 71;
  MediaBridge(HWND hwnd, flutter::BinaryMessenger* messenger);
  ~MediaBridge();
  void DrainReplies();

 private:
  using Value = flutter::EncodableValue;
  using Result = flutter::MethodResult<Value>;
  struct Work {
    std::string method;
    std::string action;
    std::unique_ptr<Result> result;
  };
  struct Reply {
    std::unique_ptr<Result> result;
    Value value;
    std::string error;
  };
  void Run();
  HWND hwnd_;
  std::unique_ptr<flutter::MethodChannel<Value>> channel_;
  std::thread worker_;
  std::mutex mutex_;
  std::condition_variable wake_;
  bool stopping_ = false;
  std::deque<Work> work_;
  std::deque<Reply> replies_;
};
#endif
