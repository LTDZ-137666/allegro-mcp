# bridge_client.py v2 — TCP 客户端 + 后台读取线程
# 消息格式: [4-byte big-endian uint32 length][JSON payload UTF-8]

import socket
import struct
import json
import threading
import queue
from typing import Optional, Dict, Any


class BridgeError(Exception):
    pass


class AllegroBridgeClient:
    """TCP 客户端, 后台线程持续读取, 分离命令响应和聊天消息"""

    def __init__(self):
        self._sock: Optional[socket.socket] = None
        self._send_lock = threading.Lock()
        self._connected = False
        self._host = "127.0.0.1"
        self._port = 57123
        self._chat_messages: list[str] = []

        # 后台读取线程
        self._reader_thread: Optional[threading.Thread] = None
        self._reader_running = False
        # 命令响应队列: (id, response_dict)
        self._response_queue: queue.Queue = queue.Queue()

    @property
    def connected(self) -> bool:
        return self._connected

    def connect(self, host: str = "127.0.0.1", port: int = 57123,
                timeout: float = 10.0) -> bool:
        self.disconnect()
        self._host = host
        self._port = port
        try:
            self._sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self._sock.settimeout(timeout)
            self._sock.connect((host, port))
            self._sock.settimeout(1.0)  # 后台线程用短超时
            self._connected = True

            # 启动后台读取线程
            self._reader_running = True
            self._reader_thread = threading.Thread(target=self._reader_loop, daemon=True)
            self._reader_thread.start()

            return True
        except (socket.error, OSError) as e:
            self._connected = False
            self._sock = None
            return False

    def disconnect(self):
        self._reader_running = False
        self._connected = False
        if self._reader_thread and self._reader_thread.is_alive():
            self._reader_thread.join(timeout=2)
        if self._sock:
            try:
                self._sock.close()
            except Exception:
                pass
            self._sock = None
        # 清空队列
        while not self._response_queue.empty():
            try:
                self._response_queue.get_nowait()
            except queue.Empty:
                break

    def _reader_loop(self):
        """后台线程: 持续从 socket 读取并分发"""
        buffer = b""
        while self._reader_running and self._sock:
            try:
                # 读可用数据
                try:
                    chunk = self._sock.recv(4096)
                except socket.timeout:
                    continue
                except (socket.error, OSError):
                    break

                if not chunk:
                    self._connected = False
                    break

                buffer += chunk

                # 解析帧: 4B 长度 + 载荷
                while len(buffer) >= 4:
                    payload_len = struct.unpack(">I", buffer[:4])[0]
                    if payload_len == 0 or payload_len > 16 * 1024 * 1024:
                        buffer = b""
                        break
                    if len(buffer) < 4 + payload_len:
                        break  # 不完整，等更多数据

                    payload = buffer[4:4 + payload_len]
                    buffer = buffer[4 + payload_len:]

                    try:
                        text = payload.decode("utf-8").strip()
                        if text:
                            msg = json.loads(text)
                    except Exception:
                        continue

                    # 分发
                    chat = msg.pop("chat", None)
                    if chat and isinstance(chat, str) and chat.strip():
                        self._chat_messages.append(chat)

                    # 有 "id" 且有 "result" → 命令响应; 只有 "result" 无 id → 聊天 ping
                    if "id" in msg and "result" in msg:
                        self._response_queue.put(msg)

            except Exception:
                continue

        self._connected = False

    def send_command(self, command: Dict[str, Any], timeout: float = 30.0) -> Dict[str, Any]:
        """发送 JSON 命令并等待响应"""
        if not self._connected or not self._sock:
            raise BridgeError("Not connected. Call allegro_connect() first.")

        payload = json.dumps(command, ensure_ascii=False).encode("utf-8")
        header = struct.pack(">I", len(payload))

        with self._send_lock:
            if not self._sock:
                raise BridgeError("Socket is closed")
            try:
                self._sock.sendall(header + payload)
            except (socket.error, OSError) as e:
                self._connected = False
                raise BridgeError(f"Send error: {e}")

        # 从响应队列取 (与命令 id 匹配或取下一个)
        try:
            response = self._response_queue.get(timeout=timeout)
            return response
        except queue.Empty:
            raise BridgeError("Timeout waiting for response")

    def pop_chat_messages(self) -> list[str]:
        msgs = self._chat_messages.copy()
        self._chat_messages.clear()
        return msgs

    def send_display(self, message: str) -> None:
        if self._connected:
            from protocol import MCPBridgeProtocol
            expr = f'_ai_chat_display("{message}")'
            self.send_command(MCPBridgeProtocol.build_raw_request(expr), timeout=5.0)

    def __del__(self):
        self.disconnect()
