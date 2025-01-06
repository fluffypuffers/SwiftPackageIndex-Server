// Copyright Dave Verwer, Sven A. Schmidt, and other contributors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import NIOCore
@preconcurrency import RediStack
import Dependencies
import DependenciesMacros


@DependencyClient
struct RedisClient {
    var set: @Sendable (_ key: String, _ value: String?, Duration?) async -> Void
    var get: @Sendable (_ key: String) async -> String?
    var increment: @Sendable (_ key: String, _ by: Int) async -> Int?
}


extension RedisClient {
    func set(key: String, value: String?, expiresIn: Duration? = nil) async {
        await set(key: key, value: value, expiresIn)
    }

    func increment(key: String) async -> Int? {
        await increment(key: key, by: 1)
    }
}


extension RedisClient: DependencyKey {
    static var liveValue: RedisClient {
        .init(
            set: { key, value, expiresIn in
                await Redis.shared?.set(key: key, value: value, expiresIn: expiresIn)
            },
            get: { key in await Redis.shared?.get(key: key) },
            increment: { key, value in try? await Redis.shared?.increment(key: key, by: value) }
        )
    }
}


extension RedisClient: TestDependencyKey {
    static var testValue: Self { Self() }
}


extension DependencyValues {
    var redis: RedisClient {
        get { self[RedisClient.self] }
        set { self[RedisClient.self] = newValue }
    }
}


#if DEBUG
extension RedisClient {
    static var disabled: Self {
        .init(set: { _, _, _ in }, get: { _ in nil }, increment: { _, _ in nil})
    }
}
#endif


private actor Redis {
    var client: RediStack.RedisClient
    static private var task: Task<Redis?, Never>?

    static var shared: Redis? {
        get async {
            if let task {
                return await task.value
            }
            let task = Task<Redis?, Never> {
                var attemptsLeft = maxConnectionAttempts
                while attemptsLeft > 0 {
                    do {
                        return try await Redis()
                    } catch {
                        attemptsLeft -= 1
                        Current.logger().warning("Redis connection failed, \(attemptsLeft) attempts left. Error: \(error)")
                        try? await Task.sleep(for: .milliseconds(500))
                    }
                }
                return nil
            }
            self.task = task
            return await task.value
        }
    }

    private init() async throws {
        let connection = RedisConnection.make(
            configuration: try .init(hostname: Redis.hostname),
            boundEventLoop: NIOSingletons.posixEventLoopGroup.any()
        )
        self.client = try await connection.get()
    }

    // This hostname has to match the redir service name in app.yml.
    static let hostname = "redis"
    static let maxConnectionAttempts = 3

    func set(key: String, value: String?, expiresIn: Duration?) async {
        if let value {
            let buffer = ByteBuffer(string: value)
            let value = RESPValue.bulkString(buffer)
            if let expiresIn {
                let ttl = Int(expiresIn.components.seconds)
                try? await client.setex(.init(key), to: value, expirationInSeconds: ttl).get()
            } else {
                try? await client.set(.init(key), to: value).get()
            }
        } else {
            _ = try? await client.delete([.init(key)]).get()
        }
    }

    func get(key: String) async -> String? {
        return try? await client.get(.init(key)).map(\.string).get()
    }

    func increment(key: String) async throws -> Int {
        try await client.increment(.init(key)).get()
    }

    func increment(key: String, by value: Int) async throws -> Int {
        try await client.increment(.init(key), by: value).get()
    }
}

