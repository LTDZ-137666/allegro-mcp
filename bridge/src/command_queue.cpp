// command_queue.cpp — 线程安全命令队列实现

#include "command_queue.h"

namespace allegro_bridge {

CommandQueue& CommandQueue::instance() {
    static CommandQueue queue;
    return queue;
}

bool CommandQueue::push_command(const Command& cmd) {
    std::lock_guard<std::mutex> lock(cmd_mutex_);
    if (commands_.size() >= MAX_QUEUE_SIZE) {
        return false; // 队列已满
    }
    commands_.push(cmd);
    return true;
}

std::optional<Command> CommandQueue::pop_command() {
    std::lock_guard<std::mutex> lock(cmd_mutex_);
    if (commands_.empty()) {
        return std::nullopt;
    }
    Command cmd = commands_.front();
    commands_.pop();
    return cmd;
}

size_t CommandQueue::pending_count() {
    std::lock_guard<std::mutex> lock(cmd_mutex_);
    return commands_.size();
}

void CommandQueue::put_response(int id, const std::string& json_result) {
    {
        std::lock_guard<std::mutex> lock(resp_mutex_);
        responses_[id] = json_result;
    }
    resp_cv_.notify_all();
}

std::optional<std::string> CommandQueue::wait_response(int id, int timeout_ms) {
    std::unique_lock<std::mutex> lock(resp_mutex_);
    auto exists = responses_.find(id) != responses_.end();
    if (!exists) {
        // 等待直到收到响应或超时
        resp_cv_.wait_for(lock, std::chrono::milliseconds(timeout_ms),
            [this, id] { return responses_.find(id) != responses_.end(); });
    }

    auto it = responses_.find(id);
    if (it != responses_.end()) {
        std::string result = it->second;
        responses_.erase(it);
        return result;
    }
    return std::nullopt; // 超时
}

void CommandQueue::set_client_connected(bool connected) {
    client_connected_ = connected;
}

void CommandQueue::clear() {
    {
        std::lock_guard<std::mutex> lock(cmd_mutex_);
        while (!commands_.empty()) commands_.pop();
    }
    {
        std::lock_guard<std::mutex> lock(resp_mutex_);
        responses_.clear();
    }
    resp_cv_.notify_all();
}

} // namespace allegro_bridge
