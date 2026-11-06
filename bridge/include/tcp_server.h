// tcp_server.h — TCP 服务器（后台线程）
// 在 Allegro 进程内提供 TCP 监听服务
// 线程安全: 所有公共方法均使用互斥锁保护

#pragma once

// winsock2.h MUST be included before windows.h
#ifdef _WINDOWS
    #define WIN32_LEAN_AND_MEAN
    #include <windows.h>
    #include <winsock2.h>
    #include <ws2tcpip.h>
    #pragma comment(lib, "ws2_32.lib")
    using socket_t = SOCKET;
    #define INVALID_SOCKET_VAL INVALID_SOCKET
    #define SOCKET_ERROR_VAL SOCKET_ERROR
#else
    #include <sys/socket.h>
    #include <netinet/in.h>
    #include <arpa/inet.h>
    #include <unistd.h>
    #include <fcntl.h>
    using socket_t = int;
    #define INVALID_SOCKET_VAL (-1)
    #define SOCKET_ERROR_VAL (-1)
#endif

#include <string>
#include <thread>
#include <atomic>
#include <mutex>
#include <functional>

namespace allegro_bridge {

using CommandCallback = std::function<void(const std::string& request_json)>;

class TcpServer {
public:
    static TcpServer& instance();

    // 生命周期
    bool start(int port = 57123);
    void stop();
    bool is_running() const { return running_.load(); }
    bool is_connected() const { return client_connected_.load(); }

    // 向已连接的客户端发送响应
    bool send_response(const std::string& json_payload);

    // 设置收到命令时的回调 (在 TCP 线程中调用)
    void set_on_command(CommandCallback cb);

private:
    TcpServer() = default;
    ~TcpServer();
    TcpServer(const TcpServer&) = delete;
    TcpServer& operator=(const TcpServer&) = delete;

    void server_loop();
    void handle_client(socket_t client_sock);
    bool send_all(socket_t sock, const char* data, int len);
    bool recv_all(socket_t sock, char* buffer, int len);
    void cleanup();

    std::thread server_thread_;
    std::atomic<bool> running_{false};
    std::atomic<bool> client_connected_{false};
    std::atomic<int> port_{57123};

    socket_t listen_socket_ = INVALID_SOCKET_VAL;
    socket_t client_socket_ = INVALID_SOCKET_VAL;
    std::mutex send_mutex_;

    CommandCallback on_command_;
};

} // namespace allegro_bridge
