import Foundation

// MARK: - SSE（Server-Sent Events）流式响应客户端

// SSE 是什么：服务端通过一条长开的 HTTP 连接持续推送文本事件——AI 聊天（ChatGPT、
// 通义、DeepSeek 全是它）的「打字机效果」就是 SSE：每生成一个词推一段 `data: {...}`。
// 协议极简，就三条规则：
//   ① 每条事件 = 若干行，行格式 `字段: 值`；AI 场景基本只见 data: 行
//   ② 事件之间用空行分隔
//   ③ `data: [DONE]` 是 OpenAI 风格的流结束标记（非协议标准，但事实标准）
// 前端对应物：浏览器 EventSource / fetch + ReadableStream 读 chunk。

// 为什么不用 APIClient.get：那是「等全部数据到齐再返回」的一次性请求；
// SSE 要的是「来一段处理一段」的流式读取——URLSession 的 bytes(for:) 就是干这个的。

public enum SSEEvent {
    case chunk(String)     // 一条 data: 事件的内容（如一个增量 token）
    case done              // 收到 [DONE] 或服务端关流：正常结束
    case failed(Error)     // 网络中断 / 非 2xx
}

public struct SSEClient: Sendable {
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // 核心：AsyncStream 把「网络字节流」包装成「事件序列」——调用侧 for await 逐个消费
    // （模块九 AsyncSequence 的实战主战场）
    public func stream(request: URLRequest) -> AsyncStream<SSEEvent> {
        // 先构造流与生产者闭包，再在返回处启动任务——avoid sending-closure 数据竞争报错
        let producer: @Sendable (AsyncStream<SSEEvent>.Continuation) async -> Void = { continuation in
            do {
                // bytes(for:) vs data(for:)：bytes 返回 AsyncSequence，逐字节到手；
                // data 会攒齐全部才返回——流式必须用 bytes
                let (bytes, response) = try await session.bytes(for: request)

                // SSE 也要自己查状态码（URLSession 不抛 404 的坑在流式同样存在）
                guard let http = response as? HTTPURLResponse,
                      (200...299).contains(http.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    continuation.yield(.failed(ApiError.httpFailed(code)))
                    continuation.finish()
                    return
                }

                // ⚠️ 大坑（本 Demo 实测踩过）：不能用 bytes.lines——它会把「空行」丢掉！
                // SSE 的事件边界恰恰是空行：空行丢了 = 边界丢了 = 所有事件连成一整条，
                // 直到流结束才一次性吐出，打字机直接变成「转圈半天后全文一次蹦出」。
                // 正确姿势：bytes.characters（逐字符、正确解码 UTF-8 中文）自己按 \n 切行
                var line = ""          // 正在攒的当前行（网络字节不按行整齐到，逐字符攒）
                var eventData = ""     // 当前事件攒的 data 内容（协议允许一个事件多行 data）

                for try await char in bytes.characters {
                    if char == "\n" {
                        if line.hasSuffix("\r") { line.removeLast() }   // 兼容 \r\n 行尾
                        if line.hasPrefix("data:") {
                            // data: 后面有个空格：`data: 你好` → 去前缀再 trim
                            let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                            if payload == "[DONE]" {
                                continuation.yield(.done)     // 流结束标记
                                continuation.finish()
                                return
                            }
                            eventData += payload              // 多行 data 拼接（协议允许，罕见）
                        } else if line.isEmpty {
                            // 空行 = 事件结束：吐出攒好的内容，清空等下一事件
                            if !eventData.isEmpty {
                                continuation.yield(.chunk(eventData))
                                eventData = ""
                            }
                        }
                        // 其他行（event:/id:/retry: 或注释行 :keep-alive）本 Demo 忽略
                        line = ""
                    } else {
                        line.append(char)
                    }
                }
                // 服务端正常关连接（EOF）：循环自然结束
                if !eventData.isEmpty { continuation.yield(.chunk(eventData)) }   // 吐出最后半截
                continuation.yield(.done)
                continuation.finish()
            } catch {
                // 网络中断 / 任务被取消（视图消失时 .task 自动取消正好走到这）
                continuation.yield(.failed(error))
                continuation.finish()
            }
        }

        // 局部类持有 continuation→任务的绑定：onTermination 需要引用 task 来取消网络
        final class Box: @unchecked Sendable {
            var task: Task<Void, Never>?
        }
        let box = Box()
        let stream = AsyncStream<SSEEvent> { continuation in
            box.task = Task { await producer(continuation) }
            // onTermination：调用侧不再消费（提前 break / 页面销毁）时，取消底层网络任务
            // 不写这段 = 网络连接泄漏，AI 长回答会持续耗流量
            continuation.onTermination = { _ in box.task?.cancel() }
        }
        return stream
    }

    // 便捷构造：POST JSON（OpenAI 兼容接口的标准形态）
    public static func jsonPOST(url: URL, body: some Encodable) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // ⚠️ SSE 接口标配两件：Accept 告诉服务端我要事件流；超时拉长防长回答被掐
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 300
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}
