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

import Dependencies
import DependenciesMacros
import IssueReporting
import Logging
import Synchronization


@DependencyClient
struct LoggerClient {
    var log: @Sendable (_ level: Logging.Logger.Level, Logging.Logger.Message) -> Void
    var setLogger: @Sendable (Logging.Logger) -> Void
}


extension LoggerClient: DependencyKey {
    static var liveValue: Self {
        .init(
            log: { level, message in
                _logger.withLock { $0.log(level: level, message) }
            },
            setLogger: { logger in
                _logger.withLock { $0.setLogger(logger) }
            }
        )
    }

    private static let _logger = Mutex(Logger.uninitialized(.init()))
}


extension LoggerClient: TestDependencyKey {
    static var testValue: Self { .init() }
}


extension DependencyValues {
    var logger: LoggerClient {
        get { self[LoggerClient.self] }
        set { self[LoggerClient.self] = newValue }
    }
}


// Modeled after https://swiftology.io/articles/typestate/

extension LoggerClient {

    private enum Logger: ~Copyable {
        case uninitialized(_UninitializedLogger)
        case initialized(_InitializedLogger)

        mutating func setLogger(_ logger: Logging.Logger) {
            self = .initialized(.init(logger: logger))
        }

        func log(
            level: Logging.Logger.Level,
            _ message: @autoclosure () -> Logging.Logger.Message,
            metadata: @autoclosure () -> Logging.Logger.Metadata? = nil,
            source: @autoclosure () -> String? = nil,
            file: String = #fileID,
            function: String = #function,
            line: UInt = #line
        ) {
            switch self {
                case .uninitialized:
                    break
                case let .initialized(logger):
                    logger.log(level: level,
                               message(),
                               metadata: metadata(),
                               source: source(),
                               file: file,
                               function: function,
                               line: line)
            }
        }
    }

}


private struct _UninitializedLogger: ~Copyable {
    consuming func setLogger(_ logger: Logging.Logger) -> _InitializedLogger {
        .init(logger: logger)
    }
}

private struct _InitializedLogger: ~Copyable {
    var logger: Logging.Logger

    init(logger: Logging.Logger) {
        self.logger = logger
    }

    func log(
        level: Logging.Logger.Level,
        _ message: @autoclosure () -> Logging.Logger.Message,
        metadata: @autoclosure () -> Logging.Logger.Metadata? = nil,
        source: @autoclosure () -> String? = nil,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) {
        logger.log(level: level, message(), metadata: metadata(), source: source(), file: file, function: function, line: line)
    }
}

