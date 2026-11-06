// tcp_server.cpp — TCP 服务器实现
// Winsock2 TCP 服务器，支持单客户端连接
// 消息帧: [4-byte big-endian uint32 length][JSON payload]

#include "tcp_server.h"
#include <cstdio>
#include <cstring>

#ifdef _WINDOWS
    #include <windows.h>
    // 关闭 send/recv 的 deprecated 警告
    #pragma warning(disable: 4996)
#else
    #include <cerrno>
    #include <signal.h>
    #define closesocket close
#endif

namespace allegro_bridge {

TcpServer& TcpServer::instance() {
    static TcpServer server;
    return server;
}

TcpServer::~TcpServer() {
    stop();
}

bool TcpServer::start(int port) {
    if (running_.load()) return true;

    port_ = port;

#ifdef _WINDOWS
    // 初始化 Winsock
    WSADATA wsaData;
    if (WSAStartup(MAKEWORD(2, 2), &wsaData) != 0) {
        return false;
    }
#else
    // 忽略 SIGPIPE (Linux: 向已关闭的 socket 写入会触发)
    signal(SIGPIPE, SIG_IGN);
#endif

    // 创建 socket
    listen_socket_ = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (listen_socket_ == INVALID_SOCKET_VAL) {
        return false;
    }

    // 设置 SO_REUSEADDR 以便快速重启
    int opt = 1;
    setsockopt(listen_socket_, SOL_SOCKET, SO_REUSEADDR,
#ifdef _WINDOWS
               (const char*)&opt, sizeof(opt));
#else
               &opt, sizeof(opt));
#endif

    // 绑定到 localhost
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = inet_addr("127.0.0.1");
    addr.sin_port = htons(static_cast<u_short>(port));

    if (bind(listen_socket_, (struct sockaddr*)&addr, sizeof(addr)) == SOCKET_ERROR_VAL) {
        closesocket(listen_socket_);
        listen_socket_ = INVALID_SOCKET_VAL;
        return false;
    }

    // 开始监听 (backlog=1, 单客户端)
    if (listen(listen_socket_, 1) == SOCKET_ERROR_VAL) {
        closesocket(listen_socket_);
        listen_socket_ = INVALID_SOCKET_VAL;
        return false;
    }

    // 启动后台线程
    running_ = true;
    server_thread_ = std::thread(&TcpServer::server_loop, this);

    return true;
}

void TcpServer::stop() {
    running_ = false;

    // 关闭 socket 以解除 accept 阻塞
    if (listen_socket_ != INVALID_SOCKET_VAL) {
        closesocket(listen_socket_);
        listen_socket_ = INVALID_SOCKET_VAL;
    }
    if (client_socket_ != INVALID_SOCKET_VAL) {
        closesocket(client_socket_);
        client_socket_ = INVALID_SOCKET_VAL;
    }

    // 等待线程结束
    if (server_thread_.joinable()) {
        server_thread_.join();
    }

#ifdef _WINDOWS
    WSACleanup();
#endif
}

void TcpServer::server_loop() {
    while (running_.load()) {
        try {
            struct sockaddr_in client_addr;
#ifdef _WINDOWS
            int addr_len = sizeof(client_addr);
#else
            socklen_t addr_len = sizeof(client_addr);
#endif
            client_socket_ = accept(listen_socket_, (struct sockaddr*)&client_addr, &addr_len);

            if (!running_.load()) break;

            if (client_socket_ != INVALID_SOCKET_VAL) {
                client_connected_ = true;
                handle_client(client_socket_);
                client_connected_ = false;
            }
        } catch (...) {
            // Prevent any exception from crashing Allegro
        }
    }
}

void TcpServer::handle_client(socket_t client_sock) {
    try {
        while (running_.load()) {
            unsigned char len_buf[4];
            if (!recv_all(client_sock, (char*)len_buf, 4)) {
                break;
            }

            uint32_t payload_len =
                ((uint32_t)len_buf[0] << 24) |
                ((uint32_t)len_buf[1] << 16) |
                ((uint32_t)len_buf[2] << 8)  |
                ((uint32_t)len_buf[3]);

            if (payload_len == 0 || payload_len > 16 * 1024 * 1024) {
                break;
            }

            std::string json_payload(payload_len, '\0');
            if (!recv_all(client_sock, &json_payload[0], payload_len)) {
                break;
            }

            if (on_command_) {
                on_command_(json_payload);
            }
        }
    } catch (...) {
        // prevent crash
    }
    client_socket_ = INVALID_SOCKET_VAL;
}

bool TcpServer::send_response(const std::string& json_payload) {
    std::lock_guard<std::mutex> lock(send_mutex_);
    if (client_socket_ == INVALID_SOCKET_VAL) return false;

    // 构造长度前缀
    uint32_t len = (uint32_t)json_payload.size();
    unsigned char len_buf[4];
    len_buf[0] = (len >> 24) & 0xFF;
    len_buf[1] = (len >> 16) & 0xFF;
    len_buf[2] = (len >> 8)  & 0xFF;
    len_buf[3] = len & 0xFF;

    // 发送长度头 + 负载
    if (!send_all(client_socket_, (const char*)len_buf, 4)) return false;
    if (!send_all(client_socket_, json_payload.c_str(), len)) return false;

    return true;
}

bool TcpServer::send_all(socket_t sock, const char* data, int len) {
    int sent = 0;
    while (sent < len) {
        int n = send(sock, data + sent, len - sent, 0);
        if (n == SOCKET_ERROR_VAL || n == 0) return false;
        sent += n;
    }
    return true;
}

bool TcpServer::recv_all(socket_t sock, char* buffer, int len) {
    int received = 0;
    while (received < len) {
        int n = recv(sock, buffer + received, len - received, 0);
        if (n == SOCKET_ERROR_VAL || n == 0) return false;
        received += n;
    }
    return true;
}

void TcpServer::set_on_command(CommandCallback cb) {
    on_command_ = std::move(cb);
}

void TcpServer::cleanup() {
    // 析构时清理
}

} // namespace allegro_bridge
