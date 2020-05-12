//
//  File.swift
//  
//
//  Created by Sven A. Schmidt on 26/04/2020.
//

import Vapor


enum Constants {
    static let masterPackageListUri = URI(string: "https://raw.githubusercontent.com/daveverwer/SwiftPMLibrary/master/packages.json")
    static let githubComPrefix = "https://github.com/"
    static let gitSuffix = ".git"
    static let reIngestionDeadtime: TimeInterval = 60 * 60  // in seconds
}
