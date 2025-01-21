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
import Vapor


@DependencyClient
struct BuildSystemClient {
#warning("remove client")
    var getStatusCount: @Sendable (_ client: Client, _ status: Gitlab.Builder.Status) async throws -> Int
}


extension BuildSystemClient: DependencyKey {
    static var liveValue: Self {
        .init(
            getStatusCount: { client, status in
                try await Gitlab.Builder.getStatusCount(client: client,
                                                        status: status,
                                                        page: 1,
                                                        pageSize: 100,
                                                        maxPageCount: 5)
            }
        )
    }
}


extension BuildSystemClient: TestDependencyKey {
    static var testValue: Self { Self() }
}


extension DependencyValues {
    var buildSystem: BuildSystemClient {
        get { self[BuildSystemClient.self] }
        set { self[BuildSystemClient.self] = newValue }
    }
}


