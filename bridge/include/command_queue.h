// command_queue.h — 线程安全命令队列
// 生产者: TCP 服务器线程 (接收命令)
// 消费者: SKILL 主线程 (bridge_poll 取出命令, bridge_respond 返回结果)

#pragma once

#include <string>
#include <queue>
#include <mutex>
#include <condition_variable>
#include <optional>
#include <unordered_map>
#include <atomic>

namespace allegro_bridge {

struct Command {
    int id;
    std::string method;       // "call_function", "evalstring", "raw"
    std::string func_name;    // 函数名 (call_function mode)
    std::string params_json;  // 参数的 JSON 字符串
    std::string expression;   // 原始 SKILL 表达式 (evalstring/raw mode)
};

class CommandQueue {
public:
    static CommandQueue& instance();

    // === TCP 线程调用 ===

    // 将收到的命令放入队列
    bool push_command(const Command& cmd);

    // 等待并获取指定 id 的响应 (阻塞, 有超时)
    std::optional<std::string> wait_response(int id, int timeout_ms = 30000);

    // 检查是否有客户端连接
    void set_client_connected(bool connected);

    // === SKILL 主线程调用 ===

    // 取出一个待处理的命令 (非阻塞)
    std::optional<Command> pop_command();

    // 放入命令执行结果
    void put_response(int id, const std::string& json_result);

    // 获取当前待处理命令数
    size_t pending_count();

    // 清理所有队列
    void clear();

private:
    CommandQueue() = default;
    CommandQueue(const CommandQueue&) = delete;
    CommandQueue& operator=(const CommandQueue&) = delete;

    std::mutex cmd_mutex_;
    std::queue<Command> commands_;
    static const size_t MAX_QUEUE_SIZE = 1024;

    std::mutex resp_mutex_;
    std::condition_variable resp_cv_;
    std::unordered_map<int, std::string> responses_;

    std::atomic<bool> client_connected_{false};
};

} // namespace allegro_bridge
