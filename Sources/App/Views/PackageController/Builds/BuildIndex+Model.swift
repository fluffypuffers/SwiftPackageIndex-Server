import Plot


extension BuildIndex {
    struct Model {
        var owner: String
        var repositoryName: String
        var packageName: String
        var buildCount: Int
        var buildMatrix: BuildMatrix

        init?(package: Package) {
            // we consider certain attributes as essential and return nil (raising .notFound)
            guard let name = package.name(),
                  let owner = package.repository?.owner,
                  let repositoryName = package.repository?.name else { return nil }

            let buildGroups = [
                package.latestVersion(for: .release)
                    .flatMap { BuildGroup(version: $0, kind: .stable) },
                package.latestVersion(for: .preRelease)
                    .flatMap { BuildGroup(version: $0, kind: .beta) },
                package.latestVersion(for: .defaultBranch)
                    .flatMap { BuildGroup(version: $0, kind: .latest) }
            ].compactMap { $0 }

            self.init(owner: owner,
                      repositoryName: repositoryName,
                      packageName: name,
                      buildGroups: buildGroups)
        }

        internal init(owner: String,
                      repositoryName: String,
                      packageName: String,
                      buildGroups: [BuildGroup]) {
            self.owner = owner
            self.repositoryName = repositoryName
            self.packageName = packageName
            self.buildCount = buildGroups.reduce(0) { $0 + $1.builds.count }
            buildMatrix = .init(buildGroups: buildGroups)
        }
    }
}


extension BuildIndex.Model {
    struct BuildGroup {
        var name: String
        var kind: Kind
        var builds: [BuildInfo]

        init?(version: Version, kind: Kind) {
            guard let name = version.reference?.description else { return nil }
            self.init(name: name, kind: kind, builds: version.builds.compactMap(BuildInfo.init))
        }

        internal init(name: String, kind: Kind, builds: [BuildInfo]) {
            self.name = name
            self.kind = kind
            self.builds = builds
        }
    }

    enum Kind {
        case stable
        case beta
        case latest
    }
}


extension BuildIndex.Model {
    struct BuildInfo {
        var id: App.Build.Id
        var platform: App.Build.Platform
        var status: App.Build.Status
        var swiftVersion: App.SwiftVersion

        init?(_ build: App.Build) {
            guard let id = build.id else { return nil }
            self.init(id: id,
                      swiftVersion: build.swiftVersion,
                      platform: build.platform,
                      status: build.status)
        }

        internal init(id: App.Build.Id,
                      swiftVersion: App.SwiftVersion,
                      platform: App.Build.Platform,
                      status: App.Build.Status) {
            self.id = id
            self.platform = platform
            self.status = status
            self.swiftVersion = swiftVersion
        }
    }
}


extension BuildIndex.Model {
    var packageURL: String {
        SiteURL.package(.value(owner), .value(repositoryName), .none).relativeURL()
    }

    struct BuildMatrix {
        var values: [RowIndex: [BuildCell]]

        init(buildGroups: [BuildGroup]) {
            values = Dictionary.init(uniqueKeysWithValues: RowIndex.all.map { ($0, []) })

            for group in buildGroups {
                var column = [RowIndex: BuildCell]()
                for build in group.builds {
                    guard let index = RowIndex(build) else { continue }
                    column[index] = .init(group.name, group.kind, build.id, build.status)
                }
                RowIndex.all.forEach {
                    values[$0, default: []]
                        .append(column[$0, default: BuildCell(group.name, group.kind)])
                }
            }
        }

        var buildItems: [BuildItem] {
            RowIndex.all.sorted(by: RowIndex.versionPlatform)
                .map { index in
                    BuildItem(index: index, values: values[index] ?? [])
                }
        }
    }

    struct BuildCell: Equatable {
        var column: ColumnIndex
        var value: Value?

        init(_ column: String, _ kind: Kind, _ id: App.Build.Id, _ status: Build.Status) {
            self.column = .init(label: column, kind: kind)
            self.value = .init(id: id, status: status)
        }

        init(_ column: String, _ kind: Kind) {
            self.column = .init(label: column, kind: kind)
        }

        var node: Node<HTML.BodyContext> {
            switch value {
                case let .some(value) where value.status == .ok:
                    return .div(.class("succeeded"),
                                .i(.class("icon matrix_succeeded")),
                                .a(.href(SiteURL.builds(.value(value.id)).relativeURL()),
                                   .text("View Build Log")))
                case let .some(value) where value.status == .failed:
                    return .div(.class("failed"),
                                .i(.class("icon matrix_failed")),
                                .a(.href(SiteURL.builds(.value(value.id)).relativeURL()),
                                   .text("View Build Log")))
                case .some, .none:
                    return .div(.class("unknown"), .i(.class("icon matrix_unknown")))
            }
        }

        struct Value: Equatable {
            var id: App.Build.Id
            var status: App.Build.Status
        }
    }

    struct ColumnIndex: Equatable {
        var label: String
        var kind: Kind
        var node: Node<HTML.BodyContext> {
            let cssClass: String
            switch kind {
                case .beta:
                    cssClass = "beta"
                case .latest:
                    cssClass = "branch"
                case .stable:
                    cssClass = "stable"
            }
            return .div(.span(.class(cssClass), .i(.class("icon \(cssClass)")), .text(label)))
        }
    }

    struct RowIndex: Hashable {
        var swiftVersion: SwiftVersionCompatibility
        var platform: Build.Platform

        init?(_ build: BuildInfo) {
            guard let swiftVersion = build.swiftVersion.compatibility else { return nil }
            self.init(swiftVersion: swiftVersion, platform: build.platform)
        }

        internal init(swiftVersion: SwiftVersionCompatibility, platform: Build.Platform) {
            self.swiftVersion = swiftVersion
            self.platform = platform
        }

        static var all: [RowIndex] {
            let versions: [SwiftVersionCompatibility] = [.v5_3, .v5_2, .v5_1, .v5_0, .v4_2]
            let platforms: [Build.Platform] = [.ios,
                                               .macosXcodebuild, .macosSpm,
                                               .tvos,
                                               .watchos]
            let rows: [(SwiftVersionCompatibility, Build.Platform)] = versions.reduce([]) { rows, version in
                rows + platforms.map { (version, $0) }
            }
            return rows.map(RowIndex.init(swiftVersion:platform:))
        }

        // sort descriptor to sort indexes by swift version desc, platform name asc
        static let versionPlatform: (RowIndex, RowIndex) -> Bool = { lhs, rhs in
            if lhs.swiftVersion != rhs.swiftVersion { return lhs.swiftVersion > rhs.swiftVersion }
            return lhs.platform.rawValue < rhs.platform.rawValue
        }
    }

    struct BuildItem {
        var index: RowIndex
        var values: [BuildCell]

        var node: Node<HTML.ListContext> {
            .li(
                .class("row"),
                .div(
                    .class("row_label"),
                    .div(
                        .div(.strong(.text(index.swiftVersion.displayName)),
                             .text(" / "),
                             .strong(.text(index.platform.displayName)))
                    )
                ),
                .div(
                    .class("row_values"),
                    columnLabels,
                    cells
                )
            )
        }

        var columnLabels: Node<HTML.BodyContext> {
            .div(
                .class("column_label"),
                .group(values.map(\.column.node))
            )
        }

        var cells: Node<HTML.BodyContext> {
            .div(
                .class("result"),
                .group(values.map(\.node))
            )
        }
    }

}
